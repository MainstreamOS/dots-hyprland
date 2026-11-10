#!/usr/bin/env python3
"""Read-only upgrade gate fixtures; does not run the privileged updater."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'sdata/update/mainstream-update-helper').read_text()
start = source.index('hyprland_lua_preflight() {')
FUNCTION = source[start:source.index('\n}\n', start) + 3]

class UpgradeTests(unittest.TestCase):
    def test_configs_before_package_upgrade(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            user = tmp / 'user/hyprland.lua'
            greeter = tmp / 'greeter/hyprland.lua'
            user.parent.mkdir()
            def check(version):
                return subprocess.run(['bash','-c',
                    't() { printf "%s" "$1"; }; tf() { printf "$@"; };\n' + FUNCTION +
                    '\nhyprland_lua_preflight "$1" "$2" "$3"',
                    'fixture', version, str(user), str(greeter)], capture_output=True, text=True).returncode
            self.assertEqual(check('0.56.2-3'), 0)
            self.assertNotEqual(check('0.57.0-1'), 0)
            user.write_text('hl.config({})\n')
            self.assertEqual(check('0.57.0-1'), 0)  # no greeter configured
            greeter.parent.mkdir()
            self.assertNotEqual(check('0.57.0-1'), 0)
            greeter.write_text('hl.config({})\n')
            self.assertEqual(check('0.57.0-1'), 0)
            user.write_text('this is not Lua\n')
            self.assertNotEqual(check('0.57.0-1'), 0)

    def test_gate_precedes_transaction(self):
        system = source.index('# ── 1. System +')
        aur = source.index('# ── 2. AUR')
        for step, transaction in (
            (source[system:aur], 'pacman_system_upgrade 2>&1'),
            (source[aur:], 'user_step 0 env HOME="$ORIG_HOME"'),
        ):
            gate = step.index('if ! hyprland_lua_preflight "$_hypr_target"')
            self.assertIn('exit 107', step[gate:step.index(transaction)])

if __name__ == '__main__': unittest.main()
