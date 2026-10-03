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
                downloadsModel.append({did: r.did, name: r.name, path: r.path, status: r.status});
            }
        });
    }

    function setDownloadStatus(did, status) {
        for (var i = 0; i < downloadsModel.count; i++) {
            if (downloadsModel.get(i).did === did) {
                if (downloadsModel.get(i).status !== "downloading") return;
                downloadsModel.setProperty(i, "status", status);
                activeDownloads = Math.max(0, activeDownloads - 1);
                db().transaction(function(tx) {
                    tx.executeSql("UPDATE downloads SET status=? WHERE did=?", [status, did]);
                });
                return;
            }
        }
    }

    function trackDownload(download) {
        var did = Date.now() + "-" + download.id;
        var name = download.downloadFileName;
        var path = download.downloadDirectory + "/" + name;
        downloadsModel.insert(0, {did: did, name: name, path: path, status: "downloading"});
        db().transaction(function(tx) {
            tx.executeSql("INSERT OR REPLACE INTO downloads VALUES(?,?,?,?,?)", [did, name, path, "downloading", Date.now()]);
        });
        activeDownloads++;
        activeName = name;
        activeProgress = 0;

        download.receivedBytesChanged.connect(function() {
            activeName = name;
            activeProgress = download.totalBytes > 0 ? download.receivedBytes / download.totalBytes : 0;
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

                Menu {
                    id: moreMenu
                    x: menuButton.width - width
                    y: -implicitHeight
                    MenuItem {
                        text: qsTr("Downloads")
                        onTriggered: downloadsPanel.visible = true
                    }
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

        Rectangle {
            id: downloadBar
            z: 10
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            color: "#E6141414"
            visible: activeDownloads > 0

            Label {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideMiddle
                color: "white"
                text: qsTr("Downloading ") + activeName
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                height: 3
                width: parent.width * activeProgress
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: downloadsPanel.visible = true
            }
        }

        Rectangle {
            id: downloadsPanel
            z: 20
            visible: false
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: headerBar.top
            color: "#F2141414"

            MouseArea { anchors.fill: parent } // block clicks to the page below

            Row {
                id: downloadsHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                height: 44
                spacing: 8
                Label {
                    width: parent.width - clearButton.width - closeButton.width - 2 * parent.spacing
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    color: "white"
                    font.bold: true
                    text: qsTr("Downloads")
                }
                CutieButton {
                    id: clearButton
                    text: qsTr("Clear")
                    onClicked: clearDownloads()
                }
                CutieButton {
                    id: closeButton
                    text: qsTr("Close")
                    onClicked: downloadsPanel.visible = false
                }
            }

            ListView {
                anchors.top: downloadsHeader.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                clip: true
                model: downloadsModel
                delegate: Item {
                    width: ListView.view.width
                    height: 56
                    Column {
                        anchors.fill: parent
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            width: parent.width
                            elide: Text.ElideMiddle
                            color: "white"
                            text: model.name
                        }
                        Label {
                            width: parent.width
                            elide: Text.ElideMiddle
                            color: "#AAAAAA"
                            font.pixelSize: 12
                            text: (model.status === "completed" ? qsTr("Completed")
                                  : model.status === "downloading" ? qsTr("Downloading…")
                                  : model.status === "cancelled" ? qsTr("Cancelled")
                                  : qsTr("Failed")) + " — " + model.path
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: model.status === "completed"
                        onClicked: Qt.openUrlExternally(encodeURI("file://" + model.path))
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: downloadsModel.count === 0
                color: "#AAAAAA"
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