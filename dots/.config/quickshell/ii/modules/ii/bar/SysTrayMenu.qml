pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string trayItemId: ""

    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin

    implicitHeight: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitHeight, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }
    implicitWidth: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitWidth, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }

    function open() {
        root.visible = true;
        root.menuOpened(root);
    }

    function close() {
        root.visible = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        ContextMenuCard {
            id: popupBackground
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.padding
            }

            opacity: 0
            Component.onCompleted: opacity = 1
            implicitWidth: stackView.implicitWidth + popupBackground.padding * 2
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            StackView {
                id: stackView
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                // Here rather than on the card, whose shadow a clip would cut
                // off: the card animates to each level's size, and a level
                // larger than it is kept inside while it grows.
                clip: true
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}

                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight

                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: ContextMenuItem {
                iconName: "chevron_left"
                label: Translation.tr("Back")
                downAction: () => stackView.pop()
            }
        }
        ContextMenuItem {
            id: pinEntry
            visible: root.trayItemId !== undefined && root.trayItemId.length > 0 && stackView.depth === 1
            iconName: "push_pin"
            label: TrayService.isPinned(root.trayItemId) ? Translation.tr("Unpin") : Translation.tr("Pin")
            releaseAction: () => TrayService.togglePin(root.trayItemId);
        }

        // Between the menu's own Back or Pin row and the app's entries, so only
        // when one of those rows is there.
        ContextMenuSeparator {
            visible: submenu.isSubMenu || pinEntry.visible
        }

        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].icon.length > 0)
                        return true;
                }
                return false;
            }
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None)
                        return true;
                }
                return false;
            }
            model: menuOpener.children
            // The app's separators are drawn as the menu's own.
            delegate: Loader {
                id: entryLoader
                required property QsMenuEntry modelData
                Layout.fillWidth: true
                sourceComponent: entryLoader.modelData.isSeparator ? entrySeparator : entryRow

                Component {
                    id: entrySeparator
                    ContextMenuSeparator {}
                }
                Component {
                    id: entryRow
                    SysTrayMenuEntry {
                        forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                        forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                        menuEntry: entryLoader.modelData

                        onDismiss: root.close()
                        onOpenSubmenu: handle => {
                            stackView.push(subMenuComponent.createObject(null, {
                                handle: handle,
                                isSubMenu: true
                            }));
                        }
                    }
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
