#!/usr/bin/env python3
# Prints one JSON object for /ollama list: the models the local server has and
# the newest ones on ollama.com/library, narrowed by an optional filter.
# "library" is null for an installed-only filter, "unreachable" says
# ollama.com/library could not be read, and "serverDown" that the local server
# did not answer.
import html
import json
import os
import re
import sys
import time
import urllib.request

TAGS_URL = "http://127.0.0.1:11434/api/tags"
LIBRARY_URL = "https://ollama.com/library"
LIBRARY_LIMIT = 16
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
                     "quickshell", "ai", "ollama-library.json")
CACHE_TTL = 3600
FEATURES = ("tools", "thinking", "vision", "embedding", "audio", "cloud")
SIZE_RE = re.compile(r"^e?\d+(\.\d+)?[bm]$")
CARD_RE = re.compile(r'<a\s+[^>]*href="/library/([a-zA-Z0-9_\-\.]+)"[^>]*class="group[^"]*"[^>]*>(.*?)</a>', re.DOTALL)
DESC_RE = re.compile(r'<p class="[^"]*text-neutral-800[^"]*">(.*?)</p>', re.DOTALL)
TAGS_RE = re.compile(r'<div class="flex flex-wrap space-x-2">(.*?)</div>', re.DOTALL)
SPAN_RE = re.compile(r"<span[^>]*>([^<]+)</span>")


def human_bytes(b):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if b < 1024:
            return f"{b:.1f} {unit}" if unit != "B" else f"{b} B"
        b /= 1024
    return f"{b:.1f} PB"


def installed_models():
    try:
        with urllib.request.urlopen(TAGS_URL, timeout=1.5) as resp:
            data = json.loads(resp.read().decode())
    except Exception:
        return None
    return [{
        "name": m.get("name", ""),
        "size": human_bytes(m.get("size", 0)),
        "parameters": m.get("details", {}).get("parameter_size", "")
    } for m in data.get("models", [])]


def library_models():
    try:
        if time.time() - os.path.getmtime(CACHE) < CACHE_TTL:
            with open(CACHE) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    models = []
    try:
        req = urllib.request.Request(LIBRARY_URL, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)"})
        with urllib.request.urlopen(req, timeout=3.5) as resp:
            content = resp.read().decode("utf-8")
    except Exception:
        return None
    seen = set()
    for name, body in CARD_RE.findall(content):
        if name in seen or "/" in name:
            continue
        seen.add(name)
        desc = DESC_RE.search(body)
        tags = TAGS_RE.search(body)
        sizes = []
        features = []
        for span in SPAN_RE.findall(tags.group(1)) if tags else []:
            val = span.strip()
            if val.lower() in FEATURES:
                features.append(val)
            elif SIZE_RE.match(val.lower()):
                sizes.append(val)
        models.append({
            "name": name,
            "description": html.unescape(desc.group(1)).strip() if desc else "",
            "sizes": sizes,
            "features": features
        })
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w") as f:
            json.dump(models, f)
    except OSError:
        pass
    return models


def suggested_tag(model):
    sizes = model["sizes"]
    if not sizes:
        return model["name"]
    for pref in ["7b", "8b", "3b", "4b", "1.5b", "1b"]:
        if pref in sizes:
            return f"{model['name']}:{pref}"
    return f"{model['name']}:{sizes[0]}"


def matches(query, model):
    return (query in model["name"].lower()
            or query in model["description"].lower()
            or any(query in s.lower() for s in model["sizes"])
            or any(query in f.lower() for f in model["features"]))


def main():
    query = " ".join(sys.argv[1:]).strip().lower()
    installed = installed_models()
    server_down = installed is None
    installed = installed or []
    if query in ("installed", "local"):
        print(json.dumps({"installed": installed, "library": None, "serverDown": server_down}))
        return
    library = library_models()
    unreachable = library is None
    library = library or []
    if query:
        installed = [m for m in installed if query in m["name"].lower()]
        library = [m for m in library if matches(query, m)]
    library = [dict(m, tag=suggested_tag(m)) for m in library[:LIBRARY_LIMIT]]
    print(json.dumps({"installed": installed, "library": library, "unreachable": unreachable,
                      "serverDown": server_down}))


if __name__ == "__main__":
    main()
