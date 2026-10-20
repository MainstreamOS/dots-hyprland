import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import "../../../services/PhoneReactions.js" as PhoneReactions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Widgets

// One conversation, or a new message when composing.
Item {
    id: root
    property bool composing: false
    property var pendingSend: null
    property var drafts: ({})
    // Files going with the message being written, as local paths.
    property var attachments: []
    // The playing video is shown as wide as the conversation, over it.
    property bool fullscreenVideo: false
    property bool fullscreenImage: false
    property var fullscreenMedia: null
    property bool gifPickerOpen: false
    readonly property bool recordingVoice: voiceRecordProc.recording
    readonly property int recordingSeconds: voiceRecordProc.seconds
    property var activeReplyMessage: null
    property string highlightedMessageUid: ""
    signal back()
    signal attachRequested()
    signal notice(string text)

    Timer {
        id: highlightClearTimer
        interval: 1400
        repeat: false
        onTriggered: root.highlightedMessageUid = ""
    }

    function startReply(msg): void {
        if (!msg) return;
        root.closeReactionBar();
        root.activeReplyMessage = msg;
        input.forceActiveFocus();
    }

    function cancelReply(): void {
        root.activeReplyMessage = null;
    }

    function setRecipient(num): void {
        recipientField.text = String(num || "");
        root.restoreDraft();
        Qt.callLater(() => { if (root.visible && root.composing) input.forceActiveFocus(); });
    }

    function draftKey(): string {
        return JSON.stringify([Phone.deviceId, root.composing ? "new" : "thread",
            root.composing ? recipientField.text.trim() : Phone.openThread]);
    }

    // Media finished after the view moved to another conversation joins the
    // draft of the one it was made for instead of being sent here.
    function addToDraft(key, path): void {
        const draft = root.drafts[key] ?? {text: "", attachments: [], reply: null};
        root.drafts = Object.assign({}, root.drafts, {[key]: Object.assign({}, draft, {attachments: draft.attachments.concat([path])})});
    }
    property string gifTarget: ""

    function saveDraft(): void {
        root.drafts = Object.assign({}, root.drafts, {[root.draftKey()]: {
            text: input.text, attachments: root.attachments.slice(), reply: root.activeReplyMessage
        }});
    }

    function restoreDraft(): void {
        const draft = root.drafts[root.draftKey()];
        input.text = draft?.text || "";
        root.attachments = draft?.attachments?.slice() || [];
        root.activeReplyMessage = draft?.reply || null;
    }

    function quoteSummaryFor(msg): var {
        if (!msg) {
            return {
                senderName: "",
                provider: "",
                snippet: "",
                thumbSource: "",
                iconName: "reply",
                isMedia: false,
                targetUid: ""
            };
        }
        const isOut = Phone.isOutgoing(msg);
        const senderName = isOut
            ? Translation.tr("You")
            : (Phone.conversationTitle(root.threadSummary) || Translation.tr("Sender"));
        const rawBody = String(msg.body ?? "");
        const parsed = PhoneReactions.parseQuote(rawBody);
        const cleanBody = parsed ? parsed.body : rawBody;
        const urls = LinkPreviewService.extractUrls(cleanBody);
        let provider = "";
        let thumbSource = "";
        let iconName = "";
        let isMedia = false;
        let snippet = urls.length > 0 ? LinkPreviewService.stripUrls(cleanBody, 2) : cleanBody;

        if (urls.length > 0) {
            const prev = LinkPreviewService.peekPreview(urls[0]);
            if (prev) {
                provider = prev.provider || prev.domain || "";
                if (prev.thumbnail && prev.thumbnail.length > 0) {
                    thumbSource = prev.thumbnail;
                }
                if (prev.media_type === "video" || prev.playable) {
                    iconName = "play_arrow";
                    isMedia = true;
                } else {
                    iconName = "link";
                }
                if (snippet.length === 0) {
                    snippet = prev.title || prev.description || urls[0];
                }
            } else if (snippet.length === 0) {
                snippet = urls[0];
            }
        }

        const atts = msg.attachments ?? [];
        if (atts.length > 0) {
            const att = atts[0];
            const uid = String(att?.uid ?? "");
            const mime = String(att?.mime ?? "").toLowerCase();
            const filePath = (uid && Phone.attachmentFiles && Phone.attachmentFiles[uid])
                ? Phone.attachmentFiles[uid]
                : (att?.path || att?.thumb || "");
            if (mime.startsWith("video/")) {
                isMedia = true;
                iconName = "play_arrow";
                if (!thumbSource && att?.thumb) thumbSource = att.thumb;
                if (snippet.length === 0) snippet = Translation.tr("Video");
            } else if (mime.startsWith("image/") || (att?.thumb && att.thumb.length > 0)) {
                isMedia = true;
                iconName = "image";
                if (!thumbSource && filePath) thumbSource = filePath;
                if (snippet.length === 0) snippet = Translation.tr("Photo");
            } else if (mime.startsWith("audio/")) {
                isMedia = true;
                iconName = "mic";
                if (snippet.length === 0) snippet = Translation.tr("Voice note");
            } else {
                isMedia = true;
                iconName = "description";
                if (snippet.length === 0) snippet = Translation.tr("Attachment");
            }
        }

        return {
            senderName: senderName,
            provider: provider,
            snippet: snippet.replace(/\s+/g, " ").trim(),
            thumbSource: thumbSource,
            iconName: iconName,
            isMedia: isMedia,
            targetUid: String(msg.uid ?? "")
        };
    }

    function resolveQuotedMessage(quotedText, beforeIndex): var {
        const needle = String(quotedText ?? "").replace(/\s+/g, " ").trim();
        const msgs = Phone.threadMessages ?? [];
        const needleLower = needle.toLowerCase();
        const startIdx = (beforeIndex !== undefined && beforeIndex >= 0 && beforeIndex <= msgs.length)
            ? beforeIndex - 1
            : msgs.length - 1;
        for (let i = startIdx; i >= 0; i--) {
            const m = msgs[i];
            if (!m) continue;
            const rawBody = String(m.body ?? "");
            const parsed = PhoneReactions.parseQuote(rawBody);
            const cleanBody = parsed ? parsed.body : rawBody;
            const cleanRaw = cleanBody.replace(/\s+/g, " ").trim().toLowerCase();
            // A plain text message's snippet is its body, so only links and attachments need the summary to compare.
            const plain = !(m.attachments?.length > 0) && LinkPreviewService.extractUrls(cleanBody).length === 0;
            if (plain && !(cleanRaw.length > 0 && (cleanRaw.includes(needleLower) || needleLower.startsWith(cleanRaw)))) continue;
            const summary = root.quoteSummaryFor(m);
            const snip = summary.snippet.toLowerCase();
            if ((snip.length > 0 && (snip === needleLower || snip.startsWith(needleLower) || needleLower.startsWith(snip)))
                || (cleanRaw.length > 0 && (cleanRaw === needleLower || cleanRaw.includes(needleLower)))) {
                return Object.assign({}, summary, {
                    snippet: summary.snippet.length > 0 ? summary.snippet : needle,
                    targetIndex: i
                });
            }
        }
        return {
            senderName: Phone.conversationTitle(root.threadSummary) || Translation.tr("Message"),
            provider: "",
            snippet: needle,
            thumbSource: "",
            iconName: "",
            isMedia: false,
            targetUid: "",
            targetIndex: -1
        };
    }

    function scrollToMessage(targetUid, targetIndex): void {
        const msgs = Phone.threadMessages ?? [];
        let idx = -1;
        if (targetUid && targetUid.length > 0) {
            idx = msgs.findIndex(m => String(m?.uid ?? "") === targetUid);
        }
        if (idx < 0 && targetIndex !== undefined && targetIndex >= 0 && targetIndex < msgs.length) {
            idx = targetIndex;
        }
        if (idx >= 0) {
            messageList.positionViewAtIndex(idx, ListView.Center);
            const uid = String(msgs[idx]?.uid ?? "");
            if (uid.length > 0) {
                root.highlightedMessageUid = uid;
                highlightClearTimer.restart();
            }
        }
    }

    function toggleGifPicker(): void {
        root.gifPickerOpen = !root.gifPickerOpen;
    }

    // A file that cannot be sent right away stays with the message being written.
    function attachOrSendGif(path, directSend = false): void {
        if (!path || path.length === 0) return;
        const target = root.gifTarget || root.draftKey();
        root.gifTarget = "";
        if (target !== root.draftKey()) {
            root.addToDraft(target, path);
            return;
        }
        root.gifPickerOpen = false;
        // A picked GIF goes out with the caption through send(), so the draft is
        // cleared only once the phone confirms; if it cannot go, it stays attached.
        if (directSend && !root.composing && !root.pendingSend && root.attachments.length === 0) {
            root.attachments = [path];
            root.send();
            return;
        }
        root.attachments = root.attachments.concat([path]);
        input.forceActiveFocus();
    }

    // A finished voice note goes out through send(), so it stays in the draft until the
    // phone confirms; with text or other files already there it joins them instead.
    function sendVoiceNote(path): void {
        if (!path || path.length === 0) return;
        if (!root.composing && !root.pendingSend && root.attachments.length === 0 && input.text.trim().length === 0) {
            root.attachments = [path];
            root.send();
            return;
        }
        root.attachments = root.attachments.concat([path]);
    }

    function addAttachments(paths): void {
        root.attachments = root.attachments.concat(paths.filter(p => !root.attachments.includes(p)));
    }

    readonly property var contactList: {
        const out = [];
        for (const contact of ContactService.records.filter(c => c.deviceId === Phone.deviceId)) {
            for (const number of contact.numbers || []) out.push({name: contact.name || number, number, picture: contact.picture || ""});
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }
    readonly property var suggestions: {
        const query = recipientField.text.trim().toLowerCase();
        if (!root.composing || query.length === 0) return [];
        const digits = query.replace(/\D/g, "");
        return root.contactList.filter(c => c.name.toLowerCase().includes(query)
            || (digits.length >= 3 && c.number.includes(digits))).slice(0, 5);
    }

    function send(): void {
        if (root.pendingSend) return;
        const rawText = input.text.trim();
        if (rawText.length === 0 && root.attachments.length === 0) return;
        let text = rawText;
        if (root.activeReplyMessage && !root.composing) {
            const q = root.quoteSummaryFor(root.activeReplyMessage);
            text = PhoneReactions.formatReply(q.snippet, rawText);
        }
        const ok = root.composing ? Phone.sendNew([recipientField.text], text, root.attachments) : Phone.reply(text, root.attachments);
        if (!ok) return;
        root.pendingSend = {request: Phone.lastSendRequest, device: Phone.deviceId, draftKey: root.draftKey(),
            thread: Phone.openThread, composing: root.composing, recipient: recipientField.text,
            text: input.text, attachments: root.attachments.slice()};
        messageList.wasAtBottom = true;
        root.snapToBottom();
    }

    // Plays an audio or video attachment, fetching it from the phone first; a
    // second click on the one playing pauses it.
    function toggleMedia(attachment, isVideoHint = false): void {
        const isVideo = isVideoHint ||
            (attachment.kind === "video") ||
            Boolean(attachment.mime && attachment.mime.startsWith("video/")) ||
            String(attachment.uid ?? "").startsWith("link:");
        if (mediaPlayer.uid === attachment.uid && mediaPlayer.source.toString().length > 0) {
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                mediaPlayer.pause();
            } else {
                if (mediaPlayer.duration > 0 && mediaPlayer.position >= mediaPlayer.duration) {
                    mediaPlayer.setPosition(0);
                }
                mediaPlayer.play();
            }
            return;
        }
        mediaPlayer.stop();
        mediaPlayer.source = "";
        mediaPlayer.videoOutput = null;
        mediaPlayer.isVideo = isVideo;
        mediaPlayer.uid = attachment.uid;
        Phone.useAttachment(attachment, "play");
    }

    function enterFullscreen(): void {
        root.fullscreenImage = false;
        root.fullscreenVideo = true;
        mediaPlayer.videoOutput = fullVideo;
        videoOverlay.forceActiveFocus();
    }

    // The video's bubble takes the picture back.
    function exitFullscreen(): void {
        if (!root.fullscreenVideo) return;
        root.fullscreenVideo = false;
        if (!root.composing) input.forceActiveFocus();
    }

    // Browse images in conversation order, keeping the message identity when
    // the same attachment appears more than once.
    readonly property var imageItems: {
        if (!root.fullscreenImage) return [];
        const images = [];
        for (const [messageIndex, message] of Phone.threadMessages.entries()) {
            for (const [attachmentIndex, attachment] of (message.attachments || []).entries()) {
                if (!Phone.isImage(attachment)) continue;
                const source = Phone.attachmentFiles[String(attachment.uid ?? "")] || attachment.path || attachment.thumb || "";
                images.push({key: `${message.uid ?? messageIndex}:${attachmentIndex}`, attachment, source,
                    isGif: /gif/i.test(attachment.mime || "") || /\.gif($|\?)/i.test(source)});
            }
        }
        return images;
    }
    readonly property int imageIndex: root.imageItems.findIndex(image => root.fullscreenMedia?.key
        ? image.key === root.fullscreenMedia.key
        : root.fullscreenMedia?.attachment && (image.attachment === root.fullscreenMedia.attachment
            || String(image.attachment.uid ?? "") !== "" && image.attachment.uid === root.fullscreenMedia.attachment.uid))
    readonly property bool hasPreviousImage: root.fullscreenImage && root.imageIndex > 0
    readonly property bool hasNextImage: root.fullscreenImage && root.imageIndex >= 0 && root.imageIndex < root.imageItems.length - 1
    function stepImage(direction): void {
        if (!root.fullscreenImage || root.imageIndex < 0) return;
        const image = root.imageItems[root.imageIndex + direction];
        if (image) root.openFullscreenImage(image.source, image.isGif, image.attachment, image.key);
    }

    function openFullscreenImage(source, isGif, attachment, key = ""): void {
        root.fullscreenVideo = false;
        imageOverlay.fullFailed = false;
        root.fullscreenMedia = { source, isGif, attachment, key };
        root.fullscreenImage = true;
        const uid = String(attachment?.uid ?? "");
        const part = Number(attachment?.part ?? -1);
        if (uid && !Phone.attachmentFiles[uid] && !Phone.attachmentBusy(uid) && part >= 0) {
            Phone.command({ "cmd": "attachment", "device": Phone.deviceId, "part": part, "uid": uid });
        }
        imageOverlay.forceActiveFocus();
    }

    function exitFullscreenImage(): void {
        if (!root.fullscreenImage) return;
        root.fullscreenImage = false;
        root.fullscreenMedia = null;
        if (!root.composing) input.forceActiveFocus();
    }

    function stopMedia(): void {
        root.fullscreenVideo = false;
        root.fullscreenImage = false;
        root.fullscreenMedia = null;
        if (root.recordingVoice) voiceRecordProc.cancel();
        mediaPlayer.stop();
        mediaPlayer.source = "";
        mediaPlayer.uid = "";
        mediaPlayer.isVideo = false;
    }

    PhoneVoiceRecorder {
        id: voiceRecordProc
        onFinished: (path, target) => {
            if (target === root.draftKey()) root.sendVoiceNote(path);
            else root.addToDraft(target, path);
        }
    }

    property bool reactionBarOpen: false
    property var activeReactionMessage: null
    property string activeReactionLink: ""
    property var activeReactionBubble: null
    property rect activeBubbleRect: Qt.rect(0, 0, 0, 0)
    property real reactionBottomPad: 0

    property var pendingReactionMessage: null
    property var pendingReactionBubble: null
    property string pendingReactionLink: ""

    NumberAnimation {
        id: reactionScrollAnim
        target: messageList
        property: "contentY"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: {
            if (root.pendingReactionBubble && root.pendingReactionMessage) {
                root.presentReactionBar(root.pendingReactionMessage, root.pendingReactionBubble, root.pendingReactionLink);
            }
            root.pendingReactionMessage = null;
            root.pendingReactionBubble = null;
            root.pendingReactionLink = "";
        }
    }

    function openReactionBar(msg, bubbleItem, link): void {
        if (!msg || !bubbleItem) return;
        reactionScrollAnim.stop();
        root.reactionBottomPad = 0;

        const wellPt = timelineWell.mapToItem(root, 0, 0);
        const wellTop = wellPt.y;
        const wellBottom = wellPt.y + timelineWell.height;
        const barH = reactionBar.implicitHeight || 46;

        const bHeight = Math.max(bubbleItem.height, bubbleItem.implicitHeight);
        let curPt = bubbleItem.mapToItem(root, 0, 0);
        let targetContentY = messageList.contentY;

        // The bubble scrolls fully into view, with room for the bar above it, before the bar opens.
        if (curPt.y - barH - 8 < wellTop + 8) {
            const neededShift = (wellTop + barH + 16) - curPt.y;
            const minY = messageList.originY - messageList.topMargin;
            targetContentY = Math.max(minY, messageList.contentY - neededShift);
        } else if (curPt.y + bHeight > wellBottom - 16) {
            const overflow = (curPt.y + bHeight) - (wellBottom - 16);
            root.reactionBottomPad = overflow + 16;
            targetContentY = messageList.contentY + overflow;
        }

        if (Math.abs(targetContentY - messageList.contentY) > 2) {
            root.pendingReactionMessage = msg;
            root.pendingReactionBubble = bubbleItem;
            root.pendingReactionLink = link || "";
            reactionScrollAnim.from = messageList.contentY;
            reactionScrollAnim.to = targetContentY;
            reactionScrollAnim.start();
            return;
        }

        root.presentReactionBar(msg, bubbleItem, link);
    }

    function presentReactionBar(msg, bubbleItem, link): void {
        if (!msg || !bubbleItem) return;
        root.activeReactionMessage = msg;
        root.activeReactionLink = link || "";
        root.activeReactionBubble = bubbleItem;

        const hasLink = !!(link && String(link).length > 0);
        let barW = reactionBar.implicitWidth > 0 ? reactionBar.implicitWidth : 300;
        if (hasLink && !reactionBar.link) {
            barW += 32;
        }
        const barH = reactionBar.implicitHeight || 46;

        const wellPt = timelineWell.mapToItem(root, 0, 0);
        const wellTop = wellPt.y;
        const wellBottom = wellPt.y + timelineWell.height;

        const bWidth = Math.max(bubbleItem.width, bubbleItem.implicitWidth);
        const bHeight = Math.max(bubbleItem.height, bubbleItem.implicitHeight);
        const pt = bubbleItem.mapToItem(root, 0, 0);
        root.activeBubbleRect = Qt.rect(pt.x, pt.y, bWidth, bHeight);

        const isOut = Phone.isOutgoing(msg);

        let targetX = isOut ? (pt.x + bWidth - barW) : pt.x;
        targetX = Math.max(12, Math.min(targetX, root.width - barW - 12));

        let targetY = pt.y - barH - 8;
        if (targetY < wellTop + 8) {
            targetY = pt.y + bHeight + 8;
        }
        targetY = Math.max(wellTop + 8, Math.min(targetY, wellBottom - barH - 8));

        reactionBar.x = targetX;
        reactionBar.y = targetY;
        root.reactionBarOpen = true;
        reactionBar.triggerPop();
        if (activeBubbleClone) activeBubbleClone.scheduleUpdate();
    }

    function closeReactionBar(): void {
        reactionScrollAnim.stop();
        root.pendingReactionMessage = null;
        root.pendingReactionBubble = null;
        root.pendingReactionLink = "";
        root.reactionBottomPad = 0;
        root.reactionBarOpen = false;
        root.activeReactionMessage = null;
        root.activeReactionLink = "";
        root.activeReactionBubble = null;
    }

    function handleReactionSelected(emoji): void {
        const msg = root.activeReactionMessage;
        root.closeReactionBar();
        if (!msg) return;

        let target = String(msg.body ?? "").trim();
        let isMedia = false;
        let mediaKind = "attachment";

        if (target.length === 0 && msg.attachments && msg.attachments.length > 0) {
            const att = msg.attachments[0];
            isMedia = true;
            if (/^video\//.test(att.mime)) mediaKind = "video";
            else if (/^image\//.test(att.mime) || (att.thumb && att.thumb.length > 0)) mediaKind = "image";
            else if (/^audio\//.test(att.mime)) mediaKind = "audio";
            else mediaKind = "attachment";
        }

        if (target.length === 0 && !isMedia) return;

        const existingReaction = (msg.reactions || []).find(r => r.outgoing);
        const isRemove = existingReaction && existingReaction.emoji === emoji;

        root.sendReaction(emoji, target, isMedia, mediaKind, isRemove);
    }

    function sendReaction(emoji, target, isMedia, mediaKind, isRemove): void {
        if (!Phone.reachable && !Phone.device) return;
        let replyText = "";
        const cleanEmoji = String(emoji || "").trim();

        if (isRemove) {
            if (isMedia) {
                replyText = `\u200aRemoved a ${cleanEmoji} from an ${mediaKind || "attachment"}\u200a`;
            } else {
                replyText = `\u200aRemoved a ${cleanEmoji} from “\u200a${target}\u200a”\u200a`;
            }
        } else {
            if (isMedia) {
                replyText = `\u200a${cleanEmoji} to an ${mediaKind || "attachment"}\u200a`;
            } else {
                replyText = `\u200a${cleanEmoji} to “\u200a${target}\u200a”\u200a`;
            }
        }

        Phone.reply(replyText, []);
    }

    // One clip plays at a time, and only while the conversation is on screen.
    MediaPlayer {
        id: mediaPlayer
        property string uid: ""
        property bool isVideo: false
        audioOutput: AudioOutput {}
        loops: (mediaPlayer.isVideo || mediaPlayer.uid.startsWith("link:")) ? MediaPlayer.Infinite : 1
        onErrorOccurred: (error, errorString) => {
            const isLink = mediaPlayer.uid.startsWith("link:");
            root.notice((isLink ? Translation.tr("Could not play this video: %1") : Translation.tr("Could not play this attachment: %1")).arg(errorString));
            root.stopMedia();
        }
        onPlaybackStateChanged: {
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState) Phone.playingMedia = "thread";
            if (mediaPlayer.playbackState === MediaPlayer.StoppedState &&
                (mediaPlayer.isVideo || mediaPlayer.uid.startsWith("link:")) &&
                mediaPlayer.duration > 0 &&
                mediaPlayer.position >= mediaPlayer.duration - 300) {
                mediaPlayer.setPosition(0);
                mediaPlayer.play();
            }
        }
    }

    property bool threadSearchOpen: false

    readonly property var threadSummary: Phone.conversations.find(m => m.thread === Phone.openThread)
        ?? Phone.threadMessages[Phone.threadMessages.length - 1]
        ?? null

    readonly property string threadPhoneSubtitle: {
        const s = root.threadSummary;
        if (!s) return "SMS";
        const addr = String((s.addresses && s.addresses[0]) || s.sender || "").trim();
        const title = String(Phone.conversationTitle(s) || "").trim();
        if (addr.length > 0 && addr !== title) return `${addr} · SMS`;
        return "SMS";
    }

    readonly property string latestTimelineDateLabel: {
        const msgs = Phone.threadMessages ?? [];
        if (msgs.length === 0) return Translation.tr("Today");
        const lastMs = msgs[msgs.length - 1]?.date ?? 0;
        if (!lastMs) return Translation.tr("Today");
        const d = new Date(lastMs);
        const now = new Date();
        if (d.toDateString() === now.toDateString()) return Translation.tr("Today");
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    function snapToBottom(): void {
        if (messageList.count <= 0) return;
        messageList.forceLayout();
        messageList.positionViewAtEnd();
        Qt.callLater(() => {
            if (messageList.count > 0 && !messageList.userScrolling) {
                messageList.forceLayout();
                messageList.positionViewAtEnd();
            }
        });
    }

    Connections {
        target: Phone
        function onSendFinished(request, success) {
            const pending = root.pendingSend;
            if (pending?.request !== request) return;
            root.pendingSend = null;
            if (!success) {
                root.notice(Translation.tr("Message not sent. Your draft has been kept; check the connection and try again."));
                return;
            }
            const draft = root.drafts[pending.draftKey];
            if (draft?.text === pending.text && JSON.stringify(draft.attachments) === JSON.stringify(pending.attachments)) {
                const remaining = Object.assign({}, root.drafts);
                delete remaining[pending.draftKey];
                root.drafts = remaining;
            }
            const sameContext = pending.device === Phone.deviceId && pending.composing === root.composing
                && (pending.composing ? recipientField.text === pending.recipient : Phone.openThread === pending.thread);
            if (!sameContext || input.text !== pending.text || JSON.stringify(root.attachments) !== JSON.stringify(pending.attachments)) return;
            input.text = "";
            root.attachments = [];
            root.activeReplyMessage = null;
            root.saveDraft();
            if (root.composing) { recipientField.text = ""; root.back(); }
        }
        function onAudioReady(uid, path, device) {
            if (uid !== mediaPlayer.uid || device !== Phone.deviceId) return;
            mediaPlayer.source = FileUtils.mediaUrl(path);
            mediaPlayer.play();
        }
        function onOpenThreadChanged() {
            root.stopMedia();
            root.activeReplyMessage = null;
            root.threadSearchOpen = false;
            messageList.wasAtBottom = true;
            root.snapToBottom();
        }
    }

    Connections {
        target: Phone
        function onPlayingMediaChanged() { if (Phone.playingMedia !== "thread") mediaPlayer.pause(); }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) return;
            mediaPlayer.pause();
            if (root.recordingVoice) voiceRecordProc.cancel();
        }
    }

    onVisibleChanged: {
        if (!visible) {
            mediaPlayer.pause();
            if (root.recordingVoice) voiceRecordProc.cancel();
            return;
        }
        if (messageList.wasAtBottom) root.snapToBottom();
        if (root.composing) recipientField.forceActiveFocus();
        else input.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 50
            radius: 14
            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 10
                    colBackground: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.88)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        root.attachments = [];
                        root.activeReplyMessage = null;
                        root.threadSearchOpen = false;
                        root.stopMedia();
                        root.back();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "arrow_back"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 10
                    Layout.maximumWidth: parent.width - 96

                    ClippingRectangle {
                        visible: !root.composing
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSecondaryContainer

                        Image {
                            id: headerAvatar
                            anchors.fill: parent
                            source: Phone.conversationPicture(root.threadSummary)
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(68, 68)
                            asynchronous: false
                            cache: true
                            visible: status === Image.Ready
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: headerAvatar.status !== Image.Ready
                            text: {
                                const t = Phone.conversationTitle(root.threadSummary);
                                return /^[\d+(]/.test(t) || t.length === 0 ? "#" : t.charAt(0).toUpperCase();
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.composing ? Translation.tr("New message")
                                : Phone.conversationTitle(root.threadSummary)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            visible: !root.composing
                            Layout.fillWidth: true
                            text: root.threadPhoneSubtitle
                            elide: Text.ElideRight
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                MaterialLoadingIndicator {
                    visible: Phone.threadLoading && !root.composing && Phone.threadMessages.length <= 1
                    implicitSize: 22
                    loading: visible
                }

                RippleButton {
                    visible: !root.composing && !(Phone.threadLoading && Phone.threadMessages.length <= 1)
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: 10
                    colBackground: root.threadSearchOpen
                        ? Appearance.colors.colPrimaryContainer
                        : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.88)
                    colBackgroundHover: root.threadSearchOpen
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer2Hover
                    onClicked: {
                        root.threadSearchOpen = !root.threadSearchOpen;
                        if (root.threadSearchOpen) threadSearchInput.forceActiveFocus();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "search"
                        iconSize: 17
                        color: root.threadSearchOpen
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: Translation.tr("Search in conversation")
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.threadSearchOpen && !root.composing
            implicitHeight: 36
            radius: 11
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                MaterialSymbol {
                    text: "search"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }

                TextField {
                    id: threadSearchInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Find in conversation…")
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    onTextChanged: {
                        const q = text.trim().toLowerCase();
                        if (q.length > 0) {
                            const msgs = Phone.threadMessages ?? [];
                            for (let i = msgs.length - 1; i >= 0; i--) {
                                if (String(msgs[i]?.body ?? "").toLowerCase().includes(q)) {
                                    root.scrollToMessage(String(msgs[i]?.uid ?? ""), i);
                                    break;
                                }
                            }
                        }
                    }
                    Keys.onEscapePressed: {
                        root.threadSearchOpen = false;
                        input.forceActiveFocus();
                    }
                }

                RippleButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        root.threadSearchOpen = false;
                        input.forceActiveFocus();
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // Recipient for a new message: a number, or a contact picked below
        Rectangle {
            Layout.fillWidth: true
            visible: root.composing
            implicitHeight: recipientField.implicitHeight + 18
            radius: Appearance.rounding.small
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                StyledText {
                    text: Translation.tr("To")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
                TextField {
                    id: recipientField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Name or number")
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    Keys.onReturnPressed: input.forceActiveFocus()
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.composing && root.suggestions.length > 0
            spacing: 2
            Repeater {
                model: root.suggestions
                delegate: Item {
                    id: suggestion
                    required property int index
                    required property var modelData
                    readonly property bool isFirst: suggestion.index === 0
                    readonly property bool isLast: suggestion.index === (root.suggestions.length - 1)
                    Layout.fillWidth: true
                    implicitHeight: 42

                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: suggestion.isFirst ? 14 : 4
                        topRightRadius: suggestion.isFirst ? 14 : 4
                        bottomLeftRadius: suggestion.isLast ? 14 : 4
                        bottomRightRadius: suggestion.isLast ? 14 : 4
                        color: suggMouse.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    }

                    MouseArea {
                        id: suggMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            recipientField.text = suggestion.modelData.number;
                            input.forceActiveFocus();
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        ClippingRectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: 14
                            color: Appearance.colors.colSecondaryContainer

                            Image {
                                id: suggAvatar
                                anchors.fill: parent
                                source: suggestion.modelData.picture ?? ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(56, 56)
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: suggAvatar.status !== Image.Ready
                                text: /^[\d+(]/.test(suggestion.modelData.name) || suggestion.modelData.name.length === 0 ? "#" : suggestion.modelData.name.charAt(0).toUpperCase()
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: `${suggestion.modelData.name}  ·  ${suggestion.modelData.number}`
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }

        Rectangle {
            id: timelineWell
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.composing
            radius: 14
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.55)
            clip: true

            layer.enabled: root.reactionBarOpen
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.4
            }

            StyledListView {
                id: messageList
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                clip: true
                spacing: 6
                cacheBuffer: 4000
                smoothScroll: messageList.wheelScrolling
                popin: false
                animateAppearance: false
                model: Phone.threadMessages
                property bool wasAtBottom: true
                readonly property bool isAtBottom: messageList.atYEnd || (messageList.contentHeight > 0 && messageList.contentY + messageList.height >= messageList.contentHeight - 50)
                onContentYChanged: if (messageList.userScrolling) messageList.wasAtBottom = messageList.isAtBottom
                onMovementEnded: messageList.wasAtBottom = messageList.isAtBottom
                onFlickEnded: messageList.wasAtBottom = messageList.isAtBottom
                onCountChanged: if (messageList.wasAtBottom && !messageList.userScrolling && !root.reactionBarOpen && !reactionScrollAnim.running && root.pendingReactionMessage === null) root.snapToBottom()
                onHeightChanged: if (messageList.wasAtBottom && !messageList.userScrolling && !root.reactionBarOpen && !reactionScrollAnim.running && root.pendingReactionMessage === null) root.snapToBottom()
                onContentHeightChanged: if (messageList.wasAtBottom && !messageList.userScrolling && !root.reactionBarOpen && !reactionScrollAnim.running && root.pendingReactionMessage === null) messageList.positionViewAtEnd()
                onMovingChanged: if (moving) root.closeReactionBar()
                onFlickStarted: root.closeReactionBar()

                header: Item {
                    width: messageList.width
                    height: 30
                    visible: messageList.count > 0

                    Rectangle {
                        anchors.centerIn: parent
                        height: 22
                        implicitWidth: dayHeaderLabel.implicitWidth + 18
                        radius: 11
                        color: Appearance.colors.colLayer2

                        StyledText {
                            id: dayHeaderLabel
                            anchors.centerIn: parent
                            text: root.latestTimelineDateLabel
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                footer: Item {
                    width: messageList.width
                    height: (root.reactionBottomPad > 0 && (root.reactionBarOpen || reactionScrollAnim.running || root.pendingReactionMessage !== null))
                        ? root.reactionBottomPad
                        : 16
                    Behavior on height {
                        enabled: !root.reactionBarOpen && !reactionScrollAnim.running && root.pendingReactionMessage === null
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }

                delegate: Item {
                    id: bubbleRow
                required property int index
                required property var modelData
                readonly property bool outgoing: Phone.isOutgoing(bubbleRow.modelData)
                readonly property color textColor: outgoing ? Appearance.chatBubble.mineText : Appearance.chatBubble.theirsText
                readonly property bool isLastMessage: bubbleRow.index === messageList.count - 1
                readonly property var reactions: bubbleRow.modelData.reactions ?? []
                readonly property bool hasReactions: reactions.length > 0
                readonly property var parsedQuote: PhoneReactions.parseQuote(bubbleRow.modelData.body ?? "")
                readonly property string quotedString: parsedQuote ? String(parsedQuote.quote || parsedQuote.quotedText || "") : ""
                readonly property bool hasQuote: quotedString.length > 0
                readonly property string rawReplyBody: hasQuote ? String(parsedQuote.body ?? "") : String(bubbleRow.modelData.body ?? "")
                readonly property var previewUrls: Config.options.sidebar.phone.linkPreviews
                    ? LinkPreviewService.extractUrls(bubbleRow.rawReplyBody).slice(0, 2) : []
                readonly property string displayBody: previewUrls.length > 0
                    ? LinkPreviewService.stripUrls(bubbleRow.rawReplyBody, 2)
                    : bubbleRow.rawReplyBody
                readonly property var resolvedQuoteMsg: hasQuote ? root.resolveQuotedMessage(bubbleRow.quotedString, bubbleRow.index) : null
                readonly property string quoteAuthorName: {
                    if (!hasQuote) return "";
                    if (resolvedQuoteMsg && resolvedQuoteMsg.senderName) {
                        return resolvedQuoteMsg.provider
                            ? `${resolvedQuoteMsg.senderName} · ${resolvedQuoteMsg.provider}`
                            : resolvedQuoteMsg.senderName;
                    }
                    return bubbleRow.outgoing
                        ? (Phone.conversationTitle(root.threadSummary) || Translation.tr("Them"))
                        : Translation.tr("You");
                }
                readonly property string quoteSnippetDisplay: hasQuote
                    ? String(resolvedQuoteMsg?.snippet || bubbleRow.quotedString)
                    : ""
                readonly property string quoteThumbPath: resolvedQuoteMsg?.thumbSource ?? ""
                readonly property bool isHighlighted: root.highlightedMessageUid.length > 0
                    && String(bubbleRow.modelData.uid ?? "") === root.highlightedMessageUid
                TextMetrics {
                    id: quoteSnippetMetrics
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: bubbleRow.quoteSnippetDisplay
                }
                TextMetrics {
                    id: quoteAuthorMetrics
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    text: bubbleRow.quoteAuthorName
                }
                readonly property real quoteDesiredWidth: bubbleRow.hasQuote
                    ? Math.max(quoteAuthorMetrics.advanceWidth + 20, quoteSnippetMetrics.advanceWidth)
                      + (bubbleRow.quoteThumbPath.length > 0 ? 40 : 0) + 24
                    : 0
                readonly property real capsuleWidth: Math.min(
                    messageList.width * 0.82,
                    Math.max(
                        bubbleColumn.implicitWidth + 20,
                        bubbleRow.quoteDesiredWidth
                    )
                )
                readonly property var groupedReactions: {
                    const list = bubbleRow.reactions;
                    if (!list || list.length === 0) return [];
                    const counts = {};
                    const order = [];
                    for (let i = 0; i < list.length; i++) {
                        const em = list[i].emoji;
                        if (!counts[em]) {
                            counts[em] = 1;
                            order.push(em);
                        } else {
                            counts[em]++;
                        }
                    }
                    return order.map(em => ({ emoji: em, count: counts[em] }));
                }
                width: messageList.width
                implicitHeight: (bubbleRow.hasQuote ? quoteCap.implicitHeight + 2 : 0) + bubble.implicitHeight + (hasReactions ? 12 : 0)
                height: implicitHeight

                HoverHandler {
                    id: rowHover
                }

                Item {
                    id: messageCapsule
                    anchors.right: bubbleRow.outgoing ? parent.right : undefined
                    anchors.left: bubbleRow.outgoing ? undefined : parent.left
                    width: bubbleRow.capsuleWidth
                    implicitHeight: (bubbleRow.hasQuote ? quoteCap.implicitHeight + 2 : 0) + bubble.implicitHeight
                    height: implicitHeight

                    Rectangle {
                        id: quoteCap
                        visible: bubbleRow.hasQuote
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        implicitHeight: visible ? quoteCapRow.implicitHeight + 12 : 0
                        topLeftRadius: Appearance.rounding.normal
                        topRightRadius: Appearance.rounding.normal
                        bottomLeftRadius: 5
                        bottomRightRadius: 5
                        color: bubbleRow.outgoing ? Appearance.chatBubble.mineQuote : Appearance.chatBubble.theirsQuote

                        RowLayout {
                            id: quoteCapRow
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "reply"
                                        iconSize: 13
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: bubbleRow.quoteAuthorName
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colPrimary
                                        elide: Text.ElideRight
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: bubbleRow.quoteSnippetDisplay
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: bubbleRow.outgoing ? Appearance.chatBubble.mineTextFaint : Appearance.chatBubble.theirsTextFaint
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            ClippingRectangle {
                                visible: bubbleRow.quoteThumbPath.length > 0
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: 7
                                color: ColorUtils.mix(bubble.baseColor, Appearance.colors.colLayer0Base, 0.35)
                                Image {
                                    anchors.fill: parent
                                    source: bubbleRow.quoteThumbPath.length > 0 ? FileUtils.mediaUrl(bubbleRow.quoteThumbPath) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    autoTransform: true
                                    sourceSize: Qt.size(64, 64)
                                    asynchronous: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: (bubbleRow.resolvedQuoteMsg && (bubbleRow.resolvedQuoteMsg.targetUid || bubbleRow.resolvedQuoteMsg.targetIndex >= 0))
                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (bubbleRow.resolvedQuoteMsg) {
                                    root.scrollToMessage(bubbleRow.resolvedQuoteMsg.targetUid, bubbleRow.resolvedQuoteMsg.targetIndex);
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: bubble
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: bubbleRow.hasQuote ? quoteCap.implicitHeight + 2 : 0
                        implicitHeight: bubbleColumn.implicitHeight + 14
                        height: implicitHeight
                    topLeftRadius: bubbleRow.hasQuote ? 5 : Appearance.rounding.normal
                    topRightRadius: bubbleRow.hasQuote ? 5 : Appearance.rounding.normal
                    bottomLeftRadius: Appearance.rounding.normal
                    bottomRightRadius: Appearance.rounding.normal
                    readonly property color baseColor: bubbleRow.outgoing ? Appearance.chatBubble.mine : Appearance.chatBubble.theirs
                    color: bubbleRow.isHighlighted ? ColorUtils.mix(baseColor, Appearance.colors.colPrimary, 0.65) : baseColor
                    Behavior on color {
                        ColorAnimation { duration: 240; easing.type: Easing.OutQuad }
                    }
                    scale: (bubbleMouseArea.pressed && holdTimer.running) ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
                    }

                    MouseArea {
                        id: bubbleMouseArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

                        property real pressStartX: 0
                        property real pressStartY: 0

                        onPressed: mouse => {
                            pressStartX = mouse.x;
                            pressStartY = mouse.y;
                            const onText = bubble.mapToItem(bodyText, mouse.x, mouse.y);
                            const rawLink = bodyText.visible ? bodyText.linkAt(onText.x, onText.y) : "";
                            const link = (rawLink && rawLink.length > 0) ? rawLink : (bubbleRow.previewUrls.length > 0 ? bubbleRow.previewUrls[0] : "");
                            if (mouse.button === Qt.RightButton) {
                                root.openReactionBar(bubbleRow.modelData, messageCapsule, link);
                            } else if (mouse.button === Qt.LeftButton) {
                                holdTimer.restart();
                            }
                        }

                        onPositionChanged: mouse => {
                            if (holdTimer.running) {
                                const dx = Math.abs(mouse.x - pressStartX);
                                const dy = Math.abs(mouse.y - pressStartY);
                                if (dx > 10 || dy > 10) holdTimer.stop();
                            }
                        }

                        onReleased: mouse => {
                            if (holdTimer.running) {
                                holdTimer.stop();
                                if (mouse.button === Qt.LeftButton && bodyText.visible) {
                                    const onText = bubble.mapToItem(bodyText, mouse.x, mouse.y);
                                    const link = bodyText.linkAt(onText.x, onText.y);
                                    if (link && link.length > 0) linkArea.activate(link);
                                }
                            }
                        }

                        onCanceled: holdTimer.stop()

                        Timer {
                            id: holdTimer
                            interval: 350
                            repeat: false
                            onTriggered: {
                                const onText = bubble.mapToItem(bodyText, bubbleMouseArea.pressStartX, bubbleMouseArea.pressStartY);
                                const rawLink = bodyText.visible ? bodyText.linkAt(onText.x, onText.y) : "";
                                const link = (rawLink && rawLink.length > 0) ? rawLink : (bubbleRow.previewUrls.length > 0 ? bubbleRow.previewUrls[0] : "");
                                root.openReactionBar(bubbleRow.modelData, messageCapsule, link);
                            }
                        }
                    }

                    ColumnLayout {
                        id: bubbleColumn
                        anchors.fill: parent
                        anchors.margins: 7
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 4

                        // A click opens the full file from the phone; the corner button saves it.
                        Repeater {
                            model: bubbleRow.modelData.attachments
                            delegate: Item {
                                id: attachmentItem
                                required property int index
                                required property var modelData
                                property bool fullFailed: false
                                readonly property bool isGif: {
                                    const mime = (attachmentItem.modelData.mime ?? "").toLowerCase();
                                    if (mime === "image/gif" || mime.endsWith("/gif")) return true;
                                    const p = (attachmentItem.fileSource || attachmentItem.modelData.path || attachmentItem.modelData.thumb || "").toLowerCase();
                                    return /\.gif($|\?)/i.test(p);
                                }
                                readonly property string fileSource: {
                                    if (fullFailed) return attachmentItem.modelData.thumb ?? "";
                                    const uid = String(attachmentItem.modelData.uid ?? "");
                                    const cached = uid ? (Phone.attachmentFiles && Phone.attachmentFiles[uid]) : "";
                                    if (cached && cached.length > 0) return cached;
                                    if (attachmentItem.modelData.path && attachmentItem.modelData.path.length > 0)
                                        return attachmentItem.modelData.path;
                                    return attachmentItem.modelData.thumb ?? "";
                                }
                                property bool newlyArrived: Math.abs(Date.now() - (bubbleRow.modelData.date ?? 0)) < 30000
                                readonly property bool isHovered: thumbHover.hovered || thumbMouse.containsMouse || saveButton.hovered || bubbleMouseArea.containsMouse
                                readonly property bool shouldPlayGif: isGif && (bubbleRow.isLastMessage || newlyArrived || isHovered)

                                Timer {
                                    id: playRecentTimer
                                    interval: 20000
                                    running: attachmentItem.newlyArrived
                                    onTriggered: attachmentItem.newlyArrived = false
                                }

                                Component.onCompleted: {
                                    if (Math.abs(Date.now() - (bubbleRow.modelData.date ?? 0)) < 30000) {
                                        attachmentItem.newlyArrived = true;
                                        playRecentTimer.restart();
                                    }
                                }

                                readonly property string kind: /^audio\//.test(attachmentItem.modelData.mime) ? "audio"
                                    : /^video\//.test(attachmentItem.modelData.mime) ? "video"
                                    : /^image\//.test(attachmentItem.modelData.mime) || (attachmentItem.modelData.thumb && attachmentItem.modelData.thumb.length > 0) ? "image" : "file"
                                readonly property bool opening: Phone.attachmentActions[Phone.actionKey(Phone.deviceId, attachmentItem.modelData.uid)]?.action === "open"
                                Layout.preferredWidth: attachmentItem.kind === "image" ? Math.min(200, messageList.width * 0.6)
                                    : attachmentItem.kind === "audio" ? Math.min(300, messageList.width * 0.72)
                                    : attachmentItem.kind === "video" ? videoLoader.implicitWidth : chip.implicitWidth
                                Layout.preferredHeight: {
                                    if (attachmentItem.kind === "image") {
                                        const img = attachmentItem.isGif ? gifThumb : staticThumb;
                                        if (img.implicitWidth > 0 && img.implicitHeight > 0) {
                                            return Layout.preferredWidth * (img.implicitHeight / img.implicitWidth);
                                        }
                                        return Layout.preferredWidth * 0.75;
                                    }
                                    if (attachmentItem.kind === "audio") return audioLoader.implicitHeight;
                                    if (attachmentItem.kind === "video") return videoLoader.implicitHeight;
                                    return chip.implicitHeight;
                                }

                                ClippingRectangle {
                                    anchors.fill: parent
                                    visible: attachmentItem.kind === "image"
                                    radius: Appearance.rounding.normal
                                    color: "transparent"

                                    AnimatedImage {
                                        id: gifThumb
                                        anchors.fill: parent
                                        visible: attachmentItem.kind === "image" && attachmentItem.isGif
                                        source: (attachmentItem.kind === "image" && attachmentItem.isGif) ? FileUtils.mediaUrl(attachmentItem.fileSource) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: false
                                        cache: true
                                        playing: true
                                        paused: !attachmentItem.shouldPlayGif || !attachmentItem.visible || !attachmentItem.Window.window?.visible
                                        opacity: attachmentItem.opening ? 0.6 : 1
                                        scale: thumbMouse.pressed ? 0.94 : 1
                                        onStatusChanged: {
                                            if (status === Image.Error && !attachmentItem.fullFailed && (attachmentItem.modelData.thumb ?? "").length > 0) {
                                                attachmentItem.fullFailed = true;
                                            }
                                        }
                                        Behavior on opacity {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                        Behavior on scale {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                    }

                                    Image {
                                        id: staticThumb
                                        anchors.fill: parent
                                        visible: attachmentItem.kind === "image" && !attachmentItem.isGif
                                        source: (attachmentItem.kind === "image" && !attachmentItem.isGif) ? FileUtils.mediaUrl(attachmentItem.fileSource) : ""
                                        fillMode: Image.PreserveAspectCrop
                                        autoTransform: true
                                        asynchronous: false
                                        cache: true
                                        sourceSize.width: 400
                                        opacity: attachmentItem.opening ? 0.6 : 1
                                        scale: thumbMouse.pressed ? 0.94 : 1
                                        onStatusChanged: {
                                            if (status === Image.Error && !attachmentItem.fullFailed && (attachmentItem.modelData.thumb ?? "").length > 0) {
                                                attachmentItem.fullFailed = true;
                                            }
                                        }
                                        Behavior on opacity {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                        Behavior on scale {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: thumbMouse
                                    anchors.fill: parent
                                    visible: attachmentItem.kind === "image"
                                    enabled: attachmentItem.kind === "image"
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    pressAndHoldInterval: 350
                                    property bool held: false
                                    onPressed: mouse => {
                                        held = false;
                                        if (mouse.button === Qt.RightButton) {
                                            const link = (bubbleRow.previewUrls && bubbleRow.previewUrls.length > 0) ? bubbleRow.previewUrls[0] : "";
                                            root.openReactionBar(bubbleRow.modelData, messageCapsule, link);
                                        }
                                    }
                                    onPressAndHold: {
                                        held = true;
                                        const link = (bubbleRow.previewUrls && bubbleRow.previewUrls.length > 0) ? bubbleRow.previewUrls[0] : "";
                                        root.openReactionBar(bubbleRow.modelData, messageCapsule, link);
                                    }
                                    onCanceled: held = false
                                    onClicked: mouse => {
                                        if (held) return;
                                        if (mouse.button === Qt.LeftButton && attachmentItem.kind === "image") {
                                            root.openFullscreenImage(attachmentItem.fileSource, attachmentItem.isGif, attachmentItem.modelData,
                                                `${bubbleRow.modelData.uid ?? bubbleRow.index}:${attachmentItem.index}`);
                                        }
                                    }
                                }

                                HoverHandler {
                                    id: thumbHover
                                    enabled: attachmentItem.kind === "image"
                                }

                                StyledToolTip {
                                    extraVisibleCondition: attachmentItem.kind === "image" && thumbHover.hovered
                                    text: Translation.tr("Click to expand")
                                }
                                Loader {
                                    id: audioLoader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    active: attachmentItem.kind === "audio"
                                    visible: active
                                    sourceComponent: PhoneAudioAttachment {
                                        attachment: attachmentItem.modelData
                                        player: mediaPlayer
                                        current: mediaPlayer.uid === attachmentItem.modelData.uid
                                        contentColor: bubbleRow.textColor
                                        onToggle: root.toggleMedia(attachmentItem.modelData, false)
                                    }
                                }
                                Loader {
                                    id: videoLoader
                                    active: attachmentItem.kind === "video"
                                    visible: active
                                    sourceComponent: PhoneVideoAttachment {
                                        attachment: attachmentItem.modelData
                                        player: mediaPlayer
                                        current: mediaPlayer.uid === attachmentItem.modelData.uid
                                        frameWidth: Math.min(240, messageList.width * 0.65)
                                        fullscreen: root.fullscreenVideo
                                        onFullscreenRequested: root.enterFullscreen()
                                        contentColor: bubbleRow.textColor
                                        onToggle: root.toggleMedia(attachmentItem.modelData, true)
                                        onReactRequested: {
                                            const link = (bubbleRow.previewUrls && bubbleRow.previewUrls.length > 0) ? bubbleRow.previewUrls[0] : "";
                                            root.openReactionBar(bubbleRow.modelData, messageCapsule, link);
                                        }
                                    }
                                }
                                RowLayout {
                                    id: chip
                                    visible: attachmentItem.kind === "file"
                                    spacing: 6
                                    MaterialSymbol {
                                        text: /^image/.test(attachmentItem.modelData.mime) ? "image" : "description"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: bubbleRow.textColor
                                    }
                                    RippleButton {
                                        implicitHeight: 28
                                        implicitWidth: openLabel.implicitWidth + 16
                                        buttonRadius: Appearance.rounding.small
                                        onClicked: Phone.useAttachment(attachmentItem.modelData, "open")
                                        contentItem: StyledText {
                                            id: openLabel
                                            anchors.centerIn: parent
                                            text: Translation.tr("Open")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: bubbleRow.textColor
                                        }
                                    }
                                    PhoneSaveButton {
                                        attachment: attachmentItem.modelData
                                        iconColor: bubbleRow.textColor
                                    }
                                }
                                PhoneSaveButton {
                                    id: saveButton
                                    visible: attachmentItem.kind === "image"
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    attachment: attachmentItem.modelData
                                    iconColor: Appearance.colors.colOnLayer0
                                    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.25)
                                }
                                MaterialLoadingIndicator {
                                    anchors.centerIn: parent
                                    visible: attachmentItem.opening && (attachmentItem.kind === "image" || attachmentItem.kind === "file")
                                    implicitSize: 32
                                    loading: visible
                                }

                                SequentialAnimation {
                                    id: openPop
                                    NumberAnimation { target: attachmentItem; property: "scale"; to: 1.05; duration: 110; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: attachmentItem; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
                                }
                                Connections {
                                    target: Phone
                                    function onOpened(uid) {
                                        if (uid === attachmentItem.modelData.uid) openPop.restart();
                                    }
                                }
                            }
                        }
                        StyledText {
                            id: bodyText
                            readonly property string linked: StringUtils.linkify(bubbleRow.displayBody)
                            Layout.fillWidth: true
                            Layout.maximumWidth: messageList.width * 0.82 - 20
                            visible: bubbleRow.displayBody.length > 0
                            text: bodyText.linked.length > 0 ? bodyText.linked : bubbleRow.displayBody
                            wrapMode: Text.Wrap
                            textFormat: bodyText.linked.length > 0 ? Text.StyledText : Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: bubbleRow.textColor
                            linkColor: bubbleRow.outgoing ? Appearance.chatBubble.mineText : Appearance.colors.colPrimary
                            onLinkActivated: link => linkArea.activate(link)

                            MessageLinkArea {
                                id: linkArea
                                textItem: bodyText
                                closeSidebarOnOpen: false
                            }
                        }
                        Repeater {
                            model: bubbleRow.previewUrls
                            delegate: PhoneLinkPreview {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.maximumWidth: messageList.width * 0.82 - 20
                                maxCardWidth: messageList.width * 0.82 - 20
                                url: modelData
                                outgoing: bubbleRow.outgoing
                                player: mediaPlayer
                                fullscreen: root.fullscreenVideo
                                onFullscreenRequested: root.enterFullscreen()
                                onReactRequested: {
                                    root.openReactionBar(bubbleRow.modelData, messageCapsule, modelData);
                                }
                            }
                        }
                        StyledText {
                            Layout.alignment: bubbleRow.outgoing ? Qt.AlignRight : Qt.AlignLeft
                            text: (bubbleRow.modelData.type === 5 ? Translation.tr("Not sent") + " · " : bubbleRow.modelData.type === 6 ? Translation.tr("Sending…") + " · " : "")
                                + new Date(bubbleRow.modelData.date).toLocaleString(Qt.locale(), Locale.ShortFormat)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: bubbleRow.modelData.type === 5
                                ? Appearance.m3colors.m3error
                                : (bubbleRow.outgoing
                                    ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.35)
                                    : ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35))
                        }
                    }
                }

                Rectangle {
                    visible: bubbleRow.hasReactions
                    z: 3
                    anchors.bottom: bubble.bottom
                    anchors.bottomMargin: -9
                    anchors.right: bubbleRow.outgoing ? undefined : bubble.right
                    anchors.left: bubbleRow.outgoing ? bubble.left : undefined
                    anchors.rightMargin: bubbleRow.outgoing ? 0 : 10
                    anchors.leftMargin: bubbleRow.outgoing ? 10 : 0
                    implicitWidth: reactionRow.implicitWidth + 12
                    implicitHeight: 24
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer3Base

                    scale: pillMouse.pressed ? 0.94 : 1
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    Row {
                        id: reactionRow
                        anchors.centerIn: parent
                        spacing: 3
                        Repeater {
                            model: bubbleRow.groupedReactions
                            delegate: Row {
                                required property var modelData
                                spacing: 2
                                StyledText {
                                    text: modelData.emoji
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    visible: modelData.count > 1
                                    text: modelData.count
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colSubtext
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openReactionBar(bubbleRow.modelData, messageCapsule, "")
                    }

                    StyledToolTip {
                        extraVisibleCondition: pillMouse.containsMouse
                        text: {
                            if (!bubbleRow.hasReactions) return "";
                            return bubbleRow.reactions.map(r => {
                                const sender = r.outgoing ? Translation.tr("You") : (Phone.nameFor(r.sender) || Translation.tr("Sender"));
                                return `${r.emoji} ${sender}`;
                            }).join("\n");
                        }
                    }
                }
                } // End messageCapsule

                RippleButton {
                    id: quickReplyBtn
                    anchors.verticalCenter: messageCapsule.verticalCenter
                    anchors.left: bubbleRow.outgoing ? undefined : messageCapsule.right
                    anchors.right: bubbleRow.outgoing ? messageCapsule.left : undefined
                    anchors.leftMargin: bubbleRow.outgoing ? 0 : 6
                    anchors.rightMargin: bubbleRow.outgoing ? 6 : 0
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colPrimary, 0.25)
                    readonly property bool showBtn: rowHover.hovered || bubbleMouseArea.containsMouse || quickReplyBtn.hovered
                    opacity: showBtn ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                    }
                    onClicked: root.startReply(bubbleRow.modelData)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "reply"
                        iconSize: 15
                        color: quickReplyBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                    }
                    StyledToolTip {
                        text: Translation.tr("Reply")
                    }
                }
            }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: root.composing
        }

        PhoneSaveCard {
            id: pageSaveCard
            Layout.fillWidth: true
            from: "message"
        }

        Repeater {
            model: root.attachments
            delegate: AttachedFileIndicator {
                required property string modelData
                Layout.fillWidth: true
                filePath: modelData
                maxHeight: 120
                onRemove: root.attachments = root.attachments.filter(p => p !== modelData)
            }
        }

        PhoneGifPicker {
            Layout.fillWidth: true
            visible: root.gifPickerOpen
            onClosed: root.gifPickerOpen = false
            onDownloadStarted: root.gifTarget = root.draftKey()
            onGifChosen: (path, directSend) => root.attachOrSendGif(path, directSend)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Rectangle {
                id: replyComposerCap
                Layout.fillWidth: true
                visible: root.activeReplyMessage !== null
                implicitHeight: visible ? Math.max(44, replyComposerRow.implicitHeight + 12) : 0
                topLeftRadius: 14
                topRightRadius: 14
                bottomLeftRadius: 4
                bottomRightRadius: 4
                color: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer0Base, 0.55)

                readonly property var quoteSummary: root.quoteSummaryFor(root.activeReplyMessage)
                readonly property string replyTargetAuthor: {
                    if (!root.activeReplyMessage) return "";
                    const base = Phone.isOutgoing(root.activeReplyMessage)
                        ? Translation.tr("yourself")
                        : (Phone.nameFor(root.activeReplyMessage.sender) || Phone.conversationTitle(root.threadSummary) || Translation.tr("message"));
                    const prov = quoteSummary?.provider ?? "";
                    return prov.length > 0 ? `${base} · ${prov}` : base;
                }
                readonly property string replyTargetThumb: quoteSummary?.thumbSource ?? ""

                RowLayout {
                    id: replyComposerRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 10

                    MaterialSymbol {
                        text: "reply"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Replying to %1").arg(replyComposerCap.replyTargetAuthor)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(replyComposerCap.quoteSummary?.snippet ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.3)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    ClippingRectangle {
                        visible: replyComposerCap.replyTargetThumb.length > 0
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: 7
                        color: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer0Base, 0.35)
                        Image {
                            anchors.fill: parent
                            source: replyComposerCap.replyTargetThumb.length > 0 ? FileUtils.mediaUrl(replyComposerCap.replyTargetThumb) : ""
                            fillMode: Image.PreserveAspectCrop
                            autoTransform: true
                            sourceSize: Qt.size(60, 60)
                            asynchronous: true
                        }
                    }

                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: 13
                        colBackground: "transparent"
                        colBackgroundHover: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer0Base, 0.3)
                        onClicked: root.cancelReply()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 15
                            color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35)
                        }
                        StyledToolTip {
                            text: Translation.tr("Cancel reply (Esc)")
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(46, input.implicitHeight + 16)
                topLeftRadius: root.activeReplyMessage !== null ? 4 : 14
                topRightRadius: root.activeReplyMessage !== null ? 4 : 14
                bottomLeftRadius: 14
                bottomRightRadius: 14
                color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 7
                    spacing: 2
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 9
                        enabled: Phone.reachable && !root.recordingVoice
                        onClicked: root.attachRequested()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "add_photo_alternate"
                            iconSize: 18
                            color: parent.enabled ? Appearance.colors.colSubtext : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5)
                        }
                        StyledToolTip {
                            text: Translation.tr("Attach pictures or files\nOr drop them on this conversation")
                        }
                    }
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 9
                        enabled: Phone.reachable && !root.recordingVoice
                        onClicked: root.toggleGifPicker()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "gif_box"
                            iconSize: 18
                            color: root.gifPickerOpen ? Appearance.colors.colPrimary : (parent.enabled ? Appearance.colors.colSubtext : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5))
                        }
                        StyledToolTip {
                            text: Translation.tr("Search and send GIFs")
                        }
                    }
                    StyledTextArea {
                        id: input
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        verticalAlignment: TextEdit.AlignVCenter
                        visible: !root.recordingVoice
                        wrapMode: TextArea.Wrap
                        placeholderText: !Phone.reachable
                            ? Translation.tr("Your phone is not reachable right now.")
                            : (root.activeReplyMessage !== null ? Translation.tr("Write a reply…") : Translation.tr("Text message"))
                        enabled: Phone.reachable && !root.recordingVoice
                        background: null
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                root.send();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.gifPickerOpen) {
                                    root.gifPickerOpen = false;
                                    event.accepted = true;
                                } else if (root.activeReplyMessage !== null) {
                                    root.cancelReply();
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 6
                        Layout.rightMargin: 4
                        visible: root.recordingVoice
                        spacing: 8

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 10
                            implicitHeight: 10
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
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colError
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: voiceRecordProc.cancel()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                            }
                            StyledToolTip {
                                text: Translation.tr("Cancel recording (Esc)")
                            }
                        }
                    }
                    RippleButton {
                        id: micButton
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        enabled: Phone.reachable && Phone.canMessage && !root.pendingSend
                        Keys.onEscapePressed: if (root.recordingVoice) voiceRecordProc.cancel()
                        onClicked: {
                            if (root.recordingVoice) {
                                voiceRecordProc.stopAndSend();
                            } else {
                                voiceRecordProc.start(root.draftKey());
                                micButton.forceActiveFocus();
                            }
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.recordingVoice ? "stop" : "mic"
                            iconSize: 18
                            color: root.recordingVoice ? Appearance.colors.colError : (parent.enabled ? (micButton.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSubtext) : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5))
                        }
                        StyledToolTip {
                            text: root.recordingVoice
                                ? Translation.tr("Stop and send voice note (Right-click or Esc to cancel)")
                                : Translation.tr("Record voice note\n(Click to record, click again to send)")
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.recordingVoice) voiceRecordProc.cancel();
                            }
                        }
                    }

                    Rectangle {
                        id: sendButton
                        Layout.alignment: Qt.AlignVCenter
                        Layout.leftMargin: 3
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 16
                        readonly property bool canSend: Phone.reachable
                            && (root.recordingVoice || input.text.trim().length > 0 || root.attachments.length > 0)
                            && (!root.composing || recipientField.text.trim().length > 0)
                        color: canSend
                            ? (sendMouse.pressed
                                ? ColorUtils.mix(Appearance.colors.colPrimary, "black", 0.85)
                                : (sendMouse.containsMouse
                                    ? ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.88)
                                    : Appearance.colors.colPrimary))
                            : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.86)

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "arrow_upward"
                            iconSize: 17
                            color: sendButton.canSend ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: sendButton.canSend
                            cursorShape: sendButton.canSend ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.recordingVoice) {
                                    voiceRecordProc.stopAndSend();
                                } else {
                                    root.send();
                                }
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: sendMouse.containsMouse
                            text: root.recordingVoice ? Translation.tr("Send voice note") : Translation.tr("Send")
                        }
                    }
                }
            }
        }
    }

    Item {
        id: videoOverlay
        // The sink reports display dimensions, including a phone video's
        // rotation. sourceRect still describes the unrotated encoded frame.
        readonly property real aspect: fullVideo.videoSink.videoSize.width > 0 && fullVideo.videoSink.videoSize.height > 0
            ? fullVideo.videoSink.videoSize.width / fullVideo.videoSink.videoSize.height : 16 / 9
        readonly property bool playing: mediaPlayer.playbackState === MediaPlayer.PlayingState

        anchors.fill: parent
        z: 10
        visible: root.fullscreenVideo
        opacity: root.fullscreenVideo ? 1 : 0
        Behavior on opacity {
            enabled: root.fullscreenVideo
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Keys.onEscapePressed: root.exitFullscreen()

        // A click around the video closes it; the conversation behind takes no input.
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize("black", 0.12)
            MouseArea {
                anchors.fill: parent
                onClicked: root.exitFullscreen()
                onWheel: wheel => wheel.accepted = true
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            scale: root.fullscreenVideo ? 1 : 0.92
            Behavior on scale {
                enabled: root.fullscreenVideo
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(videoOverlay.height - fullControls.implicitHeight - 24, width / videoOverlay.aspect)

                VideoOutput {
                    id: fullVideo
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (videoOverlay.playing) {
                            mediaPlayer.pause();
                        } else {
                            if (mediaPlayer.duration > 0 && mediaPlayer.position >= mediaPlayer.duration) mediaPlayer.setPosition(0);
                            mediaPlayer.play();
                        }
                    }
                }
                PhoneVideoCornerButton {
                    iconName: "fullscreen_exit"
                    tip: Translation.tr("Exit full screen")
                    onClicked: root.exitFullscreen()
                }
            }

            RowLayout {
                id: fullControls
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: 4
                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize("white", 0.88)
                    colBackgroundHover: ColorUtils.transparentize("white", 0.8)
                    onClicked: {
                        if (videoOverlay.playing) {
                            mediaPlayer.pause();
                        } else {
                            if (mediaPlayer.duration > 0 && mediaPlayer.position >= mediaPlayer.duration) mediaPlayer.setPosition(0);
                            mediaPlayer.play();
                        }
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: videoOverlay.playing ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: "white"
                    }
                }
                PhoneMediaSeek {
                    Layout.fillWidth: true
                    player: mediaPlayer
                    current: true
                    attachment: ({ "uid": mediaPlayer.uid })
                    contentColor: "white"
                }
            }
        }
    }

    Item {
        id: imageOverlay
        property bool fullFailed: false
        readonly property string currentSource: {
            if (!root.fullscreenMedia) return "";
            const att = root.fullscreenMedia.attachment;
            const uid = String(att?.uid ?? "");
            if (!imageOverlay.fullFailed) {
                const full = uid ? (Phone.attachmentFiles && Phone.attachmentFiles[uid]) : "";
                if (full && full.length > 0) return full;
                if (att?.path && att.path.length > 0) return att.path;
                if (root.fullscreenMedia.source && root.fullscreenMedia.source.length > 0) return root.fullscreenMedia.source;
            }
            return att?.thumb || root.fullscreenMedia.source || "";
        }
        readonly property bool isGif: {
            if (!root.fullscreenMedia) return false;
            if (root.fullscreenMedia.isGif) return true;
            const att = root.fullscreenMedia.attachment;
            const mime = (att?.mime ?? "").toLowerCase();
            if (mime.includes("gif")) return true;
            const src = imageOverlay.currentSource.toLowerCase();
            return /\.gif($|\?)/i.test(src);
        }
        readonly property real aspect: {
            const w = isGif ? fullGif.implicitWidth : fullImg.implicitWidth;
            const h = isGif ? fullGif.implicitHeight : fullImg.implicitHeight;
            return (w > 0 && h > 0) ? (w / h) : (4 / 3);
        }

        anchors.fill: parent
        z: 10
        visible: opacity > 0
        opacity: root.fullscreenImage ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Keys.onEscapePressed: root.exitFullscreenImage()
        Keys.onLeftPressed: root.stepImage(-1)
        Keys.onRightPressed: root.stepImage(1)
        onVisibleChanged: if (visible) imageOverlay.forceActiveFocus()

        // A click around the image closes it; the conversation behind takes no input.
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize("black", 0.12)
            MouseArea {
                anchors.fill: parent
                onClicked: root.exitFullscreenImage()
                onWheel: wheel => wheel.accepted = true
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            scale: root.fullscreenImage ? 1 : 0.92
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(imageOverlay.height - 32, width / imageOverlay.aspect)

                AnimatedImage {
                    id: fullGif
                    anchors.fill: parent
                    visible: imageOverlay.isGif
                    source: (visible && imageOverlay.currentSource.length > 0) ? FileUtils.mediaUrl(imageOverlay.currentSource) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    playing: imageOverlay.visible && visible
                    paused: false
                    onStatusChanged: {
                        if (status === Image.Error && !imageOverlay.fullFailed) {
                            imageOverlay.fullFailed = true;
                        }
                    }
                }

                Image {
                    id: fullImg
                    anchors.fill: parent
                    visible: !imageOverlay.isGif
                    source: (visible && imageOverlay.currentSource.length > 0) ? FileUtils.mediaUrl(imageOverlay.currentSource) : ""
                    fillMode: Image.PreserveAspectFit
                    autoTransform: true
                    asynchronous: true
                    cache: true
                    onStatusChanged: {
                        if (status === Image.Error && !imageOverlay.fullFailed) {
                            imageOverlay.fullFailed = true;
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    readonly property string uid: String(root.fullscreenMedia?.attachment?.uid ?? "")
                    readonly property bool isBusy: uid.length > 0 && Phone.attachmentBusy(uid)
                    readonly property bool isLoading: (fullImg.visible && fullImg.status === Image.Loading) || (fullGif.visible && fullGif.status === Image.Loading)
                    visible: isBusy || isLoading
                    implicitSize: 36
                    loading: visible
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.exitFullscreenImage()
                }

                PhoneVideoCornerButton {
                    iconName: "fullscreen_exit"
                    tip: Translation.tr("Exit full screen")
                    onClicked: root.exitFullscreenImage()
                }

                PhoneSaveButton {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    visible: !!root.fullscreenMedia?.attachment
                    attachment: root.fullscreenMedia?.attachment
                    iconColor: "white"
                    colBackground: ColorUtils.transparentize("black", 0.45)
                }

                RippleButton {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 6
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize("black", 0.45)
                    colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                    visible: imageOverlay.currentSource.length > 0
                    onClicked: Qt.openUrlExternally(FileUtils.mediaUrl(imageOverlay.currentSource))
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: "white"
                    }
                    StyledToolTip {
                        text: Translation.tr("Open externally")
                    }
                }
            }
        }
        PhoneImageNavigationButton {
            direction: -1
            anchors.left: parent.left
            anchors.leftMargin: 12
            visible: root.hasPreviousImage
            onClicked: root.stepImage(-1)
        }
        PhoneImageNavigationButton {
            direction: 1
            anchors.right: parent.right
            anchors.rightMargin: 12
            visible: root.hasNextImage
            onClicked: root.stepImage(1)
        }
    }

    // A click outside the reaction bar closes it.
    Item {
        id: reactionOverlay
        anchors.fill: parent
        z: 20
        visible: opacity > 0
        opacity: root.reactionBarOpen ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Keys.onEscapePressed: root.closeReactionBar()
        onVisibleChanged: {
            if (visible) reactionOverlay.forceActiveFocus();
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.45)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeReactionBar()
            onWheel: wheel => { wheel.accepted = true; root.closeReactionBar(); }
        }

        ShaderEffectSource {
            id: activeBubbleClone
            visible: root.reactionBarOpen && root.activeReactionBubble !== null
            sourceItem: root.activeReactionBubble
            x: root.activeBubbleRect.x
            y: root.activeBubbleRect.y
            width: root.activeBubbleRect.width
            height: root.activeBubbleRect.height
            live: root.reactionBarOpen
        }

        PhoneReactionBar {
            id: reactionBar
            targetMessage: root.activeReactionMessage
            link: root.activeReactionLink
            scale: root.reactionBarOpen ? 1 : 0.82
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack }
            }
            onWidthChanged: {
                if (root.reactionBarOpen) {
                    if (x + width > reactionOverlay.width - 12) {
                        x = Math.max(12, reactionOverlay.width - width - 12);
                    }
                    if (x < 12) x = 12;
                }
            }

            onReact: emoji => root.handleReactionSelected(emoji)
            onReply: root.startReply(root.activeReactionMessage)
            onCopyText: {
                if (root.activeReactionMessage?.body) {
                    Quickshell.clipboardText = root.activeReactionMessage.body;
                    root.notice(Translation.tr("Text copied"));
                }
                root.closeReactionBar();
            }
            onCopyLink: {
                if (root.activeReactionLink) {
                    Quickshell.clipboardText = root.activeReactionLink.replace(/^mailto:/i, "");
                    root.notice(Translation.tr("Link copied"));
                }
                root.closeReactionBar();
            }
        }
    }

    // The viewers cover the page's save card, so a save made in one shows here,
    // above them and solid so it reads over the picture.
    PhoneSaveCard {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 12
        }
        z: 30
        from: "message"
        visible: implicitHeight > 0 && (root.fullscreenImage || root.fullscreenVideo)
        color: Appearance.colors.colLayer2Base
        onShownChanged: if (!shown && visible) pageSaveCard.shown = false
    }
}
