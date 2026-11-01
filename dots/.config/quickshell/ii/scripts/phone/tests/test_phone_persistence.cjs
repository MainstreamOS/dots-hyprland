// Run with node --test. Use Phone.qml's persistence functions with a controllable
// asynchronous file, including FileView's cached text after a failed write.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const source = fs.readFileSync(path.resolve(__dirname, '../../../services/Phone.qml'), 'utf8');
const functions = ['retrySentRead', 'sentStateLoaded', 'sentStateLoadFailed', 'writeSent', 'writeDone'];
const plain = value => JSON.parse(JSON.stringify(value));

function fixture(initial = '{}') {
    const root = {
        savedLocalSent: {}, _sentReady: false, _readingSent: true,
        _sentWarningShown: false, _writingSent: false, _savedSentText: '', _writingSentText: '',
    };
    let disk = initial;
    let cached = initial;
    let pending;
    let attempts = 0;
    let retry = false;
    const context = vm.createContext({
        root, console: {warn() {}}, FileViewError: {FileNotFound: 1},
        retrySentTimer: {restart() { retry = true; }, stop() { retry = false; }},
        sentFileView: {
            setText(text) {
                // FileView rejects unchanged text even when the last write failed.
                if (cached === text) return;
                attempts++;
                cached = text;
                pending = text;
            },
        },
    });
    for (const name of functions) {
        const match = source.match(new RegExp(`    function ${name}\\(([^)]*)\\): void \\{([\\s\\S]*?)\\n    \\}`));
        assert.ok(match, `Missing production function ${name}`);
        root[name] = vm.runInContext(`(function(${match[1]}) {${match[2]}\n})`, context);
    }
    return {
        root,
        get disk() { return disk; },
        get attempts() { return attempts; },
        get retry() { return retry; },
        get pending() { return pending; },
        read() {
            cached = disk ?? '';
            if (disk === null) root.sentStateLoadFailed(1);
            else root.sentStateLoaded(disk);
        },
        failRead() { root.sentStateLoadFailed(2); },
        setDisk(text) { disk = text; },
        finish(success) {
            assert.notEqual(pending, undefined, 'No write was started');
            if (success) disk = pending;
            pending = undefined;
            root.writeDone(success, success ? undefined : 2);
        },
    };
}

test('the bridge waits for saved visibility before any messages can modify it', () => {
    const running = source.match(/id: bridge\s+running: ([^\n]+)/)?.[1];
    assert.ok(running?.includes('root._sentReady'), 'Bridge must wait for the initial saved-state read');
    const f = fixture('{"_hiddenConversations":{"phone":[2]},"phone":[{"uid":"saved"}]}');
    f.root.writeSent();
    assert.equal(f.attempts, 0);
    f.read();
    assert.equal(f.root._sentReady, true);
    assert.deepEqual(plain(f.root.savedLocalSent), {
        _hiddenConversations: {phone: [2]}, phone: [{uid: 'saved'}],
    });
    assert.equal(f.attempts, 0);
});

test('missing state permits first use but a transient read failure does not overwrite disk', () => {
    const missing = fixture(null);
    missing.read();
    assert.equal(missing.root._sentReady, true);
    missing.root.savedLocalSent = {_hiddenConversations: {phone: [2]}};
    missing.root.writeSent();
    missing.finish(true);
    assert.deepEqual(JSON.parse(missing.disk), {_hiddenConversations: {phone: [2]}});

    const existing = fixture('{"_hiddenConversations":{"phone":[2]}}');
    existing.failRead();
    assert.equal(existing.root._sentReady, false);
    assert.equal(existing.retry, true);
    existing.root.writeSent();
    assert.equal(existing.attempts, 0);
    existing.read();
    assert.deepEqual(plain(existing.root.savedLocalSent), {_hiddenConversations: {phone: [2]}});
});

test('malformed saved state is retained for repair instead of being replaced with an empty object', () => {
    for (const text of ['{broken', '[]', 'null', '42']) {
        const f = fixture(text);
        f.read();
        assert.equal(f.root._sentReady, false);
        assert.equal(f.retry, true);
        f.root.writeSent();
        assert.equal(f.attempts, 0);
        assert.equal(f.disk, text);
        f.setDisk('{"_hiddenConversations":{"phone":[2]}}');
        f.read();
        assert.equal(f.root._sentReady, true);
        assert.deepEqual(plain(f.root.savedLocalSent), {_hiddenConversations: {phone: [2]}});
    }
});

test('a failed save reloads the disk snapshot then retries the same desired text', () => {
    const f = fixture();
    f.read();
    f.root.savedLocalSent = {_hiddenConversations: {phone: [2]}};
    f.root.writeSent();
    f.finish(false);
    assert.equal(f.disk, '{}');
    assert.equal(f.retry, true);
    f.root.writeSent();
    assert.equal(f.attempts, 1);
    f.read();
    assert.equal(f.attempts, 2);
    assert.deepEqual(plain(f.root.savedLocalSent), {_hiddenConversations: {phone: [2]}});
    f.finish(true);
    assert.deepEqual(JSON.parse(f.disk), {_hiddenConversations: {phone: [2]}});
    assert.equal(f.root._writingSent, false);
});

test('edits during pending writes and retry reads survive in the final saved state', () => {
    const f = fixture();
    f.read();
    f.root.savedLocalSent = {_hiddenConversations: {phone: [2]}};
    f.root.writeSent();
    f.root.savedLocalSent = {_hiddenConversations: {phone: [2, 3], other: [2]}};
    f.root.writeSent();
    assert.equal(f.attempts, 1);
    f.finish(true);
    assert.equal(f.attempts, 2);
    f.finish(false);
    f.failRead();
    f.root.savedLocalSent = {_hiddenConversations: {phone: [3], other: [2]}};
    f.root.writeSent();
    assert.equal(f.attempts, 2);
    f.read();
    f.finish(true);
    assert.deepEqual(JSON.parse(f.disk), {_hiddenConversations: {phone: [3], other: [2]}});
});

test('an already persisted state does not create a redundant write or leave writing stuck', () => {
    const f = fixture('{"_hiddenConversations":{"phone":[2]}}');
    f.read();
    f.root.writeSent();
    assert.equal(f.attempts, 0);
    assert.equal(f.root._writingSent, false);
});
