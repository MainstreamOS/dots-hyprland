#!/usr/bin/env python3
"""Read-only source/catalog reports and explicit, add-only key synchronization."""

import argparse
import ast
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
DEFAULT_TRANSLATIONS = TOOLS.parent
DEFAULT_SOURCE = DEFAULT_TRANSLATIONS.parent
LITERAL = r'''(?:"(?:[^"\\]|\\[\s\S])*"|'(?:[^'\\]|\\[\s\S])*'|`(?:[^`\\]|\\[\s\S])*`)'''
JS_CALL = re.compile(r'Translation\s*\.\s*tr\s*\(')
JS_WORD = re.compile(r'[\w$]+')
JS_REGEX = re.compile(r'/((?:[^/\\\n\[]|\\[^\n]|\[(?:[^\]\\\n]|\\[^\n])*\])*)/[a-z]*')
JS_STRING = re.compile(LITERAL)
JS_SPACE = re.compile(r'(?:\s|//[^\n]*(?:\n|$)|/\*[\s\S]*?\*/)*')
JS_ESCAPE = re.compile(r'\\(?:u\{[0-9a-fA-F]+\}|u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|\r\n|[\s\S])')
SHELL_CALL = re.compile(r'''\b(?:t|tf)\s+("(?:[^"\\]|\\[\s\S])*"|'[^']*')''')
LOCALE = re.compile(r'[A-Za-z0-9_@.-]+\Z')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate key: {key!r}')
        result[key] = value
    return result


def read_catalog(path):
    data = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)
    if not isinstance(data, dict) or any(not isinstance(v, str) or not v for v in data.values()):
        raise ValueError(f'{path}: expected an object of nonempty string values')
    return data


def decode_js(literal):
    """Decode JS escapes once, without corrupting adjacent non-ASCII text."""
    def escape(match):
        token = match[0][1:]
        if token.startswith('u{'):
            return chr(int(token[2:-1], 16))
        if token.startswith(('u', 'x')):
            return chr(int(token[1:], 16))
        return {'n': '\n', 't': '\t', 'r': '\r', 'b': '\b', 'f': '\f',
                'v': '\v', '0': '\0', '\n': '', '\r': '', '\r\n': ''}.get(token, token)
    decoded = JS_ESCAPE.sub(escape, literal[1:-1])
    return decoded.encode('utf-16', 'surrogatepass').decode('utf-16')


def qml_keys(text):
    """Scan static calls, including template expressions, but not comments/literals.

    This is deliberately a small lexer, not a QML evaluator. Regex literals must
    be skipped too: quotes in /['"]/ otherwise hide subsequent translation calls.
    Dynamic arguments are reported only through manual source review.
    """
    keys = set()

    def template(start):
        pos = start + 1
        while pos < len(text):
            if text[pos] == "\\":
                pos += 2
            elif text[pos] == "`":
                return pos + 1
            elif text.startswith("${", pos):
                pos = scan(pos + 2, nested=True)
            else:
                pos += 1
        return pos

    def scan(pos, nested=False):
        depth = 0
        operand = True
        while pos < len(text):
            char = text[pos]
            if char.isspace():
                pos += 1
                continue
            if text.startswith("//", pos):
                end = text.find("\n", pos + 2)
                pos = len(text) if end < 0 else end + 1
                continue
            if text.startswith("/*", pos):
                end = text.find("*/", pos + 2)
                pos = len(text) if end < 0 else end + 2
                continue
            call = JS_CALL.match(text, pos) if char == "T" else None
            if call:
                start = JS_SPACE.match(text, call.end()).end()
                literal = JS_STRING.match(text, start)
                if literal:
                    end = JS_SPACE.match(text, literal.end()).end()
                    raw = literal[0]
                    dynamic = raw.startswith("`") and re.search(r'(?<!\\)(?:\\\\)*\$\{', raw)
                    if text[end:end + 1] == ")" and not dynamic:
                        key = decode_js(raw)
                        if key:
                            keys.add(key)
            if char in ("'", '"'):
                literal = JS_STRING.match(text, pos)
                pos = literal.end() if literal else pos + 1
                operand = False
                continue
            if char == "`":
                pos = template(pos)
                operand = False
                continue
            if char == "/" and operand:
                regex = JS_REGEX.match(text, pos)
                if regex:
                    pos = regex.end()
                    operand = False
                    continue
            word = JS_WORD.match(text, pos)
            if word:
                operand = word[0] in {"return", "throw", "case", "typeof", "void", "delete", "new", "in", "of", "yield"}
                pos = word.end()
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                if nested and depth == 0:
                    return pos + 1
                depth -= 1
            operand = char not in ")]}."
            pos += 1
        return pos

    scan(0)
    return keys


def shell_keys(text):
    keys = set()
    for line in text.splitlines():
        if line.lstrip().startswith('#'):
            continue
        for match in SHELL_CALL.finditer(line):
            raw = match[1]
            key = raw[1:-1]
            if raw.startswith('"'):
                if re.search(r'(?<!\\)(?:\\\\)*[$`]', key):
                    continue
                key = re.sub(r'\\(["$`\\])', lambda m: m[1], key)
            if key:
                keys.add(key)
    return keys


class TranslationManager:
    def __init__(self, translations_dir=DEFAULT_TRANSLATIONS, source_dir=DEFAULT_SOURCE,
                 *, script_dirs=None, extensions_dir=None):
        self.translations_dir = Path(translations_dir).resolve()
        self.source_dir = Path(source_dir).resolve()
        if not self.source_dir.is_dir():
            raise ValueError(f'Source directory does not exist: {self.source_dir}')
        if not self.translations_dir.is_dir():
            raise ValueError(f'Translation directory does not exist: {self.translations_dir}')
        repo = next((d for d in (self.source_dir, *self.source_dir.parents)
                     if (d / 'sdata/lib/tr-keys.py').is_file() and (d / 'dots').is_dir()), None)
        self.script_dirs = ([Path(d).resolve() for d in script_dirs] if script_dirs is not None
                            else ([repo / 'sdata'] if repo else []) + [self.source_dir / 'scripts'])
        if script_dirs is not None:
            for directory in self.script_dirs:
                if not directory.is_dir():
                    raise ValueError(f'Script directory does not exist: {directory}')
        self.extensions_dir = Path(extensions_dir).resolve() if extensions_dir else None
        if extensions_dir and not self.extensions_dir.is_dir():
            raise ValueError(f'Extensions directory does not exist: {self.extensions_dir}')

    def extension_files(self):
        if self.extensions_dir is not None:
            return sorted(self.extensions_dir.glob('*.py'))
        config = next((d for d in (self.source_dir, *self.source_dir.parents)
                       if d.name == '.config'), None)
        if config is None:
            return []  # Never borrow files from the user's live desktop for a custom tree.
        if config.parent == Path.home().resolve():
            data = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
            file = data / 'nautilus-python/extensions/mainstream-share.py'
            return [file] if file.is_file() else []
        return sorted((config.parent / '.local/share/nautilus-python/extensions').glob('*.py'))

    def extract_extension_texts(self):
        texts = set()
        for file in self.extension_files():
            tree = ast.parse(file.read_text(encoding='utf-8'), filename=str(file))
            nodes = [n.args[0] for n in ast.walk(tree) if isinstance(n, ast.Call)
                     and isinstance(n.func, ast.Name) and n.func.id == 'tr' and n.args]
            for node in tree.body:
                if isinstance(node, ast.Assign):
                    targets = node.targets
                elif isinstance(node, ast.AnnAssign) and node.value is not None:
                    targets = [node.target]
                else:
                    continue
                if any(isinstance(t, ast.Name) and t.id.endswith('_TEXT') for t in targets):
                    nodes.extend(node.value.values if isinstance(node.value, ast.Dict) else [node.value])
            texts.update(n.value for n in nodes if isinstance(n, ast.Constant)
                         and isinstance(n.value, str) and n.value.strip())
        return texts

    def extract_qml_texts(self):
        keys = set()
        for extension in ('*.qml', '*.js'):
            for file in sorted(self.source_dir.rglob(extension)):
                keys.update(qml_keys(file.read_text(encoding='utf-8')))
        return keys

    def extract_script_texts(self):
        keys = set()
        for directory in self.script_dirs:
            for file in sorted(directory.rglob('*')):
                if not file.is_file() or file.suffix not in ('', '.sh'):
                    continue
                content = file.read_bytes()
                if file.suffix == '' and not re.match(br'#![^\n]*(?:bash|zsh|/sh)\b', content):
                    continue
                keys.update(shell_keys(content.decode('utf-8')))
        return keys

    def extract_sources(self):
        return {'qml_js': self.extract_qml_texts(), 'extensions': self.extract_extension_texts(),
                'scripts': self.extract_script_texts()}

    def extract_translatable_texts(self):
        return set().union(*self.extract_sources().values())

    def catalog_path(self, locale):
        if not LOCALE.fullmatch(locale) or locale in ('.', '..'):
            raise ValueError(f'Invalid locale code: {locale!r}')
        return self.translations_dir / f'{locale}.json'

    def load_translation_file(self, locale):
        return read_catalog(self.catalog_path(locale))

    def get_available_languages(self):
        return sorted(p.stem for p in self.translations_dir.glob('*.json'))

    def report(self, locale=None, sources=None):
        sources = self.extract_sources() if sources is None else sources
        observed = set().union(*sources.values())
        source = self.load_translation_file('en_US')
        catalogs = {}
        for lang in ([locale] if locale else self.get_available_languages()):
            data = self.load_translation_file(lang)
            catalogs[lang] = {'keys': len(data), 'missing': [k for k in source if k not in data],
                              'extra': sorted(data.keys() - source.keys()),
                              'english_identical': sum(k == v for k, v in data.items())}
        return {'source_counts': {name: len(keys) for name, keys in sources.items()},
                'missing_from_en_US': sorted(observed - source.keys()),
                'not_observed_in_source': sorted(source.keys() - observed), 'catalogs': catalogs}

    def sync(self, locale=None, apply=False):
        """Only add missing English-source keys to existing catalogs; never delete."""
        source = self.load_translation_file('en_US')
        if not source:
            raise ValueError('en_US.json is empty; refusing synchronization')
        plans = []
        for lang in ([locale] if locale else self.get_available_languages()):
            if lang == 'en_US':
                continue
            path = self.catalog_path(lang)
            if apply and path.is_symlink():
                raise ValueError(f'Refusing to replace a symlink catalog: {path}')
            data = self.load_translation_file(lang)
            missing = [key for key in source if key not in data]
            plans.append((path, data, missing))
        # Preflight every catalog before writing any, so invalid JSON cannot be replaced with {}.
        result = {}
        for path, data, missing in plans:
            result[path.stem] = {'added' if apply else 'would_add': missing,
                                 'retained_extra': sorted(data.keys() - source.keys())}
            if apply and missing:
                updated = {**data, **{key: source[key] for key in missing}}
                with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.',
                                                 suffix='.bak', delete=False) as backup:
                    backup.write(path.read_bytes())
                temporary = None
                try:
                    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                                     prefix=path.name + '.', suffix='.tmp',
                                                     delete=False) as out:
                        temporary = Path(out.name)
                        out.write(json.dumps(updated, ensure_ascii=False, indent=2) + '\n')
                    temporary.chmod(stat.S_IMODE(path.stat().st_mode))
                    temporary.replace(path)
                finally:
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)
        return result


def add_paths(parser):
    parser.add_argument('--translations-dir', '-t', default=str(DEFAULT_TRANSLATIONS))
    parser.add_argument('--source-dir', '-s', default=str(DEFAULT_SOURCE))
    parser.add_argument('--language', '--lang', '-l')
    parser.add_argument('--scripts-dir', action='append', help='Override shell script roots; repeat for multiple roots')
    parser.add_argument('--extensions-dir', help='Override the Files extension directory')
    parser.add_argument('--json', action='store_true', help='Machine-readable output')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    add_paths(parser)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--status', action='store_true', help='Read-only source and catalog report (default)')
    mode.add_argument('--extract-only', '--extract', '-e', action='store_true', help='Print source keys without writing files')
    mode.add_argument('--check-qml', action='store_true', help='Check QML/JS and Files extension source coverage')
    mode.add_argument('--check-extensions', action='store_true', help='Check Files extension source coverage')
    mode.add_argument('--check-scripts', action='store_true', help='Check updater/shell source coverage')
    mode.add_argument('--sync', action='store_true', help='Preview additions from en_US to existing catalogs')
    parser.add_argument('--apply', action='store_true', help='Apply --sync additions; never removes keys')
    parser.add_argument('--show-temp', action='store_true', help=argparse.SUPPRESS)  # Legacy stdout-only alias.
    parser.add_argument('--yes', '-y', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.yes:
        parser.error('--yes is retired; use --sync --apply for explicit additions only')
    if args.apply and not args.sync:
        parser.error('--apply requires --sync; source reports never modify catalogs')
    try:
        manager = TranslationManager(args.translations_dir, args.source_dir,
                                     script_dirs=args.scripts_dir, extensions_dir=args.extensions_dir)
        if args.sync:
            result = manager.sync(args.language, args.apply)
            if args.json:
                print(json.dumps(result, ensure_ascii=False, indent=2))
            else:
                for locale, info in result.items():
                    field = 'added' if args.apply else 'would_add'
                    print(f'{locale}: {len(info[field])} keys {field.replace("_", " ")}; '
                          f'{len(info["retained_extra"])} extra keys retained')
                if not args.apply:
                    print('Preview only. Use --sync --apply to add keys. No keys are ever removed.')
            return 0
        if args.check_extensions:
            sources = {'extensions': manager.extract_extension_texts()}
        elif args.check_scripts:
            sources = {'scripts': manager.extract_script_texts()}
        elif args.check_qml:
            sources = {'qml_js': manager.extract_qml_texts(), 'extensions': manager.extract_extension_texts()}
        else:
            sources = manager.extract_sources()
        if args.extract_only or args.show_temp:
            keys = sorted(set().union(*sources.values()))
            print(json.dumps({key: key for key in keys}, ensure_ascii=False, indent=2))
            return 0
        source_check = args.check_qml or args.check_extensions or args.check_scripts
        result = manager.report(args.language or ('en_US' if source_check else None), sources)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print('Source keys: ' + ', '.join(f'{k}={v}' for k, v in result['source_counts'].items()))
            print(f'Missing from en_US: {len(result["missing_from_en_US"])}')
            for key in result['missing_from_en_US']:
                print(f'  {key!r}')
            for locale, info in result['catalogs'].items():
                print(f'{locale}: {info["keys"]} keys, {len(info["missing"])} missing, '
                      f'{len(info["extra"])} extra, {info["english_identical"]} English-identical')
            print(f'{len(result["not_observed_in_source"])} English keys not observed by the static scan; '
                  'retained for manual review, not assumed unused.')
        return int(bool(result['missing_from_en_US']) or any(d['missing'] or d['extra']
                   for d in result['catalogs'].values()))
    except (OSError, ValueError, SyntaxError) as error:
        if args.json:
            print(json.dumps({'error': str(error)}, ensure_ascii=False))
        else:
            print(f'Error: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
