#!/usr/bin/env python3
"""Compatibility entry point: read-only cleanup reports and add-only sync."""

import argparse
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('translation_manager', Path(__file__).with_name('translation-manager.py'))
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    manager.add_paths(parser)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--clean', '-c', action='store_true', help='Report unobserved keys; never deletes anything')
    mode.add_argument('--sync', action='store_true', help='Preview missing-key additions from en_US')
    parser.add_argument('--apply', action='store_true', help='Apply --sync additions only')
    parser.add_argument('--source-lang', choices=['en_US'], default='en_US')
    parser.add_argument('--yes', '-y', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--no-backup', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.yes or args.no_backup:
        parser.error('Automatic cleanup and --no-backup are retired; reports never delete keys')
    if args.apply and not args.sync:
        parser.error('Cleanup cannot be applied: static scans do not prove keys are unused')
    forwarded = ['--translations-dir', args.translations_dir, '--source-dir', args.source_dir]
    if args.language:
        forwarded += ['--language', args.language]
    if args.extensions_dir:
        forwarded += ['--extensions-dir', args.extensions_dir]
    for directory in args.scripts_dir or []:
        forwarded += ['--scripts-dir', directory]
    if args.json:
        forwarded += ['--json']
    if args.sync:
        forwarded += ['--sync']
        if args.apply:
            forwarded += ['--apply']
    return manager.main(forwarded)


if __name__ == '__main__':
    sys.exit(main())
