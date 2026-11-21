const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ii = path.resolve(__dirname, '../../..');
const packageDir = path.resolve(ii, '../../../../sdata/dist-arch/mainstream-assistance');
const shippedText = fs.readFileSync(path.join(ii, 'defaults/ai/models.json'), 'utf8');
const shipped = JSON.parse(shippedText);
const catalog = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(ii, 'services/ai/catalog.js'), 'utf8').replace(/^\.pragma.*$/m, ''), catalog);
const plain = value => JSON.parse(JSON.stringify(value));

function small(changes = {}) {
    return {
        schemaVersion: 1,
        thinkingProfiles: {
            steady: {levels: ['auto', 'low', 'high'], descProfile: 'gemini', defaultEffort: 'low',
                effortMap: {low: 'low', high: 'high', max: 'high'}},
        },
        geminiApiCatalog: {
            'gemini-flash-latest': {name: 'Gemini Flash', thinkingProfile: 'steady',
                endpoint: 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent'},
        },
        apiModels: {
            codex: {name: 'Codex', api_format: 'openai', endpoint: 'https://api.openai.com/v1/chat/completions'},
        },
        cliPlans: {
            'claude-code': {firstPick: 'absent', models: {'claude-fable': {alias: 'fable', name: 'Claude Fable'}}},
            'codex-cli': {fallbackCatalog: [{slug: 'gpt-6.2-sol', efforts: ['low', 'not valid']}]},
        },
        ...changes,
    };
}

test('the package ships the catalog bundled with the shell, under its version', () => {
    assert.equal(fs.readFileSync(path.join(packageDir, 'models.json'), 'utf8'), shippedText);
    assert.match(shipped.catalogVersion, /^\d{4}\.\d{2}\.\d{2}$/);
    assert.match(fs.readFileSync(path.join(packageDir, 'PKGBUILD'), 'utf8'),
        new RegExp(`^pkgver=${shipped.catalogVersion.replaceAll('.', '\\.')}$`, 'm'));
});

test('the shipped catalog is read whole and every name in it leads somewhere', () => {
    const result = catalog.parseCatalog(shippedText);
    assert.equal(result.ok, true);
    assert.deepEqual(plain(result.warnings), []);
    const read = result.catalog;
    for (const section of ['thinkingProfiles', 'geminiApiCatalog', 'apiModels', 'retiredModels']) {
        assert.deepEqual(Object.keys(read[section]), Object.keys(shipped[section]).map(key => section === 'retiredModels' ? key.toLowerCase() : key));
    }
    assert.ok(read.geminiApiCatalog[shipped.defaults.geminiDefaultModel]);

    const entries = [...Object.values(shipped.geminiApiCatalog), ...Object.values(shipped.apiModels),
        ...Object.values(shipped.cliPlans['claude-code'].models), ...Object.values(shipped.cliPlans['antigravity-cli'].models)];
    for (const entry of entries) assert.ok(shipped.thinkingProfiles[entry.thinkingProfile], `${entry.name} names no thinking profile`);
    for (const plan of ['claude-code', 'antigravity-cli']) {
        assert.deepEqual(Object.keys(read.cliPlans[plan].models), Object.keys(shipped.cliPlans[plan].models));
        assert.equal(read.cliPlans[plan].firstPick, shipped.cliPlans[plan].firstPick);
    }
    assert.deepEqual(plain(read.cliPlans['codex-cli'].fallbackCatalog), shipped.cliPlans['codex-cli'].fallbackCatalog);

    const offered = new Set([shipped.geminiGroup.id, ...Object.keys(shipped.geminiApiCatalog), ...Object.keys(shipped.apiModels),
        ...Object.keys(shipped.cliPlans['claude-code'].models), ...Object.keys(shipped.cliPlans['antigravity-cli'].models)]);
    assert.equal(catalog.findRetirementCycle(read.retiredModels), null);
    for (const retired of Object.keys(read.retiredModels)) {
        const successor = catalog.resolveRetiredModel(retired, read.retiredModels);
        assert.ok(offered.has(successor), `${retired} retires to ${successor}, which the catalog does not offer`);
    }
});

test('a catalog this shell cannot read is refused by name', () => {
    for (const [input, error] of [
        ['', 'empty-input'],
        ['{not json', 'invalid-json'],
        ['[]', 'invalid-root'],
        [small({schemaVersion: 2}), 'unsupported-schema'],
        [small({schemaVersion: '1'}), 'unsupported-schema'],
        [{schemaVersion: 1, apiModels: {later: {api_format: 'not-yet', endpoint: 'https://example.com/v1'}}}, 'empty-catalog'],
    ]) {
        const result = catalog.parseCatalog(input);
        assert.equal(result.ok, false);
        assert.equal(result.error, error);
    }
});

test('an entry this shell cannot use is left out and the rest is kept', () => {
    const result = catalog.parseCatalog(small({
        apiModels: {
            codex: small().apiModels.codex,
            later: {api_format: 'not-yet', endpoint: 'https://example.com/v1'},
            plain: {api_format: 'openai', endpoint: 'http://example.com/v1'},
            file: {api_format: 'openai', endpoint: 'file:///etc/passwd'},
            'not an id': {api_format: 'openai', endpoint: 'https://example.com/v1'},
            local: {api_format: 'openai', endpoint: 'http://localhost:11434/v1/chat/completions'},
        },
        cliPlans: {...small().cliPlans, 'later-cli': {models: {one: {alias: 'one', name: 'One'}}}},
    }));
    assert.equal(result.ok, true);
    assert.deepEqual(Object.keys(result.catalog.apiModels), ['codex', 'local']);
    assert.deepEqual(Object.keys(result.catalog.cliPlans), ['claude-code', 'codex-cli']);
    assert.equal(result.warnings.length, 5);
    assert.equal(result.catalog.cliPlans['claude-code'].firstPick, 'claude-fable');
    assert.deepEqual(plain(result.catalog.cliPlans['codex-cli'].fallbackCatalog),
        [{slug: 'gpt-6.2-sol', name: 'gpt-6.2-sol', efforts: ['low'], defaultEffort: ''}]);
});

test('only an https address, or a plain one on this machine, is an endpoint', () => {
    for (const url of ['https://api.openai.com/v1/chat/completions', 'http://localhost:11434/v1', 'http://127.0.0.1:8080/v1', 'http://[::1]:8080/v1']) {
        assert.equal(catalog.isSafeEndpoint(url), true, url);
    }
    for (const url of ['', 'http://api.openai.com/v1', 'http://localhost.example.com/v1', 'file:///etc/passwd', 'javascript:alert(1)',
        'https://example.com/v1 extra', 'https://example.com/"v1"', 'https://..example.com/v1', 'https://example..com/v1']) {
        assert.equal(catalog.isSafeEndpoint(url), false, url);
    }
});

test('a retired model leads to its successor through every step', () => {
    const retired = {first: 'second', second: 'third', 'loop-a': 'loop-b', 'loop-b': 'loop-a'};
    for (let hop = 0; hop < 7; hop++) retired[`hop-${hop}`] = `hop-${hop + 1}`;
    assert.equal(catalog.resolveRetiredModel(' First ', retired), 'third');
    assert.equal(catalog.resolveRetiredModel('current', retired), 'current');
    assert.equal(catalog.resolveRetiredModel('loop-a', retired), 'loop-a');
    assert.equal(catalog.resolveRetiredModel('hop-0', retired), `hop-${catalog.MAX_RETIREMENT_HOPS}`);
    assert.deepEqual(plain(catalog.findRetirementCycle({a: 'b', b: 'c', c: 'a'})), ['a', 'b', 'c', 'a']);
    const looping = catalog.parseCatalog(small({retiredModels: {old: 'older', older: 'old'}}));
    assert.equal(looping.ok, true);
    assert.match(looping.warnings[0], /Cycle detected/);
});

test('a model takes its thinking levels from its profile unless it sets its own', () => {
    const {thinkingProfiles} = catalog.parseCatalog(small()).catalog;
    const inherited = catalog.resolveModelThinking({thinkingProfile: 'steady'}, thinkingProfiles);
    assert.deepEqual(plain(inherited), {thinkingProfile: 'steady', descProfile: 'gemini', thinkingLevels: ['auto', 'low', 'high'],
        effortMap: {low: 'low', high: 'high', max: 'high'}, defaultEffort: 'low'});
    const own = catalog.resolveModelThinking({thinkingProfile: 'steady', thinkingLevels: ['auto', 'not a level', 'max'],
        effortMap: {max: 'xhigh'}, defaultEffort: ''}, thinkingProfiles);
    assert.deepEqual(plain(own.thinkingLevels), ['auto', 'max']);
    assert.deepEqual(plain(own.effortMap), {low: 'low', high: 'high', max: 'xhigh'});
    assert.equal(own.defaultEffort, '');
    assert.equal(catalog.resolveModelThinking({thinkingProfile: 'absent'}, thinkingProfiles).thinkingLevels, null);
});

test('two values with the same entries compare equal whatever order their keys come in', () => {
    assert.equal(catalog.stableJson({low: 'low', extra: {b: 1, a: [1, 2]}}), catalog.stableJson({extra: {a: [1, 2], b: 1}, low: 'low'}));
    assert.notEqual(catalog.stableJson({a: [1, 2]}), catalog.stableJson({a: [2, 1]}));
    assert.notEqual(catalog.stableJson({a: 1}), catalog.stableJson({a: 1, b: undefined}));
    assert.equal(catalog.stableJson(undefined), catalog.stableJson(null));
});

test('a string is translated by the catalog first, then by the shell', () => {
    const {translations} = catalog.parseCatalog(small({translations: {es_MX: {'New model': 'Modelo nuevo', Empty: ''}, broken: 'x'}})).catalog;
    const shell = text => text === 'Old model' ? 'Modelo viejo' : text;
    assert.deepEqual(plain(translations), {es_MX: {'New model': 'Modelo nuevo'}});
    assert.equal(catalog.trCatalog('New model', 'es_MX', translations, shell), 'Modelo nuevo');
    assert.equal(catalog.trCatalog('Old model', 'es_MX', translations, shell), 'Modelo viejo');
    assert.equal(catalog.trCatalog('New model', 'de_DE', translations, shell), 'New model');
    assert.equal(catalog.trCatalog('toString', 'es_MX', translations, shell), 'toString');
    assert.equal(catalog.trCatalog('', 'es_MX', translations, shell), '');
});
