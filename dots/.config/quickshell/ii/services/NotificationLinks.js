.pragma library
.import "IslandText.js" as IslandText

// A phone sends a notification without the link its app would open, so a known
// app opens the page of its site that lists what it just announced.
const sites = {
    "gmail": "https://mail.google.com/",
    "reddit": "https://www.reddit.com/notifications",
    "instagram": "https://www.instagram.com/",
    "facebook": "https://www.facebook.com/notifications",
    "messenger": "https://www.messenger.com/",
    "threads": "https://www.threads.com/",
    "bluesky": "https://bsky.app/notifications",
    "youtube": "https://www.youtube.com/",
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
const xApp = /^(x(?:\.com)?|twitter(?:\.com)?)$/;

function postExcerpt(text, markup = true) {
    let excerpt = IslandText.body(text, markup).split("\n")[0];
    if (excerpt.length > 120) {
        // Half an emoji cannot go in an address, and a search finds whole words only.
        excerpt = excerpt.slice(0, 120).replace(/[\ud800-\udbff]$/, "");
        const space = excerpt.lastIndexOf(" ");
        if (space > 60) excerpt = excerpt.slice(0, space);
    }
    return excerpt.replace(/(?:\.{3}|…)\s*$/, "").trim();
}

function redditPost(title, text) {
    // Reply and mention alerts lead to the inbox when no direct link is available.
    if (/\b(?:replied to|mentioned you)\b/i.test(title)) return sites.reddit;
    const community = /^([A-Za-z0-9_]{2,21}):$/.exec(title)
        || /(?:^|\s)r\/([A-Za-z0-9_]{2,21}):?$/i.exec(title);
    const page = community ? "https://www.reddit.com/r/" + community[1] + "/" : "https://www.reddit.com/";
    const post = postExcerpt(text);
    if (!post) return community ? page : sites.reddit;
    return page + "search/?q=" + encodeURIComponent(post) + (community ? "&restrict_sr=1" : "");
}

// YouTube tags a video alert "<video id>::<uuid>", and the phone's notification key carries that tag.
const youtubeKey = /^-?\d+\|com\.google\.android\.youtube\|-?\d+\|([\w-]{11})::[\da-f]{8}-/;

// Other YouTube alerts name the channel and the video but send no link, so search
// for them. Comment activity alerts carry no video ID, so open comment history.
function youtubeVideo(title, text, key) {
    const rawKey = String(key || "");
    const video = youtubeKey.exec(rawKey);
    if (video) return "https://www.youtube.com/watch?v=" + video[1];
    if (/\bACTIVITY_COMMENT_/i.test(rawKey)
        || /\b(?:likes? on your (?:comment|reply)|replied to|mentioned you|hearted your (?:comment|reply))\b/i.test(String(title || ""))) {
        return "https://www.youtube.com/feed/history/comment_history";
    }
    // A notification title is plain text, and the video title in the text keeps every word.
    const channel = postExcerpt(title, false).replace(/^(?:new video from\s+|live on youtube\s*:\s*)/i, "")
        .replace(/\s+(?:uploaded|posted|is live(?: now)?|is premiering(?: now)?|premieres?(?: now)?)\s*:\s*/i, " ").trim();
    const parts = [channel, postExcerpt(text)].filter(part => part && part.toLowerCase() !== "youtube");
    // Drop a part the other already holds as whole words, as when the text repeats the title.
    const words = part => " " + part.toLowerCase() + " ";
    const query = parts.filter((part, index) => !parts.some((other, at) => at !== index
        && words(other).includes(words(part)) && (other.length > part.length || at < index))).join(" ");
    return query ? "https://www.youtube.com/results?search_query=" + encodeURIComponent(query) : sites.youtube;
}

function siteFor(app, title, text, key) {
    if (app === "reddit") return redditPost(String(title || "").trim(), text);
    if (app === "youtube") return youtubeVideo(title, text, key);
    if (xApp.test(app)) {
        // The phone often sends only a post excerpt. Search X for the first
        // line, dropping a trailing ellipsis if the phone truncated it.
        const excerpt = postExcerpt(text);
        return excerpt ? "https://x.com/search?q=" + encodeURIComponent(excerpt) : "https://x.com/notifications";
    }
    return Object.prototype.hasOwnProperty.call(sites, app) ? sites[app] : "";
}

// The text to look for a web address in. Apps wrap what a person typed in
// direction marks, which would otherwise end up inside the address.
function linkText(entry) {
    // Preserve a real anchor's destination when its label does not show the URL.
    const body = String(entry.body || "").replace(
        /<a\b[^>]*?\s+href\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>/gi,
        (tag, doubleQuoted, singleQuoted) => {
            const href = doubleQuoted ?? singleQuoted;
            return /^https?:\/\//i.test(href) ? ` ${href} ` : " ";
        });
    return ((entry.summary || "") + "\n" + IslandText.body(body, true))
        .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, " ")
        .replace(/[“”]/g, '"')
        // A notification can include a post or short link without its scheme.
        .replace(/(^|[\s<("'“‘])((?:www\.|mobile\.)?(?:x\.com|twitter\.com|t\.co|reddit\.com|redd\.it)\/(?=[\w%-]))/gi,
            "$1https://$2");
}

// `urls` are the web addresses found in linkText(entry), in order.
function linkFor(entry, urls) {
    const app = String(entry.sourceApp || entry.appName || "").trim().toLowerCase();
    if (/^(?:com\.)?discord(?:[ -]?(?:canary|ptb))?(?:\.desktop)?$/.test(app)) return "";
    const webLinks = (urls || []).filter(url => /^https?:\/\//i.test(url));
    // A notice can name the site in its heading and include a post URL in its body.
    const found = webLinks.find(url => !/^https?:\/\/(?:www\.|mobile\.)?(?:x\.com|twitter\.com)(?:\/notifications)?\/?$/i.test(url));
    if (found) return found;
    if (entry.phoneOrigin && xApp.test(app)) return siteFor(app, entry.summary, entry.body);
    if (webLinks[0]) return webLinks[0];
    return entry.phoneOrigin ? siteFor(app, entry.summary, entry.body, entry.kdeInternalId) : "";
}
