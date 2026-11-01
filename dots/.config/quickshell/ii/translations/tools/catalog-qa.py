#!/usr/bin/env python3
"""Read-only structural checks for complete UI catalogs, including script keys."""

import argparse
from collections import Counter
from decimal import Decimal, InvalidOperation
import importlib.util
import json
from pathlib import Path
import re
import sys

# The manager's strict catalog loader, so both tools accept and refuse the same files.
spec = importlib.util.spec_from_file_location("translation_manager", Path(__file__).with_name("translation-manager.py"))
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
unique_object, read_catalog = manager.unique_object, manager.read_catalog

CATALOGS = Path(__file__).resolve().parents[1]
PROTECTED = (
    "Mainstream OS", "Mainstream", "illogical-impulse", "end-4", "Hyprland",
    "Quickshell", "Hyprlock", "Wayland", "X11", "Arch Linux", "Calamares",
    "Limine", "Snapper", "Plymouth", "SDDM", "GDM", "Qt", "GTK",
    "Material You", "Nerd Font", "KDE Connect", "LocalSend", "Bluetooth",
    "Wi-Fi", "Ethernet", "Samba", "SMB", "SSH", "SSHFS", "MPRIS", "CUPS",
    "NetworkManager", "firewalld", "polkit", "GNOME Keyring", "OpenAI",
    "ChatGPT", "Codex", "Anthropic", "Claude", "Google", "Gemini",
    "Antigravity", "Ollama", "Mistral", "OpenRouter", "Steam", "SteamVR",
    "Big Picture", "Proton", "gamescope", "GameMode", "WiVRn", "Discord",
    "OBS Studio", "DaVinci Resolve", "Flatpak", "Flathub", "Snap", "GitHub",
    "Ko-fi", "Patreon", "Unsplash", "Tenor", "YouTube", "Instagram",
    "Google Lens", "Cloudflare WARP", "EasyEffects", "LRCLIB", "osu!",
    "pacman", "yay", "paru", "topgrade", "updatems", "updatems-system",
    "sshfs", "brightnessctl", "ffmpeg", "songrec", "agy", "mainstream-system",
    "Ext4", "Btrfs", "HDR", "SDR", "ICC", "EDID", "VRR", "CPU", "GPU",
    "RAM", "VRAM", "API", "YOUR_API_KEY", "MODEL_NAME", "CHAT_NAME",
    "TOOL_NAME", "NUM_OF_ENTRIES", "TOOL", "MODEL", "PROVIDER", "FILTER", "VALUE",
)
PLACEHOLDER = re.compile(r"%(?:[1-9]\d*|s|d)")
TAGS = re.compile(r"</?[A-Za-z][^>]*>")
CODE = re.compile(r"```[\s\S]*?```|`[^`\n]+`")
URL = re.compile(r"https?://[^\s<>\"`)\]，。；：（）「」『』【】《》〈〉、！？“”‘’…]+|www\.[^\s<>\"`)\]，。；：（）「」『』【】《》〈〉、！？“”‘’…]+")
SHORTCUT = re.compile(r"\b(?:Super|Ctrl|Strg|Alt)(?:\+(?:[A-Za-z0-9]+|\.))+")
MARKERS = re.compile(r"\[(?:mainstream|DRY-RUN)\]")
PATHS = re.compile(r"~/(?:[^\s<>\"`,;)，。；：（）「」『』【】《》〈〉、！？“”‘’…،؛؟]*)|/(?:etc|var|usr|home|tmp)/(?:[^\s<>\"`,;)，。；：（）「」『』【】《》〈〉、！？“”‘’…،؛؟]*)")
FLAGS = re.compile(r"(?<![\w-])--[\w-]+|(?<![\w%\"'”’»›\])}-])-[A-Za-z]+")
CONFIG_FILES = re.compile(r"\b[\w-]+\.(?:conf|lua|json|lck|socket|timer|old)\b")
NUMBERS = re.compile(r"(?<![A-Za-z0-9_%])\d+(?:[.,\u00a0\u202f]\d+)*")


def tokens(pattern, text):
    matches = pattern.findall(text)
    if pattern is SHORTCUT:
        aliases = {"Strg": "Ctrl", "Umschalt": "Shift", "Entf": "Delete"}
        matches = ["+".join(aliases.get(key, key) for key in match.split("+")) for match in matches]
    if pattern is PATHS or pattern is URL:
        matches = [match.rstrip(".,;:") for match in matches]
    return Counter(matches)


def same_numbers(source, value):
    def parsed(token):
        token = token.replace("\u00a0", "").replace("\u202f", "")
        try:
            return Decimal(token)
        except InvalidOperation:
            return token

    expected = [parsed(token.replace(",", "")) for token in NUMBERS.findall(source)]
    candidates = [
        {parsed(token.replace(",", "")), parsed(token.replace(".", "").replace(",", "."))}
        for token in NUMBERS.findall(value)
    ]
    if len(expected) != len(candidates):
        return False
    matches = {}

    def assign(index, seen):
        for position, number in enumerate(expected):
            if position in seen or number not in candidates[index]:
                continue
            seen.add(position)
            if position not in matches or assign(matches[position], seen):
                matches[position] = index
                return True
        return False

    return all(assign(index, set()) for index in range(len(candidates)))


def check(source, catalog):
    errors = []
    for key in sorted(source.keys() - catalog.keys()):
        errors.append((key, "missing key"))
    for key in sorted(catalog.keys() - source.keys()):
        errors.append((key, "extra key"))
    for key, value in catalog.items():
        if key not in source:
            continue
        if not isinstance(value, str) or not value:
            errors.append((key, "empty or non-string value"))
            continue
        if value.endswith("/*keep*/"):
            value = value.removesuffix("/*keep*/").rstrip()
        for label, pattern in (
            ("placeholders", PLACEHOLDER), ("markup", TAGS), ("code", CODE),
            ("URLs", URL), ("shortcuts", SHORTCUT), ("markers", MARKERS),
            ("paths", PATHS), ("command flags", FLAGS), ("config filenames", CONFIG_FILES),
        ):
            if tokens(pattern, key) != tokens(pattern, value):
                errors.append((key, label))
        if re.findall(r"%[sd]", key) != re.findall(r"%[sd]", value):
            errors.append((key, "printf argument order"))
        if key.count("\n") != value.count("\n"):
            errors.append((key, "newline count"))
        if not same_numbers(key, value):
            errors.append((key, "numeric values"))
        if TAGS.findall(key) != TAGS.findall(value):
            errors.append((key, "markup order"))
        for marker in ("`", "**"):
            if key.count(marker) != value.count(marker):
                errors.append((key, f"Markdown delimiter: {marker}"))
        if (re.match(r"\s*", key)[0] != re.match(r"\s*", value)[0]
                or re.search(r"\s*$", key)[0] != re.search(r"\s*$", value)[0]):
            errors.append((key, "joining whitespace"))
        for name in PROTECTED:
            pattern = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(name) + r"(?![A-Za-z0-9_-])")
            suffix = r"s?" if name[0].isupper() and not name.isupper() else ""
            target_pattern = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + suffix + r"(?![A-Za-z0-9_])")
            if pattern.search(key) and not target_pattern.search(value):
                errors.append((key, f"protected name: {name}"))
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("locales", nargs="*", help="Locale codes, default all shipped catalogs")
    parser.add_argument("--language", "--lang", "-l", help="Select one locale instead of positional codes")
    parser.add_argument("--translations-dir", "-t", type=Path, default=CATALOGS)
    parser.add_argument("--json", action="store_true", help="Print detailed machine-readable results")
    args = parser.parse_args()
    if args.language and args.locales:
        parser.error("Use either --language or positional locale codes")
    try:
        source = read_catalog(args.translations_dir / "en_US.json")
    except (OSError, ValueError) as error:
        if args.json:
            print(json.dumps({"error": str(error)}, ensure_ascii=False))
        else:
            print(f"Error: {error}", file=sys.stderr)
        return 2
    locales = ([args.language] if args.language else args.locales) or [
        p.stem for p in sorted(args.translations_dir.glob("*.json")) if p.stem != "en_US"]
    results = {}
    for locale in locales:
        try:
            if not re.fullmatch(r"[A-Za-z0-9_@.-]+", locale) or locale in (".", ".."):
                raise ValueError(f"Invalid locale code: {locale!r}")
            catalog = read_catalog(args.translations_dir / f"{locale}.json")
            errors = check(source, catalog)
            results[locale] = {"keys": len(catalog), "unchanged": sum(k == v for k, v in catalog.items()), "errors": errors}
        except (OSError, ValueError) as error:
            results[locale] = {"errors": [("", str(error))]}
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        for locale, result in results.items():
            print(f"{locale}: {result.get('keys', '?')} keys, {result.get('unchanged', '?')} unchanged, {len(result['errors'])} errors")
            for key, error in result["errors"]:
                print(f"  {error}: {key!r}")
    return int(any(result["errors"] for result in results.values()))


if __name__ == "__main__":
    sys.exit(main())
