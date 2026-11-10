"""Collect fresh installation choices in a full-screen terminal wizard."""

import curses
import json
from pathlib import Path
import pwd
import re
import subprocess
import sys
import textwrap

from archinstall_plan import add_credentials, command, install_config


PROFILES = [
    ('default', 'Default · Recommended apps'),
    ('custom', 'Custom · Choose your apps'),
    ('gaming', 'Gaming · Starts in Steam'),
    ('os-only', 'OS only · The Mainstream desktop'),
]
DISK_MODES = [
    ('alongside', 'Install alongside · Use existing unallocated space'),
    ('erase', 'Erase disk · Replace everything on the selected drive'),
]
ENTER = (curses.KEY_ENTER, '\n', '\r')


class Back(Exception):
    pass


class Wizard:
    def __init__(self, screen):
        self.screen = screen
        curses.set_escdelay(100)
        self.accent = curses.A_BOLD
        self.header = curses.A_REVERSE
        if curses.has_colors():
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_CYAN, -1)
            curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_CYAN)
            self.accent |= curses.color_pair(1)
            self.header = curses.color_pair(2)
        curses.curs_set(0)

    def paint(self, title, details, footer):
        screen = self.screen
        height, columns = screen.getmaxyx()
        screen.erase()
        if height < 13 or columns < 38:
            screen.addnstr(0, 0, 'Make the terminal larger, or press Esc to go back.', max(0, columns - 1))
            return 0, 0

        self.left = 3
        self.bottom = height - 3
        width = columns - 2 * self.left

        screen.hline(0, 0, ' ', columns, self.header)
        screen.addnstr(0, self.left, 'MAINSTREAM OS    /    INSTALLER', width, self.header)
        screen.addnstr(2, self.left, title, width, curses.A_BOLD)
        notes = textwrap.wrap(details, min(width, 90))
        for row, note in enumerate(notes[:3], 3):
            screen.addnstr(row, self.left, note, width)
        screen.hline(height - 2, 0, curses.ACS_HLINE, columns, self.accent)
        screen.addnstr(height - 1, self.left, footer, width, self.accent)
        return 4 + min(3, len(notes)), width

    def key(self):
        key = self.screen.get_wch()
        if key == '\x1b':
            raise Back
        return key

    def choose(self, title, details, options, current=None, checked=None):
        multi = checked is not None
        rows = options + ([(None, 'Continue')] if multi else [])
        cursor = next((i for i, (value, _) in enumerate(rows) if value == current), 0) if current is not None else 0
        offset = 0
        while True:
            footer = '↑↓ Move   Space/Enter Select   Tab Continue   Esc Back' if multi else '↑↓ Move   Space/Enter Choose   Esc Back'
            start, width = self.paint(title, details, footer)
            if not start:
                self.key()
                continue
            visible = self.bottom - start
            offset = max(0, min(offset, cursor), cursor - visible + 1)
            for index in range(offset, min(len(rows), offset + visible)):
                value, label = rows[index]
                active = index == cursor
                marked = value in checked if multi else active
                mark = f'[{"x" if marked else " "}] ' if value is not None else ''
                line = f'{"› " if active else "  "}{mark}{label}'
                self.screen.addnstr(start + index - offset, self.left, line.ljust(width) if active else line,
                                    width, curses.A_REVERSE if active else 0)
            if len(rows) > visible:
                self.screen.addnstr(self.bottom, self.left, f'{cursor + 1} of {len(rows)}', width)
            key = self.key()
            if key == curses.KEY_DOWN:
                cursor = min(cursor + 1, len(rows) - 1)
            elif key == curses.KEY_UP:
                cursor = max(cursor - 1, 0)
            elif key == '\t' and multi:
                cursor = 0 if cursor == len(rows) - 1 else len(rows) - 1
            elif key in (*ENTER, ' '):
                value = rows[cursor][0]
                if not multi or value is None:
                    return value
                if value in checked:
                    checked.remove(value)
                else:
                    checked.add(value)

    def field(self, title, details, *, value='', secret=False):
        while True:
            start, width = self.paint(title, details, 'Enter Continue   Backspace Delete   Esc Back')
            if not start:
                self.key()
                continue
            width = min(width, 76)
            display = '*' * len(value) if secret else value
            self.screen.addnstr(start, self.left, ('> ' + display[-(width - 3):]).ljust(width), width, curses.A_REVERSE)
            key = self.key()
            if key in ENTER:
                return value
            if key in (curses.KEY_BACKSPACE, '\x08', '\x7f'):
                value = value[:-1]
            elif isinstance(key, str) and key.isprintable() and len(value.encode()) + len(key.encode()) <= (255 if secret else 32):
                value += key

    def password(self, title):
        details = 'Enter a password. It will be hidden as you type.'
        while True:
            value = self.field(title, details, secret=True)
            if value and value == self.field(f'Confirm {title.lower()}', 'Enter the same password again.', secret=True):
                return value.encode()
            details = 'The entries must match and cannot be empty. Try again.'


def disk_choices(mode):
    drives = json.loads(command('lsblk', '--json', '--bytes', '--paths', '--nodeps',
                                '-o', 'NAME,TYPE,SIZE,MODEL'))['blockdevices']
    choices = []
    for drive in drives:
        if drive['type'] != 'disk':
            continue
        disk = drive['name']
        try:
            install_config(disk, mode, 'nm')
        except (ValueError, subprocess.CalledProcessError):
            continue
        label = f'{drive["model"] or disk} · {drive["size"] / 1024**3:.1f} GiB'
        if drive['model']:
            label += f' · {disk}'
        choices.append((disk, label))
    return choices


def collect(screen, groups, selected):
    ui = Wizard(screen)
    state = {}
    step = 0
    while True:
        apps = list(groups) if state.get('profile') == 'custom' else []
        steps = ['profile', 'mode', 'disk', *apps, 'encryption', 'username', 'password', 'review']
        key = steps[step]
        try:
            if key == 'profile':
                state[key] = ui.choose('Installation method', 'Choose what to install with Mainstream.', PROFILES, state.get(key))
            elif key == 'mode':
                state[key] = ui.choose('Disk setup', 'Choose how to use the disk.', DISK_MODES, state.get(key))
            elif key == 'disk':
                drives = disk_choices(state['mode'])
                if not drives:
                    requirement = ('32 GiB of contiguous free space on a GPT drive' if state['mode'] == 'alongside'
                                   else 'a writable drive with at least 32 GiB')
                    ui.choose('Choose a drive', f'No eligible drives. This option needs {requirement}.',
                              [(None, 'Back to disk setup')])
                    step -= 1
                    continue
                state[key] = ui.choose('Choose a drive', 'Choose a drive by its model and size.', drives, state.get(key))
                state['disk_label'] = dict(drives)[state[key]]
            elif key in apps:
                ui.choose(key, f'Custom apps · {apps.index(key) + 1} of {len(apps)} categories',
                          groups[key], checked=selected)
            elif key == 'encryption':
                state[key] = ui.choose('Disk encryption', 'Require a disk passphrase whenever the computer starts?',
                                       [(False, 'Leave the disk unencrypted'), (True, 'Encrypt the system with LUKS')], state.get(key))
                state['passphrase'] = ui.password('Disk passphrase') if state[key] else b''
            elif key == 'username':
                details = 'Use lowercase letters, numbers, underscores or hyphens. Start with a letter.'
                while True:
                    name = ui.field('Create your account', details, value=state.get(key, ''))
                    try:
                        pwd.getpwnam(name)
                    except KeyError:
                        if re.fullmatch(r'[a-z][a-z0-9_-]{0,31}', name):
                            state[key] = name
                            break
                    details = 'Choose an unused username that starts with a lowercase letter.'
            elif key == 'password':
                state[key] = ui.password('Account password')
            else:
                disk_action = 'Erase all data on' if state['mode'] == 'erase' else 'Use unallocated space on'
                label = dict(PROFILES)[state['profile']].split(' · ')[0]
                summary = f'{label} · {disk_action} {state["disk_label"]} · Account: {state["username"]}'
                summary += ' · Encrypted' if state['encryption'] else ' · Unencrypted'
                if apps:
                    count = len(selected)
                    summary += f' · {count} {"app" if count == 1 else "apps"} selected'
                if ui.choose('Ready to install', summary, [(False, 'Go back'), (True, 'Install Mainstream')]):
                    return state
                step -= 1
                continue
            step += 1
        except Back:
            if step == 0:
                return None
            step -= 1


def main(staging, network):
    groups = {}
    selected = set()
    for line in (staging / 'catalog').read_text().splitlines():
        app, label, kind, group = line.split('\t')
        groups.setdefault(group, []).append((app, label))
        if kind == 'default':
            selected.add(app)

    state = curses.wrapper(collect, groups, selected)
    if state is None:
        return
    config = install_config(state['disk'], state['mode'], network)
    creds = add_credentials(config, state['username'], state['password'], state['passphrase'])
    (staging / 'config.json').write_text(json.dumps(config))
    (staging / 'credentials.json').write_text(json.dumps(creds))
    (staging / 'username').write_text(state['username'] + '\n')
    options = ['--profile', state['profile']]
    if state['profile'] == 'custom':
        options += ['--apps', ','.join(sorted(selected))]
    (staging / 'options').write_text('\n'.join(options) + '\n')


if __name__ == '__main__':
    try:
        main(Path(sys.argv[1]), sys.argv[2])
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
    except KeyboardInterrupt:
        sys.exit(130)
