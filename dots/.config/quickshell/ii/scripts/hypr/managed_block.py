# Upserts one managed block into a user-owned Lua config file, so a setting the
# shell persists can be rewritten in place while the rest of the file stays the
# user's own. Underscore name because the domain scripts import it; it also
# runs on its own:
#
#   managed_block.py <file> <block name> <content>
#
# Matching is loose about what follows the block name on the marker lines,
# because earlier writers spelled the suffix differently — a block either of
# them wrote is replaced rather than duplicated, and everything converges on
# the one form written here.
#
# New settings that persist Hyprland-side state write through here rather than
# as another writer program embedded in a QML string — the settings pages carry
# many of those from before this existed, each with its own upsert that can
# only run inside the shell. Those stay as they are until their setting is next
# touched; anything new or reworked comes through this file, where the logic
# lives once and can be run against a scratch file. Other writers sharing these
# files stay scoped to their own lines, the way the wallpaper pointer edit is.
import os
import re
import sys


def upsert(path, base, content):
    begin = '-- BEGIN ' + base + ' (managed by Settings)'
    end = '-- END ' + base
    block = begin + '\n' + content.rstrip('\n') + '\n' + end + '\n'
    text = open(path).read() if os.path.exists(path) else ''
    pattern = re.compile(
        r'-- BEGIN ' + re.escape(base) + r'[^\n]*\n.*?-- END ' + re.escape(base) + r'[^\n]*\n?',
        re.S)
    if pattern.search(text):
        text = pattern.sub(lambda match: block, text, count=1)
    else:
        if text and not text.endswith('\n'):
            text += '\n'
        text += '\n' + block
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w') as output:
        output.write(text)
    os.replace(tmp, path)


if __name__ == '__main__':
    upsert(sys.argv[1], sys.argv[2], sys.argv[3])
