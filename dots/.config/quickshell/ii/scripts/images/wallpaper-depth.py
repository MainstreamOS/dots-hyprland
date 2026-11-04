#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow", "numpy", "onnxruntime"]
# ///
"""Cut out what can stand in front of the wallpaper clock.

Prints JSON listing a copy of the wallpaper per depth layer, farthest plane first, each
with alpha keeping only what is nearer than that plane, and a coarse grid of how much of
each cell it covers. The background stacks one above the clock, and with the grid it can
pick one for wherever the clock is without coming back here. Results are kept per picture.

Depth Anything V2 small (Apache-2.0) tells what is near, in its 27 MB quantized form,
and a guided filter sharpens each mask against the wallpaper's own edges.
"""

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import signal
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell/user/generated/wallpaper-depth"
MODEL_URL = "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model_quantized.onnx"
MODEL = CACHE / "models/depth-anything-v2-small-quantized.onnx"
MAX_SIDE = 3840
THREADS = 8
# How far past a plane, on the spread depth scale, something counts as fully in front.
PLANE_RAMP = 0.08
# Shares of the picture a layer must keep to be worth offering.
MIN_LAYER, MAX_LAYER = 0.02, 0.9
GRID_COLUMNS, GRID_ROWS = 48, 27
# The guided filter's working size, its window in those pixels, and how closely it follows edges.
GUIDE_SIDE, GUIDE_RADIUS, GUIDE_EPSILON = 960, 8, 1e-4
KEPT_PICTURES = 12
# Seconds the model download may go without a byte before it gives up, so a stalled one can be retried.
DOWNLOAD_TIMEOUT = 30


def picture_key(path):
    stat = path.stat()
    return hashlib.sha256(f"{path}|{stat.st_mtime_ns}".encode()).hexdigest()[:16]


@contextmanager
def locked(path):
    """Each screen runs its own helper, so the others wait here instead of writing the same files."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def model_path():
    if MODEL.exists():
        return MODEL
    import urllib.request

    with locked(MODEL.with_suffix(".lock")):
        if not MODEL.exists():
            handle, tmp = tempfile.mkstemp(dir=MODEL.parent, suffix=".tmp")
            os.close(handle)
            try:
                with urllib.request.urlopen(MODEL_URL, timeout=DOWNLOAD_TIMEOUT) as response, open(tmp, "wb") as out:
                    shutil.copyfileobj(response, out)
                os.replace(tmp, MODEL)
            finally:
                Path(tmp).unlink(missing_ok=True)
    return MODEL


def depth_map(np, image):
    """Relative depth at the model's size, 0 far to 1 near."""
    import onnxruntime as ort
    from PIL import Image

    options = ort.SessionOptions()
    options.intra_op_num_threads = THREADS
    session = ort.InferenceSession(str(model_path()), options, providers=["CPUExecutionProvider"])
    # Long side near 518 px, both sides multiples of the model's 14 px patch.
    scale = 518 / max(image.size)
    size = (max(1, round(image.width * scale / 14)) * 14, max(1, round(image.height * scale / 14)) * 14)
    x = np.asarray(image.resize(size, Image.BICUBIC), dtype=np.float32) / 255
    x = (x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]
    x = x.transpose(2, 0, 1)[None].astype(np.float32)
    d = np.squeeze(session.run(None, {session.get_inputs()[0].name: x})[0])
    low, high = np.percentile(d, [2, 98])
    return np.clip((d - low) / (high - low + 1e-6), 0, 1).astype(np.float32)


def planes(np, spread):
    """The two levels that best split the picture into far, middle and near (Otsu)."""
    counts, edges = np.histogram(spread, bins=64, range=(0, 1))
    share = counts / counts.sum()
    levels = (edges[:-1] + edges[1:]) / 2
    below, moment = np.cumsum(share), np.cumsum(share * levels)
    best, found = -1, (0.33, 0.66)
    for i in range(1, 62):
        for j in range(i + 1, 63):
            weights = below[i], below[j] - below[i], 1 - below[j]
            if min(weights) < 1e-4:
                continue
            means = moment[i] / weights[0], (moment[j] - moment[i]) / weights[1], (moment[-1] - moment[j]) / weights[2]
            spread_between = sum(w * (m - moment[-1]) ** 2 for w, m in zip(weights, means))
            if spread_between > best:
                best, found = spread_between, (levels[i], levels[j])
    return found


def box(np, a, r):
    """Mean over a (2r+1) square window, shrinking at the edges."""
    def along(a, axis):
        c = np.cumsum(a, axis=axis)
        pad = [(0, 0)] * a.ndim
        pad[axis] = (1, 0)
        c = np.pad(c, pad)
        n = a.shape[axis]
        hi, lo = np.minimum(np.arange(n) + r + 1, n), np.maximum(np.arange(n) - r, 0)
        return (np.take(c, hi, axis=axis) - np.take(c, lo, axis=axis)) / np.expand_dims(hi - lo, 1 - axis)
    return along(along(a, 0), 1)


def sharpen(np, alpha, image):
    """Fast guided filter: a soft mask takes its edges from the picture at full size."""
    from PIL import Image

    guide = image.convert("L")
    scale = min(1, GUIDE_SIDE / max(guide.size))
    small_size = (max(1, round(guide.width * scale)), max(1, round(guide.height * scale)))
    g = np.asarray(guide.resize(small_size, Image.BILINEAR), dtype=np.float32) / 255
    p = np.asarray(Image.fromarray(alpha, mode="F").resize(small_size, Image.BILINEAR))
    mean_g, mean_p = box(np, g, GUIDE_RADIUS), box(np, p, GUIDE_RADIUS)
    a = (box(np, g * p, GUIDE_RADIUS) - mean_g * mean_p) / (box(np, g * g, GUIDE_RADIUS) - mean_g * mean_g + GUIDE_EPSILON)
    b = mean_p - a * mean_g
    a, b = box(np, a, GUIDE_RADIUS), box(np, b, GUIDE_RADIUS)
    up = lambda m: np.asarray(Image.fromarray(m.astype(np.float32), mode="F").resize(guide.size, Image.BILINEAR))
    return np.clip(up(a) * (np.asarray(guide, dtype=np.float32) / 255) + up(b), 0, 1)


def prune():
    results = sorted(CACHE.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True)
    for result in results[KEPT_PICTURES:]:
        for f in CACHE.glob(f"{result.stem}*"):
            f.unlink(missing_ok=True)


def cut_out(wall, key, result_path):
    import numpy as np
    from PIL import Image

    image = Image.open(wall).convert("RGB")
    if max(image.size) > MAX_SIDE:
        scale = MAX_SIDE / max(image.size)
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)

    # The near ground takes up most of the range, so far things like a mountain sit low
    # in it. The root spreads them out from the sky behind them.
    spread = np.sqrt(depth_map(np, image))
    layers = []
    for index, plane in enumerate(planes(np, spread)):
        if not MIN_LAYER <= (spread > plane).mean() <= MAX_LAYER:
            continue
        t = np.clip((spread - plane) / PLANE_RAMP, 0, 1)
        alpha = sharpen(np, (t * t * (3 - 2 * t)).astype(np.float32), image)
        mask = Image.fromarray((alpha * 255).astype(np.uint8))
        # Nothing shows where alpha is 0, and zeros there make the file a fraction of the size.
        cutout = Image.composite(image, Image.new("RGB", image.size), mask.point(lambda v: 255 if v else 0))
        cutout.putalpha(mask)
        out = CACHE / f"{key}-{index}.png"
        tmp = out.with_suffix(".tmp")
        cutout.save(tmp, "PNG", compress_level=1)
        tmp.replace(out)
        grid = np.asarray(mask.resize((GRID_COLUMNS, GRID_ROWS), Image.BOX), dtype=np.float32) / 255
        layers.append({"path": str(out), "cover": [round(float(v), 3) for v in grid.flat]})

    result = json.dumps({"columns": GRID_COLUMNS, "rows": GRID_ROWS, "layers": layers})
    tmp = result_path.with_suffix(".tmp")
    tmp.write_text(result)
    tmp.replace(result_path)
    prune()


def main():
    # Stopped by the shell's time limit, the cleanup below still runs and no half model stays behind.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wallpaper", type=Path)
    args = parser.parse_args()

    wall = args.wallpaper.expanduser().resolve()
    CACHE.mkdir(parents=True, exist_ok=True)
    key = picture_key(wall)
    result_path = CACHE / f"{key}.json"
    # A second screen showing the same picture waits for the first one's result and reuses it.
    with locked(CACHE / f"{key}.lock"):
        if result_path.exists():
            os.utime(result_path)
        else:
            cut_out(wall, key, result_path)
    print(result_path.read_text())


if __name__ == "__main__":
    main()
