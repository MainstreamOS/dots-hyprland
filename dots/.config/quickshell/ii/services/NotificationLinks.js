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

function postExcerpt(text) {
    let excerpt = IslandText.body(text, true).split("\n")[0];
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

function siteFor(app, title, text) {
    if (app === "reddit") return redditPost(String(title || "").trim(), text);
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
        .replace(/[‎‏‪-‮⁦-⁩]/g, " ")
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
    return entry.phoneOrigin ? siteFor(app, entry.summary, entry.body) : "";
}
