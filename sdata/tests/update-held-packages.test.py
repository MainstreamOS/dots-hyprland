#!/usr/bin/env python3
"""Fixtures for the updater's held-package notice; does not run the privileged updater."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'sdata/update/mainstream-update-helper').read_text()
start = source.index('held_packages_notice() {')
FUNCTION = source[start:source.index('\n}\n', start) + 3]

FAILED = 'error: failed to prepare transaction (could not satisfy dependencies)\n'
HELD = ''.join(f'warning: {name}: ignoring package upgrade (1-1 => 2-1)\n'
               for name in ('aquamarine', 'hyprgraphics', 'hyprland', 'hyprutils', 'mesa'))
SYNC = '''Name            : hyprutils
Provides        : libhyprutils.so=13-64
Name            : mesa
Provides        : libva-mesa-driver  mesa-libgl  opengl-driver
'''


def notice(log, sync=SYNC):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'pacman.log'
        path.write_text(log)
        return subprocess.run(['bash', '-uc',
            't() { printf "%s" "$1"; }; tf() { printf "$@"; }; pacman() { printf "%s" "$SYNC"; }\n'
            + FUNCTION + '\nheld_packages_notice "$1"', 'fixture', str(path)],
            capture_output=True, text=True, env={'SYNC': sync, 'PATH': '/usr/bin:/bin'}).stdout


class HeldPackagesTests(unittest.TestCase):
    def test_held_package_needs_what_an_upgrade_removes(self):
        out = notice(HELD + FAILED
                     + ":: installing libjxl (0.13.0-1) breaks dependency 'libjxl.so=0.12-64' required by hyprgraphics\n"
                     + ":: installing libjxl (0.13.0-1) breaks dependency 'libjxl_threads.so=0.12-64' required by hyprgraphics\n")
        self.assertIn('held back from updating on this computer: hyprgraphics\n', out)
        self.assertIn('All packages held back here: aquamarine hyprgraphics hyprland hyprutils mesa\n', out)
        self.assertIn('/etc/pacman.conf', out)

    def test_upgrade_needs_a_held_package_by_name(self):
        out = notice(HELD + FAILED + ":: unable to satisfy dependency 'aquamarine>=0.16' required by hyprtoolkit\n")
        self.assertIn('on this computer: aquamarine\n', out)

    def test_upgrade_needs_a_library_a_held_package_provides(self):
        out = notice(HELD + FAILED
                     + ":: unable to satisfy dependency 'libhyprutils.so=13-64' required by xdg-desktop-portal-hyprland\n")
        self.assertIn('on this computer: hyprutils\n', out)

    def test_silent_when_holds_are_not_the_cause(self):
        unrelated = ":: installing qt6-base (6.12.0-1) breaks dependency 'qt6-base<6.12' required by some-package\n"
        self.assertEqual(notice(HELD + FAILED + unrelated), '')
        self.assertEqual(notice(FAILED + ":: installing libjxl (0.13.0-1) breaks dependency 'libjxl.so=0.12-64' "
                                         "required by hyprgraphics\n"), '')
        self.assertEqual(notice(HELD + 'error: failed to commit transaction (conflicting files)\n'), '')
        self.assertEqual(notice(HELD), '')


if __name__ == '__main__': unittest.main()
