.pragma library

// Shared reaction detection and bundled message parsing for Phone and Dynamic Island.

function parseReaction(body) {
    if (!body || typeof body !== "string") return null;
    const text = body.trim();
    if (text.length === 0) return null;

    // 😂 to “hello”
    const googleTextMatch = text.match(/^[\s\u200a\u200b]*(\S+?)[\s\u200a\u200b]+to[\s\u200a\u200b]+[“"'\u201c]([\s\S]*?)[”"'\u201d][\s\u200a\u200b]*$/);
    if (googleTextMatch) {
        const emoji = googleTextMatch[1].replace(/[\s\u200a\u200b]/g, "");
        const target = googleTextMatch[2].replace(/^[\s\u200a\u200b]+|[\s\u200a\u200b]+$/g, "");
        if (emoji && target) {
            return { emoji: emoji, target: target, kind: "text", action: "add" };
        }
    }

    // 😂 to an image
    const googleMediaMatch = text.match(/^[\s\u200a\u200b]*(\S+?)[\s\u200a\u200b]+to[\s\u200a\u200b]+(?:an?\s+)?(image|photo|picture|video|audio|file|attachment)[\s\u200a\u200b]*$/i);
    if (googleMediaMatch) {
        const emoji = googleMediaMatch[1].replace(/[\s\u200a\u200b]/g, "");
        return { emoji: emoji, target: googleMediaMatch[2].toLowerCase(), kind: "media", action: "add" };
    }

    // iMessage: Liked “hello”
    const appleMap = {
        "Liked": "👍",
        "Loved": "❤️",
        "Disliked": "👎",
        "Laughed at": "😂",
        "Emphasized": "‼️",
        "Questioned": "❓"
    };
    const appleTextMatch = text.match(/^(Liked|Loved|Disliked|Laughed at|Emphasized|Questioned|Reacted\s+(\S+)\s+to)[\s\u200a\u200b]+[“"'\u201c]([\s\S]*?)[”"'\u201d][\s\u200a\u200b]*$/);
    if (appleTextMatch) {
        const verb = appleTextMatch[1];
        let emoji = appleMap[verb];
        if (!emoji && verb.startsWith("Reacted")) emoji = appleTextMatch[2];
        const target = appleTextMatch[3].replace(/^[\s\u200a\u200b]+|[\s\u200a\u200b]+$/g, "");
        if (emoji && target) {
            return { emoji: emoji, target: target, kind: "text", action: "add" };
        }
    }

    // iMessage: Liked an image
    const appleMediaMatch = text.match(/^(Liked|Loved|Disliked|Laughed at|Emphasized|Questioned)[\s\u200a\u200b]+(?:an?\s+)?(image|photo|picture|video|audio|file|attachment)[\s\u200a\u200b]*$/i);
    if (appleMediaMatch) {
        const emoji = appleMap[appleMediaMatch[1]] || "👍";
        return { emoji: emoji, target: appleMediaMatch[2].toLowerCase(), kind: "media", action: "add" };
    }

    // Removed 😂 from “hello”
    const removedMatch = text.match(/^[\s\u200a\u200b]*Removed\s+(?:a\s+|an\s+)?(?:\S+)\s+(?:to|from)[\s\u200a\u200b]+[“"'\u201c]([\s\S]*?)[”"'\u201d][\s\u200a\u200b]*$/);
    if (removedMatch) {
        const target = removedMatch[1].replace(/^[\s\u200a\u200b]+|[\s\u200a\u200b]+$/g, "");
        return { emoji: "", target: target, kind: "text", action: "remove" };
    }

    // Removed 😂 from an image
    const removedMediaMatch = text.match(/^[\s\u200a\u200b]*Removed\s+(?:a\s+|an\s+)?(?:\S+)\s+(?:to|from)[\s\u200a\u200b]+(?:an?\s+)?(image|photo|picture|video|audio|file|attachment)[\s\u200a\u200b]*$/i);
    if (removedMediaMatch) {
        return { emoji: "", target: removedMediaMatch[1].toLowerCase(), kind: "media", action: "remove" };
    }

    return null;
}

function isReaction(body) {
    return parseReaction(body) !== null;
}

function extractIndividualMessages(rawBody) {
    if (!rawBody || typeof rawBody !== "string") return [];
    return rawBody.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0 && !isReaction(l));
}

function parseQuote(body) {
    if (!body || typeof body !== "string") return null;
    if (isReaction(body)) return null;
    const text = body.trim();
    if (text.length === 0) return null;

    // “quoted message”\nreply
    const smartMatch = text.match(/^[\s\u200a\u200b]*[“"\u201c]([^\r\n”"\u201d]+)[”"\u201d][ \t]*\r?\n([\s\S]+)$/);
    if (smartMatch) {
        const quoted = smartMatch[1].replace(/^[\s\u200a\u200b]+|[\s\u200a\u200b]+$/g, "");
        const replyBody = smartMatch[2].trim();
        if (quoted.length > 0 && replyBody.length > 0) {
            return { quote: quoted, quotedText: quoted, body: replyBody };
        }
    }

    // > quoted message\nreply
    const blockMatch = text.match(/^>[ \t]*([^\r\n]+)\r?\n\r?\n?([\s\S]+)$/);
    if (blockMatch) {
        const quoted = blockMatch[1].trim();
        const replyBody = blockMatch[2].trim();
        if (quoted.length > 0 && replyBody.length > 0) {
            return { quote: quoted, quotedText: quoted, body: replyBody };
        }
    }

    return null;
}

function formatReply(quotedText, replyText) {
    const cleanQuote = String(quotedText ?? "").replace(/\s+/g, " ").trim().slice(0, 140);
    const cleanReply = String(replyText ?? "").trim();
    if (!cleanQuote) return cleanReply;
    if (!cleanReply) return `“${cleanQuote}”`;
    return `“${cleanQuote}”\n${cleanReply}`;
}
