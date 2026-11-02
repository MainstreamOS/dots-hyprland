const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.resolve(__dirname, '../../../services/PhoneSetup.js'), 'utf8');
const setup = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library\s*/, ''), setup);

test('pairing another computer does not turn it into a phone or trigger phone setup', () => {
    assert.equal(setup.phones([{id: 'pc', type: 'desktop'}, {id: 'phone', type: 'phone'}]).length, 1);
    assert.equal(setup.introduction([{type: 'desktop', reachable: true}], [], false, false), '');
});

test('a saved phone wins on startup even when another phone is reachable', () => {
    const phones = [{id: 'second', reachable: true}, {id: 'preferred', reachable: false}];
    assert.equal(setup.selectedDevice(phones, '', 'preferred'), 'preferred');
});

test('a second phone or a brief outage never steals the current selection', () => {
    const phones = [{id: 'second', reachable: true}, {id: 'current', reachable: false}];
    assert.equal(setup.selectedDevice(phones, 'current', 'second'), 'current');
});

test('an unpaired selection falls back to a reachable phone and an empty list clears it', () => {
    assert.equal(setup.selectedDevice([{id: 'offline'}, {id: 'online', reachable: true}], 'removed', 'removed'), 'online');
    assert.equal(setup.selectedDevice([], 'removed', 'removed'), '');
});

test('service introductions require a reachable phone and take precedence over Bluetooth', () => {
    assert.equal(setup.introduction([{reachable: true}], [{}], false, false), 'services');
    assert.equal(setup.introduction([{reachable: false}], [], false, false), '');
    assert.equal(setup.introduction([], [{}], false, false), 'bluetooth');
});

test('ordinary reconnects do not repeat a completed introduction', () => {
    assert.equal(setup.introduction([{reachable: true}], [{}], true, true), '');
    assert.equal(setup.introduction([], [{}], false, true), '');
    assert.equal(setup.introduction([{reachable: true}], [{}], true, false), '');
});

test('adding KDE Connect after a Bluetooth introduction explains the new features once', () => {
    assert.equal(setup.introduction([{reachable: true}], [{}], false, true), 'services');
});
