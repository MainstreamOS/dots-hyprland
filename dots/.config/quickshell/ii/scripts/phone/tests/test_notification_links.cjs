const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const services = path.resolve(__dirname, '../../../services');
const read = name => fs.readFileSync(path.join(services, name), 'utf8');
const islandText = vm.createContext({});
vm.runInContext(read('IslandText.js').replace(/^\.pragma.*$/m, ''), islandText);
const links = vm.createContext({IslandText: islandText});
vm.runInContext(read('NotificationLinks.js').replace(/^\.(?:pragma|import).*$/gm, ''), links);
const preview = read('LinkPreviewService.qml');
const root = {};
for (const name of ['urlEnd', 'extractUrls']) {
    const match = preview.match(new RegExp(`    function ${name}\\((\\w+): string\\): (?:int|var) \\{([\\s\\S]*?)\\n    \\}`));
    assert.ok(match, `Missing production function ${name}`);
    root[name] = vm.runInNewContext(`(function(${match[1]}) {${match[2]}\n})`, {root});
}
const phone = (sourceApp, summary, body) => ({sourceApp, summary, body, phoneOrigin: true});
const resolve = entry => links.linkFor(entry, root.extractUrls(links.linkText(entry)));

test('a web address in the text is the link, ahead of the app site', () => {
    const entry = phone('Gmail', 'Sender', 'Reacted to "\u2068https://youtu.be/abc?a=1&amp;b=2\u2069"');
    const text = links.linkText(entry);
    assert.ok(text.includes('https://youtu.be/abc?a=1&b=2 '));
    assert.equal(resolve(entry), 'https://youtu.be/abc?a=1&b=2');
});

test('known phone apps open the page that lists their notifications', () => {
    assert.equal(links.linkFor(phone('Gmail', 'Sender', 'Subject\nText'), []), 'https://mail.google.com/');
    assert.equal(links.linkFor(phone('Unknown App', 'Title', 'Text'), []), '');
    assert.equal(links.linkFor(phone('constructor', 'Title', 'Text'), []), '');
});

test('a Reddit post is looked up in the community that announced it', () => {
    assert.equal(links.linkFor(phone('Reddit', 'GeminiAI:', 'Good news, plus & free users!\nmore'), []),
        'https://www.reddit.com/r/GeminiAI/search/?q=Good%20news%2C%20plus%20%26%20free%20users!&restrict_sr=1');
    assert.equal(links.linkFor(phone('Reddit', 'Now in r/elgato', ''), []), 'https://www.reddit.com/r/elgato/');
    assert.equal(links.linkFor(phone('Reddit', 'u/someone replied to your comment in r/elgato', 'Hi'), []),
        'https://www.reddit.com/notifications');
    assert.equal(resolve(phone('Reddit', 'Trending right now in r/linux', 'A post &amp; its title…\nMore')),
        'https://www.reddit.com/r/linux/search/?q=A%20post%20%26%20its%20title&restrict_sr=1');
});

test('a Reddit post excerpt without a community searches all of Reddit', () => {
    assert.equal(resolve(phone('Reddit', 'Suggested post', 'A post &amp; its title…')),
        'https://www.reddit.com/search/?q=A%20post%20%26%20its%20title');
    assert.equal(resolve(phone('Reddit', 'u/someone mentioned you in r/linux', 'Hi')),
        'https://www.reddit.com/notifications');
    assert.equal(resolve(phone('Reddit', 'Reddit', '')), 'https://www.reddit.com/notifications');
});

test('a Reddit post URL takes precedence over a search', () => {
    assert.equal(resolve(phone('Reddit', 'r/linux', 'See reddit.com/r/linux/comments/abc/example?share=1')),
        'https://reddit.com/r/linux/comments/abc/example?share=1');
    assert.equal(resolve(phone('Reddit', 'Suggested post', 'See redd.it/abc')), 'https://redd.it/abc');
});

test('desktop notifications only have the links their text holds', () => {
    const entry = {sourceApp: 'Gmail', summary: 'Sender', body: 'Subject', phoneOrigin: false};
    assert.equal(links.linkFor(entry, []), '');
    assert.equal(links.linkFor(entry, ['ftp://example.com/file', 'https://example.com/a']), 'https://example.com/a');
});

test('X notices keep their full destination when supplied', () => {
    for (const [body, expected] of [
        ['Read x.com/i/status/12345?s=20&amp;t=example.', 'https://x.com/i/status/12345?s=20&t=example'],
        ['See “x.com/person/status/12345”.', 'https://x.com/person/status/12345'],
        ['&quot;https://x.com/person/status/12345?s=20&quot;', 'https://x.com/person/status/12345?s=20'],
        ['(&lt;t.co/Example&gt;)', 'https://t.co/Example'],
        ['<a class="post" href="https://twitter.com/person/status/12345?x=1&amp;y=2">View post</a>',
            'https://twitter.com/person/status/12345?x=1&y=2'],
    ]) {
        assert.equal(resolve(phone(' X ', 'Someone', body)), expected);
    }
    assert.equal(resolve(phone('X', 'https://x.com/', 'See x.com/i/status/12345')), 'https://x.com/i/status/12345');
});

test('X notices without a URL search for the post excerpt', () => {
    assert.equal(resolve(phone('X', 'Someone', 'A post &amp; a reply…\n\nX')),
        'https://x.com/search?q=A%20post%20%26%20a%20reply');
    assert.equal(resolve(phone('Twitter', 'Someone', 'person@x.com/status/12345')),
        'https://x.com/search?q=person%40x.com%2Fstatus%2F12345');
    assert.equal(resolve(phone('X', 'https://x.com/', 'A post excerpt')), 'https://x.com/search?q=A%20post%20excerpt');
    assert.equal(resolve(phone('X.com', 'Someone', '')), 'https://x.com/notifications');
});

test('a long post excerpt ends on a whole word and never inside an emoji', () => {
    const words = 'word '.repeat(23) + 'unfinished and more';
    assert.equal(resolve(phone('X', 'Someone', words)),
        'https://x.com/search?q=' + encodeURIComponent('word '.repeat(23).trim()));
    const unbroken = 'a'.repeat(119) + '\u{1F600}\u{1F600}';
    assert.equal(resolve(phone('X', 'Someone', unbroken)), 'https://x.com/search?q=' + 'a'.repeat(119));
});

test('Discord uses its own actions for both mirrored and desktop notifications', () => {
    assert.equal(resolve(phone('Discord', 'Sender', 'New message')), '');
    assert.equal(resolve(phone('Discord', 'Sender', 'See https://example.com/shared')), '');
    assert.equal(resolve({appName: 'Discord Canary', body: 'https://example.com/shared'}), '');
});
