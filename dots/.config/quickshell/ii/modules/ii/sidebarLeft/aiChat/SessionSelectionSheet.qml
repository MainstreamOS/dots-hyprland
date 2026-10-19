import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell

SheetBase {
    id: root

    property string mode: "load" // "load" or "save"
    readonly property string searchQuery: searchField.text.trim().toLowerCase()
    // Session to load once the unsaved chat is saved or discarded
    property string pendingLoadName: ""
    readonly property bool confirmingLoad: root.mode === "load" && root.pendingLoadName.length > 0

    readonly property bool hasUserMessage: {
        const ids = Ai.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            if (Ai.messageByID[ids[i]]?.role === "user")
                return true;
        }
        return false;
    }

    readonly property string saveName: saveNameField.text.trim()
    readonly property bool saveNameExists: root.saveName.length > 0 && Ai.sessionNameExists(root.saveName)

    readonly property var chatNames: Ai.savedChats.map(path => FileUtils.trimFileExt(FileUtils.fileNameForPath(path)))
    readonly property var filteredChats: root.searchQuery
        ? root.chatNames.filter(name => name.toLowerCase().includes(root.searchQuery))
        : root.chatNames

    function openLoad(): void {
        root.mode = "load";
        root.pendingLoadName = "";
        searchField.text = "";
        root.show(searchField.input);
        Ai.reloadSavedChats();
    }

    function openSave(): void {
        if (!root.hasUserMessage) {
            root.openLoad();
            return;
        }
        root.mode = "save";
        root.pendingLoadName = "";
        root.show(saveNameField.input);
        root.editSaveName(root.defaultSessionName());
        Ai.reloadSavedChats();
    }

    function switchMode(newMode: string): void {
        root.mode = newMode;
        root.pendingLoadName = "";
        if (newMode === "save")
            root.editSaveName(saveNameField.text || root.defaultSessionName());
        else
            searchField.input.forceActiveFocus();
    }

    function editSaveName(text: string): void {
        saveNameField.text = text;
        saveNameField.input.forceActiveFocus();
        saveNameField.selectAll();
    }

    function defaultSessionName(): string {
        let title = "";
        const ids = Ai.messageIDs;
        for (let i = 0; i < ids.length; i++) {
            const msg = Ai.messageByID[ids[i]];
            if (msg?.role !== "user")
                continue;
            const content = msg.content ?? "";
            const start = content.search(/\S/);
            if (start < 0)
                continue;
            const end = content.indexOf("\n", start);
            title = content.slice(start, Math.min(end < 0 ? content.length : end, start + 30));
            break;
        }
        if (title.length > 0) {
            // V4 regexps have no \p{} escapes, so ASCII punctuation and the Unicode
            // punctuation and symbol blocks are listed; letters of every script stay.
            title = title.replace(/[\x00-\x08\x0E-\x1F!-,.\/:-@\[-\^`{-\x7F¡-¿×÷‐-‧‰-⁞⁰-⯿⸀-⹿、-〿︰-﹏！-／：-＠［-｀｛-･\uD800-\uDFFF]/g, "").trim().replace(/\s+/g, "-").toLowerCase();
        }
        if (!title || title.length === 0) {
            const now = new Date();
            const y = now.getFullYear();
            const m = String(now.getMonth() + 1).padStart(2, '0');
            const d = String(now.getDate()).padStart(2, '0');
            const h = String(now.getHours()).padStart(2, '0');
            const min = String(now.getMinutes()).padStart(2, '0');
            title = `session-${y}-${m}-${d}-${h}${min}`;
        }
        return title;
    }

    function performSave(): void {
        const name = root.saveName;
        if (name.length === 0 || !root.hasUserMessage)
            return;
        const saved = Ai.saveChat(name);
        if (saved.length === 0)
            return;
        const pending = root.pendingLoadName;
        // Saved over the session about to load, the chat already is that
        // session, and reading it back could beat the write to the disk.
        if (pending.length > 0 && pending !== saved)
            root.loadNow(pending);
        else
            root.close();
    }

    // Also the way in for a load typed in the chat, with the sheet closed.
    function requestLoad(name: string): void {
        if (Ai.chatIsUnsaved()) {
            if (!root.shown) {
                searchField.text = "";
                Ai.reloadSavedChats();
            }
            root.mode = "load";
            root.pendingLoadName = name;
            root.show(null);
            return;
        }
        root.loadNow(name);
    }

    function loadNow(name: string): void {
        Ai.loadChat(name);
        root.close();
    }

    function cancelLoadPrompt(): void {
        root.pendingLoadName = "";
        searchField.input.forceActiveFocus();
    }

    function saveBeforeLoad(): void {
        root.mode = "save";
        root.editSaveName(root.defaultSessionName());
    }

    maxCardHeight: 480
    icon: root.mode === "save" ? "bookmark" : "history"
    title: root.mode === "save" ? Translation.tr("Save Session") : Translation.tr("Saved Sessions")
    subtitle: root.mode === "save"
        ? Translation.tr("Save current conversation to load later")
        : Translation.tr("Load a previously saved chat session")
    inputField: root.mode === "save" ? saveNameField.input : (root.confirmingLoad ? null : searchField.input)
    filterField: (root.mode === "load" && !root.confirmingLoad) ? searchField.input : null
    navList: (root.mode === "load" && !root.confirmingLoad) ? sessionListView : null

    onClosed: root.pendingLoadName = ""
    onRowActivated: index => root.requestLoad(root.filteredChats[index])

    onSheetKeyPressed: event => {
        if (root.confirmingLoad && event.key === Qt.Key_Escape) {
            root.cancelLoadPrompt();
            event.accepted = true;
        }
    }

    // Mode switcher tabs
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 34
            buttonRadius: Appearance.rounding.verysmall
            colBackground: root.mode === "load" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: root.mode === "load" ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
            onClicked: root.switchMode("load")

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "history"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.mode === "load" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    text: Translation.tr("Load")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: root.mode === "load" ? Font.DemiBold : Font.Normal
                    color: root.mode === "load" ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                }
            }
        }

        // A disabled button reports no hover, so the wrapper drives the tooltip.
        Item {
            Layout.fillWidth: true
            implicitWidth: saveTab.implicitWidth
            implicitHeight: 34

            HoverHandler {
                id: saveTabHover
            }

            RippleButton {
                id: saveTab
                anchors.fill: parent
                buttonRadius: Appearance.rounding.verysmall
                colBackground: root.mode === "save" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                colBackgroundHover: root.mode === "save" ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                enabled: root.hasUserMessage
                opacity: enabled ? 1 : 0.4
                onClicked: root.switchMode("save")

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "save"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.mode === "save" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("Save")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: root.mode === "save" ? Font.DemiBold : Font.Normal
                        color: root.mode === "save" ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                    }
                }
            }

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: root.shown && saveTabHover.hovered && !saveTab.enabled
                text: Translation.tr("Cannot save an empty chat")
            }
        }
    }

    // Save Mode View
    ColumnLayout {
        visible: root.mode === "save"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        StyledText {
            text: Translation.tr("Enter a name for this session:")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            SheetSearchField {
                id: saveNameField
                Layout.fillWidth: true
                icon: "edit"
                placeholder: Translation.tr("Session name…")

                onFieldKeyPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.performSave();
                        event.accepted = true;
                    }
                }
            }

            RippleButton {
                id: saveConfirmButton
                implicitWidth: Math.max(80, saveConfirmRow.implicitWidth + 16)
                implicitHeight: 38
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                enabled: root.saveName.length > 0
                opacity: enabled ? 1 : 0.5
                onClicked: root.performSave()

                contentItem: RowLayout {
                    id: saveConfirmRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: "save"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onPrimary
                    }
                    StyledText {
                        text: root.saveNameExists ? Translation.tr("Replace") : Translation.tr("Save")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onPrimary
                    }
                }
            }
        }

        StyledText {
            text: Translation.tr("Saved sessions (%1)").arg(Ai.savedChats.length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
            visible: Ai.savedChats.length > 0
            Layout.topMargin: 4
        }

        Rectangle {
            visible: Ai.savedChats.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.55)
            StyledListView {
                id: saveSessionListView
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 4

                model: ScriptModel {
                    values: root.chatNames
                }

                delegate: Item {
                    id: saveChatRowItem
                    required property var modelData
                    required property int index

                    width: saveSessionListView.width
                    implicitHeight: 38

                    RippleButton {
                        anchors.fill: parent
                        buttonRadius: Appearance.rounding.small
                        colBackground: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                        onClicked: root.editSaveName(saveChatRowItem.modelData)

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 10
                                rightMargin: 10
                            }
                            spacing: 8

                            MaterialSymbol {
                                text: "history"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: saveChatRowItem.modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                                elide: Text.ElideRight
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MaterialSymbol {
                                text: "edit"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Click to use this name")
                        }
                    }
                }
            }
        }

        Item {
            visible: Ai.savedChats.length === 0
            Layout.fillHeight: true
        }
    }

    // Load Mode View
    ColumnLayout {
        visible: root.mode === "load"
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        SheetSearchField {
            id: searchField
            visible: !root.confirmingLoad
            Layout.fillWidth: true
            placeholder: Translation.tr("Filter saved sessions…")
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.filteredChats.length > 0 && !root.confirmingLoad
            radius: 14
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.55)
            StyledListView {
                id: sessionListView
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 4

                model: ScriptModel {
                    values: root.filteredChats
                }

                delegate: Item {
                    id: chatRowItem
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: sessionListView.currentIndex === index && root.shown
                    property bool deleteArmed: false

                    width: sessionListView.width
                    implicitHeight: 44

                    Timer {
                        id: disarmTimer
                        interval: 3000
                        onTriggered: chatRowItem.deleteArmed = false
                    }

                    RippleButton {
                        id: loadRowButton
                        anchors {
                            left: parent.left
                            right: deleteButton.left
                            rightMargin: 4
                            top: parent.top
                            bottom: parent.bottom
                        }
                        buttonRadius: Appearance.rounding.small
                        colBackground: (chatRowItem.isSelected || hovered) ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                        onClicked: root.requestLoad(chatRowItem.modelData)

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 10

                            MaterialSymbol {
                                text: "chat"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: chatRowItem.modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.m3colors.m3onSurface
                                elide: Text.ElideRight
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MaterialSymbol {
                                text: "file_download"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    RippleButton {
                        id: deleteButton
                        anchors {
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                        }
                        implicitWidth: 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            if (chatRowItem.deleteArmed) {
                                chatRowItem.deleteArmed = false;
                                disarmTimer.stop();
                                Ai.deleteChat(chatRowItem.modelData);
                            } else {
                                chatRowItem.deleteArmed = true;
                                disarmTimer.restart();
                            }
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: chatRowItem.deleteArmed ? "delete_forever" : "delete_outline"
                            iconSize: Appearance.font.pixelSize.normal
                            color: (chatRowItem.deleteArmed || deleteButton.hovered) ? Appearance.colors.colError : Appearance.colors.colSubtext
                        }

                        StyledToolTip {
                            text: chatRowItem.deleteArmed ? Translation.tr("Click again to delete") : Translation.tr("Delete saved session")
                        }
                    }
                }
            }
        }

        // Empty state for load mode
        ColumnLayout {
            visible: root.filteredChats.length === 0 && !root.confirmingLoad
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
            spacing: 8

            Item { Layout.fillHeight: true }

            SheetEmptyState {
                Layout.alignment: Qt.AlignHCenter
                icon: "history_toggle_off"
                title: (Ai.savedChats.length === 0)
                    ? Translation.tr("No saved sessions")
                    : Translation.tr("No matching sessions")
                subtitle: (Ai.savedChats.length === 0)
                    ? Translation.tr("Save a conversation with the Save button to see it here.")
                    : Translation.tr("Try a different search query.")
            }

            Item { Layout.fillHeight: true }
        }

        // Unsaved chat prompt before loading over it
        ColumnLayout {
            visible: root.confirmingLoad
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "chat"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Save the current chat first?")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Loading %1 replaces the current chat, which is not saved.").arg(root.pendingLoadName)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                SheetPromptButton {
                    iconName: "close"
                    label: Translation.tr("Cancel")
                    onClicked: root.cancelLoadPrompt()
                }

                SheetPromptButton {
                    iconName: "delete_outline"
                    label: Translation.tr("Discard")
                    onClicked: root.loadNow(root.pendingLoadName)
                }

                SheetPromptButton {
                    iconName: "save"
                    label: Translation.tr("Save")
                    primary: true
                    onClicked: root.saveBeforeLoad()
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // Footer note
    StyledText {
        Layout.fillWidth: true
        text: root.mode === "save"
            ? Translation.tr("Saved sessions are stored locally and can be restored at any time.")
            : Translation.tr("Click a session to load. Click the trash icon to delete.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }
}
