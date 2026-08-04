#!/usr/bin/env python3
"""Generate a Kvantum theme colored from the Material You colors.

Counterpart to applycolor.sh's apply_term(): Qt apps take their widget
colors from the Kvantum style, which paints from a static SVG plus the
`[GeneralColors]` block of its kvconfig. Neither follows the wallpaper on
its own, so both are re-derived here from the generated palette.

Source is the generated `material_colors.scss`, which holds lines like:

    $surface: #141311;
    $primary: #CAC8AD;

The stock MaterialAdw theme is the template and is never written to; the
recolored copy is emitted as a separate theme and selected in
kvantum.kvconfig, so every run re-derives from the same pristine source.

SVG mapping (MaterialAdw's own palette -> Material You roles):

    #0f1416 -> surface                  window/base background
    #151b1e -> surfaceContainer         raised background
    #343a3c -> surfaceContainerHighest  hovered/pressed background
    #3f484b -> surfaceVariant           borders, separators
    #84d2e7 -> primary                  accent (sliders, checks, focus)
    #cee7ef -> primaryFixed             accent highlight
    #b2cbd2 -> primaryFixedDim          accent, dimmed
    #bfc4eb -> primary                  links
    #acb1bc -> outline                  disabled accent
    #ffb4ab -> error                    error indicators

White and black are left alone: they appear only as low-opacity overlay
tints (opacity 0.08-0.25), which read correctly over any base color.
"""

import argparse
import os
import re
import sys

XDG_CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
XDG_STATE_HOME = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
DEFAULT_SCSS = os.path.join(XDG_STATE_HOME, "quickshell/user/generated/material_colors.scss")
DEFAULT_KVANTUM_DIR = os.path.join(XDG_CONFIG_HOME, "Kvantum")
DEFAULT_SOURCE_THEME = "MaterialAdw"
DEFAULT_OUTPUT_THEME = "MaterialYou"

SCSS_LINE = re.compile(r"^\s*\$([A-Za-z0-9_]+)\s*:\s*(#[0-9A-Fa-f]{3,8})\s*;")
GENERAL_COLORS = re.compile(r"^\[GeneralColors\]\n(?:[^\[\n][^\n]*\n|\n)*", re.M)
THEME_KEY = re.compile(r"^theme=.*$", re.M)

SVG_MAP = {
    "#0f1416": "surface",
    "#151b1e": "surfaceContainer",
    "#343a3c": "surfaceContainerHighest",
    "#3f484b": "surfaceVariant",
    "#84d2e7": "primary",
    "#cee7ef": "primaryFixed",
    "#b2cbd2": "primaryFixedDim",
    "#bfc4eb": "primary",
    "#acb1bc": "outline",
    "#ffb4ab": "error",
}

PALETTE_MAP = [
    ("window.color", "surface"),
    ("base.color", "background"),
    ("alt.base.color", "surfaceContainer"),
    ("button.color", "surfaceContainer"),
    ("light.color", "surfaceContainer"),
    ("mid.light.color", "surfaceContainer"),
    ("dark.color", "surfaceVariant"),
    ("mid.color", "surfaceVariant"),
    ("highlight.color", "primary"),
    ("inactive.highlight.color", "primaryContainer"),
    ("text.color", "onSurface"),
    ("window.text.color", "onSurface"),
    ("button.text.color", "onSurface"),
    ("disabled.text.color", "outline"),
    ("tooltip.text.color", "onSurface"),
    ("highlight.text.color", "onPrimary"),
    ("link.color", "primary"),
    ("link.visited.color", "inversePrimary"),
    ("progress.indicator.text.color", "onSurface"),
]


def parse_scss(path: str) -> dict:
    """Read `$name: #hex;` lines into a {name: '#hex'} dict."""
    colors = {}
    with open(path, "r") as f:
        for line in f:
            m = SCSS_LINE.match(line)
            if m:
                colors[m.group(1)] = m.group(2)
    return colors


def color_of(c: dict, name: str) -> str:
    if name not in c:
        sys.exit(f"error: color '{name}' missing from scss source")
    return c[name].lower()


def build_svg(source: str, c: dict) -> str:
    for src, role in SVG_MAP.items():
        source = re.sub(re.escape(src), color_of(c, role), source, flags=re.I)
    return source


def build_kvconfig(source: str, c: dict) -> str:
    block = "[GeneralColors]\n"
    block += "".join(f"{key}={color_of(c, role)}\n" for key, role in PALETTE_MAP)
    result, n = GENERAL_COLORS.subn(block, source, count=1)
    if n == 0:
        sys.exit("error: no [GeneralColors] section in source kvconfig")
    return result


def select_theme(path: str, theme: str) -> None:
    if os.path.isfile(path):
        with open(path, "r") as f:
            text = f.read()
        if THEME_KEY.search(text):
            text = THEME_KEY.sub(f"theme={theme}", text, count=1)
        else:
            text = text.rstrip("\n") + f"\ntheme={theme}\n"
    else:
        text = f"[General]\ntheme={theme}\n"
    with open(path, "w") as f:
        f.write(text)


def main():
    parser = argparse.ArgumentParser(description="Generate Kvantum theme from Material colors")
    parser.add_argument("--scss", default=DEFAULT_SCSS, help="path to material_colors.scss")
    parser.add_argument("--kvantum-dir", default=DEFAULT_KVANTUM_DIR, help="Kvantum config directory")
    parser.add_argument("--source-theme", default=DEFAULT_SOURCE_THEME, help="template theme name")
    parser.add_argument("--output-theme", default=DEFAULT_OUTPUT_THEME, help="generated theme name")
    args = parser.parse_args()

    if not os.path.isfile(args.scss):
        sys.exit(f"error: scss source not found: {args.scss}")

    src_dir = os.path.join(args.kvantum_dir, args.source_theme)
    src_svg = os.path.join(src_dir, f"{args.source_theme}.svg")
    src_kvconfig = os.path.join(src_dir, f"{args.source_theme}.kvconfig")
    for path in (src_svg, src_kvconfig):
        if not os.path.isfile(path):
            sys.exit(f"error: source theme file not found: {path}")

    colors = parse_scss(args.scss)

    with open(src_svg, "r") as f:
        svg = build_svg(f.read(), colors)
    with open(src_kvconfig, "r") as f:
        kvconfig = build_kvconfig(f.read(), colors)

    out_dir = os.path.join(args.kvantum_dir, args.output_theme)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, f"{args.output_theme}.svg"), "w") as f:
        f.write(svg)
    with open(os.path.join(out_dir, f"{args.output_theme}.kvconfig"), "w") as f:
        f.write(kvconfig)

    select_theme(os.path.join(args.kvantum_dir, "kvantum.kvconfig"), args.output_theme)


if __name__ == "__main__":
    main()
