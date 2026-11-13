const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = path.resolve(__dirname, '../../../services/NotificationLinks.js');
const links = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8').replace(/^\.(?:pragma|import).*$/gm, ''), links);
const phone = (sourceApp, summary, body) => ({sourceApp, summary, body, phoneOrigin: true});

test('a web address in the text is the link, ahead of the app site', () => {
    const entry = phone('Discord', 'Sender', 'Reacted to "⁨https://youtu.be/abc?a=1&amp;b=2⁩"');
    const text = links.linkText(entry);
    assert.ok(text.includes('https://youtu.be/abc?a=1&b=2 '));
    assert.equal(links.linkFor(entry, ['https://youtu.be/abc?a=1&b=2']), 'https://youtu.be/abc?a=1&b=2');
});

test('known phone apps open the page that lists their notifications', () => {
    assert.equal(links.linkFor(phone('Gmail', 'Sender', 'Subject\nText'), []), 'https://mail.google.com/');
    assert.equal(links.linkFor(phone(' X ', 'Someone', 'A post'), []), 'https://x.com/notifications');
    assert.equal(links.linkFor(phone('Unknown App', 'Title', 'Text'), []), '');
});

test('a Reddit post is looked up in the community that announced it', () => {
    assert.equal(links.linkFor(phone('Reddit', 'GeminiAI:', 'Good news, plus & free users!\nmore'), []),
        'https://www.reddit.com/r/GeminiAI/search/?q=Good%20news%2C%20plus%20%26%20free%20users!&restrict_sr=1');
    assert.equal(links.linkFor(phone('Reddit', 'Now in r/elgato', ''), []), 'https://www.reddit.com/r/elgato/');
    assert.equal(links.linkFor(phone('Reddit', 'u/someone replied to your comment in r/elgato', 'Hi'), []),
        'https://www.reddit.com/notifications');
});

test('desktop notifications only have the links their text holds', () => {
    const entry = {sourceApp: 'Gmail', summary: 'Sender', body: 'Subject', phoneOrigin: false};
    assert.equal(links.linkFor(entry, []), '');
    assert.equal(links.linkFor(entry, ['ftp://example.com/file', 'https://example.com/a']), 'https://example.com/a');
});

test('the button names the site that really opens', () => {
    assert.equal(links.host('https://www.Reddit.com/r/elgato/'), 'reddit.com');
    assert.equal(links.host('https://mail.google.com@evil.example:8443/path?x=1'), 'evil.example');
    assert.equal(links.host('https://x.com'), 'x.com');
});
