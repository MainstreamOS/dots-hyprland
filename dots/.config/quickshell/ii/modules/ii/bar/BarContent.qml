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
    // Only what is actually showing gets a say in whether the group wears a
    // pill. Reading moduleActive alone counts a widget the layout lists but the
    // user has switched off, so a pilled entry parked beside the window title
    // with its own switch off still put a pill around the title, which is drawn
    // bare by design.
    function groupChromeless(g) {
        const ws = root.groupWidgets(g).filter(w => root.entryActive(w));
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
    // Whether a widget claims its section's spare room, which promotes the
    // group's pill to filling the section. Nothing does. The window title used
    // to, on the grounds that it needs room to elide into, but a pill promoted
    // to fill takes the whole side of the bar however short the title is, and
    // everything beside it moves on every focus change. The title is given a
    // set width instead, the same the clock keeps, and elides inside it.
    function moduleTakesSpace(name) {
        return false;
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
        active: Config.options.bar.showBackground && root.floatStyles && Config.options.bar.floatStyleShadow && !root.floatSplit
        anchors.fill: barSurface
        anchors.leftMargin: root.floatSideInset
        anchors.rightMargin: root.floatSideInset
        // The body is lifted off all four edges when it floats, so the shade
        // under it has to come in by the same amount or it reaches past the
        // shape it belongs to.
        anchors.topMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        anchors.bottomMargin: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
            color: Appearance.colors.colBarShadow
        }
    }
    // How far in from the screen the floating strip starts on either side.
    // The background is drawn to it and the two end clusters are pinned to it,
    // so narrowing the strip carries them inward together instead of leaving
    // them out at the screen's corners with nothing under them. A strip that is
    // not floating has no inset, which is what it always drew.
    // The narrowest the strip can be drawn before its own contents run into one
    // another. The middle block stays centered while the strip is trimmed from
    // both sides, so what has to fit beside it is the wider of the two end
    // clusters, twice. Their implicit widths are read rather than their actual
    // ones, which is what keeps this out of a loop: an end cluster is stretched
    // to the room the inset leaves it, so asking how wide it currently is would
    // be asking the answer to decide the question.
    // How far each edge may come in before that side's cluster meets the middle
    // block. The two sides are worked out separately rather than halving what
    // the middle leaves over: the block leans by half the difference between its
    // flanks to sit centered as a whole, so the room either side of it is not
    // the same, and a side carrying one widget more than the other runs out
    // first. The edges move together, so the tighter side governs both.
    // This file's shorthand for the shared style facts.
    readonly property bool isNotch: Appearance.sizes.barIsNotch
    readonly property bool floatStyles: Appearance.sizes.barFloats
    // Whether the notch's curves are drawn at all.
    readonly property bool notchFlares: isNotch && Config.options.bar.showBackground
    // Only the notch draws a body with separate pieces lapping it, and the lap
    // only shows through a see-through surface, so a fully opaque one skips
    // the flattening pass and the texture it costs.
    readonly property bool notchSeamFix: notchFlares
        && Appearance.colors.colBarBackground.a < 1
    readonly property bool floatSplit: root.floatStyles
        && Config.options.bar.floatSplit
    readonly property real floatPad: Appearance.rounding.screenRounding
    // Where the middle cluster begins and ends, in this item's own coordinates.
    // The middle block is centered on the window rather than on any surface, so
    // neither of these moves when the outer surfaces do.
    readonly property real centerLeft: centerLeftFlank.x
    readonly property real centerRight: centerRightFlank.x + centerRightFlank.width

    // The desktop the split keeps between surfaces: what has to survive
    // when the strip is drawn in or its content grows. Hugging, each surface
    // end carries a curve drawn beyond it, so two facing each other need
    // room to stand apart or they meet and weld the surfaces back into one.
    readonly property real splitGap: root.isNotch
        ? Math.max(Appearance.sizes.hyprlandGapsOut, Appearance.rounding.barFloat * 2)
        : Appearance.sizes.hyprlandGapsOut

    readonly property real maxFloatInset: {
        const pad = root.floatPad;
        // The styles without a strip of their own have no inset to limit, and
        // this would otherwise chase every widget's width for them.
        if (!root.floatStyles) return 0;
        if (root.floatSplit) {
            // Split, the limit is one surface meeting the next rather than a
            // cluster meeting the middle block, so the gap the desktop shows
            // through is what has to survive.
            const gap = root.splitGap;
            const leftRoom = root.centerLeft - pad - gap - (leftRow.implicitWidth + pad * 2);
            const rightRoom = root.width - root.centerRight - pad - gap
                - (rightRow.implicitWidth + pad * 2);
            return Math.max(0, Math.min(leftRoom, rightRoom));
        }
        const leftRoom = root.centerLeft - leftRow.implicitWidth - pad * 2;
        const rightRoom = root.width - root.centerRight - rightRow.implicitWidth - pad - rightRow.anchors.leftMargin;
        return Math.max(0, Math.min(leftRoom, rightRoom));
    }

    readonly property real floatSideInset: root.floatStyles
        ? Math.max(root.isNotch ? 0 : Appearance.sizes.hyprlandGapsOut,
            Math.min(root.width * (100 - Appearance.sizes.barFloatWidth) / 200,
                root.maxFloatInset))
        : 0

    // What that floor is worth as a percentage, so the slider can refuse to ask
    // for a width the strip would not honor. The widgets on show decide it, so
    // it moves as they come and go.
    // The surfaces a split strip actually draws, so the window can hold the
    // pointer to them and let the desktop between them be clicked through.
    // An empty middle draws no surface: several center layouts can hide every
    // widget, and a bare stub pill would sit at dead screen center.
    readonly property bool centerFloatShown: centerMidZone.implicitWidth > 1
    readonly property var floatSurfaces: !root.floatSplit ? []
        : root.centerFloatShown ? [leftFloat, centerFloat, rightFloat] : [leftFloat, rightFloat]

    readonly property real minFloatPercent: root.floatStyles && root.width > 0
        ? Math.min(Appearance.sizes.barFloatWidthMax, Math.ceil((root.width - root.maxFloatInset * 2) * 100 / root.width)) : 40
    Binding {
        target: GlobalStates
        property: "barFloatMinPercent"
        value: root.minFloatPercent
        // A dying bar (monitor unplug, orientation flip) must not hand back the
        // stale floor it captured at birth over a surviving bar's live one.
        restoreMode: Binding.RestoreNone
    }

    // One concave curve, drawn beside a surface rather than on it. Every piece
    // carries the same size and color as the body it grows out of, which
    // leaves each site only the two things that differ: where it hangs and
    // which way it turns.
    component BarFlare: RoundCorner {
        implicitSize: Appearance.rounding.barFloat
        color: root.notchSeamFix ? Appearance.colors.colBarBackgroundOpaque
            : Appearance.colors.colBarBackground
    }

    // The pair at a surface's own ends, on the side that sits against the
    // screen, so the strip reads as growing out of the edge instead of
    // stopping dead on it. Only the style that hugs its widgets flares:
    // floating, there is a gap on that side and the curves would have nothing
    // to curve into. Each piece laps a pixel over the body, because a
    // fractional display scale can land the body's edge between pixels and a
    // curve that merely touches it rounds to the far side, leaving a hairline
    // of desktop showing through the join. An end that has been carried out to
    // the screen's own edge puts its curve off screen, which is the same thing
    // the squared-off corner there is saying.
    component BarEndFlares: Item {
        BarFlare {
            anchors.right: parent.left
            anchors.rightMargin: -1
            anchors.top: !Config.options.bar.bottom ? parent.top : undefined
            anchors.bottom: Config.options.bar.bottom ? parent.bottom : undefined
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomRight
                : RoundCorner.CornerEnum.TopRight
        }
        BarFlare {
            anchors.left: parent.right
            anchors.leftMargin: -1
            anchors.top: !Config.options.bar.bottom ? parent.top : undefined
            anchors.bottom: Config.options.bar.bottom ? parent.bottom : undefined
            corner: Config.options.bar.bottom ? RoundCorner.CornerEnum.BottomLeft
                : RoundCorner.CornerEnum.TopLeft
        }
    }

    // Each of the three surfaces a split strip draws.
    // They carry the same dress as the single strip so switching between the
    // two changes where the edges are and nothing else.
    component FloatSurface: Item {
        id: floatSurface
        visible: root.floatSplit
        // Whether this surface's own end lands on the screen's edge, which
        // happens once the strip is asked for the whole width. A corner that
        // curves away from an edge it is sitting on opens a wedge of desktop
        // in the screen's own corner, so an end that reaches that far is
        // squared off instead.
        property bool flushLeft: false
        property bool flushRight: false
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // Hugging leaves no gap on the docked edge, and the strip these sit in
        // was never grown by one, so the surface fills it outright. Insetting
        // here would shrink the visible bar rather than lift it.
        anchors.topMargin: root.isNotch ? 0 : Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: root.isNotch ? 0 : Appearance.sizes.hyprlandGapsOut
        // Left for the shadow to read: it takes the roundness of the corners
        // that show, or it would keep a shape the surface no longer has.
        readonly property real radius: Appearance.rounding.barFloat
        // The pair against the docked edge is squared off when the surface is
        // set down on it, and so is an end that reaches the screen's own edge.
        // The pair facing the desktop keeps its roundness either way.
        readonly property real edgeCornerRadius: root.isNotch ? 0 : floatSurface.radius
        readonly property real leftEndRadius: floatSurface.flushLeft ? 0 : floatSurface.radius
        readonly property real rightEndRadius: floatSurface.flushRight ? 0 : floatSurface.radius

        // Each surface carries curves that lap its ends by a pixel, and blending
        // that lap twice is what draws the line across the join. Body and curves
        // are painted opaque and faded together here instead. The group has to
        // reach wider than the body because the curves hang past it and
        // flattening one clips to its bounds; the body is inset back by the same
        // amount, so the surface's own edges stay exactly where they were and
        // everything anchoring to this surface still lands right.
        Item {
            anchors.fill: parent
            anchors.leftMargin: -floatSurface.radius
            anchors.rightMargin: -floatSurface.radius
            opacity: root.notchSeamFix ? Appearance.colors.colBarBackground.a : 1
            layer.enabled: root.notchSeamFix

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: floatSurface.radius
                anchors.rightMargin: floatSurface.radius
                color: !Config.options.bar.showBackground ? "transparent"
                    : root.notchSeamFix ? Appearance.colors.colBarBackgroundOpaque
                    : Appearance.colors.colBarBackground
                radius: floatSurface.radius
                topLeftRadius: Config.options.bar.bottom ? floatSurface.leftEndRadius : floatSurface.edgeCornerRadius
                topRightRadius: Config.options.bar.bottom ? floatSurface.rightEndRadius : floatSurface.edgeCornerRadius
                bottomLeftRadius: Config.options.bar.bottom ? floatSurface.edgeCornerRadius : floatSurface.leftEndRadius
                bottomRightRadius: Config.options.bar.bottom ? floatSurface.edgeCornerRadius : floatSurface.rightEndRadius
                // The curves at the ends are drawn as their own pieces and carry
                // no outline, so an outline on the body would stop in mid air
                // where each one begins. Hugging means one continuous surface or
                // none.
                border.width: Config.options.bar.showBackground && !root.isNotch ? 1 : 0
                border.color: Appearance.colors.colBarBackgroundBorder

                Loader {
                    anchors.fill: parent
                    active: root.notchFlares && floatSurface.visible
                    sourceComponent: BarEndFlares {}
                }
            }
        }
    }

    FloatSurface {
        id: leftFloat
        flushLeft: root.floatSideInset <= 0
        // Parked at zero while unsplit, so a widget changing width does not
        // lay out three strips nobody sees.
        x: root.floatSplit ? root.floatSideInset : 0
        // Capped at the room before the middle surface. A surface is sized
        // around its widgets, and the title's width is the title's to choose,
        // so a long one would otherwise carry its surface across the gap and
        // over the middle block. The cap is what turns growth into elision:
        // the row inside is anchored to the surface, so a clamped surface
        // compresses the row and the title gives the room back.
        width: !root.floatSplit ? 0 : Math.max(0, Math.min(leftRow.implicitWidth + root.floatPad * 2,
            root.centerLeft - root.floatPad - root.splitGap - root.floatSideInset))
    }
    FloatSurface {
        id: centerFloat
        visible: root.floatSplit && root.centerFloatShown
        x: root.floatSplit ? root.centerLeft - root.floatPad : 0
        width: root.floatSplit ? root.centerRight - root.centerLeft + root.floatPad * 2 : 0
    }
    FloatSurface {
        id: rightFloat
        flushRight: root.floatSideInset <= 0
        x: root.floatSplit ? root.width - root.floatSideInset - width : 0
        // Capped for the same reason as its twin, from the other side.
        width: !root.floatSplit ? 0 : Math.max(0, Math.min(rightRow.implicitWidth + root.floatPad * 2,
            root.width - root.floatSideInset - root.centerRight - root.floatPad - root.splitGap))
    }

    Repeater {
        model: Config.options.bar.showBackground && Config.options.bar.floatStyleShadow
            ? root.floatSurfaces : []
        delegate: StyledRectangularShadow {
            required property var modelData
            // These are built after the surfaces they belong to, and a shadow
            // is a filled shape rather than a ring, so left in line they are
            // laid over the very surfaces they are meant to sit under.
            z: -1
            target: modelData
            color: Appearance.colors.colBarShadow
        }
    }

    // Background. The container reaches the whole width so the curves beside
    // the body fall inside it: flattening a group clips to its bounds, and the
    // curves hang past the body's own. The fade lives here rather than in the
    // colors, so the lap between body and curve is blended once, not twice.
    Item {
        id: barSurface
        anchors.fill: parent
        visible: !root.floatSplit
        opacity: root.notchSeamFix ? Appearance.colors.colBarBackground.a : 1
        layer.enabled: root.notchSeamFix

    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
            leftMargin: root.floatSideInset
            rightMargin: root.floatSideInset
        }
        color: Config.options.bar.showBackground
            ? (root.notchSeamFix ? Appearance.colors.colBarBackgroundOpaque : Appearance.colors.colBarBackground)
            : "transparent"
        // Left for the shadow to read, the way the split surfaces leave theirs.
        radius: root.floatStyles ? Appearance.rounding.barFloat : 0
        // Set down on the docked edge, the pair touching it is squared off, and
        // so are the ends when the strip is asked for the whole width and
        // reaches the screen's own corners.
        readonly property real edgeCornerRadius: root.isNotch ? 0 : barBackground.radius
        readonly property real endRadius: (root.isNotch && root.floatSideInset <= 0) ? 0 : barBackground.radius
        topLeftRadius: Config.options.bar.bottom ? barBackground.endRadius : barBackground.edgeCornerRadius
        topRightRadius: Config.options.bar.bottom ? barBackground.endRadius : barBackground.edgeCornerRadius
        bottomLeftRadius: Config.options.bar.bottom ? barBackground.edgeCornerRadius : barBackground.endRadius
        bottomRightRadius: Config.options.bar.bottom ? barBackground.edgeCornerRadius : barBackground.endRadius
        // No outline while the curves at the ends are drawn beside the body:
        // they carry none of their own, so the body's would stop in mid air
        // where each one begins.
        border.width: Config.options.bar.cornerStyle === 1 && Config.options.bar.showBackground ? 1 : 0
        border.color: Appearance.colors.colBarBackgroundBorder

        Loader {
            anchors.fill: parent
            active: root.notchFlares
            sourceComponent: BarEndFlares {}
        }
    }
    }

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: root.floatSplit ? leftFloat.left : barSurface.left
            leftMargin: root.floatSplit ? 0 : root.floatSideInset
            right: root.floatSplit ? leftFloat.right : centerLeftFlank.left
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
            left: root.floatSplit ? rightFloat.left : centerRightFlank.right
            right: root.floatSplit ? rightFloat.right : barSurface.right
            rightMargin: root.floatSplit ? 0 : root.floatSideInset
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
            // Split, the surface budgets the same pad at both of its ends.
            anchors.leftMargin: root.floatSplit ? root.floatPad : 5
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
