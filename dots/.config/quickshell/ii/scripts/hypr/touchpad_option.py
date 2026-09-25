# Reads or sets one key in the touchpad table of custom/env.lua, where
# Settings > Mouse keeps the input settings it owns:
#
#   touchpad_option.py <env.lua> <key>                       prints its value
#   touchpad_option.py <env.lua> <key> <true|false|number>  sets it
#
# Both look in the same place, so the page never shows one value while
# Hyprland reads another: the first "touchpad = {" that ends its line, and a
# key at that table's own level wherever it sits on its line, the closing
# brace's line included. Of a key given twice, the last is the one Lua keeps,
# so that is the one read and rewritten.
#
# A key the table does not have yet gets a line of its own, because a file
# from before a setting existed has no line for it; a file without the table
# gets one of its own at the end. Values are limited to Lua booleans and
# numbers so nothing written can break out of the table.
import os
import re
import sys

OPENER = re.compile(r'^\s*touchpad\s*=\s*\{\s*(--.*)?$')
VALUE = re.compile(r'^(true|false|-?\d+(\.\d+)?)$')
KEY = re.compile(r'^[a-z_]+$')


def code_part(line):
    return line.split('--', 1)[0]


# The opener's line, the closing line, the last line before it that holds an
# entry, and the key's last assignment as (line, value match). Each is None
# when not found.
def scan(lines, key):
    start = next((i for i, line in enumerate(lines) if OPENER.match(line)), None)
    if start is None:
        return None, None, None, None
    assignment = re.compile(r'(?<![\w.])' + re.escape(key) + r'\s*=\s*([^\s,;{}]+)')
    depth = 1
    last_entry = None
    found = None
    for i in range(start + 1, len(lines)):
        code = code_part(lines[i])
        for match in assignment.finditer(code):
            before = code[:match.start()]
            if depth + before.count('{') - before.count('}') == 1:
                found = (i, match)
        depth += code.count('{') - code.count('}')
        if depth <= 0:
            return start, i, last_entry, found
        if depth == 1 and code.strip():
            last_entry = i
    return start, None, last_entry, found


def get_key(text, key):
    found = scan(text.split('\n'), key)[3]
    return found[1].group(1) if found else None


def set_key(text, key, value):
    lines = text.split('\n')
    start, close, last_entry, found = scan(lines, key)
    if start is None:
        if text and not text.endswith('\n'):
            text += '\n'
        return text + ('\nhl.config({\n    input = {\n        touchpad = {\n'
                       '            %s = %s,\n        },\n    },\n})\n' % (key, value))
    if found is not None:
        i, match = found
        lines[i] = lines[i][:match.start(1)] + value + lines[i][match.end(1):]
        return '\n'.join(lines)
    if close is None:
        return text
    indent = re.match(r'\s*', lines[last_entry]).group(0) if last_entry is not None \
        else re.match(r'\s*', lines[start]).group(0) + '    '
    # Lua needs a separator between fields, and the last one before the closing
    # brace may have been written without it.
    if last_entry is not None:
        line = lines[last_entry]
        entry = code_part(line).rstrip()
        if not entry.endswith((',', ';', '{')):
            lines[last_entry] = entry + ',' + line[len(entry):]
    lines.insert(close, '%s%s = %s,' % (indent, key, value))
    return '\n'.join(lines)


def main(argv):
    if len(argv) not in (3, 4) or not KEY.match(argv[2]) or (len(argv) == 4 and not VALUE.match(argv[3])):
        sys.stderr.write('usage: touchpad_option.py <env.lua> <key> [true|false|number]\n')
        return 2
    path, key = argv[1], argv[2]
    try:
        with open(path) as handle:
            text = handle.read()
    except FileNotFoundError:
        text = ''
    if len(argv) == 3:
        value = get_key(text, key)
        if value is not None:
            print(value)
        return 0
    new = set_key(text, key, argv[3])
    if new == text:
        return 0
    tmp = path + '.tmp'
    with open(tmp, 'w') as output:
        output.write(new)
    os.replace(tmp, path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
