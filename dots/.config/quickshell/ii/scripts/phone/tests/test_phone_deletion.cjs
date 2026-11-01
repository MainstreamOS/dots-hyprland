// Desktop deletion is device-scoped and must survive cache replays and reloads.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');
const services = path.resolve(__dirname, '../../../services');
const helper = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(services, 'PhoneConversationVisibility.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), helper);
const plain = value => JSON.parse(JSON.stringify(value));
const old = {uid: 'old', thread: 2, date: 90, type: 1, attachments: [{uid: 'private'}]};
const fresh = {uid: 'fresh', thread: 2, date: 101, type: 1};

test('cutoffs survive restart and exclude old replay without excluding new or other-device messages', () => {
    const saved = helper.purgeSaved({phone: [old], other: [old], _hiddenConversations: {phone: [2]}}, 'phone', [2], 100);
    const restored = JSON.parse(JSON.stringify(saved));
    assert.deepEqual(restored.phone, []);
    assert.deepEqual(restored.other, [old]);
    assert.deepEqual(restored._hiddenConversations, {phone: [2]});
    assert.deepEqual(plain(helper.keptMessages([old, fresh], restored._deletedConversations, 'phone')), [fresh]);
    assert.deepEqual(plain(helper.keptMessages([old], restored._deletedConversations, 'other')), [old]);
    const olderAck = helper.deleteBefore(restored._deletedConversations, 'phone', [2], 80);
    assert.equal(olderAck.phone[2], 100);
});

function phoneFixture() {
    const signals = [];
    const root = {
        deviceId: 'phone', savedLocalSent: {phone: [old], other: [old],
            _hiddenConversations: {phone: [2]},
            _outgoingAttachments: [{...old, device: 'phone'}, {...old, device: 'other'}],
            _deviceAttachments: {phone: {private: '/original/user-file', shared: '/shared'}, other: {private: '/other'}}},
        conversations: [old, fresh], threadCache: {2: [old, fresh]}, threadMessages: [old, fresh],
        recentMessages: [{...old, deviceId: 'phone'}, {...old, deviceId: 'other'}],
        attachmentFiles: {private: '/original/user-file', shared: '/shared'}, attachmentThumbs: {}, attachmentDurations: {},
        attachmentActions: {one: {device: 'phone', uid: 'private'}, two: {device: 'other', uid: 'private'}},
        openThread: 2, deletionRequest: '', deletingConversations: false,
        closeConversation() { this.openThread = -1; this.threadMessages = []; },
        conversationsDeleted(...args) { signals.push(args); },
        command(fields) { signals.push(plain(fields)); return 'request'; },
    };
    const context = vm.createContext({root, ConversationVisibility: helper, saveSentTimer: {restart() {}}});
    const source = fs.readFileSync(path.join(services, 'Phone.qml'), 'utf8');
    for (const name of ['applyConversationDeletion', 'deleteHiddenConversations', 'keepMessages']) {
        const match = source.match(new RegExp(`    function ${name}\\(([^)]*)\\): (?:void|var) \\{([\\s\\S]*?)\\n    \\}`));
        assert.ok(match, `Missing production function ${name}`);
        root[name] = vm.runInContext(`(function(${match[1]}) {${match[2]}\n})`, context);
    }
    return {root, signals};
}

test('an acknowledged deletion clears local copies and pending media, preserving new messages and other phones', () => {
    const {root, signals} = phoneFixture();
    root.applyConversationDeletion('phone', [2], 100);
    assert.deepEqual(plain(root.conversations), [fresh]);
    assert.deepEqual(plain(root.threadCache), {2: [fresh]});
    assert.deepEqual(plain(root.threadMessages), [fresh]);
    assert.deepEqual(plain(root.localSent), []);
    assert.deepEqual(plain(root.savedLocalSent.other), [old]);
    assert.deepEqual(plain(root.savedLocalSent._outgoingAttachments), [{...old, device: 'other'}]);
    assert.deepEqual(plain(root.savedLocalSent._deviceAttachments), {phone: {shared: '/shared'}, other: {private: '/other'}});
    assert.deepEqual(plain(root.attachmentActions), {two: {device: 'other', uid: 'private'}});
    assert.equal(root.recentMessages.length, 1);
    assert.equal(root.recentMessages[0].deviceId, 'other');
    assert.deepEqual(plain(signals), [['phone', [2], 100]]);
    root.applyConversationDeletion('phone', [2], 100);
    assert.deepEqual(plain(root.conversations), [fresh]);
});

test('the confirmation only submits still-hidden conversations on its original phone', () => {
    const {root, signals} = phoneFixture();
    root.deleteHiddenConversations('other', [2]);
    assert.equal(signals.length, 0);
    root.deleteHiddenConversations('phone', [2, 3]);
    assert.deepEqual(signals[0], {cmd: 'deleteConversations', device: 'phone', threads: [2]});
    assert.equal(root.deletionRequest, 'request');
    assert.deepEqual(root.savedLocalSent.phone, [old], 'Nothing is discarded before the backend acknowledges');
});

test('a deleted thread closes only when it has no newer messages', () => {
    const {root} = phoneFixture();
    root.threadCache = {2: [old]};
    root.threadMessages = [old];
    root.applyConversationDeletion('phone', [2], 100);
    assert.equal(root.openThread, -1);
    assert.deepEqual(plain(root.threadCache), {});
});

test('deletion removes traditional-bar cards without removing newer or other-phone cards', () => {
    const records = [
        {deviceId: 'phone', thread: 2, time: 90},
        {deviceId: 'phone', thread: 2, time: 101},
        {deviceId: 'other', thread: 2, time: 90},
    ];
    const context = vm.createContext({
        Phone: {keepMessages: (items, device) => helper.keptMessages(items, {phone: {2: 100}}, device)},
        messageCards: {get count() { return records.length; }, get: i => ({json: JSON.stringify(records[i])}),
            remove: i => records.splice(i, 1)},
    });
    const source = fs.readFileSync(path.join(services, '../modules/ii/notificationPopup/PhoneAlertStack.qml'), 'utf8');
    const body = source.match(/function purgeDeletedCards\(\) \{([\s\S]*?)\n    \}/)[1];
    vm.runInContext(`(function(){${body}})()`, context);
    assert.deepEqual(records, [
        {deviceId: 'phone', thread: 2, time: 101}, {deviceId: 'other', thread: 2, time: 90},
    ]);
});

function islandFixture() {
    const source = fs.readFileSync(path.join(services, 'IslandPhoneHistory.qml'), 'utf8');
    const oldEntry = {deviceId: 'phone', thread: 2, time: 90, id: 'old'};
    const newEntry = {deviceId: 'phone', thread: 2, time: 101, id: 'fresh'};
    const otherEntry = {deviceId: 'other', thread: 2, time: 90, id: 'other'};
    const Phone = {
        savedLocalSent: {},
        keepMessages(messages, device) {
            return helper.keptMessages(messages, this.savedLocalSent._deletedConversations, device);
        },
    };
    const root = {
        ready: false, messages: [], pendingMessages: [oldEntry, newEntry, otherEntry],
        pendingSynced: [{device: 'phone', messages: [old, fresh]}, {device: 'other', messages: [old]}],
        pendingPhotos: [], pendingCalls: [], callsKnown: false, contacts: [],
        refreshMessages() {}, rememberContactPictures() {}, enrichContacts() {},
        observeCalls() {}, observeMessages() {}, refreshAttachments() {},
    };
    const context = vm.createContext(Object.assign(root, {
        root, Phone, ConversationVisibility: helper, save: {restart() {}},
    }));
    for (const name of ['keepMessages', 'purgeDeletedMessages', 'loaded']) {
        const match = source.match(new RegExp(`    function ${name}\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}`));
        assert.ok(match, `Missing production Island function ${name}`);
        root[name] = vm.runInContext(`(function(${match[1]}) {${match[2]}\n})`, context);
    }
    const onSaved = source.match(/function onSavedLocalSentChanged\(\) \{([^}]+)\}/)?.[1];
    assert.ok(onSaved, 'Island history must observe the later-loaded deletion cutoffs');
    return {
        root, oldEntry, newEntry, otherEntry,
        loadHistory() {
            root.messages = [oldEntry, newEntry, otherEntry];
            root.loaded();
        },
        loadPhone() {
            Phone.savedLocalSent = {_deletedConversations: {phone: {2: 100}}};
            vm.runInContext(onSaved, context);
        },
    };
}

test('Island history loaded before phone state removes deleted entries when cutoffs arrive', () => {
    const f = islandFixture();
    f.loadHistory();
    assert.deepEqual(plain(f.root.messages), [f.oldEntry, f.newEntry, f.otherEntry]);
    f.loadPhone();
    assert.deepEqual(plain(f.root.messages), [f.newEntry, f.otherEntry]);
    assert.deepEqual(plain(f.root.pendingMessages), [f.newEntry, f.otherEntry]);
});

test('phone state loaded before Island history filters both queued batches and saved entries', () => {
    const f = islandFixture();
    f.loadPhone();
    assert.equal(f.root.ready, false);
    assert.deepEqual(plain(f.root.pendingSynced), [
        {device: 'phone', messages: [fresh]}, {device: 'other', messages: [old]},
    ]);
    assert.deepEqual(plain(f.root.pendingMessages), [f.newEntry, f.otherEntry]);
    f.loadHistory();
    assert.deepEqual(plain(f.root.messages), [f.newEntry, f.otherEntry]);
    assert.deepEqual(plain(f.root.pendingSynced), []);
});
