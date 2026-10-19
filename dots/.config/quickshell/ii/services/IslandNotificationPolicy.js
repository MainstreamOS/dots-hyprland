.pragma library

// KDE Connect preserves these hints even when the displayed app is the
// originating phone app. App names alone cannot identify mirrored alerts.
function isPhone(notification) {
    const hints = notification.hints || notification.notification?.hints || {};
    const component = String(hints["x-kde-appname"] || hints["desktop-entry"] || "");
    return notification.phoneOrigin === true || !!hints["x-kdeconnect-source-device"]
        || /^(org\.kde\.)?kdeconnect(?:[.-].*)?$/i.test(component)
        || /^kde\s*connect$/i.test(notification.appName || "");
}

function panelFor(notification) {
    const hints = notification.hints || notification.notification?.hints || {};
    const event = hints["x-kde-eventId"] || "";
    if (event === "callReceived") return "call";
    if (event === "smsReceived") return "text";
    if (["call", "text"].includes(notification.islandPanel)) return notification.islandPanel;
    if (isPhone(notification)) {
        const app = application(notification);
        if (/^(?:(?:google|samsung)\s+)?(?:messages|messaging|sms|text messages)$/i.test(app)) return "text";
        if (/^(?:Incoming|Missed) call from\b/i.test(notification.plainBody || notification.body || "")) return "call";
        if (/^(?:phone|calls)$/i.test(app) && /(?:^|:\s*)Incoming call\b/i.test(notification.plainBody || notification.body || "")) return "call";
    }
    return "notifications";
}

function application(notification) {
    const hints = notification.hints || notification.notification?.hints || {};
    const app = hints["x-kde-display-appname"] || notification.sourceApp || notification.appName || "";
    return /^kde\s*connect$/i.test(app) ? notification.summary || app : app;
}

function incomingCall(notification) {
    const hints = notification.hints || notification.notification?.hints || {};
    const body = notification.plainBody || notification.body || "";
    // KDE Connect can reuse an incoming call's notification for a missed
    // call without replacing its event hint or removing the mute action.
    if (hints["x-kde-eventId"] === "missedCall" || /(?:^|:\s*)Missed call\b/i.test(body)) return false;
    return hints["x-kde-eventId"] === "callReceived"
        || /(?:^|:\s*)Incoming call\b/i.test(body);
}

function messageFor(notification) {
    let body = notification.plainBody ?? notification.body ?? "";
    const app = application(notification);
    let name = notification.summary || "";
    const hints = notification.hints || notification.notification?.hints || {};
    const native = hints["x-kde-eventId"] === "smsReceived" || /^SMS from\s+/i.test(name);
    if (/^SMS from\s+/i.test(name)) name = name.replace(/^SMS from\s+/i, "");
    else if (name === app || /^kde\s*connect$/i.test(name)) {
        const prefix = body.match(/^([^:\n]{1,100}):\s*/);
        name = prefix?.[1] || "";
        if (prefix) body = body.slice(prefix[0].length);
    }
    return {id: (native ? "sms-notification:" : "notification:") + notification.notificationId, name, body,
        number: /^\+?[\d ()\-.]+$/.test(name) ? name : "",
        // Only a contact image is a portrait; other notification images can be message artwork.
        picture: !notification.imageRole || notification.imageRole === "contact" ? notification.image || "" : "", time: notification.time,
        deviceId: notification.kdeDeviceId || "", mirrored: !native};
}

function isMediaApp(appName) {
    const lower = String(appName || "").trim().toLowerCase();
    return /^(spotify|youtube\s*music|yt\s*music|apple\s*music|soundcloud|vlc|pocket\s*casts|pandora|deezer|tidal|audible|samsung\s*music|poweramp|musicolet|plexamp|jellyfin|finamp|gramophone|auxio|metro|retro\s*music|oto\s*music)$/i.test(lower);
}

function isReplyAction(action) {
    if (!action) return false;
    const id = String(action.identifier || "").trim().toLowerCase();
    const text = String(action.text || "").trim().toLowerCase();
    return id === "inline-reply"
        || /^(reply|respond|quick\s*reply)$/i.test(text)
        || /^(reply|respond|quick\s*reply)$/i.test(id);
}

function isReliablePhoneAction(action, appName) {
    if (!action || isMediaApp(appName) || isReplyAction(action)) return false;
    const label = String(action.text || action.identifier || "").trim().toLowerCase();
    if (!label) return false;
    // Android 14 blocks background activity launches, so actions that open a phone screen fail here.
    if (/^(share|edit|modify|open|view|launch|settings|configure|turn\s*off|manage|details|snooze|watch|install|update|browser|search)\b/i.test(label)) {
        return false;
    }
    // Actions handled by a background receiver or service work from here.
    return /^(delete|trash|remove|discard|archive|mark\s*as\s*read|mark\s*read|read|seen|mark\s*as\s*done|done|complete|dismiss|clear|cancel|stop|silence|mute|unmute|copy|approve|deny|accept|reject|decline)\b/i.test(label);
}

function filterActions(rawActions, phoneOrigin, appName, isLive) {
    const list = rawActions || [];
    if (!phoneOrigin) {
        if (!isLive) return [];
        return list.filter(a => a && (a.text || a.identifier) && !isReplyAction(a));
    }
    return list.filter(a => isReliablePhoneAction(a, appName));
}

function hasReplyCapability(rawActions, hasInlineReply, kdeReplyId, phoneOrigin, appName, isLive) {
    if (phoneOrigin && isMediaApp(appName)) return false;
    if (!phoneOrigin && !isLive) return false;
    if (hasInlineReply) return true;
    if (kdeReplyId && String(kdeReplyId).trim().length > 0) return true;
    return (rawActions || []).some(a => isReplyAction(a));
}
