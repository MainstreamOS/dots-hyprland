import QtQuick
import QtQuick.Layouts
import qs.services
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
        radius: 14
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
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
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + 16
                radius: 14
                color: ColorUtils.mix(
                    ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94),
                    Appearance.colors.colSecondaryContainer, 0.75)

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 10
                        color: Appearance.colors.colSecondaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.icon
                            iconSize: 20
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.subtitle.length > 0
                            text: root.subtitle
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        id: headerActionsRow
                        visible: children.length > 0
                        spacing: 4
                    }

                    IslandButton {
                        contentColors: Appearance.colors
                        symbol: "close"
                        Accessible.name: root.closeToolTip.length > 0 ? root.closeToolTip : Translation.tr("Close")
                        onClicked: root.close()
                        StyledToolTip {
                            extraVisibleCondition: root.shown && root.closeToolTip.length > 0
                            text: root.closeToolTip
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)
            }
        }
    }
}
