#!/usr/bin/env python3
# Trims a CLI's NDJSON event stream before the shell parses it on its GUI
# thread: drops or shortens heavy events, caps every line, and (agy --diff)
# works out what each write changed. A line it cannot handle passes through
# unchanged.
import argparse
import difflib
import json
import os
import subprocess
import sys
import time

LINE_CAP = 256 * 1024
FIELD_CAP = 2000
TRUNCATED = "…[truncated]"
DIFF_LINE_LIMIT = 20000
LIST_CAP = 50
WRITE_TOOLS = ("write_to_file", "replace_file_content", "multi_replace_file_content", "sed_file")
BODY_KEYS = ("CodeContent", "codeContent", "ReplacementContent", "replacementContent",
             "TargetContent", "targetContent")
CHUNK_KEYS = ("ReplacementChunks", "replacementChunks")

# A file untouched since the request started was not written this turn: a
# refused write still reports its tool steps.
TURN_START = time.time()
# path -> snapshot to diff the next write against: the file before this turn
# when the step arrived early enough to see it, else after this turn's last write
befores = {}
MISSING = (0, [])


def truncate_strings(value, cap=FIELD_CAP):
    if isinstance(value, str):
        return value if len(value) <= cap else value[:cap] + TRUNCATED
    if isinstance(value, list):
        return [truncate_strings(v, cap) for v in value]
    if isinstance(value, dict):
        return {k: truncate_strings(v, cap) for k, v in value.items()}
    return value


def cap_lists(value):
    if isinstance(value, list):
        return [cap_lists(v) for v in value[:LIST_CAP]]
    if isinstance(value, dict):
        return {k: cap_lists(v) for k, v in value.items()}
    return value


def encode(data):
    return (json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def clean_path(value):
    if not isinstance(value, str):
        return ""
    p = value.strip()
    if p.startswith("file://"):
        p = p[7:]
    return p.strip("\"' ")


def read_snapshot(fp):
    count = 0
    lines = []
    try:
        with open(fp, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                count += 1
                if lines is not None:
                    lines.append(line)
                    if count >= DIFF_LINE_LIMIT:
                        lines = None
    except Exception:
        return None
    return (count, lines)


def modified_this_turn(fp):
    try:
        return os.stat(fp).st_mtime >= TURN_START
    except OSError:
        return False


def born_this_turn(fp):
    # Python's stat has no birth time on Linux; statx through stat(1) does.
    try:
        out = subprocess.run(["stat", "-c", "%.9W", "--", fp], capture_output=True, text=True, timeout=2).stdout
        return float(out.strip() or 0) >= TURN_START
    except Exception:
        return False


def diff_counts(before, after):
    if before[1] is None or after[1] is None:
        if before[0] == after[0]:
            return -1, -1
        delta = after[0] - before[0]
        return max(delta, 0), max(-delta, 0)
    added = deleted = 0
    for d in difflib.unified_diff(before[1], after[1], n=0):
        if d.startswith("+") and not d.startswith("+++"):
            added += 1
        elif d.startswith("-") and not d.startswith("---"):
            deleted += 1
    return added, deleted


def write_started(fp):
    if fp in befores:
        return
    if not os.path.exists(fp):
        befores[fp] = MISSING
    elif not modified_this_turn(fp):
        snap = read_snapshot(fp)
        if snap is not None:
            befores[fp] = snap


# (verb, added, removed) for a write that changed the file, None for one that
# did not. Counts are -1 when there is nothing true to show.
def write_done(fp):
    before = befores.pop(fp, None)
    if not modified_this_turn(fp):
        return None
    after = read_snapshot(fp)
    if after is None:
        return ("Edited", -1, -1)
    befores[fp] = after
    if before is MISSING or (before is None and born_this_turn(fp)):
        return ("Added", after[0], 0)
    if before is None:
        return ("Edited", -1, -1)
    added, deleted = diff_counts(before, after)
    if added == 0 and deleted == 0:
        return None
    return ("Edited", added, deleted)


def strip_bodies(params):
    for key in BODY_KEYS:
        params.pop(key, None)
    for key in CHUNK_KEYS:
        chunks = params.get(key)
        if isinstance(chunks, list):
            for chunk in chunks:
                if isinstance(chunk, dict):
                    strip_bodies(chunk)


# Each processor returns (data, changed); data is None for a dropped line.
def process_agy(data, with_diff):
    step = data.get("step_update")
    if not isinstance(step, dict) or step.get("step_type") != "tool":
        return data, False
    tool_info = step.get("tool_info")
    if not isinstance(tool_info, dict):
        tool_info = {}
    tool_name = step.get("tool_name") or tool_info.get("name") or ""
    params = tool_info.get("parameters")
    if not isinstance(params, dict):
        params = step.get("parameters")
    if not isinstance(params, dict):
        params = {}
    fp = clean_path(params.get("TargetFile") or params.get("targetFile") or params.get("AbsolutePath")
                    or params.get("absolutePath") or params.get("path") or params.get("file") or "")
    strip_bodies(params)

    if with_diff and tool_name in WRITE_TOOLS and fp:
        state = step.get("state") or ""
        if state == "ACTIVE":
            write_started(fp)
        elif state == "DONE":
            result = write_done(fp)
            if result is None:
                tool_info["skipped"] = True
            else:
                tool_info["verb"], added, deleted = result
                tool_info["diff"] = {"added": added, "deleted": deleted}
            step["tool_info"] = tool_info
    return data, True


def process_claude(data):
    kind = data.get("type")
    # Snapshots of whole messages and tool results (file bodies, command
    # output) that the chat never reads.
    if kind in ("assistant", "user"):
        return None, False
    if kind == "result":
        return truncate_strings(data), True
    return data, False


def process_codex(data):
    item = data.get("item")
    if isinstance(item, dict) and item.get("type") not in ("agent_message", "reasoning"):
        data["item"] = truncate_strings(item)
        return data, True
    return data, False


def process_line(raw, fmt, with_diff):
    if len(raw.strip()) == 0:
        return raw
    try:
        text = raw.decode("utf-8")
        data = json.loads(text)
    except Exception:
        if len(raw) > LINE_CAP:
            return raw[:FIELD_CAP] + TRUNCATED.encode("utf-8") + b"\n"
        return raw
    if not isinstance(data, dict):
        return raw if len(raw) <= LINE_CAP else None

    changed = False
    if fmt == "agy":
        data, changed = process_agy(data, with_diff)
    elif fmt == "claude":
        data, changed = process_claude(data)
        if data is None:
            return None
    elif fmt == "codex":
        data, changed = process_codex(data)

    out = encode(data) if changed else raw
    if len(out) > LINE_CAP:
        out = encode(truncate_strings(data))
    if len(out) > LINE_CAP:
        out = encode(cap_lists(truncate_strings(data)))
    if len(out) > LINE_CAP:
        return None
    if not changed and not out.endswith(b"\n"):
        out += b"\n"
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", choices=("agy", "claude", "codex"), default="")
    parser.add_argument("--diff", action="store_true")
    parser.add_argument("--since", type=float, default=None)
    args = parser.parse_args()
    global TURN_START
    if args.since is not None:
        # File times come from a coarse kernel clock that can trail the wall clock.
        TURN_START = args.since - 0.05
    out = sys.stdout.buffer
    for raw in sys.stdin.buffer:
        try:
            result = process_line(raw, args.format, args.diff)
        except Exception:
            result = raw
        if result:
            out.write(result)
            out.flush()


if __name__ == "__main__":
    main()
