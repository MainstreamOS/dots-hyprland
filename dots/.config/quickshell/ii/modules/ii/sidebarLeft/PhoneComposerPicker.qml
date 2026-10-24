pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Rectangle {
    id: root

    signal closed()
    signal emojiChosen(string emoji)
    signal downloadStarted()
    signal gifChosen(string path, bool directSend)
    property bool gifsLoaded: false

    implicitHeight: 340
    radius: Appearance.rounding.normal - 2
    color: Appearance.colors.colLayer2
    clip: true

    // Each opening starts with the keyboard's emoji page, without fetching GIFs.
    onVisibleChanged: if (visible) tabs.currentIndex = 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            SegmentedTabBar {
                id: tabs
                implicitHeight: 34
                iconSize: 18
                labelSize: Appearance.font.pixelSize.small
                onActivated: index => currentIndex = index
                onCurrentIndexChanged: if (currentIndex === 1) root.gifsLoaded = true
                model: [
                    {name: Translation.tr("Emojis"), icon: "sentiment_satisfied"},
                    {name: Translation.tr("GIFs"), icon: "gif_box"}
                ]
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                focusPolicy: Qt.TabFocus
                buttonRadius: Appearance.rounding.full
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Close picker") }
            }
        }

        PhoneEmojiPicker {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tabs.currentIndex === 0
            onClosed: root.closed()
            onEmojiChosen: emoji => root.emojiChosen(emoji)
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tabs.currentIndex === 1
            // Keep an in-flight download alive when switching tabs or closing.
            active: root.gifsLoaded
            sourceComponent: PhoneGifPicker {
                showCloseButton: false
                color: "transparent"
                onClosed: root.closed()
                onDownloadStarted: root.downloadStarted()
                onGifChosen: (path, directSend) => root.gifChosen(path, directSend)
            }
        }
    }
}
