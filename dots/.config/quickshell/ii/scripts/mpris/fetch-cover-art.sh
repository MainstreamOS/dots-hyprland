#!/usr/bin/env bash
# Downloads a track's cover art into the cache, upgrading YouTube / Google
# URLs to high-resolution variants and removing pillarboxes, letterboxes,
# and low-resolution blur before moving the result into place.
# Arguments:
#   $1 - output file path
#   $2 - art URL reported by the player
#   $3 - allowed curl protocols (e.g. "http,https,file")
#   $4 - optional track xesam:url
[ -f "$1" ] && exit 0
t="$1.part.$$"
t_oar="$1.oar.$$"
stop() { kill $(jobs -p) 2>/dev/null; wait; rm -f "$t" "$t_oar"; exit 143; }
trap stop TERM

out_dir=$(dirname -- "$1")
mkdir -p -- "$out_dir" || exit 1

art_url="$2"
proto="$3"
track_url="${4:-}"

fallback_url="$art_url"
[[ "$fallback_url" == /* ]] && fallback_url="file://$fallback_url"

https_ok=0
case ",$proto," in
    *,https,*) https_ok=1 ;;
esac

# Extract 11-char YouTube video ID from art URL or track xesam:url.
vid=""
if [[ "$art_url" =~ ^https?://(i\.ytimg\.com/vi(_webp)?|img\.youtube\.com/vi)/([A-Za-z0-9_-]{11})([/?#&]|$) ]]; then
    vid="${BASH_REMATCH[3]}"
elif [[ "$track_url" =~ (^|https?://)([A-Za-z0-9-]+\.)*youtube\.com/(watch\?([^#]*&)?v=|shorts/|live/)([A-Za-z0-9_-]{11})([/?#&]|$) ]]; then
    vid="${BASH_REMATCH[5]}"
elif [[ "$track_url" =~ (^|https?://)([A-Za-z0-9-]+\.)*youtu\.be/([A-Za-z0-9_-]{11})([/?#&]|$) ]]; then
    vid="${BASH_REMATCH[3]}"
fi

# Upgrade lh3.googleusercontent.com =w<N>-h<N> size parameter to =w1200-h1200.
upgraded_google=""
if [[ "$fallback_url" == *"lh3.googleusercontent.com"* ]] && [[ "$fallback_url" =~ ^(.*)=w[0-9]+-h[0-9]+(.*)$ ]]; then
    upgraded_google="${BASH_REMATCH[1]}=w1200-h1200${BASH_REMATCH[2]}"
fi

fetch_url() {
    local url="$1"
    local dest="$2"
    curl -4 -fsSL -g --proto "=$proto" --max-time 20 --max-filesize 20000000 --create-dirs -o "$dest" -- "$url" &
    wait $!
}

is_valid_yt_thumb() {
    python3 -c '
import sys
from PIL import Image
try:
    with Image.open(sys.argv[1]) as im:
        w, h = im.size
        sys.exit(0 if (w, h) != (120, 90) and w > 120 and h > 90 else 1)
except Exception:
    sys.exit(1)
' "$1" 2>/dev/null
}

downloaded=0
tried_oar=0

if [ -n "$vid" ] && [ "$https_ok" -eq 1 ]; then
    candidates=()
    if [[ "$track_url" == *"/shorts/"* ]]; then
        tried_oar=1
        candidates=(
            "https://i.ytimg.com/vi/${vid}/oar2.jpg"
            "https://i.ytimg.com/vi/${vid}/oar1.jpg"
            "https://i.ytimg.com/vi/${vid}/maxresdefault.jpg"
            "https://i.ytimg.com/vi/${vid}/sddefault.jpg"
            "https://i.ytimg.com/vi/${vid}/hqdefault.jpg"
        )
    else
        candidates=(
            "https://i.ytimg.com/vi/${vid}/maxresdefault.jpg"
            "https://i.ytimg.com/vi/${vid}/sddefault.jpg"
            "https://i.ytimg.com/vi/${vid}/hqdefault.jpg"
        )
    fi

    for u in "${candidates[@]}"; do
        if fetch_url "$u" "$t" && is_valid_yt_thumb "$t"; then
            downloaded=1
            break
        fi
        rm -f "$t"
    done
elif [ -n "$upgraded_google" ]; then
    if fetch_url "$upgraded_google" "$t"; then
        downloaded=1
    else
        rm -f "$t"
    fi
fi

if [ "$downloaded" -eq 0 ]; then
    if fetch_url "$fallback_url" "$t"; then
        downloaded=1
    else
        s=$?
        rm -f "$t" "$t_oar"
        exit $s
    fi
fi

process_art() {
    local try_oar="$1"
    python3 - "$t" "$track_url" "$try_oar" <<'PYEOF' &
import sys
import numpy as np
from PIL import Image, ImageFilter, ImageOps

path = sys.argv[1]
track_url = sys.argv[2]
try_oar = sys.argv[3] == "1"

try:
    with Image.open(path) as src:
        orig_fmt = src.format
        if getattr(src, "is_animated", False):
            sys.exit(0)
        im = ImageOps.exif_transpose(src)
        im.load()
except Exception:
    sys.exit(0)

if im.mode == "P":
    im = im.convert("RGBA" if "transparency" in im.info else "RGB")
elif im.mode not in ("RGB", "RGBA", "LA", "L"):
    im = im.convert("RGB")

arr = np.asarray(im.convert("RGB"), dtype=np.float32)
h, w, _ = arr.shape
changed = False

# Letterbox removal (width > height): strip solid black 4:3 bars to 16:9.
if w > h:
    strip_h = max(1, int(h * 0.10))
    top = arr[:strip_h]
    bot = arr[h - strip_h:]
    if (
        float(top.mean()) < 6.0
        and float(top.std()) < 6.0
        and float(bot.mean()) < 6.0
        and float(bot.std()) < 6.0
    ):
        target_h = round(w * 9 / 16)
        if 0 < target_h < h:
            yT = (h - target_h) // 2
            im = im.crop((0, yT, w, yT + target_h))
            arr = arr[yT:yT + target_h]
            h, w, _ = arr.shape
            changed = True

# Pillarbox removal (width > height * 1.15): detect vertical Short inside horizontal frame.
if w > h * 1.15:
    crop_w = round(h * 9 / 16)
    xL = max(0, (w - crop_w) // 2)
    xR = min(w, xL + crop_w)
    if xR - xL >= 8:
        strip = max(1, min(int(w * 0.28), max(1, xL - 1)) if xL > 1 else int(w * 0.28))
        left_std = float(arr[:, :strip].std(axis=(0, 1)).mean())
        right_std = float(arr[:, w - strip:].std(axis=(0, 1)).mean())
        mid_std = float(arr[:, xL:xR].std(axis=(0, 1)).mean())

        diffs = np.abs(arr[:, 1:] - arr[:, :-1]).mean(axis=(0, 2))
        seam_L = float(np.max(diffs[max(0, xL - 2):min(w - 1, xL + 3)]))
        seam_R = float(np.max(diffs[max(0, xR - 3):min(w - 1, xR + 2)]))
        adj_L_slice = diffs[max(0, strip // 4):max(1, xL - 4)]
        adj_R_slice = diffs[min(w - 2, xR + 4):max(xR + 5, w - strip // 4)]
        adj_L = max(float(adj_L_slice.mean()) if adj_L_slice.size else 0.5, 0.5)
        adj_R = max(float(adj_R_slice.mean()) if adj_R_slice.size else 0.5, 0.5)

        is_short_url = "/shorts/" in track_url
        is_flat_bars = left_std < 10.0 and right_std < 10.0 and mid_std > 20.0
        is_seam_916 = left_std < 35.0 and right_std < 35.0 and (
            seam_L / adj_L > 5.0 or seam_R / adj_R > 5.0
        )

        # hqdefault (4:3) cropped to 16:9 places Short seams at ~28.9% / ~71.1% width.
        is_seam_hq = False
        if not (is_short_url or is_flat_bars or is_seam_916) and w / h > 1.6 and left_std < 35.0 and right_std < 35.0:
            xL_hq = round(w * 0.289)
            xR_hq = w - xL_hq
            if xL_hq > 8 and xR_hq < w - 8:
                sL_hq = float(np.max(diffs[max(0, xL_hq - 2):min(w - 1, xL_hq + 3)]))
                sR_hq = float(np.max(diffs[max(0, xR_hq - 3):min(w - 1, xR_hq + 2)]))
                aL_hq = max(float(diffs[max(0, xL_hq // 4):max(1, xL_hq - 4)].mean()), 0.5)
                aR_hq = max(float(diffs[min(w - 2, xR_hq + 4):max(xR_hq + 5, w - xL_hq // 4)].mean()), 0.5)
                is_seam_hq = (sL_hq / aL_hq > 5.0 or sR_hq / aR_hq > 5.0)

        if is_short_url or is_flat_bars or is_seam_916 or is_seam_hq:
            if try_oar:
                sys.exit(10)
            # Trim 1px if rounding/4:2:0 shifted the actual seam 1px inside (xL, xR).
            crop_L, crop_R = xL, xR
            if 0 < crop_L < w - 2 and diffs[crop_L] > 15.0 and diffs[crop_L] > diffs[crop_L - 1] * 2.5:
                crop_L += 1
            if 2 < crop_R < w and diffs[crop_R - 2] > 15.0 and diffs[crop_R - 2] > diffs[crop_R - 1] * 2.5:
                crop_R -= 1
            if crop_R - crop_L >= 8:
                im = im.crop((crop_L, 0, crop_R, h))
                w, h = im.size
                changed = True

# Lanczos upscale + unsharp mask when min dimension is below 960px.
w, h = im.size
if min(w, h) < 960:
    if w <= h:
        new_w = 960
        new_h = max(1, round(h * 960 / w))
    else:
        new_h = 960
        new_w = max(1, round(w * 960 / h))
    im = im.resize((new_w, new_h), Image.Resampling.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=110, threshold=2))
    changed = True

if changed:
    try:
        if im.mode in ("RGBA", "LA") or orig_fmt == "PNG":
            im.save(path, format="PNG")
        else:
            if im.mode != "RGB":
                im = im.convert("RGB")
            im.save(path, format="JPEG", quality=95)
    except Exception:
        sys.exit(0)
PYEOF
    wait $!
}

can_try_oar=0
if [ -n "$vid" ] && [ "$https_ok" -eq 1 ] && [ "$tried_oar" -eq 0 ]; then
    can_try_oar=1
fi

process_art "$can_try_oar"
py_rc=$?
if [ "$py_rc" -eq 10 ] && [ "$can_try_oar" -eq 1 ]; then
    if fetch_url "https://i.ytimg.com/vi/${vid}/oar2.jpg" "$t_oar" && is_valid_yt_thumb "$t_oar"; then
        mv -f "$t_oar" "$t"
    else
        rm -f "$t_oar"
    fi
    process_art 0
fi

mv -f "$t" "$1"
s=$?
rm -f "$t" "$t_oar"
exit $s
