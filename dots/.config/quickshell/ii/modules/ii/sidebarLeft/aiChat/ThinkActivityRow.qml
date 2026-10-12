pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "thinkrows.js" as ThinkRows

// One activity record of a thought: what was read, edited, searched or run.
Rectangle {
    id: root
    required property string verb
    required property string target
    required property string path
    required property string lineRange
    required property int added
    required property int removed
    required property string copyText
    property var colorFor: name => name

    signal openRequested(string path)

    readonly property bool isRun: ThinkRows.isRunVerb(root.verb)
    readonly property var icons: ThinkRows.rowIcons(root.verb, root.target)
    readonly property bool canOpen: !root.isRun && root.path.startsWith("/")
    readonly property bool actionable: root.isRun ? root.copyText.length > 0 : root.canOpen
    property bool copiedFeedback: false

    Layout.fillWidth: true
    implicitHeight: actionRow.implicitHeight + 6
    radius: Appearance.rounding.verysmall
    color: actionMouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

    Timer {
        id: copyFeedbackTimer
        interval: 1500
        onTriggered: root.copiedFeedback = false
    }

    MouseArea {
        id: actionMouseArea
        anchors.fill: parent
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true
        onClicked: {
            if (root.isRun) {
                if (root.copyText.length === 0) return;
                Quickshell.clipboardText = root.copyText;
                root.copiedFeedback = true;
                copyFeedbackTimer.restart();
            } else if (root.canOpen) {
                root.openRequested(root.path);
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: actionMouseArea.containsMouse && root.actionable
        sourceComponent: Item {
            StyledToolTip {
                delay: 400
                text: root.copiedFeedback ? Translation.tr("Copied to clipboard!")
                    : root.isRun ? Translation.tr("Click to copy command: %1").arg(root.copyText)
                    : Translation.tr("Click to open %1").arg(root.path)
            }
        }
    }

    RowLayout {
        id: actionRow
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 6

        StyledText {
            text: root.verb
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignVCenter
        }

        // Copied notification badge
        RowLayout {
            visible: root.copiedFeedback
            spacing: 4
            Layout.alignment: Qt.AlignVCenter

            MaterialSymbol {
                text: "check"
                iconSize: 13
                color: "#4ade80"
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: Translation.tr("Copied!")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: "#4ade80"
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // File Image (e.g. document sheet or terminal)
        MaterialSymbol {
            visible: !root.copiedFeedback && root.icons.showFileIcon
            text: root.icons.fileIcon
            iconSize: 14
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignVCenter
        }

        // File Type Image (e.g. code/data with syntax color)
        MaterialSymbol {
            visible: !root.copiedFeedback && root.icons.showTypeIcon
            text: root.icons.typeIcon
            iconSize: 14
            color: root.colorFor(root.icons.typeColor)
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: root.target
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideMiddle
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            visible: root.lineRange.length > 0
            text: root.lineRange
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            visible: root.added >= 0
            text: "+" + root.added
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: "#4ade80"
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            visible: root.removed >= 0
            text: "-" + root.removed
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: "#f87171"
            Layout.alignment: Qt.AlignVCenter
        }

        MaterialSymbol {
            visible: root.isRun
            text: "chevron_right"
            iconSize: 13
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
