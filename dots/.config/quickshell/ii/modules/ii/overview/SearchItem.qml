// pragma NativeMethodBehavior: AcceptThisObject
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

RippleButton {
    id: root
    property LauncherSearchResult entry
    property string query
    property bool isSeparator: entry?.isSeparator ?? false
    property bool entryShown: isSeparator || (entry?.shown ?? true)
    property string itemType: entry?.type ?? Translation.tr("App")
    property string itemName: entry?.name ?? ""
    property var iconType: entry?.iconType
    property string iconName: entry?.iconName ?? ""
    property var itemExecute: entry?.execute
    property var fontType: switch(entry?.fontType) {
        case LauncherSearchResult.FontType.Monospace:
            return "monospace"
        case LauncherSearchResult.FontType.Normal:
            return "main"
        default:
            return "main"
    }
    property string itemClickActionName: entry?.verb ?? "Open"
    property string bigText: entry?.iconType === LauncherSearchResult.IconType.Text ? entry?.iconName ?? "" : ""
    property string materialSymbol: entry.iconType === LauncherSearchResult.IconType.Material ? entry?.iconName ?? "" : ""
    property string cliphistRawString: entry?.rawValue ?? ""
    
    visible: root.entryShown
    enabled: !root.isSeparator
    focusPolicy: root.isSeparator ? Qt.NoFocus : Qt.StrongFocus
    property int horizontalMargin: 10
    property int buttonHorizontalPadding: 10
    property int buttonVerticalPadding: 6
    property bool keyboardDown: false
    readonly property bool selected: (root.hovered || root.focus)

    implicitHeight: root.isSeparator ? separatorItem.implicitHeight : (rowLayout.implicitHeight + root.buttonVerticalPadding * 2)
    implicitWidth: root.isSeparator ? separatorItem.implicitWidth : (rowLayout.implicitWidth + root.buttonHorizontalPadding * 2)
    buttonRadius: root.isSeparator ? 0 : Appearance.rounding.normal
    // A press that does not hover the row, as a touch does, paints the
    // ripple's own color, so the text keeps the fills it is held on.
    colBackground: root.isSeparator ? "transparent" :
        (root.down ? Appearance.launcherContent.colPrimaryContainerRipple :
        root.keyboardDown ? Appearance.launcherContent.colPrimaryContainerActive :
        (selected ? Appearance.launcherContent.colPrimaryContainer :
        ColorUtils.transparentize(Appearance.launcherContent.colPrimaryContainer, 1)))
    colBackgroundHover: root.isSeparator ? "transparent" : Appearance.launcherContent.colPrimaryContainer
    colRipple: root.isSeparator ? "transparent" : Appearance.launcherContent.colPrimaryContainerRipple
    // Held against the fills painted under it. The pointer on the row paints
    // the hover fill, which a pointer press spreads the ripple over; a key
    // pressed with the pointer elsewhere paints the pressed fill.
    property color colOnFill: root.down ? Appearance.launcherContent.colOnPrimaryContainerActive
        : (root.keyboardDown && !root.hovered) ? Appearance.launcherContent.colOnPrimaryContainerPressed
        : Appearance.launcherContent.colOnPrimaryContainer
    property color colForeground: selected ? colOnFill
        : root.down ? Appearance.launcherContent.m3onSurfaceOnRipple
        : root.keyboardDown ? Appearance.launcherContent.m3onSurfacePressed : Appearance.launcherContent.m3onSurface
    // The copied entry's check disc and its glyph, held on the fills the
    // text is held on; off a picked or pressed row the disc keeps the accent.
    property color colCheck: root.down ? Appearance.launcherContent.colPrimaryOnContainerActive
        : (root.keyboardDown && !root.hovered) ? Appearance.launcherContent.colPrimaryOnContainerPressed
        : root.selected ? Appearance.launcherContent.colPrimaryOnContainer : Appearance.launcherContent.colPrimary
    property color colOnCheck: root.down ? Appearance.launcherContent.colOnPrimaryOnContainerActive
        : (root.keyboardDown && !root.hovered) ? Appearance.launcherContent.colOnPrimaryOnContainerPressed
        : root.selected ? Appearance.launcherContent.colOnPrimaryOnContainer : Appearance.launcherContent.m3onPrimary

    // Separator divider line
    Item {
        id: separatorItem
        visible: root.isSeparator
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: 13

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 40
            height: 1
            color: Appearance.launcherContent.colOutlineVariant
        }
    }

    // The match letters lie on the same fill as the title. A picked row
    // shows its name without them, so they are held only on the fills a row
    // that is not picked paints: the panel, the ripple's color under a
    // press, and the pressed fill under a key pressed on it.
    readonly property color colHighlight: root.selected ? Appearance.launcherContent.colPrimaryInk
        : root.down ? Appearance.launcherContent.colPrimaryInkOnRipple
        : root.keyboardDown ? Appearance.launcherContent.colPrimaryInkPressed : Appearance.launcherContent.colPrimaryInk
    readonly property string highlightPrefix: `<u><font color="${root.colHighlight}">`
    readonly property string highlightSuffix: `</font></u>`
    // Note that this highlighting is independent from the search
    // It's close, but does not accurately represent how the fuzzy algorithm works
    function highlightContent(content, query) {
        if (!query || query.length === 0 || content == query || fontType === "monospace")
            return StringUtils.escapeHtml(content);

        let contentLower = content.toLowerCase();
        let queryLower = query.toLowerCase();

        let result = "";
        let lastIndex = 0;
        let qIndex = 0;

        for (let i = 0; i < content.length && qIndex < query.length; i++) {
            if (contentLower[i] === queryLower[qIndex]) {
                // Add non-highlighted part (escaped)
                if (i > lastIndex)
                    result += StringUtils.escapeHtml(content.slice(lastIndex, i));
                // Add highlighted character (escaped)
                result += root.highlightPrefix + StringUtils.escapeHtml(content[i]) + root.highlightSuffix;
                lastIndex = i + 1;
                qIndex++;
            }
        }
        // Add the rest of the string (escaped)
        if (lastIndex < content.length)
            result += StringUtils.escapeHtml(content.slice(lastIndex));

        return result;
    }
    property string displayContent: highlightContent(root.itemName, root.query)

    property list<string> urls: {
        if (!root.itemName) return [];
        // Regular expression to match URLs
        const urlRegex = /https?:\/\/[^\s<>"{}|\\^`[\]]+/gi;
        const matches = root.itemName?.match(urlRegex)
            ?.filter(url => !url.includes("…")) // Elided = invalid
        return matches ? matches : [];
    }
    
    PointingHandInteraction {}

    background {
        anchors.fill: root
        anchors.leftMargin: root.horizontalMargin
        anchors.rightMargin: root.horizontalMargin
    }

    onClicked: {
        GlobalStates.overviewOpen = false
        root.itemExecute()
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Delete && event.modifiers === Qt.ShiftModifier) {
            const deleteAction = root.entry.actions.find(action => action.name == Translation.tr("Delete"));

            if (deleteAction) {
                deleteAction.execute()
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = true
            root.clicked()
            event.accepted = true;
        }
    }
    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardDown = false
            event.accepted = true;
        }
    }

    RowLayout {
        id: rowLayout
        visible: !root.isSeparator
        spacing: iconLoader.sourceComponent === null ? 0 : 10
        anchors.fill: parent
        anchors.leftMargin: root.horizontalMargin + root.buttonHorizontalPadding
        anchors.rightMargin: root.horizontalMargin + root.buttonHorizontalPadding

        // Icon
        Loader {
            id: iconLoader
            active: true
            sourceComponent: switch(root.iconType) {
                case LauncherSearchResult.IconType.Material:
                    return materialSymbolComponent
                case LauncherSearchResult.IconType.Text:
                    return bigTextComponent
                case LauncherSearchResult.IconType.System:
                    return iconImageComponent
                case LauncherSearchResult.IconType.None:
                    return null
                default:
                    return null
            }
        }

        Component {
            id: iconImageComponent
            IconImage {
                source: Quickshell.iconPath(root.iconName, "image-missing")
                width: 35
                height: 35
            }
        }

        Component {
            id: materialSymbolComponent
            MaterialSymbol {
                text: root.materialSymbol
                iconSize: 30
                color: root.colForeground
            }
        }

        Component {
            id: bigTextComponent
            StyledText {
                text: root.bigText
                font.pixelSize: Appearance.font.pixelSize.larger
                color: root.colForeground
            }
        }

        // Main text
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.selected ? root.colOnFill
                    : root.down ? Appearance.launcherContent.colSubtextOnRipple
                    : root.keyboardDown ? Appearance.launcherContent.colSubtextPressed : Appearance.launcherContent.colSubtextRead
                visible: root.itemType && root.itemType != Translation.tr("App")
                text: root.itemType
            }
            RowLayout {
                Loader { // Checkmark for copied clipboard entry
                    visible: itemName == Quickshell.clipboardText && root.cliphistRawString
                    active: itemName == Quickshell.clipboardText && root.cliphistRawString
                    sourceComponent: Rectangle {
                        implicitWidth: activeText.implicitHeight
                        implicitHeight: activeText.implicitHeight
                        radius: Appearance.rounding.full
                        color: root.colCheck
                        MaterialSymbol {
                            id: activeText
                            anchors.centerIn: parent
                            text: "check"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: root.colOnCheck
                        }
                    }
                }
                Repeater { // Favicons for links
                    model: root.query == root.itemName ? [] : root.urls
                    Favicon {
                        required property var modelData
                        size: parent.height
                        url: modelData
                    }
                }
                StyledText { // Item name/content
                    Layout.fillWidth: true
                    id: nameText
                    textFormat: Text.StyledText // RichText also works, but StyledText ensures elide work
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family[root.fontType]
                    color: root.colForeground
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    text: root.selected ? StringUtils.escapeHtml(root.itemName) : root.displayContent
                }
            }
            Loader { // Clipboard image preview
                active: root.cliphistRawString && Cliphist.entryIsImage(root.cliphistRawString)
                sourceComponent: CliphistImage {
                    Layout.fillWidth: true
                    entry: root.cliphistRawString
                    maxWidth: contentColumn.width
                    maxHeight: 140
                }
            }
        }

        // Action text
        StyledText {
            Layout.fillWidth: false
            visible: root.selected
            id: clickAction
            font.pixelSize: Appearance.font.pixelSize.normal
            color: root.colOnFill
            horizontalAlignment: Text.AlignRight
            text: root.itemClickActionName
        }

        RowLayout {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: root.buttonVerticalPadding
            Layout.bottomMargin: -root.buttonVerticalPadding // Why is this necessary? Good question.
            spacing: 4
            Repeater {
                model: (root.entry.actions ?? []).slice(0, 4)
                delegate: RippleButton {
                    id: actionButton
                    required property var modelData
                    property var iconType: modelData.iconType
                    property string iconName: modelData.iconName ?? ""
                    implicitHeight: 34
                    implicitWidth: 34

                    colBackgroundHover: Appearance.launcherContent.colActionHover
                    colRipple: Appearance.launcherContent.colActionRipple

                    contentItem: Item {
                        id: actionContentItem
                        anchors.centerIn: parent
                        Loader {
                            anchors.centerIn: parent
                            active: actionButton.iconType === LauncherSearchResult.IconType.Material || actionButton.iconName === ""
                            sourceComponent: MaterialSymbol {
                                text: actionButton.iconName || "video_settings"
                                font.pixelSize: Appearance.font.pixelSize.hugeass
                                color: actionButton.down ? Appearance.launcherContent.colOnActionActive :
                                    (actionButton.hovered ? Appearance.launcherContent.colOnActionHover : root.colForeground)
                            }
                        }
                        Loader {
                            anchors.centerIn: parent
                            active: actionButton.iconType === LauncherSearchResult.IconType.System && actionButton.iconName !== ""
                            sourceComponent: IconImage {
                                source: Quickshell.iconPath(actionButton.iconName)
                                implicitSize: 20
                            }
                        }
                    }

                    onClicked: modelData.execute()

                    StyledToolTip {
                        text: modelData.name
                    }
                }
            }
        }

    }
}
