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
import fcntl
import os
import re
import stat
import sys
import tempfile


def rewrite(path, change):
    """Rewrites path to change(old text) under <path>.lock, the lock the other
    Settings writers of these files take, through a temp file of its own.
    Settings starts these writers without waiting on them, so two can run at
    once: unlocked, one loses the other's change, and a shared temp name can
    put a half-written file in place."""
    folder = os.path.dirname(path) or '.'
    os.makedirs(folder, exist_ok=True)
    with open(path + '.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as handle:
                text = handle.read()
        except FileNotFoundError:
            text = None
        new = change(text or '')
        if new == text:
            return
        fd, tmp = tempfile.mkstemp(dir=folder, prefix='.' + os.path.basename(path) + '.')
        try:
            with os.fdopen(fd, 'w') as output:
                output.write(new)
            # mkstemp makes the file private; the config keeps the mode it had.
            mode = stat.S_IMODE(os.stat(path).st_mode) if text is not None else 0o644
            os.chmod(tmp, mode)
            os.replace(tmp, path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise


def upsert(path, base, content):
    begin = '-- BEGIN ' + base + ' (managed by Settings)'
    end = '-- END ' + base
    block = begin + '\n' + content.rstrip('\n') + '\n' + end + '\n'
    pattern = re.compile(
        r'-- BEGIN ' + re.escape(base) + r'[^\n]*\n.*?-- END ' + re.escape(base) + r'[^\n]*\n?',
        re.S)

    def change(text):
        if pattern.search(text):
            return pattern.sub(lambda match: block, text, count=1)
        if text and not text.endswith('\n'):
            text += '\n'
        return text + '\n' + block

    rewrite(path, change)


if __name__ == '__main__':
    upsert(sys.argv[1], sys.argv[2], sys.argv[3])
