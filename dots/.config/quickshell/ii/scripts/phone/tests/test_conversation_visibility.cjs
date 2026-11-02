// Run with node --test. Exercise the same helper imported by Phone.qml.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const source = path.resolve(__dirname, '../../../services/PhoneConversationVisibility.js');
const visibility = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8').replace(/^\.pragma library\s*/, ''), visibility);
const plain = value => JSON.parse(JSON.stringify(value));
const items = [1, 2, 3].map(thread => ({thread, uid: `message-${thread}`, type: 1}));
const shown = (state, device, hidden = false) => plain(visibility.conversations(items, state, device, hidden));

test('hiding survives persistence and refreshes without deleting history', () => {
    const state = visibility.setHidden({}, 'phone', 2, true);
    const saved = JSON.parse(JSON.stringify({_hiddenConversations: state, phone: [{uid: 'sent'}]}));
    assert.deepEqual(shown(saved._hiddenConversations, 'phone'), [items[0], items[2]]);
    assert.deepEqual(plain(visibility.conversations([], state, 'phone', false)), []);
    assert.deepEqual(shown(saved._hiddenConversations, 'phone', true), [items[1]]);
    assert.deepEqual(saved.phone, [{uid: 'sent'}]);
    assert.equal(items.length, 3);
});

test('unhiding and identical thread IDs on other phones remain independent', () => {
    const state = {first: [2, 3], second: [2]};
    const restored = visibility.setHidden(state, 'first', 2, false);
    assert.deepEqual(shown(restored, 'first'), [items[0], items[1]]);
    assert.deepEqual(shown(restored, 'second'), [items[0], items[2]]);
    assert.deepEqual(state, {first: [2, 3], second: [2]});
    assert.equal(visibility.setHidden(restored, 'first', 2, false), restored);
});

test('historical replays and outgoing messages never restore hidden conversations', () => {
    const state = {phone: [2]};
    for (const event of [
        {device: 'phone', live: false, message: {thread: 2, type: 1}},
        {device: 'phone', message: {thread: 2, type: 1}},
        {device: 'phone', live: true, message: {thread: 2, type: 2}},
        {device: 'phone', live: true},
    ]) assert.equal(visibility.afterMessage(state, event), state);
});

test('a live incoming message restores only its own phone and thread', () => {
    const state = {phone: [2, 3], other: [2]};
    const restored = visibility.afterMessage(state, {device: 'phone', live: true, message: {thread: 2, type: 1}});
    assert.deepEqual(plain(restored), {phone: [3], other: [2]});
    assert.deepEqual(state, {phone: [2, 3], other: [2]});
    assert.deepEqual(plain(visibility.setHidden(restored, 'phone', 3, false)), {other: [2]});
});

test('invalid and temporary threads cannot hide future real conversations', () => {
    const state = {};
    for (const thread of [null, undefined, '', -1, NaN, Infinity, 1.5, 'invalid'])
        assert.equal(visibility.setHidden(state, 'phone', thread, true), state);
    assert.equal(visibility.setHidden(state, '', 1, true), state);
    assert.deepEqual(shown(undefined, 'phone'), items);
    assert.deepEqual(shown({phone: 'invalid'}, 'phone'), items);
    const loaded = {phone: ['2']};
    assert.equal(visibility.setHidden(loaded, 'phone', 2, true), loaded);
    assert.deepEqual(plain(visibility.setHidden(loaded, 'phone', 2, false)), {});
});
