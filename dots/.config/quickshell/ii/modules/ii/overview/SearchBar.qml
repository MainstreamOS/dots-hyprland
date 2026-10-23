pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    property var contentColors: Appearance.launcherContent
    property bool quietStyle: false
    property real uiScale: 1
    spacing: 6 * root.uiScale
    readonly property real actionSize: 40 * uiScale
    readonly property real searchIconSize: 22 * uiScale
    readonly property real preferredWidth: searchInput.implicitWidth + searchIconSize
        + 8 * uiScale + actionSize * 3 + spacing * 4 + 4 * uiScale
    property bool animateWidth: false
    property alias searchInput: searchInput
    property string searchingText
    property bool inputFocused: GlobalStates.overviewOpen
    property bool fillSearchWidth: false
    property bool synchronizeQuery: true
    property bool completeFirstResult: true
    property var dismiss: () => { GlobalStates.overviewOpen = false; }
    signal accepted()
    signal keyPressed(var event)

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, DefaultSearch }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }
    
    MaterialShapeWrappedMaterialSymbol {
        id: searchIcon
        visible: !root.quietStyle
        Layout.alignment: Qt.AlignVCenter
        iconSize: Appearance.font.pixelSize.huge * root.uiScale
        padding: 6 * root.uiScale
        color: root.contentColors.colSecondaryContainer
        colSymbol: root.contentColors.colOnSecondaryContainer
        shape: switch(root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return MaterialShape.Shape.Pill;
            case SearchBar.SearchPrefixType.App: return MaterialShape.Shape.Clover4Leaf;
            case SearchBar.SearchPrefixType.Clipboard: return MaterialShape.Shape.Gem;
            case SearchBar.SearchPrefixType.Emojis: return MaterialShape.Shape.Sunny;
            case SearchBar.SearchPrefixType.Math: return MaterialShape.Shape.PuffyDiamond;
            case SearchBar.SearchPrefixType.ShellCommand: return MaterialShape.Shape.PixelCircle;
            case SearchBar.SearchPrefixType.WebSearch: return MaterialShape.Shape.SoftBurst;
            default: return MaterialShape.Shape.Cookie7Sided;
        }
        text: switch (root.searchPrefixType) {
            case SearchBar.SearchPrefixType.Action: return "settings_suggest";
            case SearchBar.SearchPrefixType.App: return "apps";
            case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
            case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
            case SearchBar.SearchPrefixType.Math: return "calculate";
            case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
            case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
            case SearchBar.SearchPrefixType.DefaultSearch: return "search";
            default: return "search";
        }
    }
    MaterialSymbol {
        visible: root.quietStyle
        Layout.minimumWidth: root.searchIconSize
        Layout.maximumWidth: root.searchIconSize
        Layout.minimumHeight: root.searchIconSize
        Layout.maximumHeight: root.searchIconSize
        Layout.leftMargin: 8 * root.uiScale
        Layout.alignment: Qt.AlignVCenter
        text: searchIcon.text
        iconSize: 22 * root.uiScale
        color: root.contentColors.colOnLayer0
    }
    ToolbarTextField { // Search box
        id: searchInput
        Layout.topMargin: 4 * root.uiScale
        Layout.bottomMargin: 4 * root.uiScale
        Layout.fillWidth: root.fillSearchWidth
        Layout.minimumWidth: root.fillSearchWidth ? 0 : -1
        implicitHeight: 40 * root.uiScale
        focus: root.inputFocused
        font.pixelSize: Appearance.font.pixelSize.small * root.uiScale
        padding: 10 * root.uiScale
        colBackground: root.quietStyle ? "transparent" : root.contentColors.colLayer1
        radius: RoundedCorners.on ? Appearance.rounding.full * root.uiScale : 0
        color: root.quietStyle ? root.contentColors.colOnLayer0 : root.contentColors.colOnLayer1Field
        placeholderTextColor: root.quietStyle ? root.contentColors.colSubtext : root.contentColors.colSubtextField
        selectedTextColor: root.contentColors.colOnSecondaryContainer
        selectionColor: root.contentColors.colSecondaryContainer
        placeholderText: Translation.tr("Search, calculate or run")
        implicitWidth: (root.searchingText == "" ? Appearance.sizes.searchWidthCollapsed : Appearance.sizes.searchWidth) * root.uiScale

        Behavior on implicitWidth {
            id: searchWidthBehavior
            enabled: root.animateWidth
            NumberAnimation {
                duration: 300
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }

        onTextChanged: if (root.synchronizeQuery) LauncherSearch.query = text
        onAccepted: root.accepted()

        Keys.onPressed: event => {
            root.keyPressed(event);
            if (event.accepted) return;
            if (event.key === Qt.Key_Tab && root.completeFirstResult) {
                if (LauncherSearch.results.length === 0) return;
                const tabbedText = LauncherSearch.results[0].name;
                LauncherSearch.query = tabbedText;
                searchInput.text = tabbedText;
                event.accepted = true;
            }
        }
    }

    SearchActionButton {
        uiScale: root.uiScale
        fixedWidth: root.quietStyle ? root.actionSize : 0
        Layout.topMargin: 4 * root.uiScale
        Layout.bottomMargin: 4 * root.uiScale
        colBackgroundHover: root.contentColors.colLayer1Hover
        colRipple: root.contentColors.colLayer1Active
        colText: (hovered || down) ? root.contentColors.colOnSurfaceVariantHover : root.contentColors.colOnSurfaceVariant
        onClicked: {
            root.dismiss();
            lensDelayTimer.start();
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Google Lens")
        }

        Timer {
            id: lensDelayTimer
            interval: 125
            repeat: false
            onTriggered: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"])
        }
    }

    SearchActionButton {
        uiScale: root.uiScale
        fixedWidth: root.quietStyle ? root.actionSize : 0
        id: songRecButton
        Layout.topMargin: 4 * root.uiScale
        Layout.bottomMargin: 4 * root.uiScale
        toggled: SongRec.running
        onClicked: SongRec.toggleRunning()
        text: "music_cast"

        StyledToolTip {
            text: Translation.tr("Recognize music")
        }

        colText: toggled ? root.contentColors.colOnPrimaryToggle
            : hovered ? root.contentColors.colOnSurfaceVariantHigh : root.contentColors.colOnSurfaceVariant
        background: MaterialShape {
            RotationAnimation on rotation {
                running: songRecButton.toggled
                duration: 12000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                from: 0
                to: 360
            }
            shape: {
                if (songRecButton.down) {
                    return songRecButton.toggled ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square
                } else {
                    return songRecButton.toggled ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle
                }
            }
            color: {
                if (songRecButton.toggled) {
                    return songRecButton.hovered ? root.contentColors.colPrimaryToggleHover : root.contentColors.colPrimary
                } else {
                    return songRecButton.hovered ? root.contentColors.colSurfaceContainerHigh : ColorUtils.transparentize(root.contentColors.colSurfaceContainerHigh)
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    SearchActionButton {
        uiScale: root.uiScale
        fixedWidth: root.quietStyle ? root.actionSize : 0
        Layout.topMargin: 4 * root.uiScale
        Layout.bottomMargin: 4 * root.uiScale
        Layout.rightMargin: 4 * root.uiScale
        colBackgroundHover: root.contentColors.colLayer1Hover
        colRipple: root.contentColors.colLayer1Active
        colText: (hovered || down) ? root.contentColors.colOnSurfaceVariantHover : root.contentColors.colOnSurfaceVariant
        onClicked: {
            root.dismiss();
            GlobalStates.sessionOpen = true;
        }
        text: "power_settings_new"
        StyledToolTip {
            text: Translation.tr("Session")
        }
    }
}
