import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    property var contentColors: Appearance.barContent
    // Room between the icons and the pill drawn around them, the same the
    // utility buttons keep, so the two read as the same kind of thing when they
    // sit beside each other.
    readonly property real contentPadding: 4 * root.uiScale
    implicitWidth: gridLayout.implicitWidth + root.contentPadding * 2
    implicitHeight: gridLayout.implicitHeight + root.contentPadding * 2
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true
    property var activeMenu: null

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems
    onUnpinnedItemsChanged: {
        if (unpinnedItems.length == 0) root.closeOverflowMenu();
    }

    function grabFocus() {
        focusGrab.active = true;
    }

    function beginMenu(window) {
        const previous = root.activeMenu;
        focusGrab.active = root.trayOverflowOpen;
        root.activeMenu = window;
        if (previous && previous !== window) previous.close();
    }

    function focusMenu(window) {
        if (root.activeMenu === window) root.grabFocus();
    }

    function releaseFocus(window) {
        if (root.activeMenu !== window) return;
        root.activeMenu = null;
        focusGrab.active = root.trayOverflowOpen;
    }

    function closeOverflowMenu() {
        focusGrab.active = false;
    }

    onTrayOverflowOpenChanged: {
        if (root.trayOverflowOpen) {
            root.grabFocus();
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [trayOverflowLayout.QsWindow?.window, root.activeMenu?.visible ? root.activeMenu : null]
        onCleared: {
            root.trayOverflowOpen = false;
            if (root.activeMenu) {
                root.activeMenu.close();
                root.activeMenu = null;
            }
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.fill: parent
        anchors.margins: root.contentPadding
        rowSpacing: 8 * root.uiScale
        columnSpacing: 15 * root.uiScale

        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0
            toggled: root.trayOverflowOpen
            property bool containsMouse: hovered

            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen

            Layout.fillHeight: !root.vertical
            Layout.fillWidth: root.vertical
            background.implicitWidth: 24
            background.implicitHeight: 24
            background.anchors.centerIn: this
            colBackgroundHover: root.contentColors.colLayer1Hover
            colRipple: root.contentColors.colLayer1Active
            colBackgroundToggled: root.contentColors.colSecondaryContainer
            colBackgroundToggledHover: root.contentColors.colSecondaryContainerHover
            colRippleToggled: root.contentColors.colSecondaryContainerActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.basePixelSize.larger * root.uiScale
                text: "expand_more"
                horizontalAlignment: Text.AlignHCenter
                color: root.trayOverflowOpen ? root.contentColors.colOnSecondaryContainer : root.contentColors.colOnLayer2
                rotation: (root.trayOverflowOpen ? 180 : 0) - (90 * root.vertical) + (180 * root.invertSide)
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton
                active: root.trayOverflowOpen && root.unpinnedItems.length > 0

                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(root.unpinnedItems.length))
                    columnSpacing: 10 * root.uiScale
                    rowSpacing: 10 * root.uiScale

                    Repeater {
                        model: root.unpinnedItems

                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            contentColors: root.contentColors
                            backdrop: Appearance.m3colors.m3surfaceContainer
                            Layout.fillHeight: !root.vertical
                            Layout.fillWidth: root.vertical
                            onMenuOpening: window => root.beginMenu(window)
                            onMenuOpened: window => root.focusMenu(window)
                            onMenuClosed: window => root.releaseFocus(window)
                        }
                    }
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.pinnedItems
            }

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                contentColors: root.contentColors
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuOpening: window => root.beginMenu(window)
                onMenuOpened: window => root.focusMenu(window)
                onMenuClosed: window => root.releaseFocus(window)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            font.pixelSize: Appearance.font.basePixelSize.larger * root.uiScale
            color: root.contentColors.colSubtext
            text: "•"
            visible: root.showSeparator && SystemTray.items.values.length > 0
        }
    }
}
