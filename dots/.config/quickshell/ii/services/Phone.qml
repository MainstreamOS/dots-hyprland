pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "PhoneReactions.js" as PhoneReactions
import "PhoneIdentity.js" as Identity
import "IslandPhoneHistory.js" as History

/**
 * Paired phones through KDE Connect or rust-connect, for the Phone tab, the
 * Dynamic Island and phone notifications. scripts/phone/kdeconnect-bridge.py
 * is the shell's only client of their D-Bus API, and the main shell keeps it
 * running so no text is missed while the tab is closed.
 */
Singleton {
    id: root

    // A KDE Connect-compatible backend is installed or available over D-Bus.
    property bool installed: false
    // Set by the tab once it has been on screen.
    property bool wanted: false
    onWantedChanged: if (wanted && bridge.running && !backendAvailable) root.startBackend()
    // Set by the main shell, and by Settings while a page shows phone status.
    property bool keepConnected: false
    property bool backendAvailable: false
    // "KDE Connect" or "rust-connect", whichever owns the bus name.
    property string backendName: "KDE Connect"
    readonly property bool connected: bridge.running && backendAvailable
    readonly property bool bridgeWanted: root.wanted || root.keepConnected
    // The bridge starts the daemon itself once a phone has paired; before that,
    // only opening the tab does, since the daemon announces this computer.
    function startBackend(): void {
        if (root.wanted) root.command({cmd: "start"});
    }
    property int backendGeneration: -1
    property int restartAttempts: 0
    readonly property string requestPrefix: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    property int requestSequence: 0
    property string lastSendRequest: ""
    property var pendingSends: ({})
    readonly property bool canMessage: root.device?.plugins?.includes("kdeconnect_sms") ?? false
    readonly property bool canBrowse: root.device?.plugins?.includes("kdeconnect_sftp") ?? false
    readonly property bool canShare: root.device?.plugins?.includes("kdeconnect_share") ?? false
    onReachableChanged: {
        if (reachable) root.syncDevice();
        else root.disconnectState();
    }
    onCanMessageChanged: if (canMessage && reachable) root.syncDevice()

    function syncDevice(): void {
        if (!root.connected || !root.reachable || !root.canMessage) return;
        root.command({cmd: "conversations", device: root.deviceId});
        if (root.openThread >= 0) root.command({cmd: "thread", device: root.deviceId, thread: root.openThread, count: 100});
    }
    function disconnectState(): void {
        root.cancelFilePreview();
        root.clearThumbnails();
        root.mounted = false;
        root.mounting = false;
        root.mountPoint = "";
        root.places = [];
        root.dropAttachmentActions();
        root.prefetched = ({});
        root.threadLoading = false;
        root.openingFilePath = "";
        for (const request in root.pendingSends) root.resolveSend(request, false);
    }
    signal sendFinished(request: string, success: bool)
    function resolveSend(request, success): void {
        if (!request || !root.pendingSends[request]) return;
        const pending = root.pendingSends[request];
        const remaining = Object.assign({}, root.pendingSends);
        delete remaining[request];
        root.pendingSends = remaining;
        const list = pending.device === root.deviceId ? root.localSent : (root.savedLocalSent[pending.device] || []);
        const updated = list.map(m => m.request === request ? Object.assign({}, m, {type: success ? 2 : 5}) : m);
        if (pending.device === root.deviceId) {
            root.localSent = updated;
            root.persistLocalSent();
            if (root.openThread >= 0) root.threadMessages = root.withLocal(root.threadMessages, root.openThread);
        } else {
            root.savedLocalSent = Object.assign({}, root.savedLocalSent, {[pending.device]: updated});
            saveSentTimer.restart();
        }
        root.sendFinished(request, success);
    }

    property var devices: []
    // Contacts are read for every reachable phone, once per connection.
    property var contactsSynced: []
    onDevicesChanged: {
        const reachable = root.devices.filter(d => d.reachable && d.plugins?.includes("kdeconnect_contacts")).map(d => d.id);
        for (const id of reachable)
            if (!root.contactsSynced.includes(id)) root.command({cmd: "contacts", device: id});
        root.contactsSynced = reachable;
    }
    // Phones that asked to pair, each {id, name, key}; answered from the Phone tab.
    property var pairRequests: []
    function acceptPairing(id): void {
        root.command({cmd: "acceptPairing", device: id});
    }
    function declinePairing(id): void {
        root.command({cmd: "declinePairing", device: id});
    }
    property string deviceId: ""
    readonly property var device: root.devices.find(d => d.id === root.deviceId) ?? null
    readonly property bool reachable: root.device?.reachable ?? false

    // The latest message of every conversation, newest first.
    property var conversations: []
    onConversationsChanged: root.checkPendingTarget()
    property bool conversationsLoaded: false
    onConversationsLoadedChanged: if (conversationsLoaded) root.checkPendingTarget()

    property int openThread: -1
    property var threadMessages: []
    property var threadCache: ({})
    // Replies sent from here, shown at once: the phone does not always report
    // a message sent through KDE Connect. One it reports replaces its copy.
    property var localSent: []
    property var savedLocalSent: ({})
    property bool threadLoading: false
    property var pendingTarget: null

    property bool mounting: false
    property bool mounted: false
    property string mountPoint: ""
    property var places: []
    property string mountError: ""
    property bool sshfsMissing: false

    // Full attachment files by unique id once fetched, and what each fetch
    // in flight is for: "open", "save" or "play".
    property var attachmentFiles: ({})
    property var attachmentDurations: ({})
    property var attachmentThumbs: ({})
    property var attachmentActions: ({})
    property var prefetched: ({})
    // The newest save: { ok, uid, from, name, path, folder }, for the card
    // that says where it went. "from" is "message" or "files".
    property var lastSave: null
    property var thumbnails: ({})
    // Thumbnails arrive in bursts while a folder scrolls; they land together.
    property var pendingThumbnails: ({})
    Timer {
        id: thumbnailFlush
        interval: 80
        onTriggered: {
            root.thumbnails = Object.assign({}, root.thumbnails, root.pendingThumbnails);
            root.pendingThumbnails = ({});
        }
    }
    function clearThumbnails(): void {
        thumbnailFlush.stop();
        root.pendingThumbnails = ({});
        root.thumbnails = ({});
    }
    // New incoming texts from every phone, newest first, in the Island's
    // message shape. Ids match saved Island history ("kde:<path>:<uid>").
    property var recentMessages: []
    // Recent telephony callReceived signals, which carry the caller's number.
    property var callDetails: []
    // The message player playing last ("thread" or "island"); the other pauses.
    property string playingMedia: ""

    signal conversationOpened(int thread)
    // Synced records can enrich saved Island history without posting an alert.
    signal messagesSynced(string device, var messages)
    signal shared(int count)
    signal opened(string uid)
    // An audio attachment is ready to play from this file.
    signal audioReady(string uid, string path, string device)
    // No file came back in time for the fetches in flight.
    signal attachmentTimedOut()
    signal attachmentUnavailable(string uid, string device)
    signal failed(string context, string message)
    signal notificationResult(var result)

    // Android message types: 1 inbox, 2 sent, 4 outbox, 5 failed, 6 queued.
    function isOutgoing(message): bool {
        return (message?.type ?? 1) !== 1;
    }

    function nameFor(address): string {
        return ContactService.nameFor(address, "", root.deviceId);
    }

    function pictureFor(address): string {
        return ContactService.pictureFor(address, "", root.deviceId);
    }

    function conversationTitle(message): string {
        const addresses = message?.addresses ?? [];
        if (addresses.length === 0) return Translation.tr("Unknown");
        const names = [];
        const seen = new Set();
        for (const a of addresses) {
            const name = root.nameFor(a);
            const key = name.toLowerCase().trim();
            if (!seen.has(key)) {
                seen.add(key);
                names.push(name);
            }
        }
        return names.length > 0 ? names.join(", ") : Translation.tr("Unknown");
    }

    function conversationPicture(message): string {
        const addresses = message?.addresses ?? [];
        for (let i = 0; i < addresses.length; i++) {
            const pic = root.pictureFor(addresses[i]);
            if (pic) return pic;
        }
        return "";
    }

    function addressText(address): string {
        return String(address?.address || address || "");
    }

    // The same recipients, each matched to a different address.
    function sameAddresses(addrsA, addrsB): bool {
        if (!addrsA || !addrsB) return false;
        const listA = (Array.isArray(addrsA) ? addrsA : [addrsA]).map(root.addressText).filter(Boolean);
        const remaining = (Array.isArray(addrsB) ? addrsB : [addrsB]).map(root.addressText).filter(Boolean);
        if (listA.length === 0 || listA.length !== remaining.length) return false;
        return listA.every(a => {
            const index = remaining.findIndex(b => Identity.numberMatches(a, b));
            return index >= 0 && remaining.splice(index, 1).length === 1;
        });
    }

    function hasNumber(conversation, number): bool {
        return (conversation?.addresses || []).some(a => Identity.numberMatches(root.addressText(a), number));
    }

    function durationFor(attachment): real {
        if (!attachment) return 0;
        const uid = String(attachment.uid ?? attachment);
        if (root.attachmentDurations[uid] !== undefined && root.attachmentDurations[uid] > 0) {
            return root.attachmentDurations[uid];
        }
        if (attachment.duration !== undefined && Number(attachment.duration) > 0) {
            return Number(attachment.duration);
        }
        return 0;
    }

    // Probes already sent, per file and attachment, until when a rebuilt delegate may
    // ask again (results are stored per attachment, so each one asks for its own).
    property var probed: ({})
    function probeFile(path, uid): void {
        const key = path + "|" + (uid ?? "");
        if (!path || (root.probed[key] ?? 0) > Date.now()) return;
        if (root.command({ "cmd": "probe", "device": root.deviceId, "path": path, "uid": uid ?? "" }))
            root.probed[key] = Date.now() + 60000;
    }

    function recordAttachmentMeta(attachments): void {
        if (!attachments || attachments.length === 0) return;
        let filesChanged = false;
        let dursChanged = false;
        let thumbsChanged = false;
        const files = Object.assign({}, root.attachmentFiles);
        const durs = Object.assign({}, root.attachmentDurations);
        const thumbs = Object.assign({}, root.attachmentThumbs);
        for (let i = 0; i < attachments.length; i++) {
            const att = attachments[i];
            const uid = String(att?.uid ?? "");
            if (!uid) continue;
            if (att.path && !files[uid]) {
                files[uid] = att.path;
                filesChanged = true;
            }
            if (att.duration > 0 && !durs[uid]) {
                durs[uid] = Number(att.duration);
                dursChanged = true;
            }
            if (att.thumb && !thumbs[uid]) {
                thumbs[uid] = att.thumb;
                thumbsChanged = true;
            }
        }
        if (filesChanged) root.attachmentFiles = files;
        if (dursChanged) root.attachmentDurations = durs;
        if (thumbsChanged) root.attachmentThumbs = thumbs;
    }

    function prefetchMedia(attachments): void {
        if (!attachments || !root.reachable) return;
        for (let i = 0; i < attachments.length; i++) {
            const att = attachments[i];
            const mime = String(att?.mime ?? "").toLowerCase();
            const isGif = mime.startsWith("image/gif") || mime.endsWith("/gif") || /\.gif($|\?)/i.test(String(att?.path ?? att?.thumb ?? ""));
            const isMissingImage = mime.startsWith("image/") && !att?.path && !att?.thumb;
            if (!mime.startsWith("audio/") && !mime.startsWith("video/") && !isGif && !isMissingImage) continue;
            const uid = String(att?.uid ?? "");
            if (!uid) continue;
            const part = Number(att?.part ?? -1);
            if (part < 0) continue;
            if (root.attachmentFiles[uid] || (isGif || isMissingImage ? false : ((root.attachmentDurations[uid] ?? 0) > 0)) || root.attachmentBusy(uid) || ((root.prefetched[uid] || 0) > Date.now())) continue;
            root.prefetched = Object.assign({}, root.prefetched, { [uid]: Date.now() + 30000 });
            root.command({ "cmd": "attachment", "device": root.deviceId, "part": part, "uid": uid });
        }
    }

    function command(fields): string {
        if (!bridge.running || (!root.backendAvailable && fields.cmd !== "devices" && fields.cmd !== "start")) return "";
        const request = root.requestPrefix + "-" + (++root.requestSequence);
        bridge.write(JSON.stringify(Object.assign({}, fields, {request})) + "\n");
        return request;
    }

    function sameThreadMessages(a, b): bool {
        if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            const ma = a[i];
            const mb = b[i];
            if (!ma || !mb) return false;
            if (ma.uid !== mb.uid || ma.date !== mb.date || ma.type !== mb.type || ma.body !== mb.body) return false;
            if (JSON.stringify(ma.reactions ?? []) !== JSON.stringify(mb.reactions ?? [])) return false;
            const aa = ma.attachments ? ma.attachments.length : 0;
            const ab = mb.attachments ? mb.attachments.length : 0;
            if (aa !== ab) return false;
            for (let j = 0; j < aa; j++) {
                if ((ma.attachments[j]?.path ?? "") !== (mb.attachments[j]?.path ?? "")
                    || (ma.attachments[j]?.thumb ?? "") !== (mb.attachments[j]?.thumb ?? "")) {
                    return false;
                }
            }
        }
        return true;
    }

    function selectDevice(id): void {
        if (id === root.deviceId) return;
        root.cancelFilePreview();
        root.clearThumbnails();
        root.deviceId = id;
        root.conversations = [];
        root.conversationsLoaded = false;
        root.threadCache = ({});
        root.closeConversation();
        root.mounting = false;
        root.mounted = false;
        root.mountPoint = "";
        root.places = [];
        root.mountError = "";
        root.attachmentFiles = root.savedLocalSent._deviceAttachments?.[id] || ({});
        root.attachmentDurations = ({});
        root.attachmentThumbs = ({});
        root.dropAttachmentActions();
        root.prefetched = ({});
        root.probed = ({});
        root.localSent = (root.savedLocalSent && id) ? (root.savedLocalSent[id] ?? []) : [];
        root.registerLocalSentAttachments(root.localSent);
        root.syncDevice();
    }

    function openConversation(thread): void {
        root.openThread = thread;
        const cached = root.threadCache[thread];
        const latest = root.conversations.find(m => m.thread === thread);
        if (latest && latest.attachments) {
            root.recordAttachmentMeta(latest.attachments);
            root.prefetchMedia(latest.attachments);
        }
        const initial = (cached && cached.length > 0) ? cached : (latest ? [latest] : []);
        for (const m of initial) {
            if (m.attachments) {
                root.recordAttachmentMeta(m.attachments);
                root.prefetchMedia(m.attachments);
            }
        }
        root.threadMessages = root.withLocal(initial, thread);
        root.threadLoading = root.connected && root.reachable && !(cached && cached.length > 1);
        if (root.threadLoading) threadTimeout.restart();
        else threadTimeout.stop();
        root.command({ "cmd": "thread", "device": root.deviceId, "thread": thread, "count": 100 });
        root.conversationOpened(thread);
    }

    function matchTargetToThread(target): int {
        if (!target) return -1;
        if (target.deviceId && target.deviceId !== root.deviceId) return -1;
        if (typeof target === "number") return target >= 0 ? target : -1;
        if (target.thread !== undefined && target.thread !== -1 && target.thread !== null) {
            if (!target.directOnly) return target.thread;
            const conversation = root.conversations.find(c => c.thread === target.thread);
            return conversation?.addresses?.length === 1 ? target.thread : -1;
        }

        function choose(matches) {
            const valid = (matches || []).filter(c => c && c.thread !== undefined && c.thread !== null && c.thread >= 0);
            const direct = valid.filter(c => (c.addresses || []).length === 1);
            const pool = target.directOnly ? direct : (direct.length > 0 ? direct : valid);
            if (pool.length === 0) return -1;
            // An ambiguous suffix/name match must not choose a different
            // recipient just because their conversation is more recent.
            if (target.directOnly && new Set(pool.map(c => String(c.addresses[0]?.address || c.addresses[0]).replace(/\D/g, ""))).size > 1) return -1;
            pool.sort((a, b) => (b.date || 0) - (a.date || 0));
            return pool[0].thread;
        }

        if (Array.isArray(target.addresses) && target.addresses.length > 0) {
            const matchedList = root.conversations.filter(c => root.sameAddresses(c.addresses, target.addresses));
            const pickList = choose(matchedList);
            if (pickList !== -1) return pickList;
        }

        const rawNumber = String(target.number || target.address || (Array.isArray(target.addresses) && target.addresses.length === 1 ? (target.addresses[0]?.address || target.addresses[0]) : "") || "");
        const number = rawNumber.replace(/\D/g, "");
        const name = String(target.name || "").trim().toLowerCase();

        if (number) {
            const exact = root.conversations.filter(c => (c.addresses || []).some(a => root.addressText(a).replace(/\D/g, "") === number));
            const pickExact = choose(exact);
            if (pickExact !== -1) return pickExact;
            const pickSame = choose(root.conversations.filter(c => root.hasNumber(c, rawNumber)));
            if (pickSame !== -1) return pickSame;
        }

        // A selected contact number is an explicit destination. If it has
        // no direct thread, compose to that number rather than another number
        // on the contact or an unrelated person with the same display name.
        if (target.directOnly && number) return -1;

        if (name) {
            const byName = root.conversations.filter(c => {
                const cName = String(c.contactName || "").trim().toLowerCase();
                const cTitle = String(root.conversationTitle(c) || "").trim().toLowerCase();
                return (cName && cName === name) || (cTitle && cTitle === name);
            });
            const pickName = choose(byName);
            if (pickName !== -1) return pickName;
        }

        if (typeof ContactService !== "undefined" && ContactService?.records) {
            const contact = ContactService.matchingContact({
                number: rawNumber,
                name: target.name || "",
                deviceId: root.deviceId
            });
            if (contact && Array.isArray(contact.numbers)) {
                for (const num of contact.numbers) {
                    if (Identity.numberMatches(num, rawNumber)) continue;
                    const pick = choose(root.conversations.filter(c => root.hasNumber(c, num)));
                    if (pick !== -1) return pick;
                }
            }
        }

        return -1;
    }

    function checkPendingTarget(): void {
        if (!root.pendingTarget) return;
        const thread = root.matchTargetToThread(root.pendingTarget);
        if (thread !== -1) {
            root.pendingTarget = null;
            root.openConversation(thread);
        }
    }

    function openTargetConversation(target): void {
        root.wanted = true;
        const thread = root.matchTargetToThread(target);
        if (thread !== -1) {
            root.pendingTarget = null;
            root.openConversation(thread);
        } else {
            root.pendingTarget = target;
        }
    }

    function closeConversation(): void {
        root.openThread = -1;
        root.threadMessages = [];
        root.threadLoading = false;
    }

    function localFiles(paths): var {
        return (paths ?? []).map(p => String(p)).filter(p => p.startsWith("/"));
    }

    function storeAttachmentMapping(uid, path): void {
        if (!uid || !path) return;
        const current = root.savedLocalSent._deviceAttachments?.[root.deviceId] || ({});
        if (current[uid] !== path) {
            const updated = Object.assign({}, current, { [uid]: path });
            root.savedLocalSent = Object.assign({}, root.savedLocalSent, { _deviceAttachments: Object.assign({}, root.savedLocalSent._deviceAttachments || {}, {[root.deviceId]: updated}) });
            saveSentTimer.restart();
        }
    }

    function recordSentMessageMeta(copy): void {
        if (!copy || !copy.attachments || copy.attachments.length === 0) return;
        const current = (root.savedLocalSent && Array.isArray(root.savedLocalSent._outgoingAttachments))
            ? root.savedLocalSent._outgoingAttachments.slice(-100) : [];
        const entry = {
            device: root.deviceId,
            thread: copy.thread,
            date: copy.date,
            body: copy.body,
            attachments: copy.attachments.map(a => ({
                mime: a.mime,
                uid: a.uid,
                path: a.path || a.thumb || "",
                thumb: a.thumb || a.path || ""
            }))
        };
        root.savedLocalSent = Object.assign({}, root.savedLocalSent, {
            _outgoingAttachments: current.concat([entry])
        });
        saveSentTimer.restart();
    }

    // A file sent from here, shown and opened from where it is.
    function localAttachment(path): var {
        const uid = "local-" + Date.now() + "-" + Math.random().toString(36).substring(2, 9);
        root.attachmentFiles = Object.assign({}, root.attachmentFiles, { [uid]: path });
        root.storeAttachmentMapping(uid, path);
        const ext = path.slice(path.lastIndexOf(".") + 1).toLowerCase();
        const kind = /^(png|jpe?g|gif|webp|bmp|heic|avif)$/.test(ext) ? "image"
            : /^(mp4|webm|3gp|mov|mkv)$/.test(ext) ? "video" : /^(mp3|m4a|ogg|opus|wav|amr|aac)$/.test(ext) ? "audio" : "application";
        if (kind === "video" || kind === "audio") {
            root.probeFile(path, uid);
        }
        return { "part": -1, "mime": kind + "/" + ext, "uid": uid, "thumb": kind === "image" ? path : "", "path": path };
    }

    // Shows a message as sent at once, until the phone reports it.
    function showLocalSend(request, thread, body, addresses, files): void {
        root.lastSendRequest = request;
        root.pendingSends = Object.assign({}, root.pendingSends, {[request]: {device: root.deviceId, deadline: Date.now() + 180000}});
        const copy = { "thread": thread, "uid": -(Date.now()), "type": 6, "request": request, "date": Date.now(), "body": body,
            "addresses": addresses, "attachments": files.map(f => root.localAttachment(f)), "read": true, "local": true };
        root.recordSentMessageMeta(copy);
        root.localSent = root.localSent.concat([copy]);
        root.persistLocalSent();
        if (thread >= 0 && root.openThread === thread)
            root.threadMessages = root.withLocal(root.threadMessages, root.openThread);
        root.upsertConversation(copy);
    }

    function reply(text, attachments): bool {
        const body = String(text ?? "").trim();
        const files = root.localFiles(attachments);
        if ((body.length === 0 && files.length === 0) || root.openThread < 0 || !root.reachable || !root.canMessage) return false;
        const request = root.command({cmd: "reply", device: root.deviceId, thread: root.openThread, text: body, attachments: files});
        if (!request) return false;
        const latest = root.conversations.find(m => m.thread === root.openThread);
        root.showLocalSend(request, root.openThread, body, latest?.addresses ?? [], files);
        return true;
    }

    // Folds reaction replies into their target messages as corner reactions.
    function processThreadReactions(rawMessages): var {
        if (!rawMessages || rawMessages.length === 0) return [];
        const list = rawMessages.map(m => Object.assign({}, m, {
            reactions: (m.reactions && Array.isArray(m.reactions)) ? m.reactions.slice() : []
        }));

        const hiddenIndices = new Set();

        for (let i = 0; i < list.length; i++) {
            const msg = list[i];
            const reaction = PhoneReactions.parseReaction(msg.body);
            if (!reaction) continue;

            let targetMsg = null;
            for (let j = i - 1; j >= 0; j--) {
                if (hiddenIndices.has(j)) continue;
                const candidate = list[j];
                if (reaction.kind === "text") {
                    const body = (candidate.body || "").trim();
                    if (!body) continue;
                    if (body === reaction.target) {
                        targetMsg = candidate;
                        break;
                    }
                    const normBody = body.replace(/[\s\u200a]+/g, " ");
                    const normTarget = reaction.target.replace(/[\s\u200a]+/g, " ");
                    if (normBody === normTarget) {
                        targetMsg = candidate;
                        break;
                    }
                    const cleanTarget = reaction.target.replace(/(?:\.{3}|…)$/, "").trim();
                    if (cleanTarget.length >= 6 && normBody.startsWith(cleanTarget.replace(/[\s\u200a]+/g, " "))) {
                        targetMsg = candidate;
                        break;
                    }
                    if (cleanTarget.length >= 10 && normBody.includes(cleanTarget.replace(/[\s\u200a]+/g, " "))) {
                        targetMsg = candidate;
                        break;
                    }
                } else if (reaction.kind === "media") {
                    if (candidate.attachments && candidate.attachments.length > 0) {
                        targetMsg = candidate;
                        break;
                    }
                }
            }

            if (targetMsg) {
                hiddenIndices.add(i);
                const isOut = root.isOutgoing(msg);
                const senderAddr = isOut ? "me" : ((msg.addresses && msg.addresses[0]) ? (msg.addresses[0].address || msg.addresses[0]) : "sender");

                if (reaction.action === "remove") {
                    targetMsg.reactions = targetMsg.reactions.filter(r => isOut ? !r.outgoing : (r.outgoing || r.sender !== senderAddr));
                } else {
                    const existingIndex = targetMsg.reactions.findIndex(r => isOut ? r.outgoing : (!r.outgoing && r.sender === senderAddr));
                    const item = { emoji: reaction.emoji, sender: senderAddr, outgoing: isOut, date: msg.date };
                    if (existingIndex >= 0) targetMsg.reactions[existingIndex] = item;
                    else targetMsg.reactions.push(item);
                }
            }
        }

        return list.filter((_, idx) => !hiddenIndices.has(idx));
    }

    // A readable summary for conversation previews.
    function previewText(message): string {
        if (!message) return "";
        const reaction = PhoneReactions.parseReaction(message.body);
        if (reaction) {
            return `${reaction.emoji} to “${reaction.target.slice(0, 36)}${reaction.target.length > 36 ? "…" : ""}”`;
        }
        const quote = PhoneReactions.parseQuote(message.body);
        if (quote && quote.body) {
            return `↩ ${quote.body}`;
        }
        if (message.body && message.body.trim().length > 0) return message.body;
        if (message.attachments?.length > 0) {
            const first = message.attachments[0];
            const mime = String(first.mime || "").toLowerCase();
            if (mime.includes("gif") || /\.gif($|\?)/i.test(first.path || first.thumb || "")) return Translation.tr("GIF");
            if (mime.startsWith("audio/")) return Translation.tr("Voice note");
            if (mime.startsWith("video/")) return Translation.tr("Video");
            if (mime.startsWith("image/")) return Translation.tr("Photo");
            return Translation.tr("Attachment");
        }
        return "";
    }

    // A thread's messages with the replies sent from here that the phone has
    // not reported yet; a reported one leaves localSent.
    function withLocal(messages, thread): var {
        const real = (messages ?? []).filter(m => !m.local);
        const prevCount = root.localSent.length;
        // Phone messages already taken as the report of a send from here, kept
        // with the pending sends so a later refresh, or a reload, cannot spend
        // one again on a second send with the same text.
        const acknowledged = Object.assign({}, root.savedLocalSent._acknowledgedSends ?? {});
        const sendKey = m => root.deviceId + "|" + (m.uid ?? (m.date + "|" + m.body));
        const conv = root.conversations.find(c => c && c.thread === thread);
        const threadAddrs = conv?.addresses || (real[0]?.addresses) || [];

        // A reply sent to a new number joins its thread once the phone reports one.
        for (const l of root.localSent) {
            if (l.thread < 0 && thread >= 0 && root.sameAddresses(threadAddrs, l.addresses)) {
                l.thread = thread;
            }
        }

        root.localSent = root.localSent.filter(l => {
            if (l.thread !== thread) return true;
            let matched = false;
            for (let i = 0; i < real.length; i++) {
                const m = real[i];
                if (m.type !== 2 || acknowledged[sendKey(m)] !== undefined) continue;
                const bodyMatches = l.body.length > 0 ? m.body === l.body : ((m.attachments ?? []).length > 0);
                const timeMatches = Math.abs(m.date - l.date) <= 120000;
                if (bodyMatches && timeMatches) {
                    matched = true;
                    acknowledged[sendKey(m)] = Date.now();
                    if (l.attachments && l.attachments.length > 0 && m.attachments && m.attachments.length > 0) {
                        for (let ai = 0; ai < Math.min(l.attachments.length, m.attachments.length); ai++) {
                            const lAtt = l.attachments[ai];
                            const mAtt = m.attachments[ai];
                            const resolvedPath = lAtt.path || lAtt.thumb;
                            if (resolvedPath) {
                                if (!mAtt.path) mAtt.path = resolvedPath;
                                if (!mAtt.thumb) mAtt.thumb = resolvedPath;
                                if (mAtt.uid) {
                                    root.attachmentFiles = Object.assign({}, root.attachmentFiles, { [mAtt.uid]: resolvedPath });
                                    root.storeAttachmentMapping(mAtt.uid, resolvedPath);
                                }
                            }
                        }
                    }
                    break;
                }
            }
            return !matched;
        });
        if (root.localSent.length !== prevCount) {
            // Well past the two minutes a report is matched within.
            for (const key in acknowledged) {
                if (acknowledged[key] < Date.now() - 600000) delete acknowledged[key];
            }
            root.savedLocalSent = Object.assign({}, root.savedLocalSent, { _acknowledgedSends: acknowledged });
            root.persistLocalSent();
        }

        const outgoingMeta = (root.savedLocalSent && Array.isArray(root.savedLocalSent._outgoingAttachments))
            ? root.savedLocalSent._outgoingAttachments : [];
        for (const m of real) {
            if (m.type === 2 && m.attachments && m.attachments.length > 0) {
                for (let ai = 0; ai < m.attachments.length; ai++) {
                    const att = m.attachments[ai];
                    if (att.uid && root.attachmentFiles[att.uid]) {
                        if (!att.path) att.path = root.attachmentFiles[att.uid];
                        if (!att.thumb) att.thumb = root.attachmentFiles[att.uid];
                    } else if (!att.path && !att.thumb) {
                        const candidates = outgoingMeta.filter(om => om.device === root.deviceId && om.thread === thread && om.body === m.body && Math.abs(om.date - m.date) < 300000);
                        const candidate = candidates.length === 1 ? candidates[0] : null;
                        if (candidate && candidate.attachments && candidate.attachments[ai]) {
                            const p = candidate.attachments[ai].path || candidate.attachments[ai].thumb;
                            if (p) {
                                att.path = p;
                                att.thumb = p;
                                if (att.uid) {
                                    root.attachmentFiles = Object.assign({}, root.attachmentFiles, { [att.uid]: p });
                                    root.storeAttachmentMapping(att.uid, p);
                                }
                            }
                        }
                    }
                }
            }
        }

        const merged = real.concat(root.localSent.filter(l => l.thread === thread)).sort(root.byDate);
        return root.processThreadReactions(merged);
    }

    function sendNew(addresses, text, attachments): bool {
        const body = String(text ?? "").trim();
        const files = root.localFiles(attachments);
        const to = (addresses ?? []).map(a => String(a).trim()).filter(a => a.length > 0);
        if ((body.length === 0 && files.length === 0) || to.length === 0 || !root.reachable || !root.canMessage) return false;
        const request = root.command({cmd: "send", device: root.deviceId, addresses: to, text: body, attachments: files});
        if (!request) return false;
        const thread = root.matchTargetToThread({addresses: to, deviceId: root.deviceId, directOnly: to.length === 1});
        root.showLocalSend(request, thread, body, to, files);
        return true;
    }

    function shareFiles(paths): bool {
        const files = root.localFiles(paths);
        if (files.length === 0 || !root.reachable || !root.canShare) return false;
        return root.command({cmd: "share", device: root.deviceId, paths: files}).length > 0;
    }

    // Attachment ids are only unique per phone, so pending work is keyed by both.
    function actionKey(device, uid): string {
        return (device || root.deviceId) + "|" + uid;
    }
    function attachmentBusy(uid, device): bool {
        return root.attachmentActions[root.actionKey(device, uid)] !== undefined;
    }

    // Opens, saves or plays an attachment at full quality, fetching it from
    // the phone first. The Island passes the phone a message came from.
    // Attachments whose local copy failed to decode, by actionKey; they are fetched
    // again until a new copy arrives.
    property var staleAttachments: ({})
    function forgetAttachment(uid, device): void {
        root.staleAttachments[root.actionKey(device, uid)] = true;
        if ((device || root.deviceId) !== root.deviceId) return;
        const files = Object.assign({}, root.attachmentFiles);
        delete files[uid];
        root.attachmentFiles = files;
    }

    function useAttachment(attachment, action, device): void {
        const uid = String(attachment?.uid ?? "");
        if (uid.length === 0) return;
        const target = device || root.deviceId;
        const key = root.actionKey(target, uid);
        const file = target === root.deviceId && !root.staleAttachments[key] ? root.attachmentFiles[uid] : "";
        if (file) {
            root.finishAttachment(file, action, attachment.mime, uid, target);
            return;
        }
        if (root.attachmentBusy(uid, target)) {
            // One fetch serves every action asked for on that phone while it runs.
            const pending = root.attachmentActions[key];
            if (pending.action !== action && !(pending.also ?? []).includes(action))
                root.attachmentActions = Object.assign({}, root.attachmentActions, {[key]: Object.assign({}, pending, {also: (pending.also ?? []).concat([action])})});
            return;
        }
        root.attachmentActions = Object.assign({}, root.attachmentActions, { [key]: { "uid": uid, "action": action, "mime": attachment.mime, "device": target, "deadline": Date.now() + 30000 } });

        const fresh = !!root.staleAttachments[key];
        if (!root.command({cmd: "attachment", device: target, part: attachment.part, uid, fresh})) root.attachmentFailed(uid, target);
    }

    function finishAttachment(path, action, mime, uid, device): void {
        if (action === "open") {
            root.openLocal(path);
            root.opened(uid);
            return;
        }
        if (action === "play") {
            root.audioReady(uid, path, device || root.deviceId);
            return;
        }
        root.saveCopy(path, uid, String(mime ?? "").startsWith("image/"), "message", mime);
    }

    readonly property var mimeExtensions: ({"image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp",
        "image/heic": "heic", "video/mp4": "mp4", "video/3gpp": "3gp", "video/webm": "webm", "audio/mpeg": "mp3",
        "audio/mp4": "m4a", "audio/aac": "aac", "audio/ogg": "ogg", "audio/amr": "amr", "application/pdf": "pdf"})

    // Older rust-connect builds cached attachments under hashed names; save those
    // under the attachment's own name, or with an extension for their type.
    function saveName(source, uid, mime): string {
        const name = FileUtils.fileNameForPath(source);
        if (/\.[A-Za-z0-9]{1,5}$/.test(name)) return name;
        if (/^[A-Za-z0-9_-][A-Za-z0-9_.-]*\.[A-Za-z0-9]{1,5}$/.test(uid || "")) return uid;
        const ext = root.mimeExtensions[String(mime ?? "").split(";")[0].trim().toLowerCase()];
        return ext ? name + "." + ext : name;
    }

    property var saveQueue: []
    property var activeSave: null
    property int saveSequence: 0
    signal saveFinished(string request, string source, bool success)

    // Serialize copies: Process.exec() is not a queue, and replacing its
    // command in a multi-select loop saves only the last file.
    function saveCopy(path, uid, toPictures, from, mime): string {
        const source = FileUtils.trimFileProtocol(String(path || ""));
        const directory = FileUtils.trimFileProtocol(toPictures ? Directories.pictures : Directories.downloads);
        if (!source.startsWith("/") || !directory.startsWith("/")) return "";
        const name = root.saveName(source, uid, mime);
        const request = root.requestPrefix + "-save-" + (++root.saveSequence);
        root.saveQueue = root.saveQueue.concat([{
            request, source, directory, uid, from, name, path: directory + "/" + name,
            folder: toPictures ? Translation.tr("Pictures") : Translation.tr("Downloads")
        }]);
        Qt.callLater(root.startNextSave);
        return request;
    }

    function startNextSave(): void {
        if (root.activeSave || saveProc.running || root.saveQueue.length === 0) return;
        root.activeSave = root.saveQueue[0];
        root.saveQueue = root.saveQueue.slice(1);
        // The same file already there is reused; a name taken by another
        // file gets " (2)", " (3)"... The path printed is where it went.
        saveProc.exec(["sh", "-c", 'mkdir -p -- "$1" || exit 1; n="$3"; stem="${n%.*}"; [ "$stem" = "$n" ] && ext="" || ext=".${n##*.}"; '
            + 'i=2; while [ -e "$1/$n" ]; do cmp -s -- "$2" "$1/$n" && { printf %s "$1/$n"; exit 0; }; n="$stem ($i)$ext"; i=$((i+1)); done; '
            + 'cp --update=none-fail -- "$2" "$1/$n" && printf %s "$1/$n"', "sh",
            root.activeSave.directory, root.activeSave.source, root.activeSave.name]);
    }

    property string openingFilePath: ""
    property string filePreviewRequest: ""
    signal filePreviewFinished(string request, string path, string error)

    // Decode previews from the local cache rather than seeking over sshfs
    // on Qt's image-reader thread. A new selection supersedes the old one.
    function prepareFilePreview(path): string {
        if (!root.mounted || !root.mountPoint || !path.startsWith(root.mountPoint + "/")) return "";
        root.filePreviewRequest = root.command({cmd: "preview", device: root.deviceId, path, mount: root.mountPoint});
        return root.filePreviewRequest;
    }
    function cancelFilePreview(): void {
        if (!root.filePreviewRequest) return;
        root.filePreviewRequest = "";
        root.command({cmd: "cancelPreview"});
    }

    // Straight into the default app, where the portal behind Qt.openUrlExternally can ask first.
    function openLocal(path): void {
        Quickshell.execDetached(["xdg-open", FileUtils.mediaUrl(path)]);
    }

    // Remote files are copied atomically to a device/path/version-scoped cache.
    function openFile(path): void {
        if (!path) return;
        if (!root.mountPoint || !(path === root.mountPoint || path.startsWith(root.mountPoint + "/"))) {
            root.openLocal(path);
            return;
        }
        root.openingFilePath = path;
        if (!root.command({cmd: "open", device: root.deviceId, path, mount: root.mountPoint})) root.openingFilePath = "";
    }
    property int thumbnailGeneration: 0
    function requestThumbnails(paths): void {
        root.thumbnailGeneration++;
        root.command({cmd: "thumbnails", device: root.deviceId, paths: (paths || []).slice(0, 48), thumbnailGeneration: root.thumbnailGeneration});
    }
    // Pending fetches cannot finish once the phone is gone; their waiters are told.
    function dropAttachmentActions(): void {
        const pending = Object.values(root.attachmentActions);
        root.attachmentActions = ({});
        for (const action of pending) root.attachmentUnavailable(action.uid, action.device);
    }

    function attachmentFailed(uid, device): void {
        if (!uid) return;
        const target = device || root.deviceId;
        const actions = Object.assign({}, root.attachmentActions);
        delete actions[root.actionKey(target, uid)];
        root.attachmentActions = actions;
        if (target === root.deviceId) root.prefetched = Object.assign({}, root.prefetched, {[uid]: Date.now() + 3000});
        root.attachmentUnavailable(uid, target);
    }

    function mountFiles(): void {
        if (root.mounting || !root.reachable || !root.canBrowse) return;
        root.mounting = true;
        root.mountError = "";
        root.command({ "cmd": "mount", "device": root.deviceId });
    }

    // Newest first, one entry per conversation. A message sent to a new number
    // has thread -1 until the phone reports its thread, which then replaces it.
    function upsertConversation(message): void {
        if (!message) return;
        const hasThread = thread => thread !== undefined && thread !== null && thread >= 0;
        const placeholder = m => m.thread < 0 && root.sameAddresses(m.addresses, message.addresses);
        if (!hasThread(message.thread)) {
            const existingReal = root.conversations.find(c => c && hasThread(c.thread) && root.sameAddresses(c.addresses, message.addresses));
            if (existingReal) message.thread = existingReal.thread;
        }
        const same = hasThread(message.thread) ? m => m.thread === message.thread : placeholder;
        const current = root.conversations.find(m => m && same(m));
        if (current && current.date > message.date) return;
        const rest = root.conversations.filter(m => m && !same(m) && !placeholder(m));
        root.conversations = [message].concat(rest).sort((a, b) => b.date - a.date);
    }

    function handle(line): void {
        let event;
        try {
            event = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (event.generation !== undefined) {
            if (event.generation < root.backendGeneration) return;
            root.backendGeneration = event.generation;
        }
        switch (event.event) {
        case "backend":
            root.backendAvailable = !!event.available;
            if (event.name) root.backendName = event.name;
            if (event.reset || !event.available) {
                root.disconnectState();
                root.devices = root.devices.map(d => Object.assign({}, d, {reachable: false}));
                root.pairRequests = [];
            }
            break;
        case "pairRequests":
            root.pairRequests = event.requests ?? [];
            break;
        case "file":
            if (event.device !== root.deviceId) break;
            root.openingFilePath = "";
            if (event.path) root.openLocal(event.path);
            break;
        case "filePreview":
            if (event.device !== root.deviceId || event.request !== root.filePreviewRequest) break;
            root.filePreviewRequest = "";
            root.filePreviewFinished(event.request, event.path || "", "");
            break;
        case "devices": {
            const incoming = event.devices ?? [];
            const isSame = incoming.length === root.devices.length && incoming.every((d, i) => {
                const c = root.devices[i];
                return c && c.id === d.id && c.name === d.name && c.reachable === d.reachable && c.charge === d.charge && c.charging === d.charging && c.type === d.type && JSON.stringify(c.plugins) === JSON.stringify(d.plugins);
            });
            if (isSame) break;

            root.devices = incoming;
            if (!root.devices.some(d => d.id === root.deviceId)) {
                const pick = root.devices.find(d => d.reachable) ?? root.devices[0];
                if (pick?.id !== root.deviceId) {
                    root.selectDevice(pick?.id ?? "");
                }
            }
            break;
        }
        case "conversations": {
            if (event.device !== root.deviceId) break;
            root.conversations = (event.items ?? []).slice().sort((a, b) => b.date - a.date);
            root.messagesSynced(event.device, root.conversations);
            const allAtts = [];
            const nextCache = Object.assign({}, root.threadCache);
            for (const item of root.conversations) {
                if (item.attachments) allAtts.push(...item.attachments);
                if (item.thread !== undefined && (!nextCache[item.thread] || nextCache[item.thread].length === 0)) {
                    nextCache[item.thread] = [item];
                }
            }
            if (allAtts.length > 0) root.recordAttachmentMeta(allAtts);
            root.threadCache = nextCache;
            let localSentChanged = false;
            for (const copy of root.localSent) {
                if (copy.thread < 0) {
                    const matched = root.conversations.find(c => c && c.thread >= 0 && root.sameAddresses(c.addresses, copy.addresses));
                    if (matched) {
                        copy.thread = matched.thread;
                        localSentChanged = true;
                    }
                }
                root.upsertConversation(copy);
            }
            if (localSentChanged) root.persistLocalSent();
            root.conversationsLoaded = true;
            break;
        }
        case "message": {
            if (event.message) {
                const key = "kde:/modules/kdeconnect/devices/" + event.device + ":" + event.message.uid;
                if (event.live || root.recentMessages.some(m => m.sourceIds?.includes(key)))
                    root.rememberLiveMessage(event.device, event.message);
                root.messagesSynced(event.device, [event.message]);
            }
            if (event.device !== root.deviceId || !event.message) break;
            const message = event.message;
            if (message.attachments) {
                root.recordAttachmentMeta(message.attachments);
                if (message.thread === root.openThread) root.prefetchMedia(message.attachments);
            }
            root.upsertConversation(message);
            if (message.thread !== undefined) {
                const existing = (root.threadCache[message.thread] ?? []).filter(m => m.uid !== message.uid);
                existing.push(message);
                existing.sort(root.byDate);
                root.threadCache[message.thread] = existing;
            }
            if (message.thread === root.openThread) {
                const nextMsgs = root.withLocal((root.threadCache[root.openThread] ?? root.threadMessages.filter(m => m.uid !== message.uid).concat([message])), root.openThread);
                if (!root.sameThreadMessages(root.threadMessages, nextMsgs)) {
                    root.threadMessages = nextMsgs;
                }
            }
            break;
        }
        case "thread": {
            if (event.device !== root.deviceId) break;
            const threadMsgs = event.messages ?? [];
            root.messagesSynced(event.device, threadMsgs);
            const allAtts = [];
            for (const m of threadMsgs) {
                if (m.attachments) allAtts.push(...m.attachments);
            }
            if (allAtts.length > 0) {
                root.recordAttachmentMeta(allAtts);
                if (event.thread === root.openThread) root.prefetchMedia(allAtts);
            }
            if (event.thread !== undefined && threadMsgs.length > 0) {
                root.threadCache[event.thread] = threadMsgs;
                const latestMsg = threadMsgs[threadMsgs.length - 1];
                if (latestMsg) root.upsertConversation(latestMsg);
            }
            if (event.thread !== root.openThread) break;
            threadTimeout.stop();
            root.threadLoading = false;
            const nextMsgs = root.withLocal(threadMsgs, root.openThread);
            if (!root.sameThreadMessages(root.threadMessages, nextMsgs)) {
                root.threadMessages = nextMsgs;
            }
            break;
        }
        case "removed":
            if (event.device !== root.deviceId) break;
            root.conversations = root.conversations.filter(m => m.thread !== event.thread);
            if (event.thread !== undefined && root.threadCache[event.thread]) {
                delete root.threadCache[event.thread];
            }
            if (event.thread === root.openThread) root.closeConversation();
            break;
        case "contacts":
            ContactService.ingest(event);
            break;
        case "call":
            root.callDetails = [{deviceId: event.device, number: event.number ?? "", name: event.name ?? "", time: event.time}]
                .concat(root.callDetails.filter(d => event.time - d.time < 60000)).slice(0, 30);
            break;
        case "notification":
            root.notificationResult(event);
            break;
        case "mount":
            if (event.device !== root.deviceId) break;
            root.mounting = false;
            root.mounted = event.mounted === true;
            root.mountPoint = event.mountPoint ?? "";
            root.places = event.places ?? [];
            root.mountError = root.mounted ? "" : (event.error ?? "");
            root.sshfsMissing = !root.mounted && event.sshfsMissing === true;
            break;
        case "thumbnail":
            // Any finished thumbnail is kept, even from an earlier request: it is still that file's.
            if (event.path && event.thumb) {
                root.pendingThumbnails[event.path] = event.thumb;
                if (!thumbnailFlush.running) thumbnailFlush.start();
            }
            break;
        case "shared":
            root.shared(event.count ?? 0);
            break;
        case "attachment": {
            const aPath = event.path ?? "";
            const aUid = event.uid ?? "";
            if (!aPath || !aUid) break;
            root.updateLiveImages(event.device, aUid, aPath);
            const aKey = root.actionKey(event.device, aUid);
            delete root.staleAttachments[aKey];
            const pending = root.attachmentActions[aKey];
            if (pending) {
                const rest = Object.assign({}, root.attachmentActions);
                delete rest[aKey];
                root.attachmentActions = rest;
                root.finishAttachment(aPath, pending.action, pending.mime, aUid, event.device);
                for (const extra of pending.also ?? []) root.finishAttachment(aPath, extra, pending.mime, aUid, event.device);
            }
            if (event.device !== root.deviceId) break;
            const aDur = Number(event.duration ?? 0);
            const aThumb = event.thumb ?? "";
            root.attachmentFiles = Object.assign({}, root.attachmentFiles, { [aUid]: aPath });
            if (aDur > 0) root.attachmentDurations = Object.assign({}, root.attachmentDurations, { [aUid]: aDur });
            if (aThumb.length > 0) root.attachmentThumbs = Object.assign({}, root.attachmentThumbs, { [aUid]: aThumb });
            break;
        }
        case "duration": {
            if (event.device && event.device !== root.deviceId) break;
            const dUid = event.uid ?? "";
            const dVal = Number(event.duration ?? 0);
            const dThumb = event.thumb ?? "";
            if (dUid.length > 0) {
                if (dVal > 0) {
                    root.attachmentDurations = Object.assign({}, root.attachmentDurations, { [dUid]: dVal });
                }
                if (dThumb.length > 0) {
                    root.attachmentThumbs = Object.assign({}, root.attachmentThumbs, { [dUid]: dThumb });
                }
            }
            break;
        }
        case "sent":
            root.resolveSend(event.request, true);
            break;
        case "error":
            if (event.device && event.device !== root.deviceId && !root.pendingSends[event.request]) break;
            if (event.context === "preview") {
                if (event.request !== root.filePreviewRequest) break;
                root.filePreviewRequest = "";
                root.filePreviewFinished(event.request, "", event.message || Translation.tr("Could not read file from phone"));
                break;
            }
            if (event.context === "mount") root.mounting = false;
            if (event.context === "thread" && (event.thread === undefined || event.thread === root.openThread)) {
                root.threadLoading = false;
                threadTimeout.stop();
            }
            if (event.context === "reply" || event.context === "send") root.resolveSend(event.request, false);
            if (event.context === "attachment") root.attachmentFailed(event.uid, event.device);
            if (event.context === "open") {
                root.openingFilePath = "";
                root.mountError = event.message || Translation.tr("Could not read file from phone");
            }
            root.failed(event.context ?? "", event.message ?? "");
            break;
        }
    }

    // Messages with the same time (the text and media of one MMS) keep the phone's order,
    // so a rebuild doesn't swap them.
    function byDate(a, b): int {
        return (a.date - b.date) || ((Number(a.uid) || 0) - (Number(b.uid) || 0));
    }

    function isImage(attachment): bool {
        return String(attachment?.mime ?? "").toLowerCase().startsWith("image/");
    }

    function messageEntry(device, message): var {
        const attachments = message.attachments ?? [];
        const images = attachments.filter(root.isImage).filter((a, i, all) =>
            !a.uid || all.findIndex(other => String(other.uid) === String(a.uid)) === i);
        // Slots line up with imageUids, so a full image replaces its own thumbnail.
        const imageSlots = images.map(a => a.path || a.thumb ? FileUtils.fileUrl(a.path || a.thumb) : "");
        const entry = {
            id: "kde:/modules/kdeconnect/devices/" + device + ":" + message.uid, backend: "KDE Connect",
            name: "", number: root.addressText(message.addresses?.[0]), live: true, deviceId: device,
            time: message.date, body: attachments.length && History.isMediaPlaceholder(message.body) ? "" : message.body ?? "",
            picture: "", thread: message.thread, type: message.type, sub: message.sub,
            media: attachments.map(a => ({uid: String(a.uid ?? ""), part: a.part, mime: a.mime || "",
                path: a.path || "", thumb: a.thumb || ""})),
            images: imageSlots.filter(u => u.length > 0).slice(0, 4), imageSlots,
            imageUids: images.map(a => String(a.uid)),
            audioClips: attachments.filter(a => /^audio\/|^application\/ogg/.test(String(a.mime ?? "").toLowerCase())).slice(0, 8)
                .map(a => ({deviceId: device, part: a.part, mime: a.mime, uid: String(a.uid)}))
        };
        entry.sourceIds = [entry.id];
        return entry;
    }

    function rememberLiveMessage(device, message): void {
        let entry = root.messageEntry(device, message);
        // A captioned MMS can arrive as two messages at the same time, one with the text and
        // one with the media; the Island shows them as one.
        const previous = root.recentMessages.find(m => m.id === entry.id || m.sourceIds?.includes(entry.id));
        const partner = previous || root.recentMessages.find(m => History.captionHalves(m, entry));
        if (partner) {
            const hasMedia = History.hasMedia(entry);
            entry = Object.assign({}, partner, {
                body: entry.body || partner.body,
                sourceIds: [...new Set((partner.sourceIds || [partner.id]).concat(entry.sourceIds))],
                images: hasMedia ? entry.images : partner.images,
                imageSlots: hasMedia ? entry.imageSlots : partner.imageSlots,
                imageUids: hasMedia ? entry.imageUids : partner.imageUids,
                audioClips: hasMedia ? entry.audioClips : partner.audioClips,
                media: hasMedia ? entry.media : partner.media
            });
        }
        root.recentMessages = [entry].concat(root.recentMessages.filter(m =>
            !(m.sourceIds || [m.id]).some(id => entry.sourceIds.includes(id)))).slice(0, 30);
        // The Island shows full images, which the phone sends on request.
        for (const a of (message.attachments ?? []).filter(root.isImage))
            if (!a.path && a.part >= 0) root.command({cmd: "attachment", device, part: a.part, uid: String(a.uid)});
    }

    function updateLiveImages(device, uid, path): void {
        const url = FileUtils.fileUrl(path);
        const slotOf = m => m.deviceId === device ? m.imageUids.indexOf(uid) : -1;
        if (!root.recentMessages.some(m => slotOf(m) >= 0 && m.imageSlots[slotOf(m)] !== url)) return;
        root.recentMessages = root.recentMessages.map(m => {
            const slot = slotOf(m);
            if (slot < 0) return m;
            const imageSlots = m.imageSlots.slice();
            imageSlots[slot] = url;
            return Object.assign({}, m, {imageSlots, images: imageSlots.filter(u => u.length > 0).slice(0, 4)});
        });
    }

    // Jobs for kde_notifications.py in the bridge; Notifications.qml answers
    // by job id through notificationResult.
    function notificationJob(job): bool {
        return root.command({cmd: "notification", job}).length > 0;
    }

    // A thread the daemon has nothing for never reports back.
    Timer {
        id: threadTimeout
        interval: 15000
        onTriggered: root.threadLoading = false
    }

    Timer {
        id: attachmentTimeout
        interval: 1000
        repeat: true
        running: Object.keys(root.attachmentActions).length > 0 || Object.keys(root.pendingSends).length > 0
        onTriggered: {
            const now = Date.now();
            let expired = false;
            for (const action of Object.values(root.attachmentActions)) {
                if (action.deadline <= now) { root.attachmentFailed(action.uid, action.device); expired = true; }
            }
            if (expired) root.attachmentTimedOut();
            for (const request in root.pendingSends) if (root.pendingSends[request].deadline <= now) root.resolveSend(request, false);
        }
    }

    FileView {
        id: sentFileView
        path: Directories.phoneSentPath
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.savedLocalSent = (data && typeof data === "object" && !Array.isArray(data)) ? data : ({});
                if (root.deviceId && data?._deviceAttachments?.[root.deviceId]) root.attachmentFiles = Object.assign({}, root.attachmentFiles, data._deviceAttachments[root.deviceId]);
                if (root.deviceId && root.savedLocalSent[root.deviceId]) {
                    const saved = root.savedLocalSent[root.deviceId];
                    const existingUids = new Set((root.localSent ?? []).map(m => String(m.uid)));
                    const additional = saved.filter(m => !existingUids.has(String(m.uid)));
                    root.localSent = (root.localSent ?? []).concat(additional);
                    root.registerLocalSentAttachments(root.localSent);
                    for (const copy of root.localSent) root.upsertConversation(copy);
                    if (root.openThread >= 0) {
                        root.threadMessages = root.withLocal(root.threadMessages, root.openThread);
                    }
                }
            } catch (e) {
                root.savedLocalSent = ({});
            }
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                console.warn("[Phone] Could not load sent messages:", error);
            }
            root.savedLocalSent = ({});
        }
        onSaved: Qt.callLater(root.writeDone)
        onSaveFailed: Qt.callLater(root.writeDone)
    }

    Timer {
        id: saveSentTimer
        interval: 300
        repeat: false
        onTriggered: root.writeSent()
    }

    property bool _writingSent: false
    property bool _writeSentAgain: false

    function persistLocalSent(): void {
        if (!root.deviceId) return;
        const trimmed = (root.localSent ?? []).slice(-200);
        root.savedLocalSent = Object.assign({}, root.savedLocalSent, { [root.deviceId]: trimmed });
        saveSentTimer.restart();
    }

    function writeSent(): void {
        if (root._writingSent) {
            root._writeSentAgain = true;
            return;
        }
        const text = JSON.stringify(root.savedLocalSent);
        if (text === sentFileView.text()) return;
        root._writingSent = true;
        sentFileView.setText(text);
    }

    function writeDone(): void {
        root._writingSent = false;
        if (root._writeSentAgain) {
            root._writeSentAgain = false;
            root.writeSent();
        }
    }

    function registerLocalSentAttachments(messages): void {
        if (!messages || !Array.isArray(messages)) return;
        let filesChanged = false;
        const files = Object.assign({}, root.attachmentFiles);
        for (const msg of messages) {
            for (const att of (msg.attachments ?? [])) {
                const uid = String(att.uid ?? "");
                const path = String(att.path ?? att.thumb ?? "");
                if (uid && path && files[uid] !== path) {
                    files[uid] = path;
                    filesChanged = true;
                    root.storeAttachmentMapping(uid, path);
                }
            }
        }
        if (filesChanged) root.attachmentFiles = files;
    }

    Process {
        id: bridge
        running: root.bridgeWanted && root.installed && !restartBridge.running
        stdinEnabled: true
        command: ["python3", "-I", FileUtils.trimFileProtocol(`${Directories.scriptPath}/phone/kdeconnect-bridge.py`)]
        stdout: SplitParser {
            onRead: line => root.handle(line)
        }
        onStarted: {
            root.backendGeneration = -1;
            root.command({cmd: "devices"});
            root.startBackend();
            bridgeStable.restart();
        }
        stderr: SplitParser { onRead: line => console.warn("[Phone bridge]", line) }
        onExited: {
            root.backendAvailable = false;
            root.disconnectState();
            root.devices = root.devices.map(d => Object.assign({}, d, {reachable: false}));
            bridgeStable.stop();
            if (root.bridgeWanted && root.installed) {
                root.restartAttempts++;
                restartBridge.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(root.restartAttempts, 5)));
                restartBridge.restart();
            }
        }
    }

    Process {
        id: saveProc
        stdout: StdioCollector { id: savedPath }
        onExited: (exitCode, exitStatus) => {
            const save = root.activeSave;
            root.activeSave = null;
            if (save) {
                const path = exitCode === 0 ? savedPath.text : save.path;
                root.lastSave = {ok: exitCode === 0, uid: save.uid, from: save.from,
                    name: FileUtils.fileNameForPath(path), path, folder: save.folder};
                root.saveFinished(save.request, save.source, exitCode === 0);
            }
            Qt.callLater(root.startNextSave);
        }
    }

    Timer { id: restartBridge; interval: 3000 }
    Timer { id: bridgeStable; interval: 10000; onTriggered: root.restartAttempts = 0 }
    // Until a backend is found, look again whenever the sidebar opens; the lookup
    // never starts one (D-Bus activation would pick whichever service file wins).
    Connections {
        target: GlobalStates
        enabled: !root.installed
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen && !installCheck.running) installCheck.running = true;
        }
    }

    Process {
        id: installCheck
        command: ["sh", "-c", "for method in ListNames ListActivatableNames; do gdbus call --session --dest org.freedesktop.DBus "
            + "--object-path /org/freedesktop/DBus --method org.freedesktop.DBus.$method | grep -q \"'org.kde.kdeconnect'\" && exit 0; done; "
            + "command -v rust-connect || command -v kdeconnectd || [ -x /usr/lib/kdeconnectd ]"]
        onExited: (exitCode, exitStatus) => root.installed = exitCode === 0
    }

    Component.onCompleted: installCheck.running = true
}
