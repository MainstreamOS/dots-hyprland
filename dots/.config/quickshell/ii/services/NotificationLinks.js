.pragma library

// A phone sends a notification without the link its app would open, so a known
// app opens the page of its site that lists what it just announced.
const sites = {
    "gmail": "https://mail.google.com/",
    "reddit": "https://www.reddit.com/notifications",
    "x": "https://x.com/notifications",
    "twitter": "https://x.com/notifications",
    "instagram": "https://www.instagram.com/",
    "facebook": "https://www.facebook.com/notifications",
    "messenger": "https://www.messenger.com/",
    "threads": "https://www.threads.com/",
    "bluesky": "https://bsky.app/notifications",
    "youtube": "https://www.youtube.com/",
    "discord": "https://discord.com/channels/@me",
    "whatsapp": "https://web.whatsapp.com/",
    "telegram": "https://web.telegram.org/",
    "linkedin": "https://www.linkedin.com/notifications/",
    "github": "https://github.com/notifications",
    "outlook": "https://outlook.live.com/mail/",
    "yahoo mail": "https://mail.yahoo.com/",
    "proton mail": "https://mail.proton.me/",
    "slack": "https://app.slack.com/client",
    "twitch": "https://www.twitch.tv/",
    "tiktok": "https://www.tiktok.com/",
    "nextdoor": "https://nextdoor.com/",
};

// Reddit titles a post's notification with its community, as "GeminiAI:" or
// "Now in r/elgato", and the text is the post's title: enough to find the post.
// A reply names a community too, but its text is a comment no search finds.
function redditPost(title, text) {
    const community = /^([A-Za-z0-9_]{2,21}):$/.exec(title) || /^\S+(?: \S+)? in r\/([A-Za-z0-9_]{2,21})$/.exec(title);
    if (!community) return "";
    const page = "https://www.reddit.com/r/" + community[1] + "/";
    const post = text.split("\n")[0].trim();
    return post ? page + "search/?q=" + encodeURIComponent(post) + "&restrict_sr=1" : page;
}

function siteFor(app, title, text) {
    const name = String(app || "").trim().toLowerCase();
    if (name === "reddit") return redditPost(String(title || "").trim(), String(text || "")) || sites.reddit;
    return sites[name] || "";
}

// The text to look for a web address in. Apps wrap what a person typed in
// direction marks, which would otherwise end up inside the address.
function linkText(entry) {
    return ((entry.summary || "") + "\n" + (entry.body || ""))
        .replace(/[‎‏‪-‮⁦-⁩]/g, " ").replace(/&amp;/g, "&");
}

// `urls` are the web addresses found in linkText(entry), in order.
function linkFor(entry, urls) {
    const found = (urls || []).find(url => /^https?:\/\//i.test(url));
    if (found) return found;
    return entry.phoneOrigin ? siteFor(entry.sourceApp || entry.appName, entry.summary, entry.body) : "";
}

// The site a link leads to, shown on its button so it is clear before the click.
function host(url) {
    const authority = String(url || "").replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split(/[\/?#]/)[0];
    return authority.slice(authority.lastIndexOf("@") + 1).replace(/:\d+$/, "").replace(/^www\./i, "").toLowerCase();
}
