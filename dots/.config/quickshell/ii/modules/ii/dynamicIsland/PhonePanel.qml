pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft

ColumnLayout {
    id: root
    implicitHeight: (messageBody.visible && messageBody.isAudioOnly)
        ? (detailHeaderBar.implicitHeight + (replyBar.visible ? replyBar.implicitHeight + root.spacing : 0) + (replyErrorText.visible ? replyErrorText.implicitHeight + root.spacing : 0) + messageBody.implicitHeight + root.spacing)
        : 204
    property bool calls: false
    property string selectedHistoryId: ""
    readonly property var entries: calls ? IslandState.recentCalls : IslandState.recentMessages
    readonly property bool liveCall: calls && !!IslandState.call
    readonly property bool liveMessage: !calls && IslandState.alertOpen && !!IslandState.message
    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)

    readonly property string pendingRequest: Object.keys(IslandState.messageRequests).find(request => IslandState.messageRequests[request].key === root.draftKey) || ""
    readonly property string draftKey: (root.entry?.deviceId || "") + ":" + (root.entry?.number || root.entry?.id || "")
    property bool composing: false
    property bool restoringDraft: false
    readonly property bool recordingVoice: voiceRecordProc.recording
    readonly property int recordingSeconds: voiceRecordProc.seconds
    readonly property bool canMessage: !!root.entry?.number && Phone.canMessage && Phone.reachable
        && (!root.entry.deviceId || root.entry.deviceId === Phone.deviceId)
    readonly property bool canReply: canMessage && !liveCall && (!calls || composing)
    readonly property bool callbackTarget: calls && !!entry && PhoneCalls.dialNumber === String(entry.number || "").trim()
    readonly property bool callbackPending: callbackTarget && PhoneCalls.dialing
    readonly property string callStatus: {
        switch (root.entry?.state) {
        case "dialing": return Translation.tr("Dialing…");
        case "alerting": return Translation.tr("Ringing…");
        case "active": return Translation.tr("In call");
        case "held": return Translation.tr("On hold");
        default: return Translation.tr("Incoming call");
        }
    }
    property bool replying: false
    property bool replySent: false

    readonly property bool busy: callbackPending || !!pendingRequest || replying || recordingVoice || (canReply && quickReplyInput.text.trim().length > 0)
    readonly property bool needsKeyboardFocus: canReply && (replying || recordingVoice || quickReplyInput.focus || quickReplyInput.activeFocus)

    function resetSendFeedback(): void {
        sendSuccess.stop();
        root.replySent = false;
        sendBtn.flight = 0;
        sendBtn.confirmation = 0;
    }

    SequentialAnimation {
        id: sendSuccess
        NumberAnimation {
            target: sendBtn
            property: "flight"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            target: sendBtn
            property: "confirmation"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        PauseAnimation { duration: 1000 }
        onFinished: root.resetSendFeedback()
    }

    PhoneVoiceRecorder {
        id: voiceRecordProc
        onFinished: (path, target) => root.sendVoiceNote(path, target)
    }

    // The note goes to the person it was recorded for, even if the panel moved on.
    function sendVoiceNote(path, target): void {
        if (!path || !target?.number || !Phone.reachable || !Phone.canMessage
            || (target.deviceId && target.deviceId !== Phone.deviceId)) return;
        root.resetSendFeedback();
        IslandState.phoneError = "";
        if (Phone.sendNew([target.number], "", [path])) {
            IslandState.messageRequests = Object.assign({}, IslandState.messageRequests, {
                [Phone.lastSendRequest]: { key: target.key, text: "" }
            });
        } else {
            IslandState.phoneError = Translation.tr("Your voice note could not be sent. Check the connection and try again.");
        }
    }

    readonly property var entry: {
        if (liveCall) return IslandState.call;
        const saved = entries.find(e => e.id === selectedHistoryId) ?? (liveMessage ? IslandState.message : null);
        if (!saved) return null;
        if (calls) {
            const pic = saved.picture || ContactService.pictureFor(saved.number, saved.name) || "";
            return pic !== saved.picture ? Object.assign({}, saved, { picture: pic }) : saved;
        }
        const current = IslandState.messages.find(m => saved.sourceIds ? saved.sourceIds.includes(m.id) : m.id === saved.id);
        const pic = current?.picture || saved.picture || ContactService.pictureFor(saved.number, saved.name) || "";
        // History owns the merged, canonical attachment images.
        return current ? Object.assign({}, saved, {
            picture: pic,
            previewImage: current.previewImage || saved.previewImage,
            audioClips: current.audioClips && current.audioClips.length ? current.audioClips : saved.audioClips
        }) : (pic !== saved.picture ? Object.assign({}, saved, { picture: pic }) : saved);
    }

    onEntriesChanged: {
        if (!IslandPhoneHistory.ready) return;
        if (!calls && IslandState.alertOpen && !selectedHistoryId && entries.length) {
            selectedHistoryId = entries[0]?.id ?? "";
        } else if (selectedHistoryId && !entries.some(e => e.id === selectedHistoryId)) {
            const grouped = entries.find(e => e.memberIds?.includes(root.selectedHistoryId)
                || e.sourceIds?.includes(root.selectedHistoryId.replace(/^message:/, "")));
            if (grouped) selectedHistoryId = grouped.id;
            else if (!liveMessage || IslandState.message?.id !== selectedHistoryId) selectedHistoryId = "";
        }
    }

    function restoreDraft() {
        if (voiceRecordProc.running) voiceRecordProc.cancel();
        root.replying = false;
        if (typeof quickReplyInput !== "undefined" && quickReplyInput) {
            root.restoringDraft = true;
            quickReplyInput.focus = false;
            quickReplyInput.text = IslandState.messageDrafts[root.draftKey] || "";
            root.restoringDraft = false;
        }
    }
    onDraftKeyChanged: {
        root.resetSendFeedback();
        if (voiceRecordProc.running) voiceRecordProc.cancel();
        root.composing = false;
        restoreDraft();
    }
    onLiveCallChanged: if (liveCall) {
        if (voiceRecordProc.running) voiceRecordProc.cancel();
        root.composing = false;
        root.replying = false;
        if (typeof quickReplyInput !== "undefined" && quickReplyInput) quickReplyInput.focus = false;
    }
    onCanReplyChanged: if (!canReply) {
        if (voiceRecordProc.running) voiceRecordProc.cancel();
        root.replying = false;
        if (typeof quickReplyInput !== "undefined" && quickReplyInput) quickReplyInput.focus = false;
    }
    Component.onDestruction: {
        if (voiceRecordProc.running) voiceRecordProc.cancel();
    }

    function composeMessage() {
        if (!root.canMessage || root.liveCall) return;
        if (root.recordingVoice) voiceRecordProc.cancel();
        root.composing = true;
        root.replying = true;
        Qt.callLater(() => { if (root.canReply) quickReplyInput.forceActiveFocus(); });
    }

    Component.onCompleted: {
        if (!calls && IslandState.alertOpen && IslandState.selected === "text") selectedHistoryId = entries[0]?.id ?? (IslandState.message?.id ?? "");
        restoreDraft();
    }

    Connections {
        target: IslandState
        function onMessageReceived(id) { if (!root.calls) root.selectedHistoryId = id; }
    }

    readonly property var privacy: Config.options.bar.island
    readonly property var messageLinkPreview: {
        if (root.calls || !root.privacy.showMessage || root.entry?.images?.length || root.entry?.audioClips?.length) return null;
        const url = root.entry?.previewUrl || LinkPreviewService.extractUrls(root.entry?.body || "")[0];
        return url ? LinkPreviewService.getPreview(url) : null;
    }
    readonly property var messageImages: {
        if (root.calls || !root.privacy.showMessage) return [];
        if (root.entry?.images?.length) return root.entry.images;
        // Audio-only messages should not get a contact/placeholder image;
        // real image attachments in mixed messages are still displayed.
        if (root.entry?.audioClips?.length) return [];
        if (root.messageLinkPreview?.thumbnail) return [root.messageLinkPreview.thumbnail];
        return (root.privacy.showContactPicture && root.entry?.previewImage ? [root.entry.previewImage] : []);
    }
    readonly property string messageText: {
        if (!root.privacy.showMessage) return Translation.tr("Message contents hidden");
        const body = root.entry?.body || "";
        if (root.entry?.previewUrl) return root.messageLinkPreview?.thumbnail ? body : root.entry.previewUrl + "\n" + body;
        return root.messageLinkPreview?.thumbnail ? LinkPreviewService.stripUrls(body, 1) : body;
    }

    spacing: 6

    PhoneHistoryList {
        Layout.fillWidth: true
        Layout.preferredHeight: 204
        visible: !root.entry
        calls: root.calls
        entries: root.entries
        onSelected: entryId => root.selectedHistoryId = entryId
        onClearRequested: root.calls ? IslandPhoneHistory.clearCalls() : IslandPhoneHistory.clearMessages()
    }

    Rectangle {
        id: detailHeaderBar
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 12
        color: root.elevatedSurface
        visible: !!root.entry

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 8

            RippleButton {
                visible: !root.liveCall
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 9
                colBackground: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                Accessible.name: Translation.tr("Back to history")
                onClicked: root.selectedHistoryId = ""
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            ClippingRectangle {
                visible: root.privacy.showContactPicture
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                Image {
                    anchors.fill: parent
                    source: root.entry?.picture || ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.entry?.picture
                    text: root.calls ? "call" : "chat"
                    color: Appearance.colors.colOnLayer1
                    iconSize: 18
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: root.privacy.showContactName && root.entry?.name && (root.entry.name !== root.entry.number || root.privacy.showPhoneNumber)
                            ? root.entry.name : root.privacy.showPhoneNumber && root.entry?.number ? root.entry.number : Translation.tr("Private contact")
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        implicitHeight: 16
                        implicitWidth: typeLabel.implicitWidth + 8
                        radius: 4
                        color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                        StyledText {
                            id: typeLabel
                            anchors.centerIn: parent
                            text: root.calls
                                ? (root.liveCall ? root.callStatus : Translation.tr("Call"))
                                : Translation.tr("Text message")
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.privacy.showPhoneNumber && !!root.entry?.number
                    text: (root.entry?.number || "") + (root.entry?.time ? " · " + Qt.formatDateTime(new Date(root.entry.time), Config.options.time.format) : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 9
                colBackground: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                visible: !root.calls && root.canReply
                Accessible.name: Translation.tr("Open in sidebar")
                onClicked: {
                    Phone.wanted = true;
                    SidebarLeftTabs.showTab("phone");
                    GlobalStates.sidebarLeftOpen = true;
                    Phone.openTargetConversation({
                        thread: root.entry?.thread,
                        number: root.entry?.number || root.entry?.address || "",
                        name: root.entry?.name || ""
                    });
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: root.composing ? 114 : 154
        implicitHeight: root.composing ? 114 : 154
        radius: 12
        color: root.elevatedSurface
        visible: root.calls && !root.liveCall && !!root.entry
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                MaterialSymbol {
                    text: root.entry?.answered ? "call_received" : (root.entry?.incoming ? "call_missed" : "call_made")
                    iconSize: 20
                    color: root.entry?.answered ? Appearance.colors.colPrimary : (root.entry?.incoming ? Appearance.colors.colError : Appearance.colors.colSubtext)
                }

                StyledText {
                    text: root.callbackPending ? Translation.tr("Starting call…") : root.entry?.answered ? Translation.tr("Call ended")
                        : (root.entry?.incoming ? Translation.tr("Missed call") : Translation.tr("Outgoing call"))
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: !!root.entry?.time
                    text: "·  " + (root.entry?.time ? Qt.formatDateTime(new Date(root.entry.time), Config.options.time.format) : "")
                    font.pixelSize: 11
                    color: Appearance.colors.colSubtext
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                IslandButton {
                    symbol: "call"
                    text: root.callbackPending ? Translation.tr("Calling…") : Translation.tr("Call back")
                    highlighted: true
                    enabled: !!root.entry?.number && PhoneCalls.canDial && !PhoneCalls.dialing
                    onClicked: PhoneCalls.dial(root.entry?.number)
                }

                IslandButton {
                    symbol: "chat"
                    text: Translation.tr("Message")
                    visible: root.canMessage
                    highlighted: root.composing
                    onClicked: root.composeMessage()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.callbackTarget && !!PhoneCalls.dialError
                text: PhoneCalls.dialError
                color: Appearance.colors.colError
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Item { Layout.fillHeight: true }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.liveCall
        text: root.callStatus
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 18
        color: Appearance.colors.colOnLayer1
    }

    MessageBody {
        id: messageBody
        Layout.fillWidth: true
        Layout.fillHeight: !messageBody.isAudioOnly
        Layout.preferredHeight: messageBody.isAudioOnly ? messageBody.implicitHeight : -1
        visible: !root.calls && !!root.entry
        images: root.messageImages
        audioClips: !root.calls && root.privacy.showMessage ? root.entry?.audioClips || [] : []
        text: root.messageText
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.liveCall && (!!IslandState.phoneError || root.entry?.backend === "KDE Connect" || (!root.entry?.canPositive && !root.entry?.canNegative))
        text: IslandState.phoneError || (root.calls && root.entry?.backend === "KDE Connect"
            ? Translation.tr("Connect your phone over Bluetooth for Accept and Decline controls.")
            : IslandState.phoneStatus)
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        visible: root.liveCall && !!(root.entry?.canNegative || root.entry?.canPositive)
        spacing: 12
        Item { Layout.fillWidth: true }
        IslandButton {
            Layout.maximumWidth: (root.width - 12) / 2
            symbol: "call_end"
            text: root.entry?.negativeLabel || Translation.tr("Decline")
            visible: root.entry?.canNegative ?? false
            onClicked: IslandState.action(root.entry.id, "negative")
        }
        IslandButton {
            Layout.maximumWidth: (root.width - 12) / 2
            symbol: root.entry?.backend === "KDE Connect" ? "volume_off" : "call"
            text: root.entry?.positiveLabel || Translation.tr("Answer")
            highlighted: true
            visible: (root.entry?.canPositive ?? false) && root.entry?.state !== "active"
            onClicked: IslandState.action(root.entry.id, "positive")
        }
        Item { Layout.fillWidth: true }
    }

    Connections {
        target: IslandState
        function onMessageReplyFinished(key, success, text) {
            if (key !== root.draftKey) return;
            if (success) {
                root.replySent = true;
                sendSuccess.restart();
                if (quickReplyInput.text === text) quickReplyInput.text = "";
                quickReplyInput.focus = false;
                root.replying = false;
            } else IslandState.phoneError = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        }
    }
    StyledText {
        id: replyErrorText
        Layout.fillWidth: true
        visible: root.canReply && !!IslandState.phoneError
        text: IslandState.phoneError
        color: Appearance.colors.colError
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // Shared composer for message history and call-log contacts.
    Rectangle {
        id: replyBar
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 10
        color: root.elevatedSurface
        visible: root.canReply

        function send(): void {
            const text = (quickReplyInput.text || "").trim();
            const number = root.entry?.number || root.entry?.address || "";
            if (!text || !number || !root.canReply || root.pendingRequest) return;
            root.resetSendFeedback();
            IslandState.messageDrafts = Object.assign({}, IslandState.messageDrafts, {[root.draftKey]: text});
            IslandState.phoneError = "";
            if (Phone.sendNew([number], text, [])) {
                IslandState.messageRequests = Object.assign({}, IslandState.messageRequests, {[Phone.lastSendRequest]: {key: root.draftKey, text}});
            } else IslandState.phoneError = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        }

        TapHandler {
            onTapped: {
                if (!root.recordingVoice) {
                    root.replying = true;
                    quickReplyInput.forceActiveFocus();
                }
            }
        }

        focus: root.recordingVoice
        Keys.onEscapePressed: {
            if (root.recordingVoice) {
                voiceRecordProc.cancel();
            }
        }
        Keys.onReturnPressed: {
            if (root.recordingVoice) {
                voiceRecordProc.stopAndSend();
            }
        }
        Keys.onEnterPressed: {
            if (root.recordingVoice) {
                voiceRecordProc.stopAndSend();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            spacing: 6

            MaterialSymbol {
                visible: !root.recordingVoice
                text: "reply"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }

            ToolbarTextField {
                id: quickReplyInput
                visible: !root.recordingVoice
                Layout.fillWidth: true
                Layout.fillHeight: true
                leftPadding: 4
                rightPadding: 4
                topPadding: 0
                bottomPadding: 0
                font.pixelSize: 12
                colBackground: "transparent"
                placeholderText: root.calls ? Translation.tr("Message…") : Translation.tr("Reply to %1…").arg(root.privacy.showContactName ? root.entry?.name || Translation.tr("contact") : Translation.tr("contact"))
                onAccepted: replyBar.send()
                onTextChanged: {
                    if (root.replySent && text.length > 0) root.resetSendFeedback();
                    if (root.entry && !root.restoringDraft)
                        IslandState.messageDrafts = Object.assign({}, IslandState.messageDrafts, {[root.draftKey]: text});
                }
                Keys.onEscapePressed: {
                    root.replying = false;
                    quickReplyInput.focus = false;
                    root.composing = false;
                }
                onFocusChanged: {
                    if (focus) root.replying = true;
                }
                onActiveFocusChanged: {
                    if (activeFocus) root.replying = true;
                }
            }

            RowLayout {
                id: recordingRow
                visible: root.recordingVoice
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colError
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.recordingVoice
                        NumberAnimation { to: 0.2; duration: 550 }
                        NumberAnimation { to: 1.0; duration: 550 }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Recording voice note: %1:%2").arg(Math.floor(root.recordingSeconds / 60)).arg((root.recordingSeconds % 60 < 10 ? "0" : "") + (root.recordingSeconds % 60))
                    font.pixelSize: 12
                    color: Appearance.colors.colError
                    elide: Text.ElideRight
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: 13
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: voiceRecordProc.cancel()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 15
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: Translation.tr("Cancel recording (Esc)")
                    }
                }
            }

            RippleButton {
                id: micBtn
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 13
                colBackground: root.recordingVoice ? ColorUtils.transparentize(Appearance.colors.colError, 0.85) : "transparent"
                colBackgroundHover: root.recordingVoice ? ColorUtils.transparentize(Appearance.colors.colError, 0.7) : Appearance.colors.colLayer2Hover
                enabled: root.canReply && !root.pendingRequest
                Accessible.name: root.recordingVoice ? Translation.tr("Stop and send voice note") : Translation.tr("Record voice note")
                onClicked: {
                    if (root.recordingVoice) {
                        voiceRecordProc.stopAndSend();
                    } else {
                        voiceRecordProc.start({number: root.entry?.number || root.entry?.address || "",
                            deviceId: root.entry?.deviceId || "", key: root.draftKey});
                        replyBar.forceActiveFocus();
                    }
                }
                altAction: () => {
                    if (root.recordingVoice) voiceRecordProc.cancel();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.recordingVoice ? "stop" : "mic"
                    iconSize: 16
                    color: root.recordingVoice ? Appearance.colors.colError : (parent.enabled ? (micBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext) : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5))
                }
                StyledToolTip {
                    text: root.recordingVoice
                        ? Translation.tr("Stop and send voice note (Right-click or Esc to cancel)")
                        : Translation.tr("Record voice note\n(Click to record, click again to send)")
                }
            }

            RippleButton {
                id: sendBtn
                property real flight: 0
                property real confirmation: 0
                readonly property bool canSend: root.recordingVoice || quickReplyInput.text.trim().length > 0
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 13
                opacity: enabled || root.replySent ? 1 : 0.4
                colBackground: canSend ? Appearance.colors.colPrimary : "transparent"
                colBackgroundHover: canSend ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                enabled: canSend && root.canReply && !root.pendingRequest
                Accessible.name: root.replySent ? Translation.tr("Message sent")
                    : root.recordingVoice ? Translation.tr("Send voice note") : Translation.tr("Send reply")
                onClicked: {
                    if (root.recordingVoice) {
                        voiceRecordProc.stopAndSend();
                    } else {
                        replyBar.send();
                    }
                }
                contentItem: Item {
                    clip: true
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_upward"
                        iconSize: 16
                        color: sendBtn.canSend ? Appearance.colors.colOnPrimary
                            : root.replySent ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: 1 - sendBtn.flight
                        transform: Translate { y: -18 * sendBtn.flight }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 16
                        color: sendBtn.canSend ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: sendBtn.confirmation
                        scale: 0.6 + 0.4 * sendBtn.confirmation
                    }
                }
                StyledToolTip {
                    text: root.recordingVoice ? Translation.tr("Send voice note") : Translation.tr("Send reply")
                }
            }
        }
    }
}
