#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


INSTALL = Path(__file__).resolve().parents[1] / 'subcmd-install'
sys.path.insert(0, str(INSTALL))
spec = importlib.util.spec_from_file_location('fresh_wizard', INSTALL / 'fresh-wizard.py')
wizard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wizard)


class CpuLevelTest(unittest.TestCase):
    def runs_v3(self, flags):
        with tempfile.NamedTemporaryFile('w', suffix='cpuinfo') as cpuinfo:
            cpuinfo.write(f'processor\t: 0\nflags\t\t: {flags}\n')
            cpuinfo.flush()
            return wizard.cpu_runs_x86_64_v3(cpuinfo.name)

    def test_matches_the_kernel_helper_flags(self):
        v3 = 'fpu avx avx2 bmi1 bmi2 f16c fma movbe xsave'
        self.assertTrue(self.runs_v3(v3 + ' abm'))
        self.assertTrue(self.runs_v3(v3 + ' lzcnt'))
        self.assertFalse(self.runs_v3(v3))
        self.assertFalse(self.runs_v3('fpu avx avx2 bmi1 bmi2 f16c fma xsave abm'))

    def test_unreadable_cpuinfo_is_not_v3(self):
        self.assertFalse(wizard.cpu_runs_x86_64_v3('/nonexistent/cpuinfo'))


class OptionsTest(unittest.TestCase):
    def test_custom_writes_every_choice(self):
        state = {'profile': 'custom', 'app_source': 'flatpak', 'kernels': {'linux', 'linux-mainstream-performance'}}
        self.assertEqual(wizard.install_options(state, {'vlc', 'steam', 'proton:cachyos', 'proton:ge'}),
                         ['--profile', 'custom', '--app-source', 'flatpak',
                          '--kernel', 'linux-mainstream-performance,linux',
                          '--proton', 'ge,cachyos', '--apps', 'steam,vlc'])

    def test_no_proton_and_no_kernel(self):
        state = {'profile': 'custom', 'app_source': 'native', 'kernels': set()}
        self.assertEqual(wizard.install_options(state, {'vlc'}),
                         ['--profile', 'custom', '--app-source', 'native', '--kernel', 'linux-mainstream',
                          '--proton', 'none', '--apps', 'vlc'])

    def test_other_profiles_write_no_custom_choices(self):
        state = {'profile': 'gaming', 'app_source': 'flatpak', 'kernels': {'linux'}}
        self.assertEqual(wizard.install_options(state, {'vlc', 'proton:ge'}), ['--profile', 'gaming'])

    def test_defaults(self):
        self.assertEqual(wizard.APP_SOURCES[0][0], 'native')
        self.assertEqual(wizard.KERNELS[0][0], 'linux-mainstream')
        self.assertEqual(set(wizard.KERNEL_ORDER), {kernel for kernel, _ in wizard.KERNELS})


if __name__ == '__main__':
    unittest.main()
