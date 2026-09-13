# Writes the keyboard-layout selection into the user's Hyprland override, so
# the pick survives restarts and dotfile updates. Identifiers are validated
# again here even though the picker only offers XKB's catalog: this is the
# last stop before the values are interpolated into Lua.
#
# Usage: write-layouts.py <general.lua path> <comma-layouts> <comma-variants>
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hypr'))
from managed_block import upsert

path, layouts, variants = sys.argv[1], sys.argv[2], sys.argv[3]
codes = layouts.split(',')
variant_codes = variants.split(',')
if (not codes or len(codes) != len(variant_codes)
        or any(not re.fullmatch(r'[A-Za-z0-9_-]+', code) for code in codes)
        or any(not re.fullmatch(r'[A-Za-z0-9_-]*', variant) for variant in variant_codes)):
    raise SystemExit('invalid XKB layout or variant identifier')
upsert(path, 'keyboard-layouts',
       'hl.config({ input = { kb_layout = "' + layouts + '", kb_variant = "' + variants + '" } })')

# The login screen types in whatever systemd-localed holds, read from its X11
# config at greeter start, so the same list goes there too. Model and options
# are kept as they are: this page does not own them. Handed over without
# waiting, because a machine without the matching polkit rule would answer with
# a password prompt this page cannot show, and the session has the layouts
# either way.
X11_CONF = '/etc/X11/xorg.conf.d/00-keyboard.conf'


def x11_option(text, name):
    match = re.search(r'Option\s+"Xkb' + name + r'"\s+"([^"]*)"', text)
    return match.group(1) if match else ''


try:
    with open(X11_CONF) as handle:
        current = handle.read()
except OSError:
    current = ''

if x11_option(current, 'Layout') != layouts or x11_option(current, 'Variant') != variants:
    import subprocess
    command = ['localectl']
    # One layout converts cleanly to a console keymap, so the text consoles
    # follow it. localed has no sound conversion for a list, so a list leaves
    # the console keymap alone.
    if ',' in layouts:
        command.append('--no-convert')
    command += ['set-x11-keymap', layouts, x11_option(current, 'Model'), variants, x11_option(current, 'Options')]
    # Whatever localed answers lands in a log, since nothing else would show
    # a refusal: a machine without the polkit rule fails here in silence.
    log_dir = os.path.join(os.environ.get('XDG_STATE_HOME', os.path.expanduser('~/.local/state')), 'mainstream')
    try:
        os.makedirs(log_dir, exist_ok=True)
        log = open(os.path.join(log_dir, 'keyboard-localed.log'), 'a')
        log.write('running: ' + ' '.join(repr(part) for part in command) + '\n')
        log.flush()
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                         start_new_session=True)
    except OSError as error:
        print('login screen layout not handed to localed: ' + str(error), file=sys.stderr)
