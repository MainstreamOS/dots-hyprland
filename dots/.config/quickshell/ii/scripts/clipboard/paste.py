"""Read the current Wayland clipboard without depending on clipboard history."""

import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit


IMAGE_TYPES = {"image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif", "image/webp": ".webp"}
MAX_BYTES = 32 * 1024 * 1024


def read_clipboard(*args, limit=MAX_BYTES):
    # Bound both the transfer and the wait for an unresponsive clipboard owner.
    def bound_output():
        resource.setrlimit(resource.RLIMIT_FSIZE, (limit + 1, limit + 1))

    with tempfile.TemporaryFile() as output:
        subprocess.run(["wl-paste", "--no-newline", *args], stdout=output,
                       stderr=subprocess.DEVNULL, timeout=5, check=True,
                       preexec_fn=bound_output)
        output.seek(0)
        data = output.read(limit + 1)
    if len(data) > limit:
        raise ValueError("The clipboard content is too large to paste.")
    return data


def local_files(text):
    paths = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        if not line.startswith("file://"):
            return []
        url = urlsplit(line)
        if url.scheme != "file" or url.netloc not in ("", "localhost"):
            return []
        path = unquote(url.path)
        if not Path(path).is_file():
            return []
        if path not in paths:
            paths.append(path)
    return paths


def paste(cache, plain=False, text_limit=50000):
    types = read_clipboard("--list-types", limit=65536).decode().splitlines()
    if not plain:
        if "text/uri-list" in types:
            paths = local_files(read_clipboard("--type", "text/uri-list").decode())
            if paths:
                return {"files": paths}
        for mime, extension in IMAGE_TYPES.items():
            if mime not in types:
                continue
            data = read_clipboard("--type", mime)
            if not data:
                return {}
            directory = Path(cache) / "clipboard"
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            path = directory / (hashlib.sha256(data).hexdigest() + extension)
            with tempfile.NamedTemporaryFile(dir=directory, delete=False) as output:
                temporary = Path(output.name)
                try:
                    output.write(data)
                    output.close()
                    temporary.replace(path)
                finally:
                    temporary.unlink(missing_ok=True)
            return {"files": [str(path)]}
    mime = next((t for t in ("text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING") if t in types), None)
    if mime is None:
        return {}
    text = read_clipboard("--type", mime).decode("utf-8", errors="replace")
    if not plain:
        paths = local_files(text)
        if paths:
            return {"files": paths}
    return {"text": text[:text_limit], "truncated": len(text) > text_limit}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", required=True)
    parser.add_argument("--plain", action="store_true")
    parser.add_argument("--text-limit", type=int, default=50000)
    args = parser.parse_args()
    try:
        result = paste(args.cache, args.plain, max(1, args.text_limit))
    except (OSError, ValueError, subprocess.SubprocessError):
        # Never include clipboard contents or filenames in error logs.
        result = {"error": "Could not read the clipboard. Try copying it again."}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
