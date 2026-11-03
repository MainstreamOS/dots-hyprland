import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    Loader {
        id: sessionLoader
        active: GlobalStates.sessionOpen
        onActiveChanged: {
            if (sessionLoader.active)
                SessionWarnings.refresh();
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.sessionOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            visible: sessionLoader.active
            property string subtitle
            readonly property real menuScale: Math.max(0.5, Math.min(2, Config.options.session.menuSize / 100))
            readonly property real menuWidthLimit: Math.max(1, width - 64)
            readonly property real menuHeightLimit: Math.max(1, height - menuHeader.implicitHeight
                - menuDescription.implicitHeight - contentColumn.spacing * 2
                - Math.max(64, warningsColumn.implicitHeight * 2 + 40))

            function hide() {
                GlobalStates.sessionOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: {
                    sessionRoot.hide();
                }
            }

            ColumnLayout { // Content column
                id: contentColumn
                anchors.centerIn: parent
                spacing: 15

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    }
                }

                ColumnLayout {
                    id: menuHeader
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0
                    StyledText {
                        // Title
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        text: Translation.tr("Session")
                    }

                    StyledText {
                        // Small instruction
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Arrow keys to navigate, Enter to select\nEsc or click anywhere to cancel")
                    }
                }

                // Only the chosen menu is built, so a button it leaves out can
                // never take the focus.
                Loader {
                    id: menuLoader
                    focus: true
                    Layout.alignment: Qt.AlignHCenter
                    sourceComponent: Config.options.session.simpleMenu ? simpleMenuComponent : fullMenuComponent
                }

                DescriptionLabel {
                    id: menuDescription
                    Layout.alignment: Qt.AlignHCenter
                    text: sessionRoot.subtitle
                }
            }

            ColumnLayout {
                id: warningsColumn
                anchors {
                    top: contentColumn.bottom
                    topMargin: 10
                    horizontalCenter: contentColumn.horizontalCenter
                }
                spacing: 10

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.packageManagerRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("Your package manager is running")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
            }

            Component {
                id: fullMenuComponent
                GridLayout {
                    id: fullGrid
                    columns: 4
                    columnSpacing: 15
                    rowSpacing: 15
                    readonly property real buttonSize: Math.max(1, Math.floor(Math.min(120 * sessionRoot.menuScale,
                        (sessionRoot.menuWidthLimit - columnSpacing * 3) / 4,
                        (sessionRoot.menuHeightLimit - rowSpacing) / 2)))

                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionLock
                        focus: sessionRoot.visible
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            Session.lock();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.right: sessionSleep
                        KeyNavigation.down: sessionHibernate
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionSleep
                        buttonIcon: "dark_mode"
                        buttonText: Translation.tr("Sleep")
                        onClicked: {
                            Session.suspend();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLock
                        KeyNavigation.right: sessionLogout
                        KeyNavigation.down: sessionShutdown
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionLogout
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Logout")
                        onClicked: {
                            Session.logout();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionSleep
                        KeyNavigation.right: sessionTaskManager
                        KeyNavigation.down: sessionReboot
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionTaskManager
                        buttonIcon: "browse_activity"
                        buttonText: Translation.tr("Task Manager")
                        onClicked: {
                            Session.launchTaskManager();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLogout
                        KeyNavigation.down: sessionFirmwareReboot
                    }

                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionHibernate
                        buttonIcon: "downloading"
                        buttonText: Translation.tr("Hibernate")
                        onClicked: {
                            Session.hibernate();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionLock
                        KeyNavigation.right: sessionShutdown
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionShutdown
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shutdown")
                        onClicked: {
                            Session.poweroff();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionHibernate
                        KeyNavigation.right: sessionReboot
                        KeyNavigation.up: sessionSleep
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionReboot
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
                        onClicked: {
                            Session.reboot();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionShutdown
                        KeyNavigation.right: sessionFirmwareReboot
                        KeyNavigation.up: sessionLogout
                    }
                    SessionActionButton {
                        size: fullGrid.buttonSize
                        id: sessionFirmwareReboot
                        buttonIcon: "settings_applications"
                        buttonText: Translation.tr("Reboot to firmware settings")
                        onClicked: {
                            Session.rebootToFirmware();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionTaskManager
                        KeyNavigation.left: sessionReboot
                    }
                }
            }

            Component {
                id: simpleMenuComponent
                RowLayout {
                    id: simpleRow
                    spacing: 15
                    readonly property real buttonSize: Math.max(1, Math.floor(Math.min(240 * sessionRoot.menuScale,
                        (sessionRoot.menuWidthLimit - spacing * 3) / 4,
                        sessionRoot.menuHeightLimit)))

                    SessionActionButton {
                        id: simpleLock
                        focus: sessionRoot.visible
                        size: simpleRow.buttonSize
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            Session.lock();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.right: simpleLogout
                    }
                    SessionActionButton {
                        id: simpleLogout
                        size: simpleRow.buttonSize
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Logout")
                        onClicked: {
                            Session.logout();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: simpleLock
                        KeyNavigation.right: simpleReboot
                    }
                    SessionActionButton {
                        id: simpleReboot
                        size: simpleRow.buttonSize
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
                        onClicked: {
                            Session.reboot();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: simpleLogout
                        KeyNavigation.right: simpleShutdown
                    }
                    SessionActionButton {
                        id: simpleShutdown
                        size: simpleRow.buttonSize
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shutdown")
                        onClicked: {
                            Session.poweroff();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: simpleReboot
                    }
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.colors.colTooltip
        clip: true
        radius: Appearance.rounding.normal
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
