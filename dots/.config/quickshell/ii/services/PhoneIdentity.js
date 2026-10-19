.pragma library

function parseNumber(value) {
    const text = String(value || "").trim();
    const international = /^(\+|00)/.test(text);
    const digits = text.replace(/\D/g, "");
    return {digits: international && text.startsWith("00") ? digits.slice(2) : digits, international};
}

// The one rule for "same phone line". Equal digits match. A national number
// (one trunk 0 dropped) matches an international one ending in it after a
// 1-3 digit country code. Two international numbers must be equal, so
// +33 1234567890 is never +44 1234567890, and short codes match only exactly.
function numberMatches(left, right) {
    const a = parseNumber(left), b = parseNumber(right);
    if (!a.digits || !b.digits) return false;
    if (a.digits === b.digits) return true;
    if (a.international && b.international) return false;
    const aNational = !a.international && (b.international || a.digits.length < b.digits.length);
    const national = (aNational ? a : b).digits.replace(/^0/, "");
    const full = (aNational ? b : a).digits;
    const countryCode = full.length - national.length;
    return national.length >= 7 && countryCode >= 1 && countryCode <= 3 && full.endsWith(national);
}

// Match the number signal to its notification, not to an older call from the
// same contact. Keep ambiguous matches private rather than guessing a number.
function forNotification(notification, details) {
    const body = notification.plainBody || notification.body || "";
    const prefix = body.match(/^(.+?):\s*(?:Incoming|Missed) call\b/i);
    const caller = prefix ? prefix[1] : body.replace(/^(?:Incoming|Missed) call from /i, "");
    const matches = details.filter(d => Math.abs(d.time - notification.time) <= 15000
        && (d.name === caller || d.number === caller));
    const detail = matches.length === 1 ? matches[0] : null;
    const number = detail ? detail.number : (/^\+?[\d ()\-.]+$/.test(caller) ? caller : "");
    return {name: detail?.name || caller, number: number};
}

function enrichCall(call, notifications, singleCall) {
    const matches = notifications.filter(n =>
        (call.number && n.number === call.number) || (call.name && n.name === call.name));
    const match = matches.length === 1 ? matches[0]
        : singleCall && notifications.length === 1 ? notifications[0] : null;
    return Object.assign({}, call, {
        name: call.name || match?.name || "",
        number: call.number || match?.number || "",
        picture: call.picture || match?.picture || ""
    });
}

function mergeNotifications(calls) {
    const merged = [];
    for (const call of calls) {
        const index = merged.findIndex(other => Math.abs(other.time - call.time) <= 15000
            && (!other.deviceName || !call.deviceName || other.deviceName === call.deviceName)
            && ((call.number && other.number === call.number) || (call.name && other.name === call.name)));
        if (index < 0) { merged.push(call); continue; }
        const old = merged[index];
        // Keep the telephony notification's action; the mirrored Phone app
        // notification can supply a newer photo without replacing controls.
        const preferred = call.nativeEvent && !old.nativeEvent ? call : old;
        merged[index] = Object.assign({}, preferred, {picture: call.picture || old.picture || "",
            number: preferred.number || old.number || call.number || ""});
    }
    return merged;
}

function matchingContact(entry, contacts) {
    if (!contacts?.length || !entry) return null;
    const number = entry.number || entry.address || "";
    const digits = parseNumber(number).digits;
    const pool = entry.deviceId ? contacts.filter(c => !c.deviceId || c.deviceId === entry.deviceId) : contacts;
    let matches = [];
    if (digits) {
        matches = pool.filter(c => (c.numbers || []).some(n => parseNumber(n).digits === digits));
        if (!matches.length) matches = pool.filter(c => (c.numbers || []).some(n => numberMatches(number, n)));
    } else if (entry.name) {
        const name = String(entry.name).trim().toLowerCase();
        matches = pool.filter(c => String(c.name || "").trim().toLowerCase() === name);
    }
    return matches.length === 1 ? matches[0] : null;
}

function withContact(entry, contacts, photos) {
    if (!entry) return entry;
    const contact = matchingContact(entry, contacts);
    const existingPic = (typeof entry.picture === "string" && (entry.picture.startsWith("file://") || entry.picture.startsWith("data:image/")))
        ? entry.picture : "";

    if (!contact) {
        const photo = !existingPic ? matchingContact(entry, photos || []) : null;
        const pic = existingPic || photo?.picture || "";
        return pic ? Object.assign({}, entry, {picture: pic}) : entry;
    }
    const resolved = Object.assign({}, entry, {
        name: contact.name || entry.name || "",
        number: entry.number || (contact.numbers && contact.numbers.length === 1 ? contact.numbers[0] : ""),
        deviceId: entry.deviceId || contact.deviceId || "",
        picture: contact.picture || existingPic || ""
    });
    if (!resolved.picture) {
        const photo = matchingContact(resolved, photos || []);
        if (photo?.picture) resolved.picture = photo.picture;
    }
    return resolved;
}
