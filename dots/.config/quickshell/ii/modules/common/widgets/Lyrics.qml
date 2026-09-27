pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft
    // Lets the owner say the view is out of sight even while it is visible,
    // such as a sidebar page that is not the current one.
    property bool active: true

    implicitWidth: 200
    implicitHeight: 200
    clip: true

    // LyricsService only looks anything up while some view is counted in.
    readonly property bool onScreen: root.active && root.visible && (root.QsWindow.window?.visible ?? false)
    property bool counted: false
    function updateCount() {
        if (root.onScreen === root.counted)
            return;
        root.counted = root.onScreen;
        if (root.counted)
            LyricsService.addViewer();
        else
            LyricsService.removeViewer();
    }
    onOnScreenChanged: root.updateCount()
    Component.onCompleted: root.updateCount()
    Component.onDestruction: {
        if (root.counted)
            LyricsService.removeViewer();
    }

    readonly property bool hasLyrics: LyricsService.status === "ok"
    readonly property bool unreachable: LyricsService.status === "offline" || LyricsService.status === "rate_limited"

    // How many lines either side of the current one fit, so a short view
    // keeps the current line in the middle rather than cutting it off.
    readonly property int reach: {
        const room = root.height;
        const line = size => size * 1.45 + linesColumn.spacing;
        let used = line(Appearance.font.pixelSize.normal);
        for (let d = 1; d <= LyricsService.before; d++) {
            used += 2 * line(d === 1 ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.smaller);
            if (used > room)
                return d - 1;
        }
        return LyricsService.before;
    }

    Item {
        anchors.fill: parent
        visible: !root.hasLyrics

        MaterialLoadingIndicator {
            id: loadingIndicator
            anchors.centerIn: parent
            visible: LyricsService.status === "loading" || LyricsService.status === "idle"
            loading: root.onScreen && LyricsService.status === "loading"
            colBg: root.indicatorColor
            colShape: root.indicatorShapeColor
            implicitSize: 48
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            spacing: 4
            visible: !loadingIndicator.visible

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: root.dimColor
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.unreachable ? Translation.tr("Couldn't reach LRCLIB") : Translation.tr("No lyrics found")
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: LyricsService.status === "offline"
                color: root.activeColor
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.underline: retryArea.containsMouse
                text: Translation.tr("Retry")

                MouseArea {
                    id: retryArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LyricsService.retry()
                }
            }
        }
    }

    ColumnLayout {
        id: linesColumn
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        visible: root.hasLyrics
        spacing: 6

        Repeater {
            model: 7
            delegate: StyledText {
                id: lyricSlot
                required property int index
                Layout.fillWidth: true
                visible: lyricSlot.dist <= root.reach
                horizontalAlignment: root.textAlignment
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: LyricsService.slots[index] ?? ""
                textFormat: Text.PlainText
                readonly property int dist: Math.abs(index - LyricsService.before)
                font.pixelSize: {
                    if (dist === 0) return Appearance.font.pixelSize.normal
                    if (dist === 1) return Appearance.font.pixelSize.small
                    return Appearance.font.pixelSize.smaller
                }
                opacity: {
                    if (dist === 0) return 1.0
                    if (dist === 1) return 0.6
                    if (dist === 2) return 0.35
                    return 0.15
                }
                color: dist === 0 ? root.activeColor : root.textColor
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }
    }
}
