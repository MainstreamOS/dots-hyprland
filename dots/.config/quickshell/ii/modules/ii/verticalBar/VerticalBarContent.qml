import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    // Widgets that have a vertical rendering. Inherently horizontal widgets
    // (activeWindow, utilButtons, weather, timers) have no vertical form and
    // are skipped on the vertical bar.
    // The bar's visible body is inset from the window by the floating gap,
    // matching barBackground's margins. The section columns consume it so
    // their pills stay the width of the bar they sit on, which is also the
    // width the center pills come out at.
    readonly property real floatingInset: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0

    // Modules that render without a surrounding pill.
    readonly property var chromelessModules: ["sidebarButton"]

    function moduleComponent(name) {
        switch (name) {
        case "sidebarButton": return comp_sidebarButton;
        case "resources": return comp_resources;
        case "media": return comp_media;
        case "workspaces": return comp_workspaces;
        case "clock": return comp_clock;
        case "battery": return comp_battery;
        case "tray": return comp_tray;
        case "volume": return comp_volume;
        case "indicators": return comp_indicators;
        default: return null;
        }
    }

    function moduleActive(name) {
        return root.moduleComponent(name) !== null;
    }

    // Widgets built to span the bar's width. Everything else is its own size
    // and sits centred — stretching them makes a widget that draws its own
    // background, such as the status indicators, look far wider than it is.
    function moduleFillWidth(name) {
        return name === "resources" || name === "media"
            || name === "clock" || name === "battery" || name === "tray";
    }

    function moduleVisible(name) {
        switch (name) {
        case "battery": return Battery.available;
        default: return true;
        }
    }

    // ---- group model helpers (mirror BarContent; tolerant of legacy layouts) ----
    function groupWidgets(g) {
        if (!g)
            return [];
        if (typeof g === "string")
            return [{ id: g, enabled: true }];
        if (g.widgets !== undefined)
            return g.widgets;
        if (g.items !== undefined)
            return g.items.map(x => (typeof x === "string") ? ({ id: x, enabled: true }) : x);
        return [];
    }
    function groupChromeless(g) {
        const ws = root.groupWidgets(g).filter(w => root.moduleActive(w.id));
        return ws.length > 0 && ws.every(w => root.chromelessModules.indexOf(w.id) !== -1);
    }
    function entryActive(w) {
        return w.enabled !== false && root.moduleActive(w.id);
    }
    function groupHasVisible(g) {
        return root.groupWidgets(g).some(w => root.entryActive(w) && root.moduleVisible(w.id));
    }

    // Generic single-widget slot (vertical).
    component BarModule: Loader {
        required property string moduleName
        property bool entryEnabled: true
        Layout.alignment: Qt.AlignHCenter
        // The button used to be inset from the top by half the room left over
        // beside it, so the gap above matched the gaps either side. Sitting
        // flush against the top instead puts its round highlight over the
        // bar's rounded corner.
        Layout.topMargin: moduleName === "sidebarButton"
            ? (Appearance.sizes.baseVerticalBarWidth - implicitWidth) / 2 : 0
        Layout.fillWidth: root.moduleFillWidth(moduleName)
        active: entryEnabled && root.moduleActive(moduleName)
        visible: active && root.moduleVisible(moduleName)
        sourceComponent: root.moduleComponent(moduleName)
    }

    // One group = one vertical pill (or a bare column for chromeless-only groups).
    component GroupPill: Item {
        id: pill
        required property var group
        readonly property var gw: root.groupWidgets(group)
        readonly property bool chromeless: root.groupChromeless(group)
        visible: root.groupHasVisible(group)
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        implicitHeight: pillLoader.implicitHeight
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true

        Loader {
            id: pillLoader
            anchors.fill: parent
            sourceComponent: pill.chromeless ? chromelessColumn : normalPill
        }

        Component {
            id: chromelessColumn
            ColumnLayout {
                spacing: 8
                Repeater {
                    model: pill.gw
                    delegate: BarModule {
                        required property var modelData
                        moduleName: modelData.id
                        entryEnabled: modelData.enabled
                    }
                }
            }
        }

        Component {
            id: normalPill
            Bar.BarGroup {
                vertical: true
                padding: 8
                Repeater {
                    model: pill.gw
                    delegate: BarModule {
                        required property var modelData
                        moduleName: modelData.id
                        entryEnabled: modelData.enabled
                    }
                }
            }
        }
    }

    // ------- Module registry (vertical variants) -------
    Component {
        id: comp_sidebarButton
        Bar.LeftSidebarButton {
            Layout.alignment: Qt.AlignHCenter
            colBackground: barTopSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        }
    }

    Component {
        id: comp_resources
        Resources {
            Layout.fillWidth: true
            Layout.fillHeight: false
        }
    }

    Component {
        id: comp_media
        VerticalMedia {
            Layout.fillWidth: true
            Layout.fillHeight: false
        }
    }

    Component {
        id: comp_workspaces
        Bar.Workspaces {
            vertical: true
            Layout.fillHeight: false
            MouseArea { // Right-click to toggle overview
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: event => {
                    if (event.button === Qt.RightButton) {
                        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                    }
                }
            }
        }
    }

    Component {
        id: comp_clock
        VerticalClockWidget {
            Layout.fillWidth: true
            Layout.fillHeight: false
        }
    }

    Component {
        id: comp_battery
        BatteryIndicator {
            Layout.fillWidth: true
            Layout.fillHeight: false
        }
    }

    Component {
        id: comp_tray
        Bar.SysTray {
            vertical: true
            Layout.fillWidth: true
            Layout.fillHeight: false
            invertSide: Config?.options.bar.bottom
        }
    }

    Component {
        id: comp_volume
        Item {
            implicitWidth: volumeIconButton.implicitWidth
            implicitHeight: volumeIconButton.implicitHeight
            Layout.alignment: Qt.AlignHCenter

            RippleButton {
                id: volumeIconButton
                anchors.centerIn: parent
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                toggled: volumeBarPopup.shown
                colBackground: barBottomSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                onClicked: volumeBarPopup.shown = !volumeBarPopup.shown

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: {
                        if (Audio.sink?.audio?.muted) return "volume_off";
                        let vol = Audio.sink?.audio?.volume ?? 0;
                        if (vol <= 0) return "volume_mute";
                        if (vol < 0.5) return "volume_down";
                        return "volume_up";
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: volumeIconButton.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0
                }
            }

            Bar.VolumeBarPopup {
                id: volumeBarPopup
                anchorTarget: volumeIconButton
            }
        }
    }

    Component {
        id: comp_indicators
        RippleButton { // Right sidebar button
            id: rightSidebarButton
            Layout.alignment: Qt.AlignHCenter

            implicitHeight: indicatorsColumnLayout.implicitHeight + 4 * 2
            implicitWidth: indicatorsColumnLayout.implicitWidth + 6 * 2

            buttonRadius: Appearance.rounding.full
            colBackground: barBottomSectionMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive
            toggled: GlobalStates.sidebarRightOpen
            property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

            Behavior on colText {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            onPressed: {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }

            ColumnLayout {
                id: indicatorsColumnLayout
                anchors.centerIn: parent
                property real realSpacing: 6
                spacing: 0

                Revealer {
                    vertical: true
                    reveal: Audio.sink?.audio?.muted ?? false
                    Layout.fillWidth: true
                    Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
                    Behavior on Layout.bottomMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    MaterialSymbol {
                        text: "volume_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                    }
                }
                Revealer {
                    vertical: true
                    reveal: Audio.source?.audio?.muted ?? false
                    Layout.fillWidth: true
                    Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
                    Behavior on Layout.topMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    MaterialSymbol {
                        text: "mic_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                    }
                }
                Bar.HyprlandXkbIndicator {
                    vertical: true
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: indicatorsColumnLayout.realSpacing
                    color: rightSidebarButton.colText
                }
                Revealer {
                    vertical: true
                    reveal: Notifications.silent || Notifications.unread > 0
                    Layout.fillWidth: true
                    Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
                    implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                    implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                    Behavior on Layout.bottomMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Bar.NotificationUnreadCount {
                        id: notificationUnreadCount
                    }
                }
                MaterialSymbol {
                    text: Network.materialSymbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
                MaterialSymbol {
                    Layout.topMargin: indicatorsColumnLayout.realSpacing
                    visible: BluetoothStatus.available
                    text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
                MaterialSymbol {
                    Layout.topMargin: indicatorsColumnLayout.realSpacing
                    text: "settings"
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
            }
        }
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
            color: Appearance.colors.colBarShadow
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 && Config.options.bar.showBackground ? 1 : 0
        border.color: Appearance.colors.colBarBackgroundBorder
    }

    Column { // Middle section (layout.center)
        id: middleSection
        anchors.centerIn: parent
        spacing: 4
        Repeater {
            model: Config.options.bar.layout.center
            delegate: GroupPill {
                required property var modelData
                group: modelData
            }
        }
    }

    FocusedScrollMouseArea { // Top section (layout.left) | scroll to change brightness
        id: barTopSectionMouseArea
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: (root.height - middleSection.height) / 2

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        ColumnLayout {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: Appearance.sizes.hyprlandGapsOut
                leftMargin: root.floatingInset
                rightMargin: root.floatingInset
            }
            spacing: 8

            Repeater {
                model: Config.options.bar.layout.left
                delegate: GroupPill {
                    required property var modelData
                    group: modelData
                }
            }
        }
    }

    FocusedScrollMouseArea { // Bottom section (layout.right) | scroll to change volume
        id: barBottomSectionMouseArea
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: (root.height - middleSection.height) / 2

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }

        // Natural height anchored to the bottom edge, mirroring the top
        // section: the column grows toward the middle, so the pills pack
        // against the edge, and with no rect to fit there is no spare space
        // to spread them apart — and no deficit to shrink them below their
        // content when a tall widget like workspaces joins the section.
        ColumnLayout {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                bottomMargin: Appearance.rounding.screenRounding
                leftMargin: root.floatingInset
                rightMargin: root.floatingInset
            }
            spacing: 8

            Repeater {
                model: Config.options.bar.layout.right
                delegate: GroupPill {
                    required property var modelData
                    group: modelData
                }
            }
        }
    }
}
