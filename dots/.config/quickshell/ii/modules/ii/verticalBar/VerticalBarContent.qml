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

    // The furthest the strip's ends can come in before the pills packed
    // against them meet the middle block. The middle block is centered on the
    // window, so the two halves are the same size, but the sections filling
    // them are not: the one carrying more widgets runs out first, and since
    // the ends move together it governs both.
    readonly property real maxFloatInset: {
        const half = (root.height - middleSection.height) / 2;
        const pad = Appearance.rounding.screenRounding;
        return Math.max(0, Math.min(half - topSectionColumn.implicitHeight - pad,
            half - bottomSectionColumn.implicitHeight - pad));
    }

    // How far each END of the strip comes in along the screen's height. Only
    // the style that flares at its own ends has anywhere to put the room this
    // frees, so every other style is handed the body it always drew: the
    // floating one its gap on all four sides, the rest none at all.
    readonly property real floatSideInset: (Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 3)
        ? Math.max(Config.options.bar.cornerStyle === 3 ? 0 : Appearance.sizes.hyprlandGapsOut,
            Math.min(root.height * (100 - Appearance.sizes.barFloatWidth) / 200,
                root.maxFloatInset))
        : 0

    // Only the notch draws curves beside the body, so only it needs the pair
    // flattened into one group before the surface is faded.
    readonly property bool notchSeamFix: Config.options.bar.cornerStyle === 3
        && Config.options.bar.showBackground

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

    component BarFlare: RoundCorner {
        implicitSize: Appearance.rounding.barFloat
        color: root.notchSeamFix ? Appearance.colors.colBarBackgroundOpaque
            : Appearance.colors.colBarBackground
    }

    component BarEndFlares: Item {
        visible: Config.options.bar.cornerStyle === 3 && Config.options.bar.showBackground
        BarFlare { // Above the strip
            anchors.bottom: parent.top
            anchors.bottomMargin: -1
            anchors.left: !Config.options.bar.bottom ? parent.left : undefined
            anchors.right: Config.options.bar.bottom ? parent.right : undefined
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomRight
                : RoundCorner.CornerEnum.BottomLeft
        }
        BarFlare { // Below it
            anchors.top: parent.bottom
            anchors.topMargin: -1
            anchors.left: !Config.options.bar.bottom ? parent.left : undefined
            anchors.right: Config.options.bar.bottom ? parent.right : undefined
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.TopRight
                : RoundCorner.CornerEnum.TopLeft
        }
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && (Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 3) && Config.options.bar.floatStyleShadow
        // The body is inset from the window, so the shade under it comes in by
        // the same amount. It anchors to the group rather than the body because
        // the body is no longer a sibling of this loader.
        anchors.fill: barSurface
        anchors.leftMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        anchors.rightMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        anchors.topMargin: root.floatSideInset
        anchors.bottomMargin: root.floatSideInset
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
            color: Appearance.colors.colBarShadow
        }
    }
    // Background. The group reaches the whole window so the curves past the
    // body's ends fall inside it, since flattening one clips to its bounds. The
    // fade lives here rather than in the colours, so the lap between body and
    // curve is blended once instead of twice.
    Item {
        id: barSurface
        anchors.fill: parent
        opacity: root.notchSeamFix ? Appearance.colors.colBarBackground.a : 1
        layer.enabled: root.notchSeamFix

    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
            // The width setting runs along the bar's length, which on this bar
            // is the screen's height, so it is the ends that come in and not
            // the sides. The inset carries the floating style's all round gap
            // as its own value there, so that style draws what it always did.
            topMargin: root.floatSideInset
            bottomMargin: root.floatSideInset
        }
        color: !Config.options.bar.showBackground ? "transparent"
            : root.notchSeamFix ? Appearance.colors.colBarBackgroundOpaque
            : Appearance.colors.colBarBackground
        // Left for the shadow to read: it takes the roundness of the corners
        // that show, or it would keep a shape the surface no longer has.
        radius: (Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 3) ? Appearance.rounding.barFloat : 0
        // Set down on the docked edge, the pair touching it is squared off. The
        // pair facing the desktop sits at the strip's ends, so it is squared
        // too once the strip runs the whole height and those ends land on the
        // screen's own corners.
        readonly property real edgeCornerRadius: Config.options.bar.cornerStyle === 3 ? 0 : barBackground.radius
        readonly property real endRadius: (Config.options.bar.cornerStyle === 3 && root.floatSideInset <= 0) ? 0 : barBackground.radius
        topLeftRadius: Config.options.bar.bottom ? barBackground.endRadius : barBackground.edgeCornerRadius
        bottomLeftRadius: Config.options.bar.bottom ? barBackground.endRadius : barBackground.edgeCornerRadius
        topRightRadius: Config.options.bar.bottom ? barBackground.edgeCornerRadius : barBackground.endRadius
        bottomRightRadius: Config.options.bar.bottom ? barBackground.edgeCornerRadius : barBackground.endRadius
        // No outline while the curves at the ends are drawn beside the body:
        // they carry none of their own, so the body's would stop in mid air
        // where each one begins.
        border.width: Config.options.bar.cornerStyle === 1 && Config.options.bar.showBackground ? 1 : 0
        border.color: Appearance.colors.colBarBackgroundBorder

        BarEndFlares { anchors.fill: parent }
    }
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
            id: topSectionColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                // Packed against the body's own end once the strip is
                // shortened, rather than against the window's, which the body
                // no longer reaches.
                // A shortened strip's end is rounded, so the first pill steps
                // in past the curve rather than sitting on top of it.
                topMargin: root.floatSplit ? root.floatPad
                    : Math.max(Appearance.sizes.hyprlandGapsOut, root.floatSideInset + (root.floatSideInset > 0 ? root.floatPad : 0))
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
            id: bottomSectionColumn
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                // Packed against the body's own end, as the top section is.
                // Packed against the body's own end, as the top section is.
                bottomMargin: root.floatSplit ? root.floatPad
                    : Math.max(Appearance.rounding.screenRounding, root.floatSideInset + (root.floatSideInset > 0 ? root.floatPad : 0))
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
