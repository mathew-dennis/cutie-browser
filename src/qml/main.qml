import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtWebEngine
import Qt5Compat.GraphicalEffects
import Cutie
import QtQuick.LocalStorage

CutieWindow {
    id: window
    width: 640
    height: 480
    visible: true
    title: qsTr("Browser")

    property string browserURL: ""
    property bool webApp: false

    property int activeDownloads: 0
    property string activeName: ""
    property real activeProgress: 0

    function fileUrl(path) {
        // encodeURI leaves '#' and '?' alone, which breaks file names containing them
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function statusText(status) {
        return status === "completed" ? qsTr("Completed")
             : status === "downloading" ? qsTr("Downloading…")
             : status === "cancelled" ? qsTr("Cancelled")
             : qsTr("Failed");
    }

    function indexOfDownload(did) {
        for (var i = 0; i < downloadsModel.count; i++)
            if (downloadsModel.get(i).did === did) return i;
        return -1;
    }

    // derive the top bar state from the model so concurrent downloads can't desync it
    function updateActive() {
        var n = 0, sum = 0, name = "";
        for (var i = 0; i < downloadsModel.count; i++) {
            var d = downloadsModel.get(i);
            if (d.status !== "downloading") continue;
            if (n === 0) name = d.name;
            sum += d.progress;
            n++;
        }
        activeDownloads = n;
        activeName = name;
        activeProgress = n > 0 ? sum / n : 0;
    }

    function db() {
        return LocalStorage.openDatabaseSync("CutieBrowser", "1.0", "Cutie Browser data", 1000000);
    }

    function loadDownloads() {
        db().transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS downloads(did TEXT PRIMARY KEY, name TEXT, path TEXT, status TEXT, ts INTEGER)");
            // anything still "downloading" from a previous run was interrupted
            tx.executeSql("UPDATE downloads SET status='failed' WHERE status='downloading'");
            var rs = tx.executeSql("SELECT * FROM downloads ORDER BY ts DESC");
            for (var i = 0; i < rs.rows.length; i++) {
                var r = rs.rows.item(i);
                downloadsModel.append({did: r.did, name: r.name, path: r.path, status: r.status, progress: 0});
            }
        });
    }

    function setDownloadStatus(did, status) {
        var i = indexOfDownload(did);
        if (i < 0 || downloadsModel.get(i).status !== "downloading") return;
        downloadsModel.setProperty(i, "status", status);
        if (status === "completed") downloadsModel.setProperty(i, "progress", 1);
        updateActive();
        db().transaction(function(tx) {
            tx.executeSql("UPDATE downloads SET status=? WHERE did=?", [status, did]);
        });
    }

    function trackDownload(download) {
        var did = Date.now() + "-" + download.id;
        var name = download.downloadFileName;
        var path = download.downloadDirectory + "/" + name;
        downloadsModel.insert(0, {did: did, name: name, path: path, status: "downloading", progress: 0});
        db().transaction(function(tx) {
            tx.executeSql("INSERT OR REPLACE INTO downloads VALUES(?,?,?,?,?)", [did, name, path, "downloading", Date.now()]);
        });
        updateActive();

        download.receivedBytesChanged.connect(function() {
            var i = indexOfDownload(did);
            if (i < 0) return;
            downloadsModel.setProperty(i, "progress", download.totalBytes > 0 ? download.receivedBytes / download.totalBytes : 0);
            updateActive();
        });
        download.stateChanged.connect(function() {
            if (download.state === WebEngineDownloadRequest.DownloadCompleted)
                setDownloadStatus(did, "completed");
            else if (download.state === WebEngineDownloadRequest.DownloadCancelled)
                setDownloadStatus(did, "cancelled");
            else if (download.state === WebEngineDownloadRequest.DownloadInterrupted)
                setDownloadStatus(did, "failed");
        });
    }

    function clearDownloads() {
        for (var i = downloadsModel.count - 1; i >= 0; i--)
            if (downloadsModel.get(i).status !== "downloading")
                downloadsModel.remove(i);
        db().transaction(function(tx) {
            tx.executeSql("DELETE FROM downloads WHERE status != 'downloading'");
        });
    }

    Component.onCompleted: loadDownloads()

    function fixUrl(url) {
        url = url.replace( /^\s+/, "").replace( /\s+$/, ""); // remove white space
        url = url.replace( /(<([^>]+)>)/ig, ""); // remove <b> tag 
        if (url == "") return url;
        if (url[0] == "/") { return "file://"+url; }
        if (url[0] == '.') { 
            var str = itemMap[currentTab].url.toString();
            var n = str.lastIndexOf('/');
            return str.substring(0, n)+url.substring(1);
        }
        //FIXME: search engine support here
        if (url.startsWith('chrome://')) { return url; } 
        if (url.indexOf('.') < 0) { return "https://duckduckgo.com/?q="+url; }
        if (url.indexOf(":") < 0) { return "https://"+url; } 
        else { return url;}
    }

    function browse(url) {
        webview.url = fixUrl(url);
    }

    initialPage: CutiePage {
        id: iPage

        Item { 
            id: headerBar
            height: webApp ? 0 : 44
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !webApp
            CutieButton {
                id: backButton
                width: 28
                height: width
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                enabled: webview.canGoBack
                background: null
                icon.name: "go-previous-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: {
                    webview.goBack()
                }
            }

            CutieButton {
                id: forwardButton
                width: 28
                height: width
                anchors.left: backButton.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                enabled: webview.canGoForward
                background: null
                icon.name: "go-next-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: {
                    webview.goForward()
                }
            }

            CutieButton {
                id: menuButton
                width: 28
                height: width
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                background: null
                icon.name: "view-more-symbolic"
                icon.color: Atmosphere.textColor

                onClicked: moreMenu.open()
            }

            CutieMenu {
                id: moreMenu
                y: -height - 10
                CutieMenuItem {
                    text: qsTr("Downloads")
                    onTriggered: downloadsPanel.visible = true
                }
            }

            CutieTextField {
                id: urlText
                anchors.left: forwardButton.right
                anchors.right: menuButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: ""

                Connections {
                    target: window
                    function onBrowserURLChanged () {
                        urlText.text = window.browserURL;
                    }
                }

                onAccepted: browse(text)

                onFocusChanged: {
                    if (focus) urlFocusTimer.start();
                }

                Timer {
                    id: urlFocusTimer
                    interval: 0
                    running: false
                    repeat: false
                    onTriggered: {
                        urlText.selectAll();
                    }
                }
            }
            Rectangle {
                id: urlProgressBar
                height: 3
                visible: webview.loadProgress < 100
                width: parent.width * (webview.loadProgress / 100)
                anchors.top: headerBar.bottom
                anchors.left: parent.left
                color: Atmosphere.textColor
            }

        }
        ListModel { id: downloadsModel }

        CutieTile {
            id: downloadBar
            z: 10
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            height: 40
            visible: activeDownloads > 0 && !downloadsPanel.visible

            CutieLabel {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                text: activeDownloads > 1
                      ? qsTr("Downloading %1 files").arg(activeDownloads)
                      : qsTr("Downloading ") + activeName
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                anchors.left: parent.left
                anchors.leftMargin: 8
                height: 3
                radius: 2
                width: (parent.width - 16) * activeProgress
                color: Atmosphere.accentColor
            }
            MouseArea {
                anchors.fill: parent
                onClicked: downloadsPanel.visible = true
            }
        }

        Item {
            id: downloadsPanel
            z: 20
            visible: false
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: headerBar.top

            MouseArea { anchors.fill: parent } // block clicks to the page below

            FastBlur {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: webview.height
                source: webview
                radius: 70
            }

            Rectangle {
                anchors.fill: parent
                color: Atmosphere.primaryColor
                opacity: 0.6
            }

            CutiePageHeader {
                id: downloadsHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                title: qsTr("Downloads")
            }

            CutieListView {
                anchors.top: downloadsHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                clip: true
                model: downloadsModel

                menu: CutieMenu {
                    CutieMenuItem {
                        text: qsTr("Clear finished")
                        onTriggered: clearDownloads()
                    }
                    CutieMenuItem {
                        text: qsTr("Close")
                        onTriggered: downloadsPanel.visible = false
                    }
                }

                delegate: CutieListItem {
                    text: model.name
                    subText: statusText(model.status) + " — " + model.path
                    wrapMode: Text.NoWrap
                    elide: Text.ElideMiddle
                    onClicked: {
                        if (model.status === "completed")
                            Qt.openUrlExternally(fileUrl(model.path))
                    }

                    Rectangle {
                        visible: model.status === "downloading"
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        anchors.left: parent.left
                        anchors.leftMargin: 36
                        height: 3
                        radius: 2
                        width: (parent.width - 72) * model.progress
                        color: Atmosphere.accentColor
                    }
                }
            }

            CutieLabel {
                anchors.centerIn: parent
                visible: downloadsModel.count === 0
                text: qsTr("No downloads")
            }
        }

        WebEngineView {
            id: webview
            settings.webRTCPublicInterfacesOnly: true
            settings.touchIconsEnabled: true
            settings.spatialNavigationEnabled: true
            settings.screenCaptureEnabled: true
            settings.printElementBackgrounds: true
            settings.playbackRequiresUserGesture: true
            settings.localContentCanAccessRemoteUrls: true
            settings.linksIncludedInFocusChain: true
            settings.localContentCanAccessFileUrls: true
            settings.allowGeolocationOnInsecureOrigins: true
            settings.allowRunningInsecureContent: true
            settings.allowWindowActivationFromJavaScript: true
            settings.autoLoadIconsForPage: true
            settings.errorPageEnabled: true
            settings.focusOnNavigationEnabled: true
            settings.hyperlinkAuditingEnabled: true
            settings.javascriptCanPaste: true
            settings.javascriptCanOpenWindows: true
            settings.javascriptCanAccessClipboard: true
            settings.localStorageEnabled: true
            settings.pluginsEnabled: true
            settings.showScrollBars: false
            settings.webGLEnabled: true
            settings.fullScreenSupportEnabled: true
            settings.javascriptEnabled: true
            settings.autoLoadImages: true
            settings.accelerated2dCanvasEnabled: true
            url: "https://start.duckduckgo.com"
            transformOrigin: Item.Center
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -23 * !webApp
            width: parent.width
            height: parent.height -46 * !webApp
            
            profile: WebEngineProfile {
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                storageName: "CutieBrowser"
                httpUserAgent: "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.76 Mobile Safari/537.36"

                onDownloadRequested: function(download) {
                    download.accept()
                    trackDownload(download)
                }
            }
            
            onLoadingChanged: {
                window.browserURL = webview.url;
                zoomFactor =  6;
            }
        }
    }
}