.pragma library

function normalize(text) {
    return String(text || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/\bwi[-\s]+fi\b/g, "wifi").replace(/[-_–—/]+/g, " ").replace(/\s+/g, " ").trim();
}

function titleScore(text, term) {
    if (text === term) return 100;
    if (text.startsWith(term)) return 75;
    return text.includes(term) ? 60 : 0;
}

function breadcrumb(page, sections) {
    return [page, ...sections].filter((part, i, all) => i === 0 || part !== all[i - 1]).join(" › ");
}

function prepareEntries(pages, index, translate) {
    const searchable = [];
    for (let i = 0; i < pages.length; i++) {
        const page = pages[i];
        const entries = [{label: page.name, sections: [], keywords: [], pageOnly: true}, ...(index[page.component] ?? [])];
        for (const entry of entries) {
            const label = entry.pageOnly ? entry.label : translate(entry.label);
            const sections = entry.sections.map(translate);
            const fields = [label, entry.label, page.name, ...sections, ...entry.sections, ...entry.keywords.map(translate), ...entry.keywords];
            searchable.push({page: i, pageName: page.name, icon: page.icon, iconRotation: page.iconRotation ?? 0, label, sourceLabel: entry.label,
                breadcrumb: entry.pageOnly ? "" : breadcrumb(page.name, sections),
                sourceSections: entry.sections, pageOnly: !!entry.pageOnly,
                title: normalize(label), sourceTitle: normalize(entry.label), haystack: normalize(fields.join(" "))});
        }
    }
    return searchable;
}

function search(entries, query) {
    const term = normalize(query);
    if (!term) return [];
    const words = term.split(" ");
    const matches = [];
    for (const entry of entries) {
        if (!words.every(word => entry.haystack.includes(word))) continue;
        let score = Math.max(titleScore(entry.title, term), titleScore(entry.sourceTitle, term));
        score += words.filter(word => entry.title.includes(word)).length * 5;
        if (entry.pageOnly) score += 4;
        matches.push({entry, score});
    }
    matches.sort((a, b) => b.score - a.score);
    return matches.map(match => match.entry);
}
