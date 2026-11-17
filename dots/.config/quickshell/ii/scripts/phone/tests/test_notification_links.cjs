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

test('a YouTube notice searches for the channel and video it names', () => {
    const search = query => 'https://www.youtube.com/results?search_query=' + encodeURIComponent(query);
    assert.equal(resolve(phone('YouTube', 'Veritasium', 'Why the sky is blue &amp; sunsets are red')),
        search('Veritasium Why the sky is blue & sunsets are red'));
    assert.equal(resolve(phone('YouTube', 'Veritasium uploaded: Why the sky is blue', '')),
        search('Veritasium Why the sky is blue'));
    assert.equal(resolve(phone('YouTube', 'New video from Veritasium', 'Why the sky is blue…')),
        search('Veritasium Why the sky is blue'));
    assert.equal(resolve(phone('YouTube', '\u{1F534} Gacha Smack is live now: Story time', 'Story time')),
        search('\u{1F534} Gacha Smack Story time'));
    assert.equal(resolve(phone('YouTube', 'YouTube', '')), 'https://www.youtube.com/');
    assert.equal(resolve(phone('YouTube', 'Veritasium', 'Watch https://youtu.be/abc')), 'https://youtu.be/abc');
    assert.equal(resolve(phone('YouTube', 'ZEE5', 'Dont Be Quite | A ZEE5 Initiative | Watch Vedha on Now on ZEE5')),
        search('Dont Be Quite | A ZEE5 Initiative | Watch Vedha on Now on ZEE5'));
    assert.equal(resolve(phone('YouTube', 'Vox', 'Voxel engines explained')), search('Vox Voxel engines explained'));
    assert.equal(resolve(phone('YouTube', 'Channel', 'Season 2 premiere: what to expect')),
        search('Channel Season 2 premiere: what to expect'));
    assert.equal(resolve(phone('YouTube', 'Fireship uploaded: <div> vs <span>', '')), search('Fireship <div> vs <span>'));
});

test('a YouTube video alert opens the video its phone key names', () => {
    const alert = key => ({...phone('YouTube', 'Channel', 'Video'), kdeInternalId: key});
    assert.equal(resolve(alert('0|com.google.android.youtube|0|wc58LDd96AQ::ece5218b-02f7-46f4-8301-1d167fb3d8b2|10288')),
        'https://www.youtube.com/watch?v=wc58LDd96AQ');
    assert.equal(resolve({
        ...phone('YouTube', '\u{1F534} Channel is live now: Stream title', 'Stream title'),
        kdeInternalId: '0|com.google.android.youtube|0|dQw4w9WgXcQ::ece5218b-02f7-46f4-8301-1d167fb3d8b2|10288',
    }), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    assert.equal(resolve(alert('0|com.google.android.youtube|0|qof3T-pbe-J3ncWroVopjA::14e9d6c6-3174-47bb-b3e0-cfb19d838768|10288')),
        'https://www.youtube.com/results?search_query=Channel%20Video');
});

test('a YouTube comment activity alert opens comment history', () => {
    const commentHistory = 'https://www.youtube.com/feed/history/comment_history';
    assert.equal(resolve({
        ...phone('YouTube', '5 likes on your comment', '"Bro found the Darkhold lol"'),
        kdeInternalId: '0|com.google.android.youtube|0|ACTIVITY_COMMENT_LIKE_AGGREGATED-Ugx7fyYqqjW14ZYjB794AaABAg::f1365934-5341-4012-9850-064b28093301|10253',
    }), commentHistory);
    assert.equal(resolve({
        ...phone('YouTube', 'New comment activity', '"Nice video"'),
        kdeInternalId: '0|com.google.android.youtube|0|ACTIVITY_COMMENT_REPLY-Ugx7fyYqqjW14ZYjB794AaABAg::f1365934-5341-4012-9850-064b28093301|10253',
    }), commentHistory);
    for (const summary of [
        '1 like on your reply',
        'Someone replied to your comment',
        'Someone mentioned you in a comment',
        'Creator hearted your comment',
        'Creator hearted your reply',
    ]) {
        assert.equal(resolve(phone('YouTube', summary, '"Example comment text"')), commentHistory);
    }
});

test('Discord uses its own actions for both mirrored and desktop notifications', () => {
    assert.equal(resolve(phone('Discord', 'Sender', 'New message')), '');
    assert.equal(resolve(phone('Discord', 'Sender', 'See https://example.com/shared')), '');
    assert.equal(resolve({appName: 'Discord Canary', body: 'https://example.com/shared'}), '');
});
