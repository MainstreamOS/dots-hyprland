.pragma library

const map = {
    "reddit": "reddit",
    "weather": "weather",
    "youtube": "youtube",
    "gmail": "gmail",
    "facebook": "facebook",
    "messenger": "fbmessenger",
    "facebook messenger": "fbmessenger",
    "x": "twitter-x",
    "twitter": "twitter-x",
    "messages": "AndroidMessages",
    "messaging": "AndroidMessages",
    "sms": "AndroidMessages",
    "google messages": "AndroidMessages",
    "samsung messages": "AndroidMessages",
    "photos": "google-photos",
    "google photos": "google-photos",
    "gallery": "google-photos",
    "samsung capture": "accessories-screenshot",
    "screenshot": "accessories-screenshot",
    "discord": "discord",
    "instagram": "instagram",
    "tiktok": "tiktok",
    "telegram": "telegram",
    "whatsapp": "whatsapp",
    "signal": "signal-desktop",
    "spotify": "spotify",
    "slack": "slack",
    "snapchat": "snapchat",
    "steam": "steam",
    "netflix": "netflix",
    "amazon": "amazon",
    "twitch": "gnome-twitch",
    "github": "github",
    "outlook": "ms-outlook"
};

// Notification titles and payload images are content, not app identities.
// Resolve only explicit application names and exact installed desktop IDs.
function appIconFor(name, apps) {
    if (!name) return "";
    const lower = name.trim().toLowerCase();
    if (/^(kde\s*connect|kdeconnect|iphone|phone)$/i.test(lower)) return "";
    if (map[lower]) return map[lower];
    // Message titles and fuzzy launcher matches are not app identities.
    // Only use an installed app whose name or desktop ID matches exactly.
    const desktopEntry = apps.find(app =>
        app.name?.toLowerCase() === lower || app.id?.toLowerCase().replace(/\.desktop$/, "") === lower.replace(/\.desktop$/, ""));
    if (desktopEntry?.icon) return desktopEntry.icon;
    return "";
}
