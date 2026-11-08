.pragma library
.import "PhoneReactions.js" as Reactions
.import "PhoneIdentity.js" as Identity

const limit = 30;
const mediaPlaceholders = new Set(["image", "photo", "gif", "video", "audio", "audio clip", "voice message", "media", "attachment"]);

// Equal times keep one fixed order. The engine's sort is not stable, so records
// reshuffled on every pass would compare as changed and be saved again, endlessly.
function tieBreak(a, b) {
    const x = String(a.id ?? JSON.stringify(a)), y = String(b.id ?? JSON.stringify(b));
    return x < y ? -1 : x > y ? 1 : 0;
}
function newestFirst(a, b) {
    return b.time - a.time || tieBreak(a, b);
}

function isMediaPlaceholder(body) {
    return mediaPlaceholders.has(String(body || "").trim().toLowerCase());
}

function hasMedia(message) {
    // Attachment identity exists before its thumbnail or full file arrives.
    return !!(message.media?.length || message.imageUids?.length || message.images?.length || message.audioClips?.length);
}

function notificationEventId(message) {
    if (!message.mirrored || !message.notificationKey) return "";
    return "notification:" + JSON.stringify([message.notificationKey,
        message.bundled ? 0 : Number(message.notificationTime) || 0,
        String(message.body || ""), message.notificationPart || 0]);
}

function notificationMessage(message) {
    const id = notificationEventId(message);
    return id ? Object.assign({}, message, {
        id, sourceIds: [...new Set((message.sourceIds || [message.id]).concat([id]))],
        time: Number(message.notificationTime) || message.time
    }) : message;
}

function sameNotification(a, b) {
    if (!a.mirrored || !b.mirrored || !a.notificationKey || a.notificationKey !== b.notificationKey
        || (a.deviceId && b.deviceId && a.deviceId !== b.deviceId)
        || String(a.body || "") !== String(b.body || "")
        || (a.notificationPart || 0) !== (b.notificationPart || 0)) return false;
    return a.bundled || b.bundled || !a.notificationTime || !b.notificationTime
        || a.notificationTime === b.notificationTime;
}

// Older entries kept only the desktop ID. A surviving ID ties that saved
// notification to its phone key; retain all source IDs when its copies merge.
function adoptNotificationKeys(history, incoming) {
    let records = history.slice();
    for (const message of incoming) {
        if (!message.mirrored || !message.notificationKey) continue;
        const aliases = message.sourceIds || [message.id];
        let seed = records.find(m => m.mirrored && !m.notificationKey
            && m.sourceIds?.some(id => aliases.includes(id)));
        if (!seed) {
            // If every desktop ID was replaced, one canonical phone event can
            // still identify its old notification-only copies. Multiple known
            // events with identical text are ambiguous and stay separate.
            const canonical = records.filter(m => m.mirrored && m.notificationKey === message.notificationKey
                && m.body === message.body && (m.notificationPart || 0) === (message.notificationPart || 0));
            if (canonical.length === 1) seed = canonical[0];
        }
        if (!seed) continue;
        records = records.map(m => m.mirrored && !m.notificationKey && sameConversation(m, seed)
            && m.body === seed.body ? Object.assign({}, m, {
                notificationKey: message.notificationKey, notificationTime: message.notificationTime || 0,
                notificationPart: message.notificationPart || 0, bundled: !!message.bundled
            }) : m);
    }
    return records;
}

function sameConversation(a, b) {
    return a.deviceId === b.deviceId && contactMatches(a, b)
        && (a.thread === undefined || b.thread === undefined || a.thread === b.thread)
        && (a.type === undefined || b.type === undefined || a.type === b.type)
        && (a.sub === undefined || b.sub === undefined || a.sub === b.sub);
}

function captionHalves(a, b) {
    const textOnly = m => !!String(m.body || "").trim() && !hasMedia(m);
    const mediaOnly = m => (!String(m.body || "").trim() || isMediaPlaceholder(m.body)) && hasMedia(m);
    return a.time > 0 && a.time === b.time && sameConversation(a, b)
        && ((textOnly(a) && mediaOnly(b)) || (mediaOnly(a) && textOnly(b)));
}

// Reactions fold into the message they react to, so history keeps neither.
function sanitizeHistoryMessages(rawList) {
    return Array.isArray(rawList) ? coalesceMessages(rawList.filter(m => m && !Reactions.isReaction(String(m.body || "")))) : [];
}

// Android can publish one captioned MMS as a text row and a media row. Combine only
// native halves with the same sender and timestamp; nearby texts stay separate.
function coalesceMessages(messages) {
    const records = [];
    const sources = m => m.sourceIds || [m.id];
    const native = m => sources(m).some(id => id.startsWith("kde:"));
    for (const message of messages) {
        const copy = records.findIndex(other => sameNotification(other, message)
            || (message.mirrored && other.mirrored && !message.notificationKey && !other.notificationKey
                && message.time > 0 && message.time === other.time && message.body === other.body
                && sameConversation(message, other)));
        if (copy >= 0) {
            const other = records[copy];
            const media = hasMedia(other) ? other : message;
            records[copy] = Object.assign({}, other, {
                sourceIds: [...new Set(sources(other).concat(sources(message)))],
                picture: other.picture || message.picture || "",
                media: media.media || [], images: media.images || [], audioClips: media.audioClips || [],
                imageUids: media.imageUids || [], imageSlots: media.imageSlots || [],
                previewImage: media.previewImage || ""
            });
            continue;
        }
        const index = native(message) ? records.findIndex(other => native(other)
            && captionHalves(other, message)) : -1;
        if (index < 0) {
            records.push(message);
            continue;
        }
        const other = records[index];
        const media = hasMedia(message) ? message : other;
        records[index] = Object.assign({}, other, {
            sourceIds: [...new Set(sources(other).concat(sources(message)))],
            body: (hasMedia(other) ? message.body : other.body) || "",
            images: media.images || [], audioClips: media.audioClips || [],
            media: media.media || [], imageUids: media.imageUids || [], imageSlots: media.imageSlots || [],
            picture: other.picture || message.picture || "",
            previewImage: media.previewImage || ""
        });
    }
    return records;
}

// A caption and its media or link can arrive as records seconds apart. Group them
// for display only; history and the backend keep every original record.
function groupMessages(messages, extractUrls) {
    const sources = m => m.sourceIds || [m.id];
    const native = m => !m.mirrored && m.deviceId && m.thread !== undefined
        && sources(m).some(id => id.startsWith("kde:"));
    const uid = m => Number(sources(m).find(id => id.startsWith("kde:"))?.split(":").pop()) || 0;
    const ordered = messages.slice().sort((a, b) => a.time - b.time || uid(a) - uid(b) || tieBreak(a, b));
    const grouped = new Map();
    const captions = new Set();
    for (let i = 0; i < ordered.length; i++) {
        const part = ordered[i];
        if (!native(part) || part.previewUrl || !(part.time > 0)) continue;
        const mediaOnly = hasMedia(part) && (!String(part.body || "").trim() || isMediaPlaceholder(part.body));
        const urls = !hasMedia(part) && /^(?:https?:\/\/|www\.)\S+$/i.test(String(part.body || "").trim())
            ? extractUrls(part.body) : [];
        if (!mediaOnly && urls.length !== 1) continue;
        const sameThread = other => native(other) && other.deviceId === part.deviceId
            && other.thread === part.thread && contactMatches(other, part);
        const following = ordered.slice(i + 1).find(sameThread);
        const previous = ordered.slice(0, i).reverse().find(sameThread);
        // Media follows its caption on Android. Link previews commonly arrive
        // first. An intervening message is a boundary, never skipped over.
        const candidates = mediaOnly ? [previous, following] : [following, previous];
        const caption = candidates.find(other => other && !captions.has(other.id)
            && !grouped.has(other.id) && sameConversation(other, part)
            && other.time > 0 && Math.abs(other.time - part.time) <= 30000
            && !hasMedia(other) && !other.previewUrl && String(other.body || "").trim()
            && !isMediaPlaceholder(other.body) && extractUrls(other.body).length === 0);
        if (!caption) continue;
        grouped.set(part.id, Object.assign({}, part, {
            id: part.id, time: Math.max(part.time, caption.time), body: caption.body,
            picture: part.picture || caption.picture || "",
            sourceIds: [...new Set(sources(part).concat(sources(caption)))],
            memberIds: [part.id, caption.id],
            previewUrl: urls[0] || ""
        }));
        captions.add(caption.id);
    }
    return ordered.filter(message => !captions.has(message.id))
        .map(message => grouped.get(message.id) || message).sort(newestFirst);
}

// Older history kept a thumbnail alongside the fetched file. Resolve only
// thumbnails in this phone's cache with an authoritative attachment mapping.
function resolveImages(messages, device, files, thumbnailDirectory) {
    const prefix = thumbnailDirectory.replace(/\/$/, "") + "/";
    return messages.map(message => {
        if (message.deviceId !== device) return message;
        const media = (message.media || []).map(a => Object.assign({}, a, {path: files[a.uid] || a.path || ""}));
        const sources = media.length ? media.map(a => /^image\//.test(a.mime) ? (a.path || a.thumb)
            : /^video\//.test(a.mime) ? a.thumb : "").filter(Boolean) : (message.images || []);
        const images = sources.map(source => {
            // Descriptors already choose the right representation. A video's
            // thumbnail must stay an image even after its MP4 has been fetched.
            if (media.length) return source.startsWith("/") ? "file://" + source : source;
            const file = source.startsWith("file://") ? source.slice(7) : source;
            if (!file.startsWith(prefix) || !/\.(png|jpe?g|webp|gif)$/.test(file))
                return source.startsWith("/") ? "file://" + source : source;
            const uid = file.slice(prefix.length).replace(/\.(png|jpe?g|webp|gif)$/, "");
            const path = !uid.includes("/") && files[uid];
            return path ? (path.startsWith("file://") ? path : "file://" + path) : source;
        }).filter((source, i, all) => all.indexOf(source) === i);
        return Object.assign({}, message, {images, media});
    });
}

function savedImage(source) {
    return typeof source === "string" && /^(data:image\/|file:\/\/|\/)/.test(source) ? source : "";
}

// A phone's own text and the notification mirroring it, within a minute.
function sameText(native, mirrored) {
    if (!native || !mirrored || Math.abs(native.time - mirrored.time) > 60000 || !contactMatches(native, mirrored)) return false;
    if (native.body && (native.body === mirrored.body || String(mirrored.body || "").includes(native.body))) return true;
    return hasMedia(native) && (isMediaPlaceholder(mirrored.body) || !mirrored.body);
}

function contactMatches(a, b) {
    if (a.deviceId && b.deviceId && a.deviceId !== b.deviceId) return false;
    if (a.number && b.number) {
        return Identity.numberMatches(a.number, b.number);
    }
    return !!a.name && a.name.toLowerCase() === String(b.name || "").toLowerCase();
}

function updateContactPhotos(known, entries, now) {
    const result = known.slice();
    for (const entry of entries) {
        const picture = savedImage(entry.picture);
        if (!picture || (!entry.name && !entry.number)) continue;
        const index = result.findIndex(c => contactMatches({name: c.name, number: c.numbers[0], deviceId: c.deviceId}, entry));
        const old = result[index];
        const time = Number(entry.time) || (old?.picture === picture ? old.time : now);
        if (old && time < old.time) continue;
        const number = String(entry.number || old?.numbers[0] || "").replace(/\D/g, "");
        const contact = {name: entry.name || old?.name || "", deviceId: entry.deviceId || old?.deviceId || "",
            numbers: number ? [number] : [], picture, time};
        if (index >= 0) result[index] = contact;
        else result.push(contact);
    }
    return result.sort(newestFirst).slice(0, 100);
}

function mirrorRepresented(message, records) {
    let remaining = String(message.body || "").trim();
    if (!remaining) return false;
    let lines = remaining.split("\n");
    // A replayed unread notification, outside the usual window, can be represented
    // only by the latest synced message before it.
    const synced = records.filter(other => other.deviceId && other.deviceId === message.deviceId
        && other.time > 0 && contactMatches(other, message)
        && (other.thread === undefined || message.thread === undefined || other.thread === message.thread)
        && other.sourceIds.some(id => id.startsWith("kde:")))
        .sort((a, b) => a.time - b.time || tieBreak(a, b));
    const latestSynced = synced.filter(other => other.time <= message.time).pop();
    // Some phones post the notification before dating the SMS: only the first
    // following SMS within ten minutes, with identical text, represents it.
    const followingSynced = synced.find(other => other.time > message.time);
    if (followingSynced && followingSynced.time - message.time <= 600000
        && String(followingSynced.body || "").trim() === remaining) return true;
    for (const other of records) {
        if (other.id === message.id || !other.sourceIds.some(id => !id.startsWith("notification:"))
            || (Math.abs(other.time - message.time) > 120000 && other !== latestSynced) || !contactMatches(other, message)) continue;
        const content = String(other.body || "").trim();
        if (!content) {
            if (hasMedia(other)) lines = lines.filter(line => !isMediaPlaceholder(line));
            continue;
        }
        const parts = content.split("\n");
        for (let i = lines.length - parts.length; i >= 0; i--) {
            if (parts.every((part, j) => lines[i + j].trim() === part.trim())) {
                lines.splice(i, parts.length);
                break;
            }
        }
    }
    remaining = lines.join("\n").trim();
    return !remaining;
}

function updateCalls(history, previous, incoming, now) {
    const records = history.map(c => Object.assign({}, c));
    const active = [];
    const used = [];
    for (const call of incoming) {
        let prior = previous.find(p => p.sourceId === call.id && !used.includes(p.id));
        if (!prior) prior = previous.find(p => !used.includes(p.id) && contactMatches(p, call));
        let record = prior ? records.find(c => c.id === prior.id) : null;
        // Reattach a call still in progress after a shell reload.
        if (!record) record = records.find(c => !c.endedAt && c.sourceId === call.id && !used.includes(c.id));
        if (!record) {
            record = {id: "call:" + now + ":" + active.length, time: now, endedAt: 0};
            records.unshift(record);
        }
        Object.assign(record, {
            sourceId: call.id, name: call.name || record.name || "",
            number: call.number || record.number || "",
            deviceId: call.deviceId || record.deviceId || "",
            picture: savedImage(call.picture) || record.picture || "",
            incoming: record.incoming || ["incoming", "waiting"].includes(call.state) || call.backend === "KDE Connect",
            answered: record.answered || ["active", "held"].includes(call.state), endedAt: 0
        });
        used.push(record.id);
        active.push({id: record.id, sourceId: call.id, name: record.name, number: record.number});
    }
    for (const record of records) {
        if (!record.endedAt && !used.includes(record.id)) record.endedAt = now;
    }
    return {calls: records.sort(newestFirst).slice(0, limit), active: active};
}

function updateMessages(history, seen, incoming, clearedAt, now) {
    const records = coalesceMessages(adoptNotificationKeys(history, incoming));
    const ids = seen.slice();
    const sanitizedIncoming = sanitizeHistoryMessages(incoming);
    for (const message of sanitizedIncoming.slice().reverse()) {
        const time = Number(message.notificationTime) || Number(message.time) || now;
        const key = notificationEventId(message) || message.id;
        if (!key || time <= clearedAt) continue;
        let index = records.findIndex(m => m.sourceIds.includes(key) || sameNotification(m, message)
            || (m.sourceIds.includes(message.id) && (!m.notificationKey || !message.notificationKey)));
        if (index < 0) index = records.findIndex(m => {
            if (Math.abs(m.time - time) > 30000 || !contactMatches(m, message)) return false;
            if (m.sourceIds.some(id => id.split(":")[0] === key.split(":")[0])) return false;
            if (m.body === (message.body || "")) return true;
            return (hasMedia(m) || hasMedia(message)) && (isMediaPlaceholder(message.body) || isMediaPlaceholder(m.body));
        });
        if (index < 0 && ids.includes(key)) continue;
        const old = index >= 0 ? records[index] : null;
        // Phone notifications reuse an ID as their unread-message bundle
        // grows. Never replace an individual synced SMS with that bundle.
        if (old && message.mirrored && old.body !== message.body
            && old.sourceIds.some(id => !id.startsWith("notification:"))) {
            const picture = savedImage(message.picture);
            if (picture) records[index] = Object.assign({}, old, {picture});
            continue;
        }
        const resolvedBody = old && hasMedia(old) && isMediaPlaceholder(message.body) ? (old.body || "")
            : hasMedia(message) && isMediaPlaceholder(old?.body) ? (message.body || "") : (message.body || old?.body || "");
        const record = {
            id: old?.id || "message:" + key, sourceIds: (old?.sourceIds || []).concat(message.sourceIds || [message.id], [key]).filter((id, i, all) => all.indexOf(id) === i),
            time: old?.time || time, thread: message.thread ?? old?.thread, name: message.name || old?.name || "",
            notificationKey: message.notificationKey || old?.notificationKey || "",
            notificationTime: Number(message.notificationTime) || old?.notificationTime || 0,
            notificationPart: message.notificationPart ?? old?.notificationPart ?? 0,
            bundled: !!message.bundled || !!old?.bundled,
            type: message.type ?? old?.type, sub: message.sub ?? old?.sub,
            number: message.number || old?.number || "", body: resolvedBody,
            deviceId: message.deviceId || old?.deviceId || "",
            picture: savedImage(message.picture) || old?.picture || "",
            previewImage: savedImage(message.previewImage) || old?.previewImage || "",
            media: (message.media?.length ? message.media : old?.media || []).slice(0, 16),
            images: (message.images || []).map(savedImage).filter(Boolean).slice(0, 4),
            audioClips: (message.audioClips || []).slice(0, 8).map(clip => ({
                deviceId: clip.deviceId || message.deviceId || "", part: clip.part,
                mime: clip.mime || "audio/*", uid: clip.uid || ""
            })),
            mirrored: !!message.mirrored && !(old?.sourceIds || []).some(id => !id.startsWith("notification:"))
        };
        if (!record.images.length && old?.images?.length) record.images = old.images;
        if (!record.audioClips.length && old?.audioClips?.length) record.audioClips = old.audioClips;
        if (index >= 0) records[index] = record;
        else records.push(record);
        if (!ids.includes(key)) ids.push(key);
    }
    const reconciled = coalesceMessages(adoptNotificationKeys(records, sanitizedIncoming));
    return {messages: reconciled.filter(m => !m.mirrored || !mirrorRepresented(m, reconciled))
        .sort(newestFirst).slice(0, limit), seen: ids.slice(-500)};
}
