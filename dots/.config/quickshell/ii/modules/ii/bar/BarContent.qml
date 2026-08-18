import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    // Modules that render without a surrounding pill (they carry their own
    // background or fill the available width).
    readonly property var chromelessModules: ["sidebarButton", "activeWindow", "timers", "releaseUpdates"]

    function moduleComponent(name) {
        switch (name) {
        case "sidebarButton": return comp_sidebarButton;
        case "activeWindow": return comp_activeWindow;
        case "activeWindowPill": return comp_activeWindowPill;
        case "resources": return comp_resources;
        case "media": return comp_media;
        case "workspaces": return comp_workspaces;
        case "clock": return comp_clock;
        case "utilButtons": return comp_utilButtons;
        case "battery": return comp_battery;
        case "indicators": return comp_indicators;
        case "volume": return comp_volume;
        case "tray": return comp_tray;
        case "timers": return comp_timers;
        case "weather": return comp_weather;
        case "releaseUpdates": return comp_releaseUpdates;
        default: return null;
        }
    }

    function moduleActive(name) {
        return root.moduleComponent(name) !== null;
    }

    function moduleVisible(name) {
        switch (name) {
        // The button hides itself when none of the things it opens are turned
        // on. The slot can't see that from the outside, so it would keep the
        // space reserved for a button nobody can see.
        case "sidebarButton": return Config.options.policies.ai !== 0
            || Config.options.sidebar.translator.enable
            || Config.options.policies.weeb !== 0;
        case "activeWindow": return root.useShortenedForm === 0;
        case "activeWindowPill": return root.useShortenedForm === 0;
        case "media": return root.useShortenedForm < 2;
        case "utilButtons": return Config.options.bar.verbose && root.useShortenedForm === 0;
        case "battery": return root.useShortenedForm < 2 && Battery.available;
        case "volume": return root.useShortenedForm === 0;
        case "weather": return root.useShortenedForm === 0;
        case "tray": return root.useShortenedForm === 0;
        // Nothing to say while you're up to date, and the slot would otherwise
        // hold space for an icon that isn't drawn.
        case "releaseUpdates": return ReleaseUpdates.updateAvailable && ReleaseUpdates.wantTray;
        default: return true;
        }
    }

    // Widgets that stretch to the bar's height. The rest keep their own and sit
    // centred — stretching one that draws its own background turns a circle or
    // a capsule into a slab the full height of the bar.
    function moduleFillHeight(name) {
        return name === "activeWindow" || name === "activeWindowPill" || name === "workspaces" || name === "tray"
            || name === "volume";
    }

    function moduleFillWidth(name) {
        return name === "activeWindow" || name === "activeWindowPill" || name === "media" || name === "clock" || (name === "resources" && root.useShortenedForm === 2);
    }

    // Widgets whose own width comes and goes: a track title is there or it
    // isn't, and readings change length as they change value. A group holding
    // one of these gets a floor so the bar doesn't shift about underneath it.
    // The clock is deliberately not one — its width barely moves, and giving
    // it the floor leaves a pill twice the size of the time inside it.
    function moduleWidthVolatile(name) {
        return name === "media" || (name === "resources" && root.useShortenedForm === 2);
    }

    readonly property int mediaMinimumWidth: 140

    // When resources and media share a group, media takes the room resources
    // leaves rather than growing the pill, so switching resources on never
    // moves the bar.
    function mediaYieldsIn(g) {
        const ws = root.groupWidgets(g);
        return ws.some(w => w.id === "media" && root.entryActive(w) && root.moduleVisible(w.id))
            && ws.some(w => w.id === "resources" && root.entryActive(w) && root.moduleVisible(w.id));
    }

    // ---- group model helpers (tolerant of legacy flat/string layouts) ----
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
    function centerGroups() {
        const a = Config.options.bar.layout.center;
        if (!a) return [];
        return Array.prototype.slice.call(a).filter(g => root.groupHasVisible(g));
    }
    readonly property var centerGroupsVisible: root.centerGroups()
    // Odd count: anchor the middle group to screen center (side groups flank it
    // and grow outward, so the middle widget stays centered). Even count: no
    // single middle, so center the whole block as one unit — keeps it balanced.
    function groupsBefore() {
        const g = root.centerGroupsVisible;
        const n = g.length;
        return (n % 2 === 1) ? g.slice(0, (n - 1) / 2) : [];
    }
    function groupsAt() {
        const g = root.centerGroupsVisible;
        const n = g.length;
        return (n % 2 === 1) ? [g[(n - 1) / 2]] : g;
    }
    function groupsAfter() {
        const g = root.centerGroupsVisible;
        const n = g.length;
        return (n % 2 === 1) ? g.slice((n - 1) / 2 + 1) : [];
    }
    // The widgets whose job is genuinely width: the window title needs the
    // section's spare room so it can shrink to an ellipsis.
    function moduleTakesSpace(name) {
        return name === "activeWindow" || name === "activeWindowPill";
    }
    // Whether anything showing in this group needs its section's spare width.
    function groupTakesSpace(g) {
        return root.groupWidgets(g).some(w => root.entryActive(w) && root.moduleVisible(w.id)
            && root.moduleTakesSpace(w.id));
    }
    // Whether a side section needs its packer: a row wider than its content
    // does not push items against its edge — columns with no stretch share the
    // surplus in proportion to their size, so free-standing pills drift apart
    // across the section. The packer is a guaranteed stretch item that eats
    // the surplus, and it stands down when the window title is there to take
    // it — two stretch items would split the surplus, leaving whatever
    // follows the title adrift by the other half.
    function sectionNeedsPacker(groups) {
        if (!groups)
            return true;
        return !Array.prototype.some.call(groups, g => root.groupTakesSpace(g));
    }

    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        implicitHeight: Appearance.sizes.baseBarHeight / 3
        color: Appearance.colors.colOutlineVariant
    }

    // Generic single-widget slot.
    component BarModule: Loader {
        required property string moduleName
        property bool entryEnabled: true
        // Set when this pill is the stock media-and-resources pairing, where
        // media gives up room rather than the pill growing.
        property bool yieldsToGroupMate: false
        // What a module's popup should sit under. Media and resources in one
        // pill read as a single control, so the popup follows the pill they
        // share rather than the media half of it; left null a module speaks
        // for itself.
        property Item popupAnchor: null
        // Whether this slot sits in a center-section pill. Fill only means
        // something there for most widgets: a center pill has a set width,
        // and filling shares it — media's spare room goes to the track
        // title, the clock centers in its slot. Off center the pill can be
        // as wide as its section, where filling would grow those same
        // widgets past their set width instead of leaving the surplus to
        // the widget the section fill exists for. The media-and-resources
        // pairing fills anywhere, because its pill keeps a set width in
        // every section.
        property bool inCenter: false
        Layout.alignment: Qt.AlignVCenter
        Layout.fillWidth: root.moduleFillWidth(moduleName)
            && (inCenter || yieldsToGroupMate || root.moduleTakesSpace(moduleName))
        // Media asks for a set amount rather than for as much as its track
        // title happens to need. That keeps the group a predictable size —
        // titles come and go and the bar shouldn't move when they do — while
        // still letting media take any room the group has left over. Sharing
        // with resources is the exception: ask for the least it can live with
        // and let the group's set width hand back whatever resources didn't use.
        Layout.preferredWidth: moduleName !== "media" ? -1
            : yieldsToGroupMate ? root.mediaMinimumWidth
            : Math.max(root.mediaMinimumWidth, root.centerSideModuleWidth - 40)
        Layout.fillHeight: root.moduleFillHeight(moduleName)
        active: entryEnabled && root.moduleActive(moduleName)
        visible: active && root.moduleVisible(moduleName)
        sourceComponent: root.moduleComponent(moduleName)
    }

    // One group = one pill (or a bare row for chromeless-only groups).
    component GroupPill: Item {
        id: pill
        required property var group
        property bool centerSection: false
        readonly property var gw: root.groupWidgets(group)
        readonly property bool chromeless: root.groupChromeless(group)
        readonly property bool isWorkspaces: gw.length === 1 && gw[0].id === "workspaces"
        // Needing the section's spare width is what promotes the pill to
        // filling outside the center. Everything else on the fill-width list
        // fills as center-pill layout — sharing a set width inside the pill —
        // and promoting the pill for one of those would turn its group into
        // a full-section bar.
        readonly property bool takesSpace: root.groupTakesSpace(group)
        readonly property bool widthVolatile: gw.some(w => root.entryActive(w) && root.moduleVisible(w.id) && root.moduleWidthVolatile(w.id))
        readonly property bool mediaYields: root.mediaYieldsIn(group)
        visible: root.groupHasVisible(group)
        readonly property real contentWidth: chromeless ? chromelessRow.implicitWidth : pillLoader.implicitWidth
        // A group beside the middle whose contents change width never falls
        // below a set width, so one holding only media doesn't shrink to the
        // width of its icon when nothing is playing and leave the two sides
        // mismatched. The media-and-resources pairing keeps the floor in
        // every section — media hands its room to resources and takes back
        // what is left, which only means something inside a set width. A
        // group can still grow past it: put workspaces and media in the
        // same group and both need room, which a set width would deny them.
        implicitWidth: ((centerSection && widthVolatile) || mediaYields) ? Math.max(root.centerSideModuleWidth, contentWidth) : contentWidth
        // Outside the centre a group has to be allowed to take the width its
        // widgets asked for, and to be squeezed below what they'd like. The
        // window title is the one that shows it: pinned to its own width it
        // can't shrink, so a long title runs past the end of its section
        // instead of ending in an ellipsis.
        Layout.fillWidth: !centerSection && takesSpace
        implicitHeight: Appearance.sizes.baseBarHeight
        Layout.alignment: Qt.AlignVCenter

        Loader {
            id: pillLoader
            anchors.fill: parent
            active: !pill.chromeless
            sourceComponent: pill.isWorkspaces ? workspacesPill : normalPill
        }

        RowLayout {
            id: chromelessRow
            anchors.fill: parent
            visible: pill.chromeless
            spacing: 4
            Repeater {
                // Gated on chromelessness, not just hidden: an always-built
                // model would keep a live duplicate of every widget behind
                // each pill.
                model: pill.chromeless ? pill.gw : []
                delegate: BarModule {
                    required property var modelData
                    moduleName: modelData.id
                    entryEnabled: modelData.enabled
                    inCenter: pill.centerSection
                }
            }
        }

        Component {
            id: normalPill
            BarGroup {
                Repeater {
                    model: pill.gw
                    delegate: BarModule {
                        required property var modelData
                        moduleName: modelData.id
                        entryEnabled: modelData.enabled
                        // The yield pairing only holds while nothing else
                        // stretches the pill; beside the window title media
                        // keeps its set width and the title takes the room.
                        yieldsToGroupMate: pill.mediaYields && !pill.takesSpace
                        // The pair is merged whenever both are in the pill,
                        // stretched by a group-mate or not.
                        popupAnchor: pill.mediaYields ? pill : null
                        inCenter: pill.centerSection
                    }
                }
            }
        }

        Component {
            id: workspacesPill
            BarGroup {
                padding: workspacesWidget?.widgetPadding ?? 4
                glowing: workspacesWidget?.dragOver ?? false
                Workspaces {
                    id: workspacesWidget
                    Layout.fillHeight: true
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
        }
    }

    // ------- Module registry (bare widgets; the pill comes from GroupPill) -------
    Component {
        id: comp_sidebarButton
        LeftSidebarButton {
            colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        }
    }

    Component {
        id: comp_activeWindow
        ActiveWindow {}
    }

    Component {
        id: comp_activeWindowPill
        ActiveWindow { pilled: true }
    }

    Component {
        id: comp_resources
        Resources {
            // The collapse to a single meter exists to hand the shared
            // pill's room to media, so it only applies beside media: the
            // parent is the BarModule slot, whose yieldsToGroupMate marks
            // that pairing. Standing alone, the full readout stays.
            alwaysShowAllResources: root.useShortenedForm === 2
                || !(parent?.yieldsToGroupMate ?? false)
        }
    }

    Component {
        id: comp_media
        Media {}
    }

    Component {
        id: comp_workspaces
        Workspaces {
            Layout.fillHeight: true
            MouseArea {
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
        MouseArea {
            implicitWidth: clockInner.implicitWidth + 60
            implicitHeight: clockInner.implicitHeight
            acceptedButtons: Qt.LeftButton
            onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
            ClockWidget {
                id: clockInner
                anchors.fill: parent
                showDate: (Config.options.bar.verbose && root.useShortenedForm < 2)
            }
        }
    }

    Component {
        id: comp_utilButtons
        UtilButtons {
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Component {
        id: comp_battery
        BatteryIndicator {
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Component {
        id: comp_tray
        SysTray {
            invertSide: Config?.options.bar.bottom
        }
    }

    Component {
        id: comp_timers
        TimersTray {}
    }

    Component {
        id: comp_weather
        WeatherBar {}
    }

    Component {
        id: comp_releaseUpdates
        ReleaseUpdatesIndicator {}
    }

    Component {
        id: comp_indicators
        RippleButton { // Right sidebar button
            id: rightSidebarButton

            implicitWidth: indicatorsRowLayout.implicitWidth + 10 * 2
            implicitHeight: indicatorsRowLayout.implicitHeight + 5 * 2

            buttonRadius: Appearance.rounding.full
            colBackground: barRightSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
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

            RowLayout {
                id: indicatorsRowLayout
                anchors.centerIn: parent
                property real realSpacing: 15
                spacing: 0

                Revealer {
                    reveal: Audio.sink?.audio?.muted ?? false
                    Layout.fillHeight: true
                    Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                    Behavior on Layout.rightMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    MaterialSymbol {
                        text: "volume_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                    }
                }
                Revealer {
                    reveal: Audio.source?.audio?.muted ?? false
                    Layout.fillHeight: true
                    Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                    Behavior on Layout.rightMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    MaterialSymbol {
                        text: "mic_off"
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                    }
                }
                HyprlandXkbIndicator {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: indicatorsRowLayout.realSpacing
                    color: rightSidebarButton.colText
                }
                Revealer {
                    reveal: Notifications.silent || Notifications.unread > 0
                    Layout.fillHeight: true
                    Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                    implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                    implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                    Behavior on Layout.rightMargin {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    NotificationUnreadCount {
                        id: notificationUnreadCount
                    }
                }
                MaterialSymbol {
                    text: Network.materialSymbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
                MaterialSymbol {
                    Layout.leftMargin: indicatorsRowLayout.realSpacing
                    visible: BluetoothStatus.available
                    text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
                MaterialSymbol {
                    Layout.leftMargin: indicatorsRowLayout.realSpacing
                    text: "settings"
                    iconSize: Appearance.font.pixelSize.larger
                    color: rightSidebarButton.colText
                }
            }
        }
    }

    Component {
        id: comp_volume
        Item {
            implicitWidth: volumeIconButton.implicitWidth
            implicitHeight: volumeIconButton.implicitHeight

            RippleButton {
                id: volumeIconButton
                anchors.centerIn: parent
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                toggled: volumeBarPopup.shown
                colBackground: barRightSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
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

            VolumeBarPopup {
                id: volumeBarPopup
                anchorTarget: volumeIconButton
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

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: centerLeftFlank.left
        }
        implicitWidth: leftRow.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        // Visual content
        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: leftRow
            anchors.fill: parent
            anchors.leftMargin: Appearance.rounding.screenRounding
            anchors.rightMargin: Appearance.rounding.screenRounding
            spacing: 4

            Repeater {
                model: Config.options.bar.layout.left
                delegate: GroupPill {
                    required property var modelData
                    group: modelData
                }
            }

            Item { // Packs the pills against the screen edge (see sectionNeedsPacker)
                Layout.fillWidth: true
                visible: root.sectionNeedsPacker(Config.options.bar.layout.left)
            }
        }
    }

    // Middle section — the middle group is anchored to screen center; the
    // left/right flanks are natural width and hug it, so the middle stays
    // centered and side widgets never balloon or overlap.
    Item {
        id: centerMidZone
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            // With an odd number of groups the middle one is pinned here and
            // the flanks grow outward from it, so flanks of different widths
            // leave the block as a whole sitting off centre. Lean by half
            // their difference: the block is centred, at the cost of the
            // middle group no longer being exactly so.
            horizontalCenterOffset: (centerLeftFlank.width - centerRightFlank.width) / 2
        }
        implicitWidth: centerMidRow.implicitWidth
        width: implicitWidth

        Row {
            id: centerMidRow
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: root.groupsAt()
                delegate: GroupPill {
                    required property var modelData
                    group: modelData
                    centerSection: true
                }
            }
        }
    }

    Row { // Left flank — groups before the middle, hugging center
        id: centerLeftFlank
        anchors {
            right: centerMidZone.left
            rightMargin: root.groupsAt().length > 0 ? 6 : 3
            verticalCenter: parent.verticalCenter
        }
        spacing: 4
        Repeater {
            model: root.groupsBefore()
            delegate: GroupPill {
                required property var modelData
                group: modelData
                    centerSection: true
            }
        }
    }

    VerticalBarSeparator {
        anchors {
            right: centerMidZone.left
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }
        visible: Config.options?.bar.borderless && centerLeftFlank.width > 0 && root.groupsAt().length > 0
    }

    MouseArea { // Right flank — groups after the middle; also opens the right sidebar
        id: centerRightFlank
        anchors {
            left: centerMidZone.right
            leftMargin: root.groupsAt().length > 0 ? 6 : 3
            verticalCenter: parent.verticalCenter
        }
        implicitWidth: centerRightFlankRow.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight
        onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

        Row {
            id: centerRightFlankRow
            anchors.fill: parent
            spacing: 4
            Repeater {
                model: root.groupsAfter()
                delegate: GroupPill {
                    required property var modelData
                    group: modelData
                    centerSection: true
                }
            }
        }
    }

    VerticalBarSeparator {
        anchors {
            left: centerMidZone.right
            leftMargin: 2
            verticalCenter: parent.verticalCenter
        }
        visible: Config.options?.bar.borderless && centerRightFlank.width > 0 && root.groupsAt().length > 0
    }

    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: centerRightFlank.right
            right: parent.right
        }
        implicitWidth: rightRow.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }

        // Visual content
        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: rightRow
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: Appearance.rounding.screenRounding
            spacing: 5

            Item { // Packs the pills against the screen edge (see sectionNeedsPacker)
                Layout.fillWidth: true
                visible: root.sectionNeedsPacker(Config.options.bar.layout.right)
            }

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
