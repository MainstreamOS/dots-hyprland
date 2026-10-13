import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    // Guarded wherever the strings below read it. A chat being torn down can
    // have its translated strings asked for a value once more after its own
    // id has gone. Nothing shows them by then, so they are left empty rather
    // than reaching through an id that is no longer there.
    property string commandPrefix: "/"
    property var scopeRoot: null
    // False while the sidebar is closed or another tab is on show.
    property bool onScreen: true
    readonly property int clipboardInsertLimit: 50000

    property var suggestionQuery: ""
    property var suggestionList: []

    readonly property bool anySheetShown: [modelSheetLoader, executionModeSheetLoader, reasoningSheetLoader, fileSheetLoader]
        .some(loader => loader.shown)

    // The keyring is left closed at startup when nobody typed its password, so
    // the API keys are read here, when the chat is opened or switched to a model
    // that needs one. Asking now, while someone is using the chat, beats asking
    // the moment the desktop appears.
    function loadApiKeysIfNeeded() {
        if (Ai.currentModel?.requires_key && !KeyringStorage.loaded)
            KeyringStorage.fetchKeyringData();
    }
    Component.onCompleted: loadApiKeysIfNeeded()
    Connections {
        target: Ai
        function onCurrentModelIdChanged() {
            root.loadApiKeysIfNeeded();
        }
    }
    onOnScreenChanged: {
        if (!root.onScreen)
            return;
        // Nothing is laid out while hidden, so a followed reply takes its new height on showing.
        messageListView.holdLonger();
    }

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        if (root.anySheetShown)
            return;
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.pageBy(-messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.pageBy(messageListView.height / 2);
                event.accepted = true;
            }
        } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
            event.accepted = true;
        }
    }

    function focusInput(): void {
        Qt.callLater(() => root.inputField.forceActiveFocus());
    }

    function openModelSheet(): void {
        modelSheetLoader.load().open();
    }
    function openExecutionModeSheet(): void {
        executionModeSheetLoader.load().open();
    }
    function openReasoningSheet(): void {
        reasoningSheetLoader.load().open();
    }
    function openFileSheet(): void {
        fileSheetLoader.load().open();
    }

    function prefillInput(text: string): void {
        if (messageInputField.readOnly)
            return;
        messageInputField.text = text;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function postNotice(text: string): void {
        Ai.addMessage(text, Ai.interfaceRole, { persist: false });
    }

    function setMode(id: string): bool {
        if (!AiModes.set(id))
            return false;
        Ai.addMessage(Translation.tr("Execution mode set to %1").arg(AiModes.name(id)), Ai.interfaceRole);
        return true;
    }

    // The clipboard can hold a whole log; laying out megabytes in the input
    // would stall the sidebar.
    function clipboardTextCapped(): string {
        const text = Quickshell.clipboardText ?? "";
        if (text.length <= root.clipboardInsertLimit)
            return text;
        let end = root.clipboardInsertLimit;
        const last = text.charCodeAt(end - 1);
        if (last >= 0xD800 && last <= 0xDBFF)
            end -= 1;
        root.postNotice(Translation.tr("The clipboard text was cut to 50,000 characters."));
        return text.slice(0, end);
    }

    function isAutoThinkingLevel(level): bool {
        const lvl = (level || "").toLowerCase();
        return lvl === "" || lvl === "auto" || lvl === "default";
    }

    function formatTokenCount(count): string {
        if (count === undefined || count === null || count < 0) return "";
        if (count < 1000) return count.toString();
        const k = count / 1000;
        const kValue = k >= 100 ? Math.round(k) : (Math.round(k * 10) / 10);
        if (kValue < 1000) return kValue + "k";
        const m = count / 1000000;
        const mValue = m >= 10 ? Math.round(m) : (Math.round(m * 10) / 10);
        return mValue + "M";
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file"),
            execute: args => {
                if (args.length === 0) {
                    root.openFileSheet();
                    return;
                }
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "mode",
            description: Translation.tr("Set execution mode: ask, auto, or plan"),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.addMessage(Translation.tr("Current mode: %1\nUsage: %2mode [ask|auto|plan]").arg(AiModes.name(AiModes.current)).arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                if (!root.setMode(args[0]))
                    Ai.addMessage(Translation.tr("Invalid mode. Supported: ask, auto, plan"), Ai.interfaceRole);
            }
        },
        {
            name: "auto",
            description: Translation.tr("Toggle Auto mode (auto-approve all tools and commands)"),
            execute: () => root.setMode(AiModes.current === "auto" ? "ask" : "auto")
        },
        {
            name: "plan",
            description: Translation.tr("Toggle Plan mode (architectural planning without executing edits)"),
            execute: () => root.setMode(AiModes.current === "plan" ? "ask" : "plan")
        },
        {
            name: "ollama",
            description: Translation.tr("Set up local AI"),
            // Kept out of the command list: local AI is reached by picking it
            // under /model, and offering it here as well puts a second door on
            // one room. It still runs when typed, which is what the setup
            // walkthrough tells the user to do to fetch a model.
            hidden: true,
            execute: args => {
                const action = (args[0] ?? "").toLowerCase();
                if (action === "pull") {
                    Ai.pullOllamaModel(args.slice(1).join(" "));
                } else if (action.length === 0 || action === "status") {
                    Ai.startOllamaWalkthrough();
                } else {
                    Ai.addMessage(Translation.tr("Usage: %1ollama pull MODEL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                }
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "style",
            description: Translation.tr("Set response style (precise, balanced, creative). Controls sampling temperature for applicable models."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    Ai.printResponseStyle();
                } else {
                    Ai.setResponseStyle(args[0]);
                }
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set sampling temperature (0-1). Note: Gemini 3 series and CLI models use default sampling; adjust thinking level with /think instead."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    if (!isNaN(temp)) {
                        Ai.setTemperature(temp);
                    } else {
                        Ai.setResponseStyle(args[0]);
                    }
                }
            }
        },
        {
            name: "think",
            description: Translation.tr("Set thinking level (reasoning effort). Values: minimal, low, medium, high, auto. Replaces deprecated thinking budget."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    Ai.printThinkingLevel();
                } else {
                    Ai.setThinkingLevel(args[0]);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        },
    ]

    function handleInput(inputText): bool {
        const isCommand = inputText.startsWith(root.commandPrefix);
        if (!isCommand && Ai.isGenerating)
            return false;
        if (isCommand) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
            messageListView.pinToEnd();
            return true;
        }
        const sent = Ai.sendUserMessage(inputText);
        if (sent)
            messageListView.pinToEnd();
        return sent;
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", '[ -f "$1" ] || printf \'%s\\n\' "$2" | "$3" decode > "$1"',
                "_", imageDecodeFilePath, entry, Cliphist.cliphistBinary]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string text: ""
        property bool compact: statusBg.compact
        readonly property string statusText: compact ? "" : text
        property string description
        property bool clickable: true
        hoverEnabled: true
        cursorShape: clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        implicitHeight: statusItemRow.implicitHeight
        implicitWidth: statusItemRow.implicitWidth

        readonly property real fullWidth: Math.max(iconSymbol.implicitWidth, Appearance.font.pixelSize.huge) + (statusItem.text.length > 0 ? (textLabel.implicitWidth + statusItemRow.spacing) : 0)

        Row {
            id: statusItemRow
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            MaterialSymbol {
                id: iconSymbol
                anchors.verticalCenter: parent.verticalCenter
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: (statusItem.containsMouse && statusItem.clickable) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                id: textLabel
                anchors.verticalCenter: parent.verticalCenter
                visible: statusItem.statusText.length > 0
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.text
                color: (statusItem.containsMouse && statusItem.clickable) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StarterChip: Item {
        id: chipRoot
        property string icon
        property string title
        signal clicked()

        Layout.fillWidth: true
        implicitHeight: 38

        RippleButton {
            id: chip
            anchors.fill: parent
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: chipRoot.clicked()

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                MaterialSymbol {
                    text: chipRoot.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: chipRoot.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    text: "arrow_forward"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    component ShortcutControlRow: Item {
        id: rowRoot
        property string icon
        property string label
        signal clicked()

        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: 36

        RippleButton {
            id: button
            anchors.fill: parent
            buttonRadius: Appearance.rounding.verysmall
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: rowRoot.clicked()

            contentItem: RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                MaterialSymbol {
                    text: rowRoot.icon
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: rowRoot.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurface
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    text: "arrow_forward"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    component StatusSeparator: Rectangle {
        required property Item next
        visible: next.visible && statusBg.hasVisibleBefore(next)
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                // The mask is stretched over the area, so its size sets the corner
                // shape; it takes the page's size, as the sidebar's page view does.
                maskSource: Rectangle {
                    width: root.width
                    height: root.height
                    radius: Appearance.rounding.small
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                readonly property list<Item> items: [responseStyleStatusItem, keyStatusItem, reasoningStatusItem, newChatStatusItem, tokenCountStatusItem]
                // A separator shows before an item only when some item to its left shows too.
                function hasVisibleBefore(item: Item): bool {
                    for (const other of statusBg.items) {
                        if (other === item)
                            return false;
                        if (other.visible)
                            return true;
                    }
                    return false;
                }
                readonly property real fullContentWidth: {
                    let w = 0;
                    let count = 0;
                    for (const item of statusBg.items) {
                        if (!item.visible)
                            continue;
                        w += item.fullWidth;
                        count++;
                    }
                    if (count > 1) {
                        const sepCount = count - 1;
                        w += (sepCount * 4) + (sepCount * 2 * 8);
                    }
                    return w + 20;
                }
                readonly property bool compact: parent ? (fullContentWidth > (parent.width - 24)) : false
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                width: Math.min(parent.width - 16, implicitWidth)
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                clip: true
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: statusBg.compact ? 6 : 8

                    StatusItem {
                        id: responseStyleStatusItem
                        visible: Boolean(Ai.currentModel?.sendTemperature !== false)
                        readonly property var styleInfo: {
                            const temp = Ai.temperature;
                            const style = Ai.responseStyleId(temp);
                            if (style === "precise") {
                                return {
                                    icon: "target",
                                    desc: Translation.tr("Response style: Precise (%1)\nBest for code, syntax, and factual lookups\nClick to switch to Balanced").arg(temp.toFixed(1))
                                };
                            } else if (style === "balanced") {
                                return {
                                    icon: "balance",
                                    desc: Translation.tr("Response style: Balanced (%1)\nNatural conversational tone for everyday tasks\nClick to switch to Creative").arg(temp.toFixed(1))
                                };
                            } else {
                                return {
                                    icon: "auto_awesome",
                                    desc: Translation.tr("Response style: Creative (%1)\nBest for brainstorming, ideas, and open-ended writing\nClick to switch to Precise").arg(temp.toFixed(1))
                                };
                            }
                        }
                        icon: styleInfo.icon
                        text: Ai.getResponseStyleName(Ai.temperature)
                        description: styleInfo.desc
                        onClicked: Ai.cycleResponseStyle()
                    }
                    StatusSeparator {
                        next: keyStatusItem
                    }
                    StatusItem {
                        id: keyStatusItem
                        visible: Boolean(Ai.currentModel?.requires_key)
                        icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                        text: ""
                        description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nClick to switch model") : Translation.tr("No API key\nClick to set it with /key")
                        onClicked: {
                            if (Ai.currentModelHasApiKey)
                                root.openModelSheet();
                            else
                                root.prefillInput(root.commandPrefix + "key ");
                        }
                    }
                    StatusSeparator {
                        next: reasoningStatusItem
                    }
                    StatusItem {
                        id: reasoningStatusItem
                        icon: "psychology"
                        readonly property string label: root.isAutoThinkingLevel(Ai.thinkingLevel) ? Translation.tr("think") : Ai.thinkingLevelName(Ai.thinkingLevel)
                        text: label
                        description: Translation.tr("Reasoning effort: %1\nClick to choose reasoning depth").arg(label)
                        onClicked: root.openReasoningSheet()
                    }
                    StatusSeparator {
                        next: newChatStatusItem
                    }
                    StatusItem {
                        id: newChatStatusItem
                        icon: "add"
                        text: Translation.tr("New")
                        description: Translation.tr("Start fresh chat (Ctrl+Shift+O)")
                        onClicked: Ai.clearMessages()
                    }
                    StatusSeparator {
                        next: tokenCountStatusItem
                    }
                    StatusItem {
                        id: tokenCountStatusItem
                        visible: Ai.tokenCount.total > 0
                        compact: false
                        clickable: false
                        icon: "token"
                        text: root.formatTokenCount(Ai.tokenCount.total)
                        description: Translation.tr("Total token count: %1\nInput: %2 · Output: %3").arg(Ai.tokenCount.total).arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                    }
                }
            }

            ScrollEdgeFade {
                id: messageEdgeFade
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 10
                popin: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                // Slack below the end while it can shrink under the view (a followed reply
                // dipping for a pass, rows leaving the end): a tight end would clamp the view up.
                bottomMargin: slack ? height : followGlow
                wheelBottomReach: followGlow
                // The list's own moves land at once; the reader's wheel keeps its easing.
                smoothScroll: !parking && (!holding || wheelScrolling)

                // The newest line stays above the bottom edge. Scrolling up stops that;
                // scrolling back near the end, sending or Scroll to Bottom resumes it.
                property bool following: true
                readonly property real followGlow: messageEdgeFade.fadeSize
                readonly property bool holding: following && (Ai.isGenerating || followHoldTimer.running)
                property real parkedY: NaN
                property real lastContentY: 0
                property int laidOutCount: 0
                property int seenCount: 0
                property int recoveries: 0
                property bool resized: false
                property bool parking: false
                property bool jumpPending: false
                property bool settleWanted: false
                property bool latchPending: false
                property bool continuing: false
                // Set outside the list's layout only: by the settle, or before rows leave the end.
                property bool slack: false
                // Rows left the end and the list has not laid that out yet.
                property bool modelPending: false
                property int idCount: 0
                property string tailId: ""
                // Following began below the end of a reply shorter than the one it replaced:
                // the reply grows into the view instead of the view moving up to meet it.
                property bool ahead: false
                // A move up in steps over rows the list has made; peeked when the step made
                // the row above and it has not been laid out yet.
                property bool climbing: false
                property bool peeked: false
                property real climbFrom: Infinity

                // The last row's real end: the list's own end is estimated from rows it
                // has not created and shifts as rows above are created and released.
                function followTarget(): real {
                    const tail = itemAtIndex(count - 1);
                    if (!tail)
                        return NaN;
                    return Math.round(Math.max(originY - topMargin, tail.y + tail.height + followGlow - height));
                }
                function nearEnd(): bool {
                    return nearEndAt(contentY, false);
                }
                function nearEndAt(y: real, strict: bool): bool {
                    const target = followTarget();
                    // A streaming end moves too fast to land on exactly.
                    return !isNaN(target) && y >= target - (Ai.isGenerating && !strict ? Math.max(160, height * 0.35) : 1);
                }
                function lastLiveRow(): var {
                    for (let i = count - 1; i >= Math.max(0, count - 50); i--) {
                        const row = itemAtIndex(i);
                        if (row)
                            return row;
                    }
                    return null;
                }
                // The top of the rows made at the end of the list. A row above it would be
                // made inside the view at a guessed height and push the rows below down as it grows.
                function climbLimit(): real {
                    let i = count - 1;
                    while (i > 0 && itemAtIndex(i - 1))
                        i--;
                    const row = itemAtIndex(i);
                    return (i > 0 && row) ? row.y : -Infinity;
                }
                function moveTo(y: real): void {
                    if (Math.abs(y - contentY) < 0.5)
                        return;
                    parking = true;
                    contentY = y;
                    parking = false;
                }
                function park(y: real): void {
                    followShrinkTimer.stop();
                    const top = y < contentY - 0.5 ? (peeked ? contentY : climbLimit()) : -Infinity;
                    if (y < top && !climbing)
                        climbFrom = Infinity;
                    climbing = y < top;
                    moveTo(Math.max(y, top));
                    parkedY = contentY;
                    ahead = false;
                }
                // Steps a pixel past the top so the list makes the row above while it still
                // ends above the view: laid out next frame, it grows upward, not into the view.
                function climbStep(): void {
                    const top = climbLimit();
                    climbing = Math.abs(contentY - top) < 0.5 && top < climbFrom;
                    if (!climbing)
                        return;
                    climbFrom = top;
                    peeked = true;
                    moveTo(top - spacing - 1);
                    moveTo(top);
                }
                // Rows a jump creates take their height in the next layout, so
                // parking waits for it. NaN jumps to the list's own end.
                function jump(y: real): void {
                    followShrinkTimer.stop();
                    climbing = false;
                    ahead = false;
                    parking = true;
                    if (isNaN(y))
                        positionViewAtEnd();
                    else
                        contentY = y;
                    parking = false;
                    parkedY = NaN;
                    jumpPending = true;
                    followJumpTimer.restart();
                }
                // The settle runs once after the frame's layout, before it is drawn, or on
                // the next pass when no frame comes.
                function requestSettle(): void {
                    settleWanted = true;
                    Qt.callLater(messageListView.settleFollow);
                }
                function settleFollow(): void {
                    continuing = false;
                    // Rows still waiting for the list's layout; that layout settles again.
                    if (!settleWanted || count !== laidOutCount)
                        return;
                    settleWanted = false;
                    if (latchPending && !following && !userScrolling && nearEnd()) {
                        latchPending = false;
                        following = true;
                        recoveries = 0;
                        ahead = contentY > followTarget() + 0.5;
                    }
                    if (count === 0)
                        following = true;
                    if (following && (count > seenCount || resized))
                        followHoldTimer.restart();
                    seenCount = count;
                    const wasResized = resized;
                    resized = false;
                    const target = followTarget();
                    // Dropped only where a tight end cannot clamp the view.
                    const wantSlack = holding || modelPending || contentY > target + 0.5;
                    if (slack !== wantSlack && !chatScrollBar.pressed)
                        slack = wantSlack;
                    if (!following || userScrolling || jumpPending)
                        return;
                    if (isNaN(target)) {
                        if (count === 0)
                            return;
                        const row = lastLiveRow();
                        if (!holding || !row || recoveries >= 8) {
                            following = false;
                            return;
                        }
                        // Rows above the newest one grew past the rows the list keeps.
                        // The last row it still has is real and leads toward the end.
                        recoveries++;
                        jump(Math.round(row.y + row.height));
                        return;
                    }
                    recoveries = 0;
                    if (!holding && !climbing) {
                        // Grown by hand (a block opened): the reader stays put.
                        if (target > contentY + 1)
                            following = false;
                        return;
                    }
                    if (target < contentY - 0.5 && !wasResized && !climbing) {
                        if (ahead)
                            return;
                        // Rows refill a dip a pass or two later; only a lasting shrink moves the view.
                        if (Math.abs(contentY - parkedY) < 0.5) {
                            if (!followShrinkTimer.running || target < followShrinkTimer.low)
                                followShrinkTimer.restart();
                            followShrinkTimer.low = target;
                            return;
                        }
                    }
                    park(target);
                }
                function holdLonger(): void {
                    if (following)
                        followHoldTimer.restart();
                }
                function pinToEnd(): void {
                    following = true;
                    recoveries = 0;
                    followHoldTimer.restart();
                    const target = followTarget();
                    if (isNaN(target))
                        jump(NaN);
                    else
                        park(target);
                }
                // Moving up leaves the end; moving back down near it follows again, by
                // a pixel at least since the list rounds its position after a move.
                function readerMoved(y: real, dy: real): void {
                    latchPending = false;
                    if (dy <= -1 && following) {
                        const target = followTarget();
                        if (isNaN(target) || y < target - 1)
                            following = false;
                    } else if (dy >= 1 && !following && nearEndAt(y, false)) {
                        following = true;
                        recoveries = 0;
                        // Holding turns the easing off, so a paged move lands before the settle reads it.
                        followHoldTimer.restart();
                        requestSettle();
                    }
                }
                function pageBy(dy: real): void {
                    const y = clampToWheelRange(contentY + dy);
                    readerMoved(y, dy);
                    contentY = y;
                }

                Component.onCompleted: {
                    following = Ai.messageIDs.length === 0;
                    laidOutCount = count;
                    seenCount = count;
                    idCount = Ai.messageIDs.length;
                    tailId = Ai.messageIDs[idCount - 1] ?? "";
                }

                Timer {
                    id: followJumpTimer
                    // In case the jump changed no row heights.
                    interval: 100
                    onTriggered: {
                        messageListView.jumpPending = false;
                        messageListView.requestSettle();
                    }
                }
                Timer {
                    id: followHoldTimer
                    // Rows still lay out for a few passes after a reply ends, a row
                    // arrives or the view resizes.
                    interval: 1000
                    onTriggered: {
                        const target = messageListView.followTarget();
                        if (!Ai.isGenerating && messageListView.following && !messageListView.userScrolling && !isNaN(target)
                                && !messageListView.ahead)
                            messageListView.park(target);
                    }
                }
                Timer {
                    id: followShrinkTimer
                    property real low: 0
                    interval: 300
                    onTriggered: {
                        const target = messageListView.followTarget();
                        // A streaming reply grows back over a small gap, so until it ends only a
                        // large one moves the view up.
                        if (messageListView.holding && !messageListView.userScrolling && !isNaN(target)
                                && (!Ai.isGenerating || messageListView.contentY - target > messageListView.height / 2))
                            messageListView.park(target);
                    }
                }
                Connections {
                    target: Ai
                    function onIsGeneratingChanged() {
                        const v = messageListView;
                        if (Ai.isGenerating) {
                            // The rows this request adds are laid out later, so the settle checks the end.
                            // A request that continues the one just ended leaves the reader where they are.
                            v.latchPending = !v.following && !v.continuing;
                        } else {
                            v.latchPending = false;
                            v.continuing = true;
                            v.holdLonger();
                        }
                        v.requestSettle();
                    }
                    function onSessionLoadingChanged() {
                        // A loaded chat opens where the list puts it, not at its end.
                        if (!Ai.sessionLoading && Ai.messageIDs.length > 0)
                            messageListView.following = false;
                    }
                    // Rows leaving the end shorten it before the list lays them out, from estimates
                    // the removed rows shaped; the slack keeps that from clamping the view onto other rows.
                    function onMessageIDsChanged() {
                        const v = messageListView;
                        const ids = Ai.messageIDs;
                        const grew = ids.length > v.idCount && (v.idCount === 0 || ids[v.idCount - 1] === v.tailId || ids[ids.length - 1] === v.tailId);
                        v.idCount = ids.length;
                        v.tailId = ids[ids.length - 1] ?? "";
                        if (grew || chatScrollBar.pressed)
                            return;
                        v.slack = true;
                        v.modelPending = true;
                        v.requestSettle();
                    }
                }
                Connections {
                    target: LatexRenderer
                    // A formula rendered after the reply ended still grows it. Posted, since a
                    // cached image is reported from inside row creation.
                    function onRenderFinished() {
                        if (messageListView.following)
                            Qt.callLater(messageListView.holdLonger);
                    }
                }
                Connections {
                    target: messageListView.Window.window
                    enabled: messageListView.settleWanted || messageListView.modelPending || messageListView.climbing
                    // The end moves in the frame that grew it rather than in one more frame.
                    function onAfterAnimating() {
                        const v = messageListView;
                        // This frame's layout has applied the model and laid out a peeked row.
                        v.peeked = false;
                        if (v.modelPending || v.climbing)
                            v.settleWanted = true;
                        v.modelPending = false;
                        v.settleFollow();
                        if (v.climbing && v.following && !v.userScrolling && !v.jumpPending)
                            v.climbStep();
                    }
                }

                // While the scrollbar handle is held, streamed growth keeps
                // remapping the same hand position onto a longer range, which
                // yanked the view on every chunk. The bar remembers where the
                // hand actually put the view and growth restores that anchor;
                // real hand movement updates it.
                ScrollBar.vertical: StyledScrollBar {
                    id: chatScrollBar
                    property bool compensating: false
                    property real anchorY: 0
                    property real pressY: 0
                    // Whether the hand left the view at the end; growth while it holds moves the end away.
                    property bool anchorAtEnd: false
                    onPressedChanged: {
                        if (pressed) {
                            pressY = messageListView.contentY;
                            anchorY = pressY;
                            anchorAtEnd = messageListView.nearEnd();
                        } else {
                            messageListView.latchPending = false;
                            // As with the wheel, a hand that went up follows only from the very end.
                            if (Math.abs(messageListView.contentY - pressY) >= 1)
                                messageListView.following = anchorAtEnd || messageListView.nearEndAt(messageListView.contentY, messageListView.contentY < pressY);
                        }
                    }
                }
                onContentHeightChanged: {
                    if (chatScrollBar.pressed) {
                        chatScrollBar.compensating = true;
                        contentY = chatScrollBar.anchorY;
                        chatScrollBar.compensating = false;
                    }
                    if (!parking)
                        jumpPending = false;
                    requestSettle();
                }
                onCountChanged: {
                    laidOutCount = count;
                    requestSettle();
                }
                onHeightChanged: {
                    resized = true;
                    requestSettle();
                }
                onWidthChanged: {
                    resized = true;
                    requestSettle();
                }
                onUserScrollingChanged: if (!userScrolling) requestSettle()
                onHoldingChanged: requestSettle()
                onFollowingChanged: {
                    ahead = false;
                    climbing = false;
                }
                onContentYChanged: {
                    const dy = contentY - lastContentY;
                    // A parked view the list clamped to a shorter end stays parked, so that
                    // shrink waits like any other.
                    if (!parking && !userScrolling && Math.abs(lastContentY - parkedY) < 0.5)
                        parkedY = contentY;
                    lastContentY = contentY;
                    if (chatScrollBar.pressed) {
                        // The bar moves the list after its own position signal, so the hand's
                        // position is read here.
                        if (!chatScrollBar.compensating) {
                            chatScrollBar.anchorY = contentY;
                            chatScrollBar.anchorAtEnd = nearEndAt(contentY, contentY < chatScrollBar.pressY);
                        }
                    } else if (!parking && userScrolling) {
                        readerMoved(contentY, dy);
                    }
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    messageId: modelData
                    messageData: Ai.messageByID[modelData] ?? null
                }
            }

            // A followed reply already sits at its end, so a scroll down would only
            // run into the slack below it and be pulled back. Sideways swipes pass on
            // to the code blocks that scroll that way.
            MouseArea {
                anchors.fill: messageListView
                enabled: messageListView.holding
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    wheel.accepted = wheel.angleDelta.y < 0 && -wheel.angleDelta.y >= Math.abs(wheel.angleDelta.x);
                }
            }

            Item {
                id: emptyStatePlaceholder
                z: 2
                anchors.fill: parent
                visible: opacity > 0
                opacity: Ai.messageIDs.length === 0 ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                readonly property bool isWide: width >= 560

                Flickable {
                    id: emptyFlickable
                    anchors {
                        fill: parent
                        topMargin: statusBg.implicitHeight + 12
                        bottomMargin: 8
                        leftMargin: 8
                        rightMargin: 8
                    }
                    contentWidth: width
                    contentHeight: emptyContentContainer.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        id: emptyContentContainer
                        width: emptyFlickable.width
                        height: Math.max(emptyFlickable.height, emptyLayout.implicitHeight + 16)

                        ColumnLayout {
                            id: emptyLayout
                            anchors.centerIn: parent
                            width: emptyStatePlaceholder.isWide ? Math.min(parent.width - 24, 700) : Math.min(parent.width - 24, 340)
                            spacing: emptyStatePlaceholder.isWide ? 14 : 10

                            // Header section
                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                MaterialShapeWrappedMaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    padding: emptyStatePlaceholder.isWide ? 10 : 12
                                    iconSize: emptyStatePlaceholder.isWide ? 36 : 42
                                    text: "neurology"
                                    shape: MaterialShape.Shape.PixelCircle
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("AI Assistant")
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.larger
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    color: Appearance.m3colors.m3onSurface
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("Model: %1 · Mode: %2").arg((Ai.currentModel && Ai.currentModel.name) ? Ai.currentModel.name : Ai.currentModelId).arg(AiModes.name(AiModes.current))
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }

                            // Reactive layout: 2 columns when wide, 1 column when narrow
                            GridLayout {
                                Layout.fillWidth: true
                                columns: emptyStatePlaceholder.isWide ? 2 : 1
                                columnSpacing: 12
                                rowSpacing: 10

                                // Column 1: Quick starters
                                ColumnLayout {
                                    id: quickStartersColumn
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 6

                                    StyledText {
                                        id: startersHeader
                                        text: Translation.tr("Quick starters:")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                        Layout.leftMargin: 2
                                    }

                                    StarterChip {
                                        icon: "content_paste"
                                        title: Translation.tr("Summarize clipboard")
                                        onClicked: {
                                            const text = root.clipboardTextCapped();
                                            root.prefillInput(text.length > 0 ? Translation.tr("Summarize this: %1").arg(text) : Translation.tr("Summarize "));
                                        }
                                    }

                                    StarterChip {
                                        icon: "terminal"
                                        title: Translation.tr("Explain or write bash command")
                                        onClicked: root.prefillInput(Translation.tr("How do I "))
                                    }

                                    StarterChip {
                                        icon: "search"
                                        title: Translation.tr("Search web with Gemini")
                                        onClicked: root.prefillInput(Translation.tr("Search the web for "))
                                    }

                                    StarterChip {
                                        icon: "tune"
                                        title: Translation.tr("Switch AI model")
                                        onClicked: root.openModelSheet()
                                    }
                                }

                                // Column 2: Sidebar controls
                                ColumnLayout {
                                    id: sidebarControlsColumn
                                    Layout.fillWidth: true
                                    Layout.fillHeight: emptyStatePlaceholder.isWide
                                    Layout.alignment: Qt.AlignTop
                                    spacing: 6

                                    StyledText {
                                        id: controlsHeader
                                        text: Translation.tr("Sidebar controls:")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                        Layout.leftMargin: 2
                                    }

                                    Rectangle {
                                        id: shortcutsCard
                                        Layout.fillWidth: true
                                        Layout.fillHeight: emptyStatePlaceholder.isWide
                                        Layout.preferredHeight: emptyStatePlaceholder.isWide
                                            ? (quickStartersColumn.implicitHeight - startersHeader.implicitHeight - quickStartersColumn.spacing)
                                            : (shortcutsCardColumn.implicitHeight + 8 * 2)
                                        implicitHeight: shortcutsCardColumn.implicitHeight + 8 * 2
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer2
                                        border.color: Appearance.colors.colLayer0
                                        border.width: 1

                                        ColumnLayout {
                                            id: shortcutsCardColumn
                                            anchors {
                                                fill: parent
                                                margins: 8
                                            }
                                            spacing: emptyStatePlaceholder.isWide ? 6 : 4

                                            ShortcutControlRow {
                                                icon: "open_in_full"
                                                label: (root.scopeRoot?.extend ?? false) ? Translation.tr("Ctrl+O to collapse sidebar") : Translation.tr("Ctrl+O to expand sidebar")
                                                onClicked: root.scopeRoot.toggleExtend()
                                            }

                                            ShortcutControlRow {
                                                icon: "push_pin"
                                                label: (root.scopeRoot?.pin ?? false) ? Translation.tr("Ctrl+P to unpin sidebar") : Translation.tr("Ctrl+P to pin sidebar")
                                                onClicked: root.scopeRoot.togglePin()
                                            }

                                            ShortcutControlRow {
                                                icon: "open_in_new"
                                                label: (root.scopeRoot?.detach ?? false) ? Translation.tr("Ctrl+D to attach sidebar") : Translation.tr("Ctrl+D to detach sidebar")
                                                onClicked: root.scopeRoot.toggleDetach()
                                            }

                                            ShortcutControlRow {
                                                icon: "add"
                                                label: Translation.tr("Ctrl+Shift+O for new page")
                                                onClicked: Ai.clearMessages()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }


            ScrollToBottomButton {
                z: 3
                target: messageListView
                glowOffset: messageEdgeFade.fadeSize
                pinned: messageListView.following
                downAction: () => messageListView.pinToEnd()
            }
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    // The flow wraps, so the cap is not about space: it only
                    // bounds a runaway completion list. Ten hid the tail of
                    // the model picker once the plan models joined it.
                    return root.suggestionList.slice(0, 30);
                }
                delegate: AiCommandButton {
                    id: commandButton
                    buttonText: modelData.displayName ?? modelData.name
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData);
                    }
                }
            }

            function acceptSuggestion(entry) {
                const word = entry?.name ?? entry;
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                // An entry that completes a whole invocation says so at build
                // time, so this shared path holds no command names of its own.
                if (entry?.executeOnAccept) {
                    root.handleInput(updatedText.trim());
                    messageInputField.clear();
                    messageInputField.forceActiveFocus();
                    return;
                }
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    suggestions.acceptSuggestion(root.suggestionList[suggestions.selectedIndex]);
                }
            }
        }

        Rectangle { // Plan-model setup banner
            visible: Ai.currentModelNeedsSetup
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            implicitHeight: setupCol.implicitHeight + 22
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimaryContainer

            ColumnLayout {
                id: setupCol
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12; rightMargin: 12
                }
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colOnPrimaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: {
                        const n = Ai.currentCliSetup?.name ?? "";
                        switch (Ai.setupState) {
                        case "installing": return Translation.tr("Installing %1…").arg(n);
                        case "loggingIn":
                            if (Ai.loginCodeSent) return Translation.tr("Checking the code…");
                            if (Ai.currentCliSetup?.loginCodePipe)
                                return Translation.tr("Sign in to Google in your browser within a minute, then click Copy to Clipboard on the page that shows a code. The sidebar picks it up from there.");
                            return (Ai.currentCliSetup?.loginInBackground
                                ? Translation.tr("Finish signing in to %1 in your browser…")
                                : Translation.tr("Finish signing in to %1 in the window that just opened…")).arg(n);
                        case "error": return Translation.tr("Setup didn't finish. Try again.");
                        default: return Translation.tr("%1 needs a one-time sign-in: no API key, just your subscription.").arg(n);
                        }
                    }
                }

                RippleButtonWithIcon {
                    visible: Ai.setupState === "" || Ai.setupState === "error"
                    Layout.alignment: Qt.AlignRight
                    materialIcon: Ai.setupState === "error" ? "refresh" : "login"
                    mainText: Ai.setupState === "error" ? Translation.tr("Retry")
                        : Translation.tr("Log in to %1").arg(Ai.currentCliSetup?.name ?? "")
                    onClicked: Ai.setupCurrentModel()
                }

                RippleButtonWithIcon {
                    visible: Ai.setupState === "loggingIn" && !Ai.loginCodeSent
                        && (Ai.currentCliSetup?.loginCodePipe ?? "") !== ""
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "content_paste"
                    mainText: Translation.tr("Paste Code")
                    onClicked: Ai.pasteLoginCode()
                }

                RippleButtonWithIcon {
                    visible: Ai.setupState === "loggingIn" && !Ai.loginCodeSent && (Ai.currentCliSetup?.loginInBackground ?? false)
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "open_in_browser"
                    mainText: Translation.tr("Open the page again")
                    onClicked: Ai.restartLogin()
                }

                RippleButtonWithIcon {
                    visible: Ai.setupState === "error" && (Ai.currentCliSetup?.terminalLogin ?? "") !== ""
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "terminal"
                    mainText: Translation.tr("Sign in with a terminal")
                    onClicked: Ai.loginInTerminal()
                    StyledToolTip {
                        text: Translation.tr("Opens the full app, which shows any first-run screens and takes a pasted sign-in code.")
                    }
                }

                // The download can fail in ways retrying will not mend, and
                // the same command is in the system repositories. Offered only
                // once the first way has actually failed, so the ordinary path
                // stays the one that needs no password.
                RippleButtonWithIcon {
                    visible: Ai.setupState === "error"
                        && (Ai.currentCliSetup?.installFallback ?? "") !== ""
                    Layout.alignment: Qt.AlignRight
                    materialIcon: "inventory_2"
                    mainText: Translation.tr("Install from system repo")
                    onClicked: Ai.installFromSystemRepo()
                    StyledToolTip {
                        text: Translation.tr("Installs it with the package manager instead. Asks for your password once.")
                    }
                }
            }
        }

        AiUsageCard {
            Layout.fillWidth: true
            Layout.bottomMargin: visible ? 6 : 0
        }

        ActionConfirmationCard {
            Layout.fillWidth: true
            Layout.bottomMargin: Math.min(6, implicitHeight)
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: 5
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: 5
                }
                spacing: 2

                RippleButton {
                    id: attachFileButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 4
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "attach_file"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }

                    onClicked: root.openFileSheet()

                    StyledToolTip {
                        text: Translation.tr("Attach file (browse inside sidebar)")
                    }
                }

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: root ? Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix) : ""

                        background: null

                        onTextChanged: {
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`,
                                        // A model entry completes the whole
                                        // invocation, so accepting one runs it.
                                        executeOnAccept: true
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Load chat from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => !cmd.hidden && cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                        }

                        function accept() {
                            if (root.handleInput(text))
                                clear();
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    messageInputField.accept();
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste
                                    event.accepted = true;
                                    if (messageInputField.readOnly)
                                        return;
                                    const pasted = root.clipboardTextCapped();
                                    if (messageInputField.selectedText.length > 0)
                                        messageInputField.remove(messageInputField.selectionStart, messageInputField.selectionEnd);
                                    messageInputField.insert(messageInputField.cursorPosition, pasted);
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                        }
                    }
                }

                RippleButton { // Send / Stop button
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: 5
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    enabled: Ai.isGenerating || messageInputField.text.length > 0
                    toggled: enabled

                    colBackgroundToggled: Ai.isGenerating ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
                    colBackgroundToggledHover: Ai.isGenerating ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryHover

                    onClicked: {
                        if (Ai.isGenerating) {
                            Ai.cancelRequest();
                            return;
                        }
                        messageInputField.accept();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: {
                            if (Ai.isGenerating) return Appearance.colors.colOnErrorContainer;
                            return sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled;
                        }
                        text: Ai.isGenerating ? "stop" : "arrow_upward"
                    }

                    StyledToolTip {
                        text: Ai.isGenerating ? Translation.tr("Stop generating") : Translation.tr("Send message")
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.leftMargin: 10
                anchors.rightMargin: 5
                spacing: 4

                AiInputBoxIndicator {
                    // Model indicator
                    id: modelIndicator
                    Layout.alignment: Qt.AlignVCenter
                    icon: "api"
                    customIcon: (Ai.currentModel && Ai.currentModel.icon) ? Ai.currentModel.icon : ""
                    readonly property string fullModelName: {
                        const raw = (Ai.currentModel && Ai.currentModel.name) ? Ai.currentModel.name : (Ai.ollamaSetupEntryName || "");
                        return raw.replace(/^Custom:\s*/i, "");
                    }
                    readonly property int maxNameLength: 14
                    text: (root.width >= 580 || fullModelName.length <= maxNameLength)
                        ? fullModelName
                        : (fullModelName.slice(0, maxNameLength).replace(/\s+$/, "") + "…")
                    tooltipText: Translation.tr("Current model: %1\nClick to choose model").arg(fullModelName)
                    maxTextWidth: (root.width >= 580) ? 9999 : 160
                    onClicked: root.openModelSheet()
                }

                AiInputBoxIndicator {
                    // Execution Mode indicator
                    id: modeIndicator
                    Layout.alignment: Qt.AlignVCenter
                    icon: AiModes.icon(AiModes.current)
                    text: Translation.tr("Execution Mode")
                    maxTextWidth: 160
                    tooltipText: Translation.tr("Execution Mode: %1\nClick to choose execution mode").arg(AiModes.name(AiModes.current))
                    onClicked: root.openExecutionModeSheet()
                }

                AiInputBoxIndicator {
                    // Reasoning indicator (aligned to the right of execution mode)
                    id: reasoningIndicator
                    Layout.alignment: Qt.AlignVCenter
                    icon: "psychology"
                    text: Translation.tr("Reasoning")
                    maxTextWidth: 120
                    tooltipText: Translation.tr("Reasoning Level: %1\nClick to choose reasoning depth")
                        .arg(Ai.thinkingLevelName(Ai.thinkingLevel))
                    onClicked: root.openReasoningSheet()
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    SheetLoader {
        id: modelSheetLoader
        sourceComponent: ModelSelectionSheet {
            onClosed: root.focusInput()
        }
    }

    SheetLoader {
        id: executionModeSheetLoader
        sourceComponent: ExecutionModeSelectionSheet {
            onModeSelected: mode => AiModes.set(mode)
            onClosed: root.focusInput()
        }
    }

    SheetLoader {
        id: reasoningSheetLoader
        sourceComponent: ReasoningSelectionSheet {
            onClosed: root.focusInput()
        }
    }

    SheetLoader {
        id: fileSheetLoader
        sourceComponent: FileSelectionSheet {
            onFileSelected: fileUrl => Ai.attachFile(fileUrl)
            onClosed: root.focusInput()
        }
    }

    Process {
        id: dropCheckProc
        property string path: ""
        property int extraCount: 0
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.postNotice(Translation.tr("Only files can be attached."));
                return;
            }
            Ai.attachFile(dropCheckProc.path);
            if (dropCheckProc.extraCount > 0)
                root.postNotice(Translation.tr("Only the first file was attached."));
        }
    }

    DropArea {
        id: fileDropArea
        anchors.fill: parent
        z: 150

        function isLocalFileDrag(drag): bool {
            if (!drag.hasUrls)
                return false;
            const urls = drag.urls;
            return urls.length > 0 && String(urls[0]).startsWith("file:");
        }

        onEntered: (drag) => {
            if (!fileDropArea.isLocalFileDrag(drag)) {
                drag.accepted = false;
                return;
            }
            drag.accept(Qt.CopyAction);
        }

        // Moves only arrive for a drag that onEntered accepted.
        onPositionChanged: (drag) => drag.accept(Qt.CopyAction)

        onDropped: (drop) => {
            if (!fileDropArea.isLocalFileDrag(drop)) return;
            let path = "";
            try {
                path = decodeURIComponent(FileUtils.trimFileProtocol(String(drop.urls[0])));
            } catch (e) {
                path = "";
            }
            if (fileSheetLoader.shown) fileSheetLoader.item.close();
            drop.accept(Qt.CopyAction);
            if (!path.startsWith("/")) {
                root.postNotice(Translation.tr("Only local files can be attached."));
                return;
            }
            dropCheckProc.path = path;
            dropCheckProc.extraCount = drop.urls.length - 1;
            dropCheckProc.exec(["test", "-f", path]);
        }

        Rectangle {
            id: dropOverlay
            anchors.fill: parent
            anchors.margins: root.padding
            enabled: false
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.colors.colLayer2Base, 0.15)
            border.width: 2
            border.color: Appearance.colors.colPrimary
            visible: opacity > 0
            opacity: fileDropArea.containsDrag ? 1 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "attach_file"
                        iconSize: 32
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop file to attach")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Release to attach to AI chat")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
