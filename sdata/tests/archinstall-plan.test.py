#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


PLAN = Path(__file__).resolve().parents[1] / 'subcmd-install' / 'archinstall-plan.py'
spec = importlib.util.spec_from_file_location('archinstall_plan', PLAN)
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)


class DiskLayoutTest(unittest.TestCase):
    def setUp(self):
        self.disk = {'name': '/dev/vda', 'type': 'disk', 'ro': False, 'pttype': 'gpt',
                     'log-sec': 4096, 'size': 64 * plan.GIB, 'mountpoints': [None],
                     'children': [{'type': 'part', 'mountpoints': [None]}]}
        self.free = ('BYT;\n/dev/vda:16777216s:virtblk:4096:4096:gpt:Test:;\n'
                     '1:256s:1048575s:1048320s::Other OS:;\n'
                     '1:1048576s:16777183s:15728608s:free;\n')

    def command(self, *args):
        if args[0] == 'lsblk':
            return json.dumps({'blockdevices': [self.disk]})
        self.assertEqual(args, ('parted', '--machine', '--script', '/dev/vda', 'unit', 's', 'print', 'free'))
        return self.free

    def layout(self, mode):
        with patch.object(plan, 'command', self.command):
            return plan.disk_layout('/dev/vda', mode)['device_modifications'][0]

    def test_alongside_creates_partitions_inside_free_space(self):
        layout = self.layout('alongside')
        self.assertFalse(layout['wipe'])
        esp, root = layout['partitions']
        self.assertEqual([esp['status'], root['status']], ['create', 'create'])
        self.assertEqual(esp['start']['value'], 1048576)
        self.assertEqual(esp['size']['value'] * 4096, 2 * plan.GIB)
        self.assertEqual(root['start']['value'], esp['start']['value'] + esp['size']['value'])
        self.assertLessEqual(root['start']['value'] + root['size']['value'], 16777184)

    def test_active_partition_refuses_both_modes(self):
        self.disk['children'][0]['mountpoints'] = ['/run/archiso/bootmnt']
        for mode in ('alongside', 'erase'):
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'mounted or active'):
                self.layout(mode)

    def test_alongside_refuses_mbr_and_too_small_a_gap(self):
        self.disk['pttype'] = 'dos'
        with self.assertRaisesRegex(ValueError, 'GPT'):
            self.layout('alongside')
        self.disk['pttype'] = 'gpt'
        self.free = '1:256s:1048575s:1048320s:free;\n'
        with self.assertRaisesRegex(ValueError, '32 GiB'):
            self.layout('alongside')

    def test_erase_is_explicit(self):
        layout = self.layout('erase')
        self.assertTrue(layout['wipe'])
        self.assertEqual(layout['partitions'][0]['start']['value'], 256)

    def test_encryption_targets_only_new_root(self):
        layout = self.layout('alongside')
        config = {'disk_config': {'device_modifications': [layout]}}
        with patch.object(plan.subprocess, 'check_output', return_value=b'$6$example\n') as hash_password:
            credentials = plan.add_credentials(config, 'tester', b'account password', b'disk passphrase')
        hash_password.assert_called_once_with(
            ['openssl', 'passwd', '-6', '-stdin'], input=b'account password\n',
        )
        self.assertEqual(config['disk_config']['disk_encryption']['partitions'],
                         [layout['partitions'][1]['obj_id']])
        self.assertEqual(credentials, {
            'users': [{'username': 'tester', 'enc_password': '$6$example', 'sudo': True}],
            'encryption_password': 'disk passphrase',
        })


if __name__ == '__main__':
    unittest.main()
