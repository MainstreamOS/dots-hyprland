"""Maintenance regressions; every write is confined to a temporary fixture."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('translation_manager', TOOLS / 'translation-manager.py')
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class SourceExtraction(unittest.TestCase):
    def test_js_escapes_preserve_unicode_and_decode_once(self):
        text = r'''Translation.tr("café \u4e16\u754c"); Translation.tr("literal \\n");
                  Translation.tr('line\nbreak'); Translation.tr("\uD83D\uDE00");'''
        self.assertEqual(manager.qml_keys(text), {'café 世界', 'literal \\n', 'line\nbreak', '😀'})

    def test_comments_strings_regex_and_nested_template_expressions(self):
        text = r'''// Translation.tr("line comment")
            /* Translation.tr('block comment') */
            const example = 'Translation.tr("example")';
            const regex = /['"`]/g;
            const nested = `text ${flag ? `${Translation.tr("nested")}` : Translation.tr('fallback')}`;
            Translation.tr(`static`); Translation.tr(`dynamic ${name}`);
            Translation.tr("prefix " + name); Translation.tr(key);
            Translation.tr(/* comment */ "after regex");
            let quotient = left / right; Translation.tr("after division");'''
        self.assertEqual(manager.qml_keys(text), {'nested', 'fallback', 'static', 'after regex', 'after division'})

    def test_shell_static_and_dynamic_arguments(self):
        text = r'''# t "comment"
            t "Double quoted"; tf 'Single %s' "$value"
            t "Not $static"; t "Not $(command)"; t "Not `command`"
            t 'Literal $value'; t "Keep \\n"; t "Quote \"word\""'''
        self.assertEqual(manager.shell_keys(text), {'Double quoted', 'Single %s', 'Literal $value',
                                                    'Keep \\n', 'Quote "word"'})


class Maintenance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='translation tools ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.catalogs = self.root / 'catalogs with spaces'
        self.source = self.root / 'source with spaces'
        self.scripts = self.root / 'external scripts'
        self.extensions = self.root / 'extensions'
        for directory in (self.catalogs, self.source, self.scripts, self.extensions):
            directory.mkdir()
        self.write('en_US', {'UI': 'UI', 'Script %s': 'Script %s', 'Extension': 'Extension', 'New': 'New'})
        self.write('es_MX', {'UI': 'Interfaz', 'Old': 'Conservar/*keep*/'})
        (self.source / 'example.qml').write_text('text: Translation.tr("UI")', encoding='utf-8')
        (self.scripts / 'updater').write_text('#!/usr/bin/env bash\ntf "Script %s" "$value"\n')
        (self.extensions / 'example.py').write_text('LABEL_TEXT = {"example": "Extension"}\ntr("UI")\n')
        self.paths = ['--translations-dir', str(self.catalogs), '--source-dir', str(self.source),
                      '--scripts-dir', str(self.scripts), '--extensions-dir', str(self.extensions)]

    def write(self, locale, data):
        (self.catalogs / f'{locale}.json').write_text(json.dumps(data, ensure_ascii=False) + '\n', encoding='utf-8')

    def snapshot(self):
        return {p.relative_to(self.root): (p.read_bytes(), p.stat().st_mtime_ns)
                for p in self.root.rglob('*') if p.is_file()}

    def run_cli(self, script, *args, paths=True, expected=0):
        result = subprocess.run([sys.executable, str(TOOLS / script), *args, *(self.paths if paths else [])],
                                cwd='/', capture_output=True, text=True,
                                env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        return result

    def wrapper(self, *args, expected=0):
        result = subprocess.run(['bash', str(TOOLS / 'manage-translations.sh'), *args], cwd='/',
                                capture_output=True, text=True,
                                env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        return result

    def test_reports_previews_and_cleanup_never_write(self):
        before = self.snapshot()
        for script, args, code in [('translation-manager.py', [], 1),
                                   ('translation-cleaner.py', ['--clean'], 1),
                                   ('translation-manager.py', ['--sync'], 0),
                                   ('translation-cleaner.py', ['--sync'], 0)]:
            self.run_cli(script, *args, '--json', expected=code)
        self.wrapper('update', *self.paths, '--json')
        self.wrapper('clean', *self.paths, '--json', expected=1)
        self.assertEqual(self.snapshot(), before)

    def test_extract_includes_external_scripts_and_extensions(self):
        result = self.run_cli('translation-manager.py', '--extract-only')
        self.assertEqual(set(json.loads(result.stdout)), {'UI', 'Script %s', 'Extension'})

    def test_source_only_checks_do_not_require_complete_other_locales(self):
        for option in ('--check-qml', '--check-scripts', '--check-extensions'):
            result = self.run_cli('translation-manager.py', option, '--json')
            self.assertEqual(set(json.loads(result.stdout)['catalogs']), {'en_US'})

    def test_explicit_sync_adds_only_and_noop_does_not_rewrite(self):
        original = (self.catalogs / 'es_MX.json').read_bytes()
        self.wrapper('sync', '--apply', *self.paths, '--json')
        data = json.loads((self.catalogs / 'es_MX.json').read_text())
        self.assertEqual(list(data), ['UI', 'Old', 'Script %s', 'Extension', 'New'])
        self.assertEqual(data['UI'], 'Interfaz')
        self.assertEqual(data['Old'], 'Conservar/*keep*/')
        backup, = self.catalogs.glob('*.bak')
        self.assertEqual(backup.read_bytes(), original)
        before = self.snapshot()
        self.run_cli('translation-manager.py', '--sync', '--apply')
        self.assertEqual(self.snapshot(), before)

    def test_invalid_later_catalog_prevents_any_write(self):
        for invalid in ('{"UI": "A", "UI": "B"}', '[]', '{broken', '{"UI": 3}'):
            with self.subTest(invalid=invalid):
                (self.catalogs / 'zz_ZZ.json').write_text(invalid)
                before = self.snapshot()
                result = self.run_cli('translation-manager.py', '--sync', '--apply', '--json', expected=2)
                self.assertIn('error', json.loads(result.stdout))
                self.assertEqual(self.snapshot(), before)

    def test_old_automatic_cleanup_and_unrelated_apply_are_rejected(self):
        before = self.snapshot()
        for script, args in [('translation-manager.py', ['--yes']),
                             ('translation-manager.py', ['--apply']),
                             ('translation-cleaner.py', ['--clean', '--apply']),
                             ('translation-cleaner.py', ['--no-backup']),
                             ('translation-cleaner.py', ['--yes'])]:
            self.run_cli(script, *args, expected=2)
        self.wrapper('clean', '--apply', *self.paths, expected=2)
        self.assertEqual(self.snapshot(), before)

    def test_missing_directories_not_created_and_json_errors_are_parseable(self):
        missing = self.root / 'not created'
        result = self.run_cli('translation-manager.py', '--translations-dir', str(missing),
                              '--source-dir', str(self.source), '--json', paths=False, expected=2)
        self.assertIn('error', json.loads(result.stdout))
        self.assertFalse(missing.exists())
        (self.catalogs / 'en_US.json').write_text('[]')
        result = self.run_cli('catalog-qa.py', '--translations-dir', str(self.catalogs),
                              '--json', paths=False, expected=2)
        self.assertIn('error', json.loads(result.stdout))

    def test_symlink_and_locale_traversal_cannot_be_written(self):
        outside = self.root / 'outside.json'
        outside.write_text('{"UI": "Outside"}')
        (self.catalogs / 'es_MX.json').unlink()
        (self.catalogs / 'es_MX.json').symlink_to(outside)
        before = self.snapshot()
        self.run_cli('translation-manager.py', '--sync', '--apply', expected=2)
        self.run_cli('translation-manager.py', '--sync', '--apply', '-l', '../outside', expected=2)
        self.assertEqual(self.snapshot(), before)

    def test_gemini_caller_stops_before_api_if_source_check_fails(self):
        script = self.root / 'ii/scripts/ai/gemini-translate.sh'
        script.parent.mkdir(parents=True)
        script.write_bytes((TOOLS.parents[1] / 'scripts/ai/gemini-translate.sh').read_bytes())
        wrapper = self.root / 'ii/translations/tools/manage-translations.sh'
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text('#!/bin/sh\n[ "$1" = status ] && [ "$2" = -l ] && [ "$3" = en_US ] || exit 8\nexit 7\n')
        wrapper.chmod(0o755)
        result = subprocess.run(['bash', str(script), 'es_MX'], cwd='/', capture_output=True,
                                env={**os.environ, 'XDG_CONFIG_HOME': str(self.root / 'config')})
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse((self.root / 'config').exists())

    def test_wrapper_checks_custom_paths_and_language(self):
        self.write('es_MX', {'UI': 'Interfaz', 'Script %s': 'Guion %s', 'Extension': 'Extensión', 'New': 'Nuevo'})
        result = self.wrapper('check', '-t', str(self.catalogs), '-l', 'es_MX', '--json')
        self.assertEqual(set(json.loads(result.stdout)), {'es_MX'})
        self.assertEqual(json.loads(result.stdout)['es_MX']['errors'], [])
        for args in (('status', '--lang'), ('sync', '--source-dir'), ('sync', 'status'), ('--yes',)):
            self.wrapper(*args, expected=2)


if __name__ == '__main__':
    unittest.main()
