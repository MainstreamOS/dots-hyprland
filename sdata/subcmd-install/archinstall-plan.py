"""Build an Archinstall disk preset without modifying a block device."""

import json
import subprocess
import sys
import uuid


GIB = 1024**3
MIB = 1024**2


def command(*args):
    return subprocess.check_output(args, text=True)


def free_regions(disk):
    output = command('parted', '--machine', '--script', disk, 'unit', 's', 'print', 'free')
    for row in output.splitlines():
        fields = row.rstrip(';').split(':')
        if len(fields) >= 5 and fields[4] == 'free':
            yield int(fields[1].removesuffix('s')), int(fields[2].removesuffix('s')) + 1


def disk_layout(disk, mode):
    devices = json.loads(command('lsblk', '--json', '--bytes', '--paths', '--tree',
                                 '-o', 'NAME,TYPE,RO,MOUNTPOINTS,PTTYPE,LOG-SEC,SIZE', disk))['blockdevices']
    if len(devices) != 1 or devices[0]['type'] != 'disk' or devices[0]['ro']:
        raise ValueError('Select a writable whole disk.')
    device = devices[0]
    active_partitions = any(part['type'] != 'part' or any(part['mountpoints'] or []) or part.get('children')
                            for part in device.get('children', []))
    if any(device['mountpoints'] or []) or active_partitions:
        raise ValueError('The disk has a mounted or active partition. Unmount it before installing.')

    sector_size = device['log-sec']
    alignment = MIB // sector_size
    if alignment < 1 or MIB % sector_size:
        raise ValueError('Unsupported disk sector size.')
    if mode == 'alongside':
        if device['pttype'] != 'gpt':
            raise ValueError('Install alongside requires an existing GPT partition table.')
        regions = free_regions(device['name'])
    else:
        regions = [(alignment, device['size'] // sector_size - alignment)]
    aligned = [((start + alignment - 1) // alignment * alignment, end // alignment * alignment)
               for start, end in regions]
    start, end = max(aligned, key=lambda region: region[1] - region[0], default=(0, 0))
    if (end - start) * sector_size < 32 * GIB:
        raise ValueError('Mainstream needs a contiguous region of at least 32 GiB.')

    def size(value):
        return {'value': value, 'unit': 'sectors', 'sector_size': {'value': sector_size, 'unit': 'B'}}

    def partition(first, last, filesystem, mountpoint, flags, subvolumes):
        return {'status': 'create', 'type': 'primary', 'start': size(first), 'size': size(last - first),
                'fs_type': filesystem, 'mountpoint': mountpoint, 'dev_path': None,
                'flags': flags, 'btrfs': subvolumes,
                'obj_id': str(uuid.uuid4()), 'mount_options': ['compress=zstd'] if subvolumes else []}

    root_start = start + 2 * GIB // sector_size
    subvolumes = [{'name': name, 'mountpoint': mountpoint} for name, mountpoint in
                  [('@', '/'), ('@home', '/home'), ('@log', '/var/log'), ('@pkg', '/var/cache/pacman/pkg')]]
    partitions = [partition(start, root_start, 'fat32', '/boot', ['boot', 'esp'], []),
                  partition(root_start, end, 'btrfs', None, [], subvolumes)]
    return {'config_type': 'manual_partitioning', 'device_modifications': [
        {'device': device['name'], 'wipe': mode == 'erase', 'partitions': partitions}]}


def install_config(disk, mode, network):
    if mode not in ('alongside', 'erase'):
        raise ValueError('Unknown installation mode.')
    return {
        'hostname': 'mainstream',
        'disk_config': disk_layout(disk, mode),
        'bootloader_config': {'bootloader': 'Systemd-boot', 'uki': False, 'removable': False},
        'network_config': {'type': network},
        'mirror_config': {'optional_repositories': ['multilib']},
        'packages': ['git', 'sudo', 'linux-firmware'],
    }


def add_credentials(config, username, password, passphrase):
    password_hash = subprocess.check_output(
        ['openssl', 'passwd', '-6', '-stdin'], input=password + b'\n',
    ).decode().strip()
    credentials = {'users': [{'username': username, 'enc_password': password_hash, 'sudo': True}]}
    if passphrase:
        disk_config = config['disk_config']
        root = disk_config['device_modifications'][0]['partitions'][1]
        disk_config['disk_encryption'] = {
            'encryption_type': 'luks',
            'partitions': [root['obj_id']],
            'lvm_volumes': [],
        }
        credentials['encryption_password'] = passphrase.decode()
    return credentials


if __name__ == '__main__':
    disk, mode, *account = sys.argv[1:]
    try:
        config = install_config(disk, mode, account[1] if account else 'nm')
        if account:
            username, _, credentials_path = account
            password, passphrase = sys.stdin.buffer.read().split(b'\0', 1)
            credentials = add_credentials(config, username, password, passphrase)
            with open(credentials_path, 'x', encoding='utf-8') as output:
                json.dump(credentials, output)
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
    print(json.dumps(config))
