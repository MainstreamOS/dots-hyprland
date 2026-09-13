# The one place the enabled keyboard layouts are stored and applied. Settings,
# the session start and the bar's layout service all come through here, so the
# list is validated, ordered and handed on the same way whoever asks.
#
# Usage: write-layouts.py [options] [<general.lua>] [<comma-layouts> <comma-variants>]
#   --from-hyprland  take the list from the keyboard Hyprland is typing on
#                    instead of the arguments (waits a moment for keyboards to
#                    exist, for the session start)
#   --lead L[:V]     put that layout first, adding it if it is not in the list
#   --lead-active    put the layout Hyprland is typing in first
#   --localed-only   tell localed which layouts lead and touch nothing else
#   --apply          apply the written list to the running compositor as well
#
# Three things hold a layout order and this tool keeps them agreeing: the
# managed block in general.lua (the session's list, in the order it was
# stored), the running compositor (which keeps its active index across a
# keymap rebuild, so a rebuilt list is re-seated on the layout that was in
# effect rather than left on the index), and localed (which the login screen
# reads, and which always gets the list rotated to the layout in effect).
#
# The general.lua path defaults to the user's custom/general.lua. Identifiers
# are validated here even though the callers only offer XKB's catalog: this is
# the last stop before the values are interpolated into Lua.
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'hypr'))
from managed_block import upsert

HOME = os.path.expanduser('~')
X11_CONF = '/etc/X11/xorg.conf.d/00-keyboard.conf'
STATE_DIR = os.path.join(os.environ.get('XDG_STATE_HOME', os.path.join(HOME, '.local', 'state')), 'mainstream')
ID = re.compile(r'[A-Za-z0-9_-]+')
OPTIONAL_ID = re.compile(r'[A-Za-z0-9_-]*')


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def hyprctl(*args):
    try:
        return subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ''


def pair_up(layouts, variants):
    codes = layouts.split(',')
    variant_codes = variants.split(',') if variants else []
    variant_codes += [''] * (len(codes) - len(variant_codes))
    return list(zip(codes, variant_codes[:len(codes)]))


def read_hyprland():
    # The session start hook can run before Hyprland has its keyboards
    # registered, so an empty answer gets a few seconds of patience.
    for _ in range(15):
        try:
            keyboards = json.loads(hyprctl('-j', 'devices')).get('keyboards') or []
        except ValueError:
            keyboards = []
        # An input method's virtual keyboard forwards keys a group behind and
        # is never the truth about what is typed, main or not.
        keyboards = [k for k in keyboards if not str(k.get('name', '')).startswith('hl-virtual')]
        keyboard = next((k for k in keyboards if k.get('main')), keyboards[0] if keyboards else None)
        if keyboard and keyboard.get('layout'):
            return pair_up(keyboard['layout'], keyboard.get('variant') or ''), int(keyboard.get('active_layout_index') or 0)
        time.sleep(0.2)
    fail('could not read the current layouts from Hyprland')


def joined(entries):
    return ','.join(code for code, _ in entries), ','.join(variant for _, variant in entries)


def lua_for(entries):
    layouts, variants = joined(entries)
    return 'hl.config({ input = { kb_layout = "' + layouts + '", kb_variant = "' + variants + '" } })'


def block_holds(conf, lua):
    try:
        with open(conf) as handle:
            return ('-- BEGIN keyboard-layouts (managed by Settings)\n' + lua + '\n-- END keyboard-layouts') in handle.read()
    except OSError:
        return False


def x11_option(text, name):
    match = re.search(r'Option\s+"Xkb' + name + r'"\s+"([^"]*)"', text)
    return match.group(1) if match else ''


def tell_localed(entries):
    # The login screen types in whatever localed holds, read from its X11
    # config at greeter start, so the same list goes there. Model and options
    # are kept as they are: this tool does not own them. Handed over without
    # waiting, because a machine without the matching polkit rule would answer
    # with a password prompt nobody can see. The last request is remembered in
    # the state directory, since a second switch can arrive before localed has
    # written the first one to disk.
    layouts, variants = joined(entries)
    try:
        with open(X11_CONF) as handle:
            current = handle.read()
    except OSError:
        current = ''
    marker = os.path.join(STATE_DIR, 'localed.requested')
    try:
        with open(marker) as handle:
            requested = handle.read().split('\n')[:2]
    except OSError:
        requested = [layouts, variants]
    if (x11_option(current, 'Layout') == layouts and x11_option(current, 'Variant') == variants
            and requested == [layouts, variants]):
        return
    command = ['localectl']
    # One layout converts cleanly to a console keymap, so the text consoles
    # follow it. localed has no sound conversion for a list.
    if ',' in layouts:
        command.append('--no-convert')
    command += ['set-x11-keymap', layouts, x11_option(current, 'Model'), variants, x11_option(current, 'Options')]
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(marker, 'w') as handle:
            handle.write(layouts + '\n' + variants + '\n')
        subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass


def main():
    args = sys.argv[1:]
    from_hyprland = localed_only = apply = lead_active = False
    lead = None
    positional = []
    while args:
        arg = args.pop(0)
        if arg == '--from-hyprland':
            from_hyprland = True
        elif arg == '--localed-only':
            localed_only = True
        elif arg == '--apply':
            apply = True
        elif arg == '--lead-active':
            lead_active = True
        elif arg == '--lead':
            lead = args.pop(0) if args else ''
        else:
            positional.append(arg)
    conf = positional[0] if positional else os.path.join(HOME, '.config', 'hypr', 'custom', 'general.lua')

    # What the compositor types in now: the list it runs and the layout in
    # effect. Needed whenever that layout has to be kept or become the lead.
    running, active_index = read_hyprland()
    active = running[active_index] if 0 <= active_index < len(running) else None

    if from_hyprland:
        entries = list(running)
    elif len(positional) >= 3:
        entries = pair_up(positional[1], positional[2])
    else:
        fail('usage: write-layouts.py [options] [general.lua] <layouts> <variants>')
    if (not entries or any(not ID.fullmatch(code) for code, _ in entries)
            or any(not OPTIONAL_ID.fullmatch(variant) for _, variant in entries)):
        fail('invalid XKB layout or variant identifier in ' + ' / '.join(positional[1:3]))

    if lead_active and active:
        lead = active[0] + ':' + active[1]
    if lead is not None:
        lead_code, _, lead_variant = lead.partition(':')
        if not ID.fullmatch(lead_code) or not OPTIONAL_ID.fullmatch(lead_variant):
            fail('invalid leading layout ' + repr(lead))
        entries = [(lead_code, lead_variant)] + [entry for entry in entries if entry != (lead_code, lead_variant)]

    layouts, variants = joined(entries)
    lua = lua_for(entries)
    # The layout that will be in effect once this is done. With a lead it is
    # the lead; otherwise it is what was in effect, if the list still has it.
    if lead is not None:
        effective = entries[0]
    elif active in entries:
        effective = active
    else:
        effective = entries[0]

    if not localed_only:
        if not block_holds(conf, lua):
            upsert(conf, 'keyboard-layouts', lua)
        if apply:
            if entries != running:
                hyprctl('eval', lua)
            # A rebuild keeps the active index, not the layout, so the layout
            # in effect is re-seated by identity; a removed one gives way to
            # the first.
            seat = entries.index(effective)
            if entries != running or seat != active_index:
                hyprctl('switchxkblayout', 'all', str(seat))

    tell_localed([effective] + [entry for entry in entries if entry != effective])


main()
