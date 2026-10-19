pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "IslandPhoneHistory.js" as History
import "PhoneIdentity.js" as Identity

Singleton {
    id: root
    property var calls: []
    property var messages: []
    property var activeCalls: []
    property var seenMessages: []
    property double messagesClearedAt: 0
    property bool ready: false
    property var pendingCalls: []
    property bool callsKnown: false
    property var pendingMessages: []
    property var contacts: []
    property var contactPhotos: []
    property var pendingPhotos: []
    property var pendingPictureSources: []
    property bool writing: false
    property bool writeAgain: false
    property var cachedAttachments: ({})
    property var pendingSynced: []

    function refreshMessages(device, messages) {
        if (!root.ready) {
            root.pendingSynced = root.pendingSynced.concat({device, messages: messages.slice(-100)}).slice(-20);
            return;
        }
        const known = new Set();
        for (const message of root.messages)
            if (message.deviceId === device) for (const id of message.sourceIds) known.add(id);
        const entries = messages.map(m => Phone.messageEntry(device, m)).filter(m => known.has(m.id));
        if (!entries.length) return;
        const updated = History.updateMessages(root.messages, root.seenMessages, entries, root.messagesClearedAt, Date.now());
        if (JSON.stringify(root.messages) !== JSON.stringify(updated.messages)) {
            root.messages = updated.messages;
            root.seenMessages = updated.seen;
            root.refreshAttachments();
            save.restart();
        }
    }

    // Until the call helper has reported, an empty list does not mean a saved
    // call in progress has ended.
    function observeCalls(incoming, known) {
        pendingCalls = incoming;
        callsKnown = known;
        capturePictureSources(incoming);
        if (!ready || !known) return;
        const updated = History.updateCalls(calls, activeCalls, incoming, Date.now());
        activeCalls = updated.active;
        if (JSON.stringify(calls) !== JSON.stringify(updated.calls)) {
            calls = updated.calls;
            save.restart();
        }
        Qt.callLater(root.rememberContactPictures, incoming);
    }
    function observeMessages(incoming) {
        pendingMessages = incoming;
        capturePictureSources(incoming);
        if (!ready) return;
        const updated = History.updateMessages(messages, seenMessages, incoming, messagesClearedAt, Date.now());
        if (JSON.stringify(messages) !== JSON.stringify(updated.messages) || JSON.stringify(seenMessages) !== JSON.stringify(updated.seen)) {
            messages = updated.messages;
            seenMessages = updated.seen;
            save.restart();
        }
        root.refreshAttachments();
        Qt.callLater(root.rememberContactPictures, incoming);
    }
    function refreshAttachments() {
        if (!ready) return;
        let updated = messages;
        const devices = [...new Set(messages.map(m => m.deviceId).filter(Boolean))];
        for (const device of devices) {
            const files = Object.assign({}, cachedAttachments[device] || {},
                device === Phone.deviceId ? Phone.attachmentFiles : {});
            const directory = FileUtils.trimFileProtocol(`${Directories.cache}/phone/${device}`);
            updated = History.resolveImages(updated, device, files, directory);
        }
        if (JSON.stringify(messages) !== JSON.stringify(updated)) {
            messages = updated;
            save.restart();
        }
    }
    // The bridge keeps incoming files across restarts, while the live map fills only
    // as threads open; its cache repairs history for conversations not open.
    FileView {
        path: FileUtils.trimFileProtocol(`${Directories.cache}/phone/attachments.json`)
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.cachedAttachments = data && typeof data === "object" && !Array.isArray(data) ? data : ({});
                root.refreshAttachments();
            } catch (error) { console.warn("[Island history] Could not read attachment cache:", error); }
        }
    }
    Connections {
        target: Phone
        function onMessagesSynced(device, messages) {
            root.refreshMessages(device, messages);
        }
        function onAttachmentFilesChanged() { root.refreshAttachments(); }
        function onDeviceIdChanged() { root.refreshAttachments(); }
    }
    function clearCalls() {
        calls = calls.filter(c => activeCalls.some(a => a.id === c.id));
        save.restart();
    }
    function enrichContacts(incoming) {
        contacts = incoming;
        if (!ready) return;
        const updatedCalls = calls.map(c => Identity.withContact(c, contacts, contactPhotos));
        const updatedMessages = messages.map(m => Identity.withContact(m, contacts, contactPhotos));
        if (JSON.stringify(updatedCalls) !== JSON.stringify(calls) || JSON.stringify(updatedMessages) !== JSON.stringify(messages)) {
            calls = updatedCalls;
            messages = updatedMessages;
            save.restart();
        }
    }
    function capturePictureSources(entries) {
        for (const entry of entries) {
            if (!entry.picture?.startsWith("image://qsimage/") || pendingPictureSources.some(p => p.picture === entry.picture)) continue;
            pendingPictureSources = pendingPictureSources.concat(Object.assign({}, entry)).slice(-60);
        }
    }
    function rememberContactPictures(entries) {
        if (!ready) {
            if (entries.length) pendingPhotos = pendingPhotos.concat(entries).slice(-100);
            return;
        }
        const photos = History.updateContactPhotos(contactPhotos, entries, Date.now());
        if (JSON.stringify(photos) === JSON.stringify(contactPhotos)) return;
        contactPhotos = photos;
        enrichContacts(contacts);
        save.restart();
    }
    Connections {
        target: NotificationImageCache
        function onStored(notificationId, original, cached) {
            const entries = root.pendingPictureSources.filter(p => p.picture === original);
            root.pendingPictureSources = root.pendingPictureSources.filter(p => p.picture !== original);
            root.rememberContactPictures(entries.map(p => Object.assign({}, p, {picture: cached})));
        }
    }
    function clearMessages() {
        messages = [];
        messagesClearedAt = Date.now();
        save.restart();
    }
    function write() {
        if (!ready) return;
        if (writing) { writeAgain = true; return; }
        const text = JSON.stringify({version: 1, calls: calls, messages: messages, contactPhotos: contactPhotos,
            seenMessages: seenMessages, messagesClearedAt: messagesClearedAt});
        if (text === historyFile.text()) return;
        writing = true;
        historyFile.setText(text);
    }
    function writeDone() {
        writing = false;
        if (writeAgain) { writeAgain = false; save.restart(); }
    }
    function loaded() {
        ready = true;
        for (const batch of pendingSynced) root.refreshMessages(batch.device, batch.messages);
        pendingSynced = [];
        rememberContactPictures(pendingPhotos);
        pendingPhotos = [];
        enrichContacts(contacts);
        observeCalls(pendingCalls, callsKnown);
        observeMessages(pendingMessages);
        refreshAttachments();
        save.restart();
    }
    Timer { id: save; interval: 200; onTriggered: root.write() }
    FileView {
        id: historyFile
        path: Directories.islandPhoneHistoryPath
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.calls = (Array.isArray(data.calls) ? data.calls : []).slice(0, 30);
                const rawMessages = (Array.isArray(data.messages) ? data.messages : []).filter(m => Array.isArray(m.sourceIds));
                root.messages = History.sanitizeHistoryMessages(rawMessages).slice(0, 30);
                root.contactPhotos = (Array.isArray(data.contactPhotos) ? data.contactPhotos : []).slice(0, 100);
                root.seenMessages = (Array.isArray(data.seenMessages) ? data.seenMessages : []).slice(-500);
                root.messagesClearedAt = Number(data.messagesClearedAt) || 0;
            } catch (error) { console.warn("[Island history] Unable to read recent phone history:", error); }
            root.loaded();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) console.warn("[Island history] History file could not be loaded:", error);
            root.loaded();
        }
        onSaved: Qt.callLater(root.writeDone)
        onSaveFailed: Qt.callLater(root.writeDone)
    }
}
