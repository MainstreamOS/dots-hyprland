.pragma library

function body(value, markup) {
    let text = String(value || "").replace(/\r\n?/g, "\n");
    if (markup) {
        text = text.replace(/<br\s*\/?\s*>/gi, "\n")
            .replace(/<\/(?:p|div)>/gi, "\n\n")
            .replace(/<li\b[^>]*>/gi, "\n• ")
            .replace(/<\/?(?:b|i|u|strong|em|span|a|p|div|li|ul|ol)\b[^>]*>/gi, "")
            .replace(/<img\b[^>]*>/gi, "")
            .replace(/&#(x[\da-f]+|\d+);/gi, (match, code) => {
                const point = code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code);
                return point > 0 && point <= 0x10ffff ? String.fromCodePoint(point) : match;
            })
            .replace(/&(lt|gt|quot|apos|nbsp|amp);/g, (match, entity) =>
                ({lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", amp: "&"})[entity]);
    }
    return text.split("\n").map(line => line.replace(/\s+$/, "")).join("\n").replace(/\n{3,}/g, "\n\n").trim();
}
