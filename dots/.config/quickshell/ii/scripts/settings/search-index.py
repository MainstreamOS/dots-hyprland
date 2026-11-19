#!/usr/bin/env python3
"""Index Settings labels without instantiating configuration pages."""

import ast
import json
from pathlib import Path
import re
import sys


SHELL = Path(__file__).resolve().parents[2]
SETTINGS = SHELL / "modules/settings"
OBJECT = re.compile(r"^(?:(?:delegate|sourceComponent):\s*|(component) \w+:\s*)?([A-Z]\w*)\s*\{")
LABEL = re.compile(r"^(?:(?:readonly )?property string )?(title|text|label|mainText|buttonText|displayName|tooltipText|tooltip|description)\s*:")
STRING = r"""(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')"""
TRANSLATION_CALL = rf"Translation\.tr\(\s*({STRING})\s*\)"
TRANSLATED = re.compile(TRANSLATION_CALL)
LITERAL = re.compile(rf"\s*({STRING})\s*(?:;|$|//)")
INLINE_FIELDS = re.compile(rf"(?:{STRING}|[^;\"'])+")
APP_ROLE_LABEL = re.compile(rf"\blabel:\s*{TRANSLATION_CALL}")
CLEANUP_LABEL = re.compile(rf"\bname:\s*{TRANSLATION_CALL}")
CLEANUP_ROWS = re.compile(r"^    readonly property var cleanupRows: \[(.*?)^    \]", re.MULTILINE | re.DOTALL)
SECTION_TYPES = {"ContentSection", "ContentSubsection"}
DESCRIPTION_FIELDS = {"tooltipText", "tooltip", "description"}
NON_NAVIGABLE_TYPES = {"Window", "ApplicationWindow", "QtObject", "ContextMenuItem", "MenuItem"}
TEXT_TYPES = {"StyledText", "Text", "Label", "NoticeBox", "SubtleNoticeBox"}
ROW_TYPES = {"ConfigRow", "RippleButton"}
CUSTOM_ROW_LABELS = {
    "DisplayConfig": {"Mode", "Scale", "Orientation", "Duplicate screen", "Position", "Horizontal Offset", "Vertical Offset",
                      "Color Management", "HDR Mode", "Calibrate Monitor for HDR", "Fine Tune", "Import ICC Profile", "Intensity"},
    "InterfaceConfig": {"Layout"},
    "PowerConfig": {"Live wallpaper"},
    "SecureBootSection": {"Boot verification"},
    "AntiCheatSection": {"Easy Anti-Cheat"},
}
COMMON_ACTIONS = {"Reset", "Apply", "Cancel", "Close", "Save", "Edit", "Remove", "Delete", "Add", "OK", "On", "Off", "Keep", "Revert"}
SEARCH_TERMS = {
    ("AccountsConfig", "User Accounts"): ["Change Password", "Change Full Name", "Change Login Image", "Remove Account"],
    ("BarConfig", "Size"): ["Dynamic Island", "closed island size"],
    ("BarConfig", "Panel size"): ["Dynamic Island", "expanded island size"],
    ("DisplayConfig", "Mode"): ["resolution", "refresh rate"],
    ("DisplayConfig", "Scale"): ["display scaling", "dpi"],
    ("DisplayConfig", "Night Light"): ["blue light"],
    ("DisplayConfig", "App font size"): ["application text size"],
    ("DisplayConfig", "UI text size"): ["desktop font size"],
    ("StorageConfig", "EFI Boot Partition"): ["boot partition", "kernel updates", "snapshots"],
    ("DefaultAppsSection", "Web Browser"): ["default browser"],
    ("SecureBootSection", "Secure Boot"): ["Secure Boot", "BitLocker", "sbctl", "UEFI", "Setup Mode", "Limine", "boot verification", "signing keys"],
    ("SecureBootSection", "Boot verification"): ["Secure Boot", "BitLocker", "sbctl", "UEFI", "Setup Mode", "Limine"],
    ("AntiCheatSection", "Anti-Cheat Games"): ["anti-cheat", "Easy Anti-Cheat", "EAC", "Fortnite", "TPM", "IOMMU", "kernel lockdown", "measured boot"],
    ("AntiCheatSection", "Easy Anti-Cheat"): ["anti-cheat", "EAC", "Fortnite", "TPM", "IOMMU", "kernel lockdown", "measured boot"],
}


def add_labels(obj, line, file):
    field = LABEL.match(line)
    if not field:
        return
    value = line[field.end():].strip()
    if value.startswith(("`", "{", "[")):
        return
    literals = TRANSLATED.findall(value)
    if "?" in value and not value.startswith(("Translation.tr(", '"', "'")) and len(literals) == 1:
        return
    if not literals and (literal := LITERAL.match(value.rstrip(" };"))):
        literals = [literal[1]]
    for literal in literals:
        try:
            text = ast.literal_eval(literal)
        except (SyntaxError, ValueError):
            continue
        if not text or "\n" in text or "%1" in text or len(text) > 160:
            continue
        # Choice labels, tooltip text and notices can help find their setting,
        # but cannot be revealed as independent controls.
        standalone_text = (obj["type"] not in TEXT_TYPES
                           or text in CUSTOM_ROW_LABELS.get(file.stem, ())
                           or any(parent["type"] in ROW_TYPES for parent in obj["parents"]))
        if (field[1] in DESCRIPTION_FIELDS or field[1] == "displayName" or obj["type"].endswith("ToolTip")
                or field[1] == "text" and (not standalone_text or len(text) > 85)):
            subject = next((parent for parent in [obj, *reversed(obj["parents"])] if parent["labels"]), None)
            if subject:
                subject["keywords"].append(text)
        elif TRANSLATED.search(value) or field[1] != "text" or " " in text:
            obj["labels"].append((field[1], text))


def labels_in(file):
    """Associate labels and tooltips with their surrounding QML objects."""
    objects = []
    stack = []
    in_comment = False
    for line in file.read_text(encoding="utf-8").splitlines():
        stripped = line.lstrip()
        if in_comment or stripped.startswith("/*"):
            in_comment = "*/" not in stripped
            continue
        if not stripped or stripped.startswith("//"):
            continue
        indent = len(line) - len(stripped)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        declaration = OBJECT.match(stripped)
        if declaration:
            obj = {"type": declaration[2], "definition": bool(declaration[1]),
                   "parents": [ancestor for _, ancestor in stack], "labels": [], "keywords": []}
            objects.append(obj)
            stack.append((indent, obj))
            for field in INLINE_FIELDS.findall(stripped[declaration.end():]):
                add_labels(obj, field.strip(), file)
        elif stack:
            add_labels(stack[-1][1], stripped, file)
    return objects


def entries_for(file, components, ancestors=(), visited=()):
    if file in visited:
        return
    for obj in labels_in(file):
        # Ignore dialogs, popups and action-only editors. Results point to
        # settings that a normal page visit can reveal directly.
        if any(parent["definition"] or parent["type"] in NON_NAVIGABLE_TYPES or parent["type"].endswith(("Dialog", "Popup", "Menu"))
               for parent in [*obj["parents"], obj]):
            continue
        sections = (*ancestors, *(title for parent in obj["parents"] if parent["type"] in SECTION_TYPES
                                 for field, title in parent["labels"] if field == "title"))
        for _, title in obj["labels"]:
            if title not in COMMON_ACTIONS and not title.startswith("Reset "):
                keywords = [*obj["keywords"], *SEARCH_TERMS.get((file.stem, title), ())]
                yield {"label": title, "sections": list(sections), "keywords": keywords}
        if file.stem == "DefaultAppsSection" and not obj["parents"]:
            # The browser, file manager and other roles are generated by a Repeater.
            role_sections = [*sections, *(title for field, title in obj["labels"] if field == "title")]
            roles = (SHELL / "services/DefaultApps.qml").read_text(encoding="utf-8")
            for match in APP_ROLE_LABEL.finditer(roles):
                label = ast.literal_eval(match[1])
                yield {"label": label, "sections": role_sections, "keywords": SEARCH_TERMS.get((file.stem, label), [])}
        if file.stem == "StorageConfig" and ("title", "Free up space") in obj["labels"]:
            # The cleanup rows only exist once the storage scan has populated them.
            rows = CLEANUP_ROWS.search(file.read_text(encoding="utf-8"))
            if rows:
                for match in CLEANUP_LABEL.finditer(rows[1]):
                    yield {"label": ast.literal_eval(match[1]), "sections": [*sections, "Free up space"], "keywords": []}
        child = components.get(obj["type"])
        if child:
            yield from entries_for(child, components, sections, (*visited, file))


def main():
    components = {path.stem: path for path in sorted(SETTINGS.glob("*/*.qml"))}
    pages = sys.argv[1:] or [f"modules/settings/{path.name}" for path in sorted(SETTINGS.glob("*.qml"))]
    for page in pages:
        path = SETTINGS / Path(page).name
        if not path.is_file():
            continue
        entries = {}
        for entry in entries_for(path, components):
            key = (entry["label"], tuple(entry["sections"]))
            if key in entries:
                current = entries[key]
                current["keywords"] = list(dict.fromkeys([*current["keywords"], *entry["keywords"]]))
            else:
                entries[key] = entry
        print(json.dumps({"page": page, "entries": list(entries.values())}, ensure_ascii=False))


if __name__ == "__main__":
    main()
