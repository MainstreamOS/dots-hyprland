import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Shared shell of the chat tab's bottom sheets: scrim, card, header, fade, and
// the key handling that keeps keys typed in an open sheet out of the chat.
FocusScope {
    id: root

    property bool shown: false
    property real maxCardHeight: 520
    property string icon
    property string title
    property string subtitle
    property string closeToolTip
    // Printable keys typed anywhere else in the sheet go to this field.
    property Item inputField: null
    // Escape clears this field's text before it closes the sheet.
    property Item filterField: null
    // Up and Down move this list's current row; Enter (and Space without an
    // input field) emits rowActivated with that row.
    property var navList: null

    default property alias content: contentColumn.data
    property alias headerActions: headerActionsRow.data

    signal closed()
    // Emitted first for every key that reaches the sheet; accept it to skip the defaults.
    signal sheetKeyPressed(var event)
    signal rowActivated(int index)

    // A null target focuses an empty item, so a button clicked earlier
    // cannot keep the keys (Space would click it again).
    function show(focusTarget: Item): void {
        root.shown = true;
        (focusTarget ?? keyTarget).forceActiveFocus();
    }

    function close(): void {
        root.shown = false;
        root.closed();
    }

    anchors.fill: parent
    z: 100
    enabled: root.shown
    visible: opacity > 0
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Keys.onPressed: event => {
        root.sheetKeyPressed(event);
        if (event.accepted)
            return;
        if (event.key === Qt.Key_Escape) {
            if (root.filterField && root.filterField.text.length > 0)
                root.filterField.text = "";
            else
                root.close();
            event.accepted = true;
            return;
        }
        const list = root.navList;
        if (list) {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                if (event.key === Qt.Key_Down)
                    list.incrementCurrentIndex();
                else
                    list.decrementCurrentIndex();
                event.accepted = true;
                return;
            }
            const activates = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_Space && !root.inputField);
            if (activates && list.count > 0) {
                root.rowActivated(Math.max(0, Math.min(list.count - 1, list.currentIndex)));
                event.accepted = true;
                return;
            }
        }
        // Ctrl shortcuts belong to the sidebar.
        if (event.modifiers & Qt.ControlModifier)
            return;
        const code = event.text.length > 0 ? event.text.charCodeAt(0) : 0;
        const printable = code >= 0x20 && code !== 0x7f && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier));
        const field = root.inputField;
        if (printable && field && field.visible && !field.activeFocus) {
            field.forceActiveFocus();
            field.insert(field.cursorPosition, event.text);
        }
        event.accepted = true;
    }

    Item {
        id: keyTarget
    }

    // Scrim backdrop
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        radius: Appearance.rounding.normal

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Modal Card
    Rectangle {
        id: card
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 8
        }
        height: Math.min(parent.height - 16, root.maxCardHeight)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        StyledRectangularShadow {
            z: -1
            target: card
            color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
        }

        // Keeps clicks inside the card from reaching the scrim
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    spacing: 1

                    StyledText {
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                    }

                    StyledText {
                        visible: root.subtitle.length > 0
                        text: root.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                RowLayout {
                    id: headerActionsRow
                    visible: children.length > 0
                    spacing: 8
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    onClicked: root.close()

                    StyledToolTip {
                        extraVisibleCondition: root.shown && root.closeToolTip.length > 0
                        text: root.closeToolTip
                    }
                }
            }
        }
    }
}
