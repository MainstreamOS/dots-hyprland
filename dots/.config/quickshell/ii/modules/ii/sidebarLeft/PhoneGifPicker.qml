pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Rectangle {
    id: root

    signal closed()
    signal downloadStarted()
    signal gifChosen(string path, bool directSend)

    property var gifList: []
    property bool searching: false
    property bool downloading: false
    property bool targetDirect: false
    property bool showCloseButton: true

    implicitHeight: 290
    radius: Appearance.rounding.normal - 2
    color: Appearance.colors.colLayer2
    clip: true

    // A query typed while a search still runs; that search's results are
    // dropped and this one starts when it ends, so the grid shows the newest.
    property var pendingQuery: null

    function performSearch(query): void {
        root.searching = true;
        if (gifSearchProc.running) {
            root.pendingQuery = query.trim();
            return;
        }
        root.pendingQuery = null;
        gifSearchProc.command = [
            "python3", "-I",
            FileUtils.trimFileProtocol(`${Directories.scriptPath}/phone/gif-search.py`),
            query.trim()
        ];
        gifSearchProc.running = true;
    }

    function searchFinished(): void {
        if (gifSearchProc.running) return;
        if (root.pendingQuery !== null) root.performSearch(root.pendingQuery);
        else root.searching = false;
    }

    function showTrending(): void {
        if (root.visible && root.gifList.length === 0 && !root.searching) root.performSearch("");
    }
    onVisibleChanged: root.showTrending()

    Process {
        id: gifSearchProc
        // A failed start emits no exit signal or collected output.
        onRunningChanged: if (!running) Qt.callLater(root.searchFinished)
        stdout: StdioCollector {
            id: gifSearchOut
            onStreamFinished: {
                if (root.pendingQuery !== null) return;
                root.searching = false;
                try {
                    const text = gifSearchOut.text.trim();
                    if (text.length > 0) {
                        root.gifList = JSON.parse(text);
                    } else {
                        root.gifList = [];
                    }
                } catch (e) {
                    root.gifList = [];
                }
            }
        }
    }

    Process {
        id: downloadGifProc
        property string destPath: ""
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (!downloadGifProc.running) root.downloading = false;
        })
        onExited: exitCode => {
            root.downloading = false;
            if (exitCode === 0 && destPath.length > 0) {
                root.gifChosen(destPath, root.targetDirect);
            }
        }
    }

    function downloadAndSelect(url, directSend): void {
        if (root.downloading) return;
        root.downloading = true;
        root.downloadStarted();
        root.targetDirect = directSend;
        const ts = Date.now();
        const rand = Math.random().toString(36).substring(2, 8);
        const dest = `${Directories.phoneGifs}/tenor_${ts}_${rand}.gif`;
        downloadGifProc.destPath = dest;
        downloadGifProc.command = ["curl", "-fsSL", "--create-dirs", "-o", dest, url];
        downloadGifProc.running = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Layout.fillHeight: false
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.fillHeight: false
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: searchInput.activeFocus ? 2 : 1
                border.color: searchInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "search"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0 && !searchInput.inputMethodComposing
                            text: Translation.tr("Search Tenor GIFs...")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }

                        StyledTextInput {
                            id: searchInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            onTextChanged: searchDebounce.restart()
                            Keys.onEscapePressed: root.closed()

                            Timer {
                                id: searchDebounce
                                interval: 350
                                repeat: false
                                onTriggered: root.performSearch(searchInput.text)
                            }
                        }
                    }

                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        visible: searchInput.text.length > 0
                        onClicked: searchInput.text = ""
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            RippleButton {
                visible: root.showCloseButton
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: Translation.tr("Close GIF picker")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.fillHeight: false
            visible: root.downloading
            radius: Appearance.rounding.small
            color: Appearance.colors.colPrimaryContainer

            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "downloading"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: Translation.tr("Attaching GIF...")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            StyledText {
                anchors.centerIn: parent
                visible: root.searching && root.gifList.length === 0
                text: Translation.tr("Finding GIFs...")
                color: Appearance.colors.colSubtext
            }

            StyledText {
                anchors.centerIn: parent
                visible: !root.searching && root.gifList.length === 0
                text: Translation.tr("No GIFs found")
                color: Appearance.colors.colSubtext
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: root.gifList.length > 0
                clip: true
                cellWidth: Math.max(90, Math.floor(grid.width / 2))
                cellHeight: 110
                model: root.gifList
                ScrollBar.vertical: StyledScrollBar {}

                delegate: Item {
                    id: gifDelegate
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: cellBox
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        clip: true

                        readonly property bool isHovered: cellHover.hovered || cellMouse.containsMouse || sendBtn.hovered

                        HoverHandler {
                            id: cellHover
                        }

                        AnimatedImage {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: gifDelegate.modelData.thumb
                            playing: grid.visible
                            asynchronous: true
                            cache: true
                        }

                        Rectangle {
                            id: hoverOverlay
                            anchors.fill: parent
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.4)
                            visible: cellBox.isHovered
                            radius: Appearance.rounding.small

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                MaterialSymbol {
                                    text: "add_circle"
                                    iconSize: 26
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.downloadAndSelect(gifDelegate.modelData.url, false)
                        }

                        RippleButton {
                            id: sendBtn
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.full
                            visible: cellBox.isHovered
                            colBackground: ColorUtils.transparentize("black", 0.5)
                            onClicked: root.downloadAndSelect(gifDelegate.modelData.url, true)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "send"
                                iconSize: 14
                                color: "white"
                            }
                            StyledToolTip {
                                text: Translation.tr("Send GIF directly")
                            }
                        }
                    }
                }
            }
        }
    }
}
