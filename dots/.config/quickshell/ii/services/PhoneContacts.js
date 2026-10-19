.pragma library

// Keep contact identity separate from its display name: names and phone
// numbers can be shared by different people and different paired devices.
function dialNumber(value) {
    const number = String(value ?? "").replace(/[\s().-]/g, "");
    return /^\+?[0-9*#]{1,80}$/.test(number) ? number : "";
}

function directory(records, deviceId) {
    const contacts = new Map();
    for (const record of records || []) {
        if (!record || (deviceId && record.deviceId !== deviceId)) continue;
        const name = String(record.name || "").trim();
        const numbers = [];
        for (const value of Array.isArray(record.numbers) ? record.numbers : []) {
            const number = dialNumber(value);
            if (!number) continue;
            const index = numbers.findIndex(n => n.replace(/^\+/, "") === number.replace(/^\+/, ""));
            if (index < 0) numbers.push(number);
            else if (number.startsWith("+")) numbers[index] = number;
        }
        if (!name && !numbers.length) continue;
        const device = String(record.deviceId || "");
        const key = JSON.stringify([device, record.uid || [name, numbers.slice().sort()]]);
        const previous = contacts.get(key);
        if (previous) {
            previous.numbers = [...new Set(previous.numbers.concat(numbers))];
            previous.picture = previous.picture || record.picture || "";
        } else {
            contacts.set(key, {key, deviceId: device, name: name || numbers[0], numbers,
                picture: record.picture || ""});
        }
    }
    return Array.from(contacts.values()).sort((a, b) => a.name.localeCompare(b.name));
}

function search(contacts, query) {
    const text = String(query || "").trim().toLocaleLowerCase();
    if (!text) return contacts;
    const digits = text.replace(/\D/g, "");
    return contacts.filter(contact => contact.name.toLocaleLowerCase().includes(text)
        || contact.numbers.some(number => number.includes(text)
            || (digits.length >= 3 && number.replace(/\D/g, "").includes(digits))));
}

function initials(name) {
    const parts = String(name || "").trim().split(/\s+/);
    if (parts.length > 1) return (Array.from(parts[0])[0] + Array.from(parts[1])[0]).toLocaleUpperCase();
    return (Array.from(parts[0] || "").slice(0, 2).join("") || "??").toLocaleUpperCase();
}
