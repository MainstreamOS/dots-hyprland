const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const dir = path.resolve(__dirname, '../../../services');
function load(name, globals = {}) {
    const ctx = vm.createContext(globals);
    vm.runInContext(fs.readFileSync(path.join(dir, name + '.js'), 'utf8')
        .replace(/^\.(?:pragma|import).*$/gm, ''), ctx);
    return ctx;
}
const identity = load('PhoneIdentity');
const reactions = load('PhoneReactions');
const history = load('IslandPhoneHistory', {Identity: identity, Reactions: reactions});
const policy = load('IslandNotificationPolicy');
const mirror = (id, body = 'Hello', time = 100, extra = {}) => ({
    id: 'notification:' + id, deviceId: 'phone', name: 'Sender', body, time,
    mirrored: true, notificationKey: 'phone-key', notificationTime: time, ...extra,
});
const apply = (state, incoming, cleared = 0) => history.updateMessages(state.messages, state.seen, incoming, cleared, 100000);
const empty = () => ({messages: [], seen: []});

test('two hundred desktop ID reallocations keep one phone message and one seen identity', () => {
    let state = empty();
    for (let i = 1; i <= 200; i++) state = apply(state, [mirror(i)]);
    assert.equal(state.messages.length, 1);
    assert.equal(state.seen.length, 1);
    assert.ok(state.messages[0].sourceIds.includes('notification:200'));
});

test('new identical messages with different phone posting times stay separate even on the same desktop ID', () => {
    let state = apply(empty(), [mirror(1)]);
    state = apply(state, [mirror(1, 'Hello', 200)]);
    assert.equal(state.messages.length, 2);
    state = apply(state, [mirror(2, 'Hello', 200)]);
    assert.equal(state.messages.length, 2);
});

test('a changed notification body adds a message rather than replacing its predecessor', () => {
    let state = apply(empty(), [mirror(1)]);
    state = apply(state, [mirror(1, 'Next message', 200)]);
    assert.equal(state.messages.length, 2);
    assert.deepEqual(Array.from(state.messages, m => m.body).sort(), ['Hello', 'Next message']);
});

test('saved desktop-only copies are repaired using a surviving notification ID, retaining all source IDs', () => {
    const old = Array.from({length: 10}, (_, i) => ({
        ...mirror(i + 1, 'Hello', 100 + i * 100000), id: 'message:notification:' + (i + 1),
        sourceIds: ['notification:' + (i + 1)], notificationKey: '', notificationTime: 0,
    }));
    const state = apply({messages: old, seen: []}, [mirror(10)]);
    assert.equal(state.messages.length, 1);
    for (let i = 1; i <= 10; i++) assert.ok(state.messages[0].sourceIds.includes('notification:' + i));
});

test('reload sanitation collapses exact legacy copies without a surviving active notification', () => {
    const old = [1, 2].map(i => ({...mirror(i), id: 'message:notification:' + i,
        sourceIds: ['notification:' + i], notificationKey: '', notificationTime: 0}));
    assert.equal(history.sanitizeHistoryMessages(old).length, 1);
});

test('bundle positions may shift without replaying old lines, while repeated lines within a bundle remain separate', () => {
    let state = apply(empty(), [mirror('1:0', 'A', 100, {bundled: true}), mirror('1:1', 'B', 100, {bundled: true})]);
    state = apply(state, [mirror('2:0', 'B', 200, {bundled: true}), mirror('2:1', 'C', 200, {bundled: true})]);
    assert.equal(state.messages.length, 3);
    state = apply(state, [mirror('3:0', 'B', 300, {bundled: true}), mirror('3:1', 'B', 300, {bundled: true, notificationPart: 1})]);
    assert.equal(state.messages.filter(m => m.body === 'B').length, 2);
});

test('distinct phones and native SMS IDs are never collapsed by identical content and timestamps', () => {
    const a = {...mirror(1), id: 'kde:phone:1', mirrored: false};
    const b = {...a, id: 'kde:phone:2'};
    const state = apply(empty(), [a, b, mirror(3), mirror(4, 'Hello', 100, {deviceId: 'other', notificationKey: 'other-key'})]);
    assert.ok(state.messages.some(m => m.sourceIds.includes(a.id)));
    assert.ok(state.messages.some(m => m.sourceIds.includes(b.id)));
    assert.ok(state.messages.some(m => m.deviceId === 'other'));
});

test('clearing history cannot be undone by a replay with a new desktop ID', () => {
    let state = apply(empty(), [mirror(1)]);
    state.messages = [];
    state = apply(state, [mirror(2)]);
    assert.equal(state.messages.length, 0);
    state = apply(state, [mirror(3)], 150);
    assert.equal(state.messages.length, 0);
});

test('a later thumbnail update retains the full attachment and source provenance', () => {
    let state = apply(empty(), [mirror(1, 'Photo', 100, {media: [{uid: 'photo'}]})]);
    state = apply(state, [mirror(2, 'Photo', 100, {images: ['file:///thumbnail.png']})]);
    assert.equal(state.messages.length, 1);
    assert.equal(state.messages[0].media[0].uid, 'photo');
    assert.equal(state.messages[0].images[0], 'file:///thumbnail.png');
});

test('phone identity and posting time survive notification conversion', () => {
    const entry = policy.messageFor({notificationId: 7, phoneKey: 'stable', phoneTime: 123,
        appName: 'Messages', summary: 'Sender', body: 'Hello', kdeDeviceId: 'phone'});
    assert.equal(entry.notificationKey, 'stable');
    assert.equal(entry.notificationTime, 123);
});


test('live message IDs stay stable and preserve desktop aliases for saved-history repair', () => {
    const first = history.notificationMessage(mirror(1));
    const replay = history.notificationMessage(mirror(2));
    assert.equal(first.id, replay.id);
    assert.ok(replay.sourceIds.includes('notification:2'));
    const old = {...mirror(2), notificationKey:'', notificationTime:0,
        id:'message:notification:2', sourceIds:['notification:2']};
    const state = apply({messages:[old],seen:[]}, [replay]);
    assert.equal(state.messages.length, 1);
});

test('legacy copies can migrate after every desktop ID was replaced', () => {
    const old = [1, 2, 3].map(i => ({...mirror(i, 'Hello', 100 + i * 10000), notificationKey:'',
        notificationTime:0, id:'message:notification:'+i, sourceIds:['notification:'+i]}));
    const state = apply({messages:old, seen:[]}, [history.notificationMessage(mirror(500))]);
    assert.equal(state.messages.length, 1);
    for (let i = 1; i <= 3; i++) assert.ok(state.messages[0].sourceIds.includes('notification:'+i));
});

test('ambiguous legacy copies are not attributed to one of two identical known phone events', () => {
    let state = apply(empty(), [mirror(1)]);
    state = apply(state, [mirror(2, 'Hello', 200)]);
    state.messages.push({...mirror(30, 'Hello', 50000), notificationKey:'', notificationTime:0,
        id:'message:notification:30',sourceIds:['notification:30']});
    state = apply(state, [mirror(3, 'Hello', 200)]);
    assert.equal(state.messages.length, 3);
});
