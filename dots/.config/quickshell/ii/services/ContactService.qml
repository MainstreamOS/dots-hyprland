pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "PhoneIdentity.js" as Identity

Singleton {
    id: root
    property var records: []

    function ingest(data): void {
        if (!data) return;
        const incoming = Array.isArray(data) ? data : (data.records || data.contacts || []);
        const device = data.device || "";
        const next = device ? root.records.filter(r => r.deviceId !== device).concat(incoming) : incoming.slice();
        if (JSON.stringify(next) !== JSON.stringify(root.records)) root.records = next;
    }

    function matchingContact(entry): var { return Identity.matchingContact(entry, root.records); }
    function nameFor(address, fallbackName, deviceId): string {
        const raw = address?.address ?? address?.number ?? address;
        const contact = root.matchingContact({number: raw, name: fallbackName || "", deviceId: deviceId || address?.deviceId || ""});
        return contact?.name || fallbackName || String(raw ?? "");
    }
    function pictureFor(address, name, deviceId): string {
        const raw = address?.address ?? address?.number ?? address;
        const entry = {number: raw, name: name || address?.name || "", deviceId: deviceId || address?.deviceId || ""};
        const contact = root.matchingContact(entry);
        if (contact?.picture) return contact.picture;
        const photo = Identity.matchingContact(entry, IslandPhoneHistory.contactPhotos || []);
        return photo?.picture || "";
    }
    function withContact(entry): var {
        return Identity.withContact(entry, root.records, IslandPhoneHistory.contactPhotos || []);
    }
}
