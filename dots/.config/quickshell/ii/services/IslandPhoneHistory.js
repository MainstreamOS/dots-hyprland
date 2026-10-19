.pragma library
.import "PhoneReactions.js" as Reactions
.import "PhoneIdentity.js" as Identity

const limit = 30;
const mediaPlaceholders = new Set(["image", "photo", "gif", "video", "audio", "voice message", "media", "attachment"]);

function isMediaPlaceholder(body) {
    return mediaPlaceholders.has(String(body || "").trim().toLowerCase());
}

function hasMedia(message) {
    return !!(message.images?.length || message.audioClips?.length);
}

// Reactions fold into the message they react to, so history keeps neither.
function sanitizeHistoryMessages(rawList) {
    return Array.isArray(rawList) ? rawList.filter(m => m && !Reactions.isReaction(String(m.body || ""))) : [];
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
    return result.sort((a, b) => b.time - a.time).slice(0, 100);
}

function mirrorRepresented(message, records) {
    let remaining = String(message.body || "").trim();
    if (!remaining) return false;
    let lines = remaining.split("\n");
    for (const other of records) {
        if (other.id === message.id || !other.sourceIds.some(id => !id.startsWith("notification:"))
            || Math.abs(other.time - message.time) > 120000 || !contactMatches(other, message)) continue;
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
    return {calls: records.sort((a, b) => b.time - a.time).slice(0, limit), active: active};
}

function updateMessages(history, seen, incoming, clearedAt, now) {
    const records = history.slice();
    const ids = seen.slice();
    const sanitizedIncoming = sanitizeHistoryMessages(incoming);
    for (const message of sanitizedIncoming.slice().reverse()) {
        const time = Number(message.time) || now;
        const key = message.id;
        if (!key || time <= clearedAt) continue;
        let index = records.findIndex(m => m.sourceIds.includes(key));
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
        const resolvedBody = (old?.images?.length && isMediaPlaceholder(message.body)) ? (old.body || "") : (message.body || old?.body || "");
        const record = {
            id: old?.id || "message:" + key, sourceIds: (old?.sourceIds || []).concat(key).filter((id, i, all) => all.indexOf(id) === i),
            time: old?.time || time, name: message.name || old?.name || "",
            number: message.number || old?.number || "", body: resolvedBody,
            deviceId: message.deviceId || old?.deviceId || "",
            picture: savedImage(message.picture) || old?.picture || "",
            previewImage: savedImage(message.previewImage) || old?.previewImage || "",
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
    return {messages: records.filter(m => !m.mirrored || !mirrorRepresented(m, records))
        .sort((a, b) => b.time - a.time).slice(0, limit), seen: ids.slice(-500)};
}
