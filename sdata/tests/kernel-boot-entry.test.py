#!/usr/bin/env python3
"""The update and Settings > Recovery name the same boot entry, over fake module trees."""
from pathlib import Path
import json
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULES = '/usr/lib/modules'

helper = (ROOT / 'sdata/update/mainstream-update-helper').read_text()
start = helper.index('        kernel_entry=""\n')
end = helper.index('\n', helper.index('[[ -n "$kernel_entry" ]] ||', start))
HELPER_PROBE = helper[start:end + 1]

recover = (ROOT / 'dots/.config/quickshell/ii/modules/settings/RecoverConfig.qml').read_text()
RECOVER_DEFAULT = json.loads(re.search(r'property string kernelEntry: ("[^"]*")', recover).group(1))
block = recover[recover.index('id: kernelEntryProbe'):]
command = re.search(r'command: \["sh", "-c",(.*?)\]\n', block, re.DOTALL).group(1)
RECOVER_PROBE = ''.join(json.loads(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', command))


def tree(*bases):
    tmp = tempfile.TemporaryDirectory()
    for i, base in enumerate(bases):
        d = Path(tmp.name) / f'7.3.{i}-{base}'
        d.mkdir()
        (d / 'pkgbase').write_text(base + '\n')
    return tmp


def helper_entry(modules):
    script = HELPER_PROBE.replace(MODULES, modules) + 'printf "%s" "${kernel_entry:-linux}"\n'
    return subprocess.run(['bash', '-uc', script], capture_output=True, text=True,
                          env={'PATH': '/usr/bin:/bin'}).stdout


def recover_entry(modules):
    out = subprocess.run(['sh', '-c', RECOVER_PROBE.replace(MODULES, modules)], capture_output=True,
                         text=True, env={'PATH': '/usr/bin:/bin'}).stdout.strip()
    return out or RECOVER_DEFAULT


class KernelBootEntryTests(unittest.TestCase):
    def test_probes_read_the_module_trees(self):
        self.assertIn(MODULES, HELPER_PROBE)
        self.assertIn(MODULES, RECOVER_PROBE)

    def test_both_name_the_same_entry(self):
        cases = [
            ((), 'linux'),
            (('linux',), 'linux'),
            (('linux-mainstream',), 'linux-mainstream'),
            (('linux', 'linux-mainstream'), 'linux-mainstream'),
            (('linux', 'linux-mainstream-performance', 'linux-mainstream'), 'linux-mainstream-performance'),
            (('linux-mainstream-performance', 'linux'), 'linux-mainstream-performance'),
            (('linux-lts', 'linux'), 'linux'),
            (('linux-t2',), 'linux-t2'),
        ]
        for bases, want in cases:
            with self.subTest(bases=bases), tree(*bases) as modules:
                self.assertEqual(helper_entry(modules), want)
                self.assertEqual(recover_entry(modules), want)


if __name__ == '__main__': unittest.main()
