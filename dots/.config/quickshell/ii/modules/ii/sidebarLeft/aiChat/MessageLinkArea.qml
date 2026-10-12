import qs
import qs.services
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * Hover layer for a text item that shows links: pointing hand, a tooltip with
 * the real target, and activate() that opens only web and mail links.
 */
MouseArea {
    id: root
    required property Item textItem
    property bool selectable: false
    readonly property string link: root.textItem?.hoveredLink ?? ""
    property point tipPosition: Qt.point(0, 0)

    function opens(url: string): bool {
        return /^(https?|mailto):/i.test(url);
    }

    function activate(url: string): void {
        if (root.opens(url)) {
            Qt.openUrlExternally(url);
            GlobalStates.sidebarLeftOpen = false;
        } else {
            Quickshell.clipboardText = url;
        }
    }

    anchors.fill: parent
    acceptedButtons: Qt.NoButton // Only for hover
    hoverEnabled: true
    cursorShape: root.link !== "" ? Qt.PointingHandCursor :
        root.selectable ? Qt.IBeamCursor : Qt.ArrowCursor
    onLinkChanged: if (root.link !== "") root.tipPosition = Qt.point(root.mouseX, root.mouseY)

    Loader {
        active: root.link !== ""
        x: root.tipPosition.x
        y: root.tipPosition.y
        sourceComponent: Item {
            StyledToolTip {
                text: root.opens(root.link) ? root.link : (root.link + "\n" + Translation.tr("Click to copy"))
            }
        }
    }
}
