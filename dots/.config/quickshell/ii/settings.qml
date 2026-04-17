//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    property var pages: [
        {
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("Wi-Fi"),
            icon: "wifi",
            component: "modules/settings/WifiConfig.qml"
        },
        {
            name: Translation.tr("Bluetooth"),
            icon: "bluetooth",
            component: "modules/settings/BluetoothConfig.qml"
        },
        {
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Themes"),
            icon: "style",
            component: "modules/settings/ThemesConfig.qml"
        },
        {
            name: Translation.tr("Display"),
            icon: "monitor",
            component: "modules/settings/DisplayConfig.qml"
        },
        {
            name: Translation.tr("Layouts"),
            icon: "view_quilt",
            component: "modules/settings/LayoutsConfig.qml"
        },
        {
            name: Translation.tr("Mouse"),
            icon: "mouse",
            component: "modules/settings/MouseConfig.qml"
        },
        {
            name: Translation.tr("Power"),
            icon: "bolt",
            component: "modules/settings/PowerConfig.qml"
        },
        {
            name: Translation.tr("Accounts"),
            icon: "manage_accounts",
            component: "modules/settings/AccountsConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Update"),
            icon: "system_update_alt",
            component: "modules/settings/UpdateConfig.qml"
        },
        {
            name: Translation.tr("Recovery"),
            icon: "healing",
            component: "modules/settings/RecoverConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]
    
    // Read deep-linking from environment variables (set by dialogs)
    property int initialPage: {
        const envPage = Quickshell.env("QS_SETTINGS_PAGE");
        return envPage ? parseInt(envPage) : 0;
    }
    property int initialTab: {
        const envTab = Quickshell.env("QS_SETTINGS_TAB");
        return envTab ? parseInt(envTab) : 0;
    }
    property int currentPage: initialPage

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                } 
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: 150
                Flickable {
                    id: navRailFlickable
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: navRail.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                ColumnLayout {
                    id: navRail
                    width: navRailFlickable.width
                    spacing: 0

                    // Group 1: Quick, Wi-Fi, Bluetooth (Indices 0, 1, 2)
                    Repeater {
                        model: root.pages.slice(0, 3)
                        SettingsNavButton {
                            required property var index
                            required property var modelData
                            toggled: root.currentPage === index
                            onPressed: root.currentPage = index
                            buttonIcon: modelData.icon
                            buttonText: modelData.name
                        }
                    }

                    // Separator 1
                    Rectangle { Layout.fillWidth: true; height: 1; opacity: 0.3; Layout.margins: 12
                                color: Appearance.m3colors.m3outlineVariant }

                    // Group 2: Bar, Interface, Background, Themes (Indices 3, 4, 5, 6)
                    Repeater {
                        model: root.pages.slice(3, 7)
                        SettingsNavButton {
                            required property var index
                            required property var modelData
                            toggled: root.currentPage === (index + 3)
                            onPressed: root.currentPage = (index + 3)
                            buttonIcon: modelData.icon
                            buttonText: modelData.name
                        }
                    }

                    // Separator 2
                    Rectangle { Layout.fillWidth: true; height: 1; opacity: 0.3; Layout.margins: 12
                                color: Appearance.m3colors.m3outlineVariant }

                    // Group 3: Display, Layouts, Mouse, Power (Indices 7, 8, 9, 10)
                    Repeater {
                        model: root.pages.slice(7, 11)
                        SettingsNavButton {
                            required property var index
                            required property var modelData
                            toggled: root.currentPage === (index + 7)
                            onPressed: root.currentPage = (index + 7)
                            buttonIcon: modelData.icon
                            buttonText: modelData.name
                        }
                    }

                    // Separator 3
                    Rectangle { Layout.fillWidth: true; height: 1; opacity: 0.3; Layout.margins: 12
                                color: Appearance.m3colors.m3outlineVariant }

                    // Group 4: Accounts, Services, Update, Recovery (Indices 11, 12, 13, 14)
                    Repeater {
                        model: root.pages.slice(11, 15)
                        SettingsNavButton {
                            required property var index
                            required property var modelData
                            toggled: root.currentPage === (index + 11)
                            onPressed: root.currentPage = (index + 11)
                            buttonIcon: modelData.icon
                            buttonText: modelData.name
                        }
                    }

                    // Separator 4
                    Rectangle { Layout.fillWidth: true; height: 1; opacity: 0.3; Layout.margins: 12
                                color: Appearance.m3colors.m3outlineVariant }

                    // Group 5: About (Index 15)
                    Repeater {
                        model: root.pages.slice(15)
                        SettingsNavButton {
                            required property var index
                            required property var modelData
                            toggled: root.currentPage === (index + 15)
                            onPressed: root.currentPage = (index + 15)
                            buttonIcon: modelData.icon
                            buttonText: modelData.name
                        }
                    }
                } // ColumnLayout navRail
                } // Flickable
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    source: Config.ready ? root.pages[root.currentPage].component : ""

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }

    // Inline nav button for settings — same visual style as NavigationRailButton
    // in expanded mode but without states/transitions to avoid animation on first open.
    component SettingsNavButton: TabButton {
        id: navBtn
        property bool toggled: false
        property string buttonIcon
        property string buttonText

        readonly property real baseSize: 56
        readonly property real visualWidth: baseSize + 20 + navBtnText.implicitWidth

        Layout.fillWidth: true
        implicitHeight: baseSize
        padding: 0
        background: null
        PointingHandInteraction {}

        contentItem: Item {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            implicitWidth: navBtn.visualWidth

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                implicitWidth: navBtn.visualWidth
                radius: Appearance.rounding.full
                color: navBtn.toggled ?
                    (navBtn.down ? Appearance.colors.colSecondaryContainerActive : navBtn.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer) :
                    (navBtn.down ? Appearance.colors.colLayer1Active : navBtn.hovered ? Appearance.colors.colLayer1Hover : CF.ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Item {
                id: navBtnIconArea
                implicitWidth: navBtn.baseSize
                implicitHeight: 32
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    fill: navBtn.toggled ? 1 : 0
                    font.weight: (navBtn.toggled || navBtn.hovered) ? Font.DemiBold : Font.Normal
                    text: navBtn.buttonIcon
                    color: navBtn.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            StyledText {
                id: navBtnText
                anchors {
                    left: navBtnIconArea.right
                    verticalCenter: navBtnIconArea.verticalCenter
                }
                text: navBtn.buttonText
                font.pixelSize: 14
                color: Appearance.colors.colOnLayer1
            }
        }
    }
}
