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
