#!/usr/bin/env python3
"""Keep the scripts' messages in step with the shell's translation files.

Every string a script hands to t "..." or tf "..." has to exist as a key in
translations/en_US.json, the file Crowdin reads, or it never reaches a
translator. This lists the ones that do not, and with --add appends them
to en_US.json and to every other locale in English, the way new shell
strings ride in, without rewriting anything already there.

    tr-keys.py [--add] <script>...
"""
import json, re, sys, glob, os

HERE = os.path.dirname(os.path.abspath(__file__))
TR_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "dots", ".config", "quickshell", "ii", "translations"))
CALL = re.compile(r'\b(?:t|tf)\s+"((?:[^"\\]|\\.)*)"')

def unescape(s):
    return s.replace('\\"', '"').replace("\\$", "$").replace("\\\\", "\\")

def keys_in(path):
    found = []
    for line in open(path, encoding="utf-8"):
        for m in CALL.finditer(line):
            k = unescape(m.group(1))
            if k and k not in found:
                found.append(k)
    return found

def append_key(path, key):
    text = open(path, encoding="utf-8").read().rstrip("\n")
    assert text.endswith("}"), path
    body = text[:-1].rstrip("\n")
    entry = json.dumps(key, ensure_ascii=False)
    sep = "," if body.rstrip().endswith('"') else ""
    new = body + sep + "\n  " + entry + ": " + entry + "\n}\n"
    json.loads(new)
    open(path, "w", encoding="utf-8").write(new)

def main():
    add = "--add" in sys.argv
    scripts = [a for a in sys.argv[1:] if a != "--add"]
    if not scripts:
        print(__doc__); return 2
    source = os.path.join(TR_DIR, "en_US.json")
    have = json.load(open(source, encoding="utf-8"))
    missing = []
    for s in scripts:
        for k in keys_in(s):
            if k not in have and k not in missing:
                missing.append(k)
    if not missing:
        print("every script message is in en_US.json"); return 0
    for k in missing:
        print(("adding: " if add else "missing: ") + k)
    if add:
        for f in sorted(glob.glob(os.path.join(TR_DIR, "*.json"))):
            for k in missing:
                append_key(f, k)
        print(f"added {len(missing)} key(s) to {len(glob.glob(os.path.join(TR_DIR, '*.json')))} locale files")
        return 0
    return 1

if __name__ == "__main__":
    sys.exit(main())
