#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light
    # Only steer the widget theme while the user is on the stock adw-gtk3
    # pair — a manual pick in Settings > Themes > System look wins.
    local current_gtk
    current_gtk="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        case "$current_gtk" in adw-gtk3|adw-gtk3-dark|"")
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' ;;
        esac
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        case "$current_gtk" in adw-gtk3|adw-gtk3-dark|"")
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3' ;;
        esac
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

set_sddm_background() {
    local wallpaper_path="$1"
    [[ -z "$wallpaper_path" || ! -f "$wallpaper_path" ]] && return

    # For video wallpapers, use the thumbnail instead
    if is_video "$wallpaper_path"; then
        local thumb="$THUMBNAIL_DIR/$(basename "$wallpaper_path").jpg"
        [[ -f "$thumb" ]] && wallpaper_path="$thumb" || return
    fi

    local username
    username="$(whoami)"
    local sddm_theme_dir="/usr/share/sddm/themes/pixie"
    local sddm_bg_dir="$sddm_theme_dir/assets/backgrounds"
    local dest="$sddm_bg_dir/${username}.jpg"

    [[ ! -d "$sddm_theme_dir" ]] && return

    # Convert to jpg (or copy if already jpg) using a temp file, then move into place
    local tmpfile
    tmpfile="$(mktemp /tmp/sddm-bg-XXXXXX.jpg)"
    if command -v magick &>/dev/null; then
        magick "$wallpaper_path" -quality 90 "$tmpfile" 2>/dev/null || return
    elif command -v convert &>/dev/null; then
        convert "$wallpaper_path" -quality 90 "$tmpfile" 2>/dev/null || return
    else
        cp "$wallpaper_path" "$tmpfile" 2>/dev/null || return
    fi

    # Copy to SDDM theme dir
    # Try direct copy first, fall back to pkexec with polkit helper (no password needed)
    if cp "$tmpfile" "$dest" 2>/dev/null; then
        chmod 644 "$dest" 2>/dev/null
    elif command -v sddm-bg-helper &>/dev/null; then
        pkexec sddm-bg-helper "$tmpfile" "$dest" 2>/dev/null
    fi
    rm -f "$tmpfile"
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    # A theme apply holds its lock on file descriptor 9 and every child inherits
    # it, so anything still running once the apply exits would keep that lock
    # held and stall the next one. Background work closes it with 9>&-.
    #
    # Logs rather than the caller's stdout, so a helper that misbehaves leaves
    # something to read instead of scrolling past in whatever launched us.
    local logdir="$STATE_DIR/user/generated"
    mkdir -p "$logdir"
    "$SCRIPT_DIR/code/material-code-set-color.sh" >"$logdir/material-code.log" 2>&1 9>&- &
    # Both of these re-encode the wallpaper with ImageMagick, and between them
    # they cost more than everything the desktop actually needs. Neither result
    # is on screen while the wallpaper is being changed — one is the login
    # background, the other is only drawn once the overview is opened — so they
    # run alongside the rest instead of holding it up. Their own lock keeps two
    # runs in quick succession from finishing out of order and leaving a stale
    # image behind.
    (
        # Bounded: the section below re-encodes with ImageMagick and can reach
        # pkexec for the login background, either of which may sit there. A run
        # that gives up on the lock still does its work — the cost is a
        # derivative that may land out of order, against a subshell per
        # wallpaper change waiting for something that is never coming.
        if command -v flock >/dev/null 2>&1 && exec 8>"${XDG_RUNTIME_DIR:-/tmp}/quickshell-wallpaper-derivatives.lock"; then
            flock -w 30 8 2>/dev/null || true
        fi
        # A rotation tick asks for the palette too when recolour is on, but it is
        # still a timer. The login background is re-encoded from the full-size
        # image for something nobody sees until they log out, and the overview
        # backdrop is pushed with a reload that makes every client reconfigure —
        # neither is worth doing every interval, so the tick keeps the cheap
        # single-key push and leaves the login screen on the theme's wallpaper.
        if [[ -n "${keep_slideshow_flag:-}" ]]; then
            set_scrolloverview_wallpaper "$wallpaper_path" "$screen_width" "$screen_height" "eval"
        else
            set_sddm_background "$wallpaper_path"
            set_scrolloverview_wallpaper "$wallpaper_path" "$screen_width" "$screen_height"
        fi
    ) >/dev/null 2>&1 9>&- &
    # Under apply-theme.sh the widget theme, the icon theme and the interface
    # fonts are all still to come, so the portal is restaged at the end of that
    # run instead.
    if [[ -z "${noswitch_flag:-}" ]]; then
        "$SCRIPT_DIR/restage-portals.sh" >/dev/null 2>&1 9>&- &
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" || "$extension" == "m4v" || "$extension" == "ogv" ]] && return 0 || return 1
}

# Small tab-separated stores, newest line first, keyed on a path and the file's
# own mtime and size so an edited picture is never answered from a stale entry.
# One line per picture rather than one line total: the wallpaper slideshow asks
# about a different picture every few minutes, and a single slot meant it wiped
# whatever the theme had just paid to work out.
PALETTE_CACHE_KEEP=64
SRCCOLOR_CACHE="$STATE_DIR/user/generated/source-color-for-image.cache"
cache_key_for() {
    local meta
    meta="$(stat -c '%Y:%s' "$1" 2>/dev/null)" || return 1
    [[ -n "$meta" ]] || return 1
    # A record is one line and its fields are tab-separated, and both characters
    # are legal in a filename, so a path carrying either would split its own key
    # across the boundary.
    local safe="${1//$'\t'/ }"
    printf '%s:%s' "${safe//$'\n'/ }" "$meta"
}
# Answers through $cache_value rather than stdout: at 64 short lines the shell
# reads the whole store for less than the fork a command substitution costs.
cache_get() {
    # Two stores share these helpers and hold different kinds of value — a
    # colour in one, a scheme name in the other — so the caller says what a
    # good answer looks like. The default rejects anything with whitespace,
    # which is what a key split across the field boundary leaves behind.
    local file="$1" key="$2" pattern="${3:-^[^[:space:]]+$}" k v
    cache_value=""
    [[ -n "$key" && -f "$file" ]] || return 1
    while IFS=$'\t' read -r k v; do
        if [[ "$k" == "$key" ]]; then
            cache_value="$v"
            break
        fi
    done < "$file"
    # A value that doesn't look right reads as absent, so the miss path
    # regenerates it and writes the line again: the store repairs itself
    # instead of handing the same unusable answer back for the file's lifetime.
    [[ "$cache_value" =~ $pattern ]] || { cache_value=""; return 1; }
}
# awk is given the key through the environment because -v expands escape
# sequences in what it is assigned, and a path may contain a backslash.
cache_rewrite() {
    local file="$1" key="$2" value="${3:-}" tmp
    [[ -n "$key" ]] || return 0
    mkdir -p "${file%/*}" 2>/dev/null || return 0
    tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 0
    {
        [[ -n "$value" ]] && printf '%s\t%s\n' "$key" "$value"
        [[ -f "$file" ]] && CACHE_KEY="$key" awk -F'\t' '$1 != ENVIRON["CACHE_KEY"]' "$file" 2>/dev/null
    } | head -n "$PALETTE_CACHE_KEEP" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}
cache_put() {
    [[ -n "${3:-}" ]] || return 0
    cache_rewrite "$1" "$2" "$3"
}
cache_drop() {
    [[ -f "$1" ]] || return 0
    cache_rewrite "$1" "$2" ""
}

# pkill/pgrep read every /proc/*/cmdline, which hangs whenever any task is
# wedged in the kernel holding its mm lock (an amdgpu HMM oops leaves one
# behind). Matching /proc/*/comm directly avoids cmdline reads entirely, so
# wallpaper switching keeps working through such a wedge.
kill_existing_mpvpaper() {
    local p comm
    for p in /proc/[0-9]*; do
        read -r comm < "$p/comm" 2>/dev/null || continue
        [[ "$comm" == "mpvpaper" ]] && kill -9 "${p#/proc/}" 2>/dev/null
    done
    return 0
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

for p in /proc/[0-9]*; do
    read -r comm < "\$p/comm" 2>/dev/null || continue
    [ "\$comm" = "mpvpaper" ] && kill -9 "\${p#/proc/}" 2>/dev/null
done

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    mpvpaper -o "$VIDEO_OPTS" "\$monitor" "$video_path" &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

# Every edit to config.json here is a read-modify-write of a file the shell's
# own adapter also writes. The temp is unique and sits beside the target, so two
# writers can't publish each other's half-finished output and the rename a
# reader sees is atomic. The lock only decides which of two edits survives; it
# is bounded and skippable, since a rewrite that raced is better than one that
# never happened.
CONFIG_WRITE_LOCK="${XDG_RUNTIME_DIR:-/tmp}/quickshell-config-write.${UID:-0}.lock"
config_jq() {
    [ -f "$SHELL_CONFIG_FILE" ] || return 0
    (
        if command -v flock >/dev/null 2>&1 && { exec 6>"$CONFIG_WRITE_LOCK"; } 2>/dev/null; then
            flock -w 5 6 2>/dev/null
        fi
        local tmp
        tmp="$(mktemp "$SHELL_CONFIG_FILE.XXXXXX" 2>/dev/null)" || return 0
        if jq "$@" "$SHELL_CONFIG_FILE" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            chmod --reference="$SHELL_CONFIG_FILE" "$tmp" 2>/dev/null
            mv -f "$tmp" "$SHELL_CONFIG_FILE"
        else
            rm -f "$tmp"
        fi
    )
}

set_wallpaper_path() {
    local path="$1"
    # Ending a rotation rides along in the write that records the picture, so
    # the shell reads one change rather than two. Said outright rather than by
    # dropping the key: the config adapter keeps a value whose key has gone.
    local stop_slideshow="${2:-}"
    local filter='.background.wallpaperPath = $path'
    if [[ -n "$stop_slideshow" ]]; then
        filter+=' | (if ((.background.slideshow.enable)? // false) == true then .background.slideshow.enable = false else . end)'
    fi
    config_jq --arg path "$path" "$filter"
}

set_thumbnail_path() {
    local path="$1"
    config_jq --arg path "$path" '.background.thumbnailPath = $path'
}

# Rewrite the `wallpaper_path = ...` line that the scrolloverview plugin
# (built from sdata/scrolloverview/) reads, then poke Hyprland to reload
# its config. The plugin keys its texture cache off the configured path,
# so on the next overview render it will rebuild both the sharp texture
# and the CPU-pre-blurred copy from the new image. We only update when
# the line already exists — the install script is responsible for first
# insertion.
set_scrolloverview_wallpaper() {
    local path="$1"
    local screen_width="$2"
    local screen_height="$3"
    # How the running compositor is told: a full reload picks up matugen's
    # colour templates alongside this value, which is what a colour change
    # needs. `eval` sets this one key and nothing else — the plugin reads the
    # path through a pointer into the config, so it rebuilds its textures on
    # the next overview render either way. A reload makes every Wayland client
    # re-configure, so it isn't something to run on a timer.
    local push_mode="${4:-reload}"
    local target="$XDG_CONFIG_HOME/hypr/custom/general.lua"
    [[ -z "$path" || ! -f "$target" ]] && return

    # The plugin uploads its wallpaper twice (sharp + pre-blurred), so hand it a
    # monitor-sized copy rather than the raw source (often 4K, and a video the
    # plugin can't decode). Shrink-only ('>') keeps the visible result identical.
    local plugin_path="$path"
    local src="$path"
    if is_video "$src"; then
        local thumb="$THUMBNAIL_DIR/$(basename "$src").jpg"
        [[ -f "$thumb" ]] && src="$thumb"
    fi
    if [[ -f "$src" && "$screen_width" =~ ^[0-9]+$ && "$screen_height" =~ ^[0-9]+$ ]]; then
        local scaled="$CACHE_DIR/user/generated/scrolloverview_$(basename "$src").jpg"
        mkdir -p "$CACHE_DIR/user/generated"
        if [[ -s "$scaled" && "$scaled" -nt "$src" ]]; then
            # Already scaled from this very picture. A rotation revisits the same
            # folder for as long as it runs, and this is a full decode and encode.
            plugin_path="$scaled"
        elif command -v magick &>/dev/null; then
            magick "$src" -resize "${screen_width}x${screen_height}>" "$scaled" 2>/dev/null && plugin_path="$scaled"
        elif command -v convert &>/dev/null; then
            convert "$src" -resize "${screen_width}x${screen_height}>" "$scaled" 2>/dev/null && plugin_path="$scaled"
        fi
        # One monitor-sized copy per picture, and a rotation is pointed at whole
        # folders, so the oldest are dropped rather than kept for a wallpaper
        # nobody has chosen in months.
        ls -1t "$CACHE_DIR"/user/generated/scrolloverview_*.jpg 2>/dev/null \
            | tail -n +33 | while IFS= read -r stale; do rm -f "$stale"; done
    fi

    if grep -qE '^[[:space:]]*wallpaper_path[[:space:]]*=' "$target"; then
        # The value lands inside a Lua double-quoted string, in the file and in
        # the eval alike, so a backslash or a quote in the name has to survive
        # as itself. Escaped once here for both. A line break is legal in a
        # filename but not inside a Lua string literal, and the rewrite below is
        # line-oriented besides, so those go in as escapes and Lua puts them
        # back. Backslashes are doubled first, or the escapes added after would
        # be doubled too.
        local lua_path="${plugin_path//\\/\\\\}"
        lua_path="${lua_path//\"/\\\"}"
        lua_path="${lua_path//$'\n'/\\n}"
        lua_path="${lua_path//$'\r'/\\r}"

        local tmpfile
        # Beside the target, so replacing it is a rename. general.lua is
        # sourced by the Hyprland config and a reload can be reading it at any
        # moment; a copy in from elsewhere would truncate it first.
        tmpfile="$(mktemp "$target.XXXXXX" 2>/dev/null)" || return
        # Lua form: `wallpaper_path = "...",` (with quotes and trailing comma).
        # Preserves leading indent so the value stays inside the parent table.
        # Passed through the environment because awk -v expands escape
        # sequences in what it is given.
        if SCROLLOVERVIEW_PATH="$lua_path" awk '
            /^[[:space:]]*wallpaper_path[[:space:]]*=/ {
                match($0, /^[[:space:]]*/)
                printf "%swallpaper_path = \"%s\",\n", substr($0, 1, RLENGTH), ENVIRON["SCROLLOVERVIEW_PATH"]
                next
            }
            { print }
        ' "$target" > "$tmpfile" && [ -s "$tmpfile" ]; then
            chmod --reference="$target" "$tmpfile" 2>/dev/null
            mv -f "$tmpfile" "$target"
        else
            rm -f "$tmpfile"
            return
        fi

        # Push the new value into the running compositor (and thus the
        # plugin's getDataStaticPtr-cached value). Run async so we don't
        # block the rest of post_process.
        if [[ "$push_mode" == "eval" ]]; then
            hyprctl eval "hl.config({ plugin = { scrolloverview = { wallpaper_path = \"$lua_path\" } } })" >/dev/null 2>&1 &
        else
            hyprctl reload >/dev/null 2>&1 &
        fi
    fi
}

# A slideshow tick: refresh what else draws the same picture, without the
# palette work. The login background is deliberately not among them — it is
# re-encoded from the full-size image and would keep a rotation busy for
# something nobody sees until they log out, so it stays on the wallpaper the
# theme was applied with.
picture_only_post_process() {
    local wallpaper_path="$1"
    (
        if command -v flock >/dev/null 2>&1 && exec 8>"${XDG_RUNTIME_DIR:-/tmp}/quickshell-wallpaper-derivatives.lock"; then
            flock -w 30 8 2>/dev/null || true
        fi
        local screen_width screen_height
        read -r screen_width screen_height < <(hyprctl monitors -j \
            | jq -r '([.[].width] | min), ([.[].height] | min)' | xargs)
        set_scrolloverview_wallpaper "$wallpaper_path" "$screen_width" "$screen_height" "eval"
    ) >/dev/null 2>&1 9>&- &
}

categorize_wallpaper() {
    img_cat=$("$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$1")
    # notify-send "Wallpaper category" "$img_cat"
    echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    # apply-theme.sh has already staged wallpaperPath atomically via its own
    # jq/mv. Rewriting it here adds an extra fs-event that quickshell processes
    # reload from, which worsens the write race, so that caller says so and the
    # write is skipped.
    #
    # Keyed on saying so rather than on --noswitch, which ten other callers pass
    # while staging nothing. The variant resolution below can swap the picture
    # for its -dark or -light sibling, and wallpaperPath is the only one of the
    # things downstream that is actually drawn, so it has to end up naming
    # whatever the palette was built from.
    local skip_config_writes="${config_staged_flag:-}"

    # Start Gemini auto-categorization if enabled
    aiStylingEnabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" ]]; then
        categorize_wallpaper "$imgpath" &
    fi

    read scale screenx screeny screensizey < <(hyprctl monitors -j | jq '.[] | select(.focused) | .scale, .x, .y, .height' | xargs)
    cursorposx=$(hyprctl cursorpos -j | jq '.x' 2>/dev/null) || cursorposx=960
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j | jq '.y' 2>/dev/null) || cursorposy=540
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    matugen_args=(--source-color-index 0)
    # Only set on the picture path; a hand-picked accent colour needs no cache
    # because there is no picture to read.
    palette_key=""
    palette_hex=""

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        kill_existing_mpvpaper

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            missing_deps=()
            if ! command -v mpvpaper &> /dev/null; then
                missing_deps+=("mpvpaper")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[*]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            # Set wallpaper path (skip if apply-theme.sh already staged it)
            if [[ -z "$skip_config_writes" ]]; then
                [[ -n "${clear_accent_color:-}" ]] && set_accent_color ""
                set_wallpaper_path "$imgpath" "${stop_slideshow:-}"
            fi

            # Set video wallpaper
            local video_path="$imgpath"
            monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
            for monitor in $monitors; do
                nohup mpvpaper -o "$VIDEO_OPTS" "$monitor" "$video_path" >/dev/null 2>&1 &
                sleep 0.1
            done

            # Extract first frame for color generation
            thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null

            # Set thumbnail path (skip if apply-theme.sh already staged it)
            if [[ -z "$skip_config_writes" ]]; then
                set_thumbnail_path "$thumbnail"
            fi

            if [ -f "$thumbnail" ]; then
                palette_img="$thumbnail"
                # Keyed on the video rather than the thumbnail: ffmpeg rewrites
                # the thumbnail every run, so its mtime never matches twice and
                # a thumbnail key could only ever miss, filling the store with
                # entries nothing can read.
                palette_key="$(cache_key_for "$video_path")"
                if cache_get "$SRCCOLOR_CACHE" "$palette_key" '^#[0-9a-fA-F]{6}$'; then
                    palette_hex="$cache_value"
                    matugen_args+=(color hex "$palette_hex")
                else
                    palette_hex=""
                    matugen_args+=(image "$thumbnail")
                fi
                generate_colors_material_args=(--path "$thumbnail")
                create_restore_script "$video_path"
            else
                echo "Cannot create image to colorgen"
                remove_restore
                exit 1
            fi
        else
            # Handing matugen the picture means decoding it, which on anything
            # camera-sized is most of the wait. All it takes from the picture is
            # one colour, and the scheme it builds from that colour is the same
            # either way — so once that colour is known, the picture never has
            # to be opened again.
            palette_img="$imgpath"
            # matugen exits 101 on AVIF and on SVG, and the material generator
            # is PIL-based with the same gaps, but both formats display fine —
            # so the colour is read from a small rasterised copy while the
            # wallpaper stays the original. The cache is keyed on that original,
            # since this copy is rewritten whenever the source changes and a key
            # on it could only ever miss.
            local palette_src="$imgpath"
            case "${imgpath,,}" in
                *.avif|*.svg|*.svgz)
                    if command -v magick >/dev/null 2>&1; then
                        local colorsrc="$CACHE_DIR/user/generated/colorsrc-$(basename "$imgpath").png"
                        if [[ ! -f "$colorsrc" || "$imgpath" -nt "$colorsrc" ]]; then
                            mkdir -p "${colorsrc%/*}" 2>/dev/null
                            magick "$imgpath" -resize '512x512>' -flatten "$colorsrc" 2>/dev/null || true
                        fi
                        [[ -s "$colorsrc" ]] && palette_src="$colorsrc"
                    fi
                    ;;
            esac
            palette_key="$(cache_key_for "$imgpath")"
            if cache_get "$SRCCOLOR_CACHE" "$palette_key" '^#[0-9a-fA-F]{6}$'; then
                palette_hex="$cache_value"
                matugen_args+=(color hex "$palette_hex")
            else
                palette_hex=""
                matugen_args+=(image "$palette_src")
            fi
            generate_colors_material_args=(--path "$palette_src")
            # Update wallpaper path in config (skip if apply-theme.sh already staged it)
            if [[ -z "$skip_config_writes" ]]; then
                [[ -n "${clear_accent_color:-}" ]] && set_accent_color ""
                set_wallpaper_path "$imgpath" "${stop_slideshow:-}"
            fi
            remove_restore
        fi
    fi

    # The picture is on screen and every path that draws it has been told; the
    # rest of this function is the palette, which a slideshow leaves alone.
    if [[ -n "${picture_only_flag:-}" ]]; then
        picture_only_post_process "$imgpath"
        return 0
    fi

    # Determine mode if not set
    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi

    # enforce dark mode for terminal
    force_dark_mode=""
    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        force_dark_mode="$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE" 2>/dev/null)"
        if [[ "$force_dark_mode" == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    # Deciding which scheme suits the picture means decoding it at full size,
    # which is a noticeable wait on a machine that has just been asked to change
    # the wallpaper. Nothing above needs the answer, and the picture is already
    # on screen by now, so it is worked out here rather than beforehand.
    # If type_flag is 'auto', detect scheme type from image (after imgpath is set)
    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            detected_type="$(detect_scheme_type_from_image "$imgpath")"
            # Only use detected_type if it's valid
            valid_detected=0
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    valid_detected=1
                    break
                fi
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)

    pre_process "$mode_flag"

    # Check if app and shell theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    # Set harmony and related properties
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
    mkdir -p "$STATE_DIR"/user/generated
    generated_colors_tmp=$(mktemp "$STATE_DIR"/user/generated/material_colors.scss.XXXXXX)
    # The stylesheet is written to one side and moved into place only once it
    # has been checked, so a run that ends anywhere in between leaves the
    # half-written copy behind to accumulate.
    trap 'rm -f "$generated_colors_tmp"' EXIT INT TERM HUP
    # These two read the same wallpaper and neither reads anything the other
    # writes, so running one after the other only made the wait longer.
    # The colour the editor theme is set from stays matugen's alone: the two
    # extractors disagree, and while the stylesheet generator was also writing
    # it, which one you got depended on whether the cache had been hit. Start
    # the stylesheet first and let matugen work at the same time; the result is
    # collected below before anything depends on it.
    # The stylesheet cannot be rebuilt from a single colour the way matugen's
    # scheme can — its terminal colours come out of the picture itself — so what
    # gets kept is the finished stylesheet, under everything that went into it.
    scss_cache_key=""
    scss_cache_file=""
    if [[ -n "${palette_key:-}" ]]; then
        # forceDarkMode belongs in here: it decides whether the generator is
        # run against the dark palette or the current one, so it changes what
        # the cached stylesheet contains without changing anything else here.
        scss_cache_key="$(printf '%s|%s|%s|%s|%s|%s|%s|%s|%s' \
            "$palette_key" "${mode_flag:-}" "${type_flag:-}" "${harmony:-}" \
            "${harmonize_threshold:-}" "${term_fg_boost:-}" "${force_dark_mode:-}" \
            "$(cache_key_for "$terminalscheme")" \
            "$(cache_key_for "$SCRIPT_DIR/generate_colors_material.py")" | sha256sum 2>/dev/null)"
        scss_cache_key="${scss_cache_key:0:32}"
        [[ -n "$scss_cache_key" ]] && scss_cache_file="$CACHE_DIR/user/generated/palette-scss/$scss_cache_key.scss"
    fi
    if [[ -n "$scss_cache_file" && -s "$scss_cache_file" ]]; then
        cp -f "$scss_cache_file" "$generated_colors_tmp" 2>/dev/null
        generated_colors_pid=""
    else
        python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" > "$generated_colors_tmp" &
        generated_colors_pid=$!
    fi

    matugen_status=0
    matugen "${matugen_args[@]}" || matugen_status=$?

    # matugen records the colour it settled on, so the next apply of this same
    # picture can be handed the answer instead of the picture.
    if [[ $matugen_status -eq 0 && -n "${palette_key:-}" && -z "${palette_hex:-}" ]]; then
        extracted_hex="$(jq -r '.source_color // empty' "$STATE_DIR/user/generated/colors.json" 2>/dev/null)"
        [[ "$extracted_hex" =~ ^#[0-9a-fA-F]{6}$ ]] && cache_put "$SRCCOLOR_CACHE" "$palette_key" "$extracted_hex"
    fi

    # The picture behind the current palette, recorded here rather than by a
    # matugen template: matugen only knows it when it was handed the picture, and
    # wrote the string Null the rest of the time — over an accent pick, which
    # changes no wallpaper at all, as much as over a cached one.
    if [[ $matugen_status -eq 0 && -n "${palette_img:-}" ]]; then
        mkdir -p "$STATE_DIR/user/generated/wallpaper" 2>/dev/null \
            && printf '%s\n' "$palette_img" > "$STATE_DIR/user/generated/wallpaper/path.txt" 2>/dev/null
    fi

    generated_colors_status=0
    [[ -n "$generated_colors_pid" ]] && { wait "$generated_colors_pid"; generated_colors_status=$?; }
    # A failed matugen leaves the previous colors.json in place, and every check
    # downstream would pass on it — so stop here rather than let the theme apply
    # with the old palette under the new theme's name.
    if [[ $matugen_status -ne 0 ]]; then
        # A stored colour matugen won't take is dropped, so the next run reads
        # the picture again instead of being handed the same refusal.
        [[ -n "${palette_hex:-}" && -n "${palette_key:-}" ]] && cache_drop "$SRCCOLOR_CACHE" "$palette_key"
        rm -f "$generated_colors_tmp"
        echo "[switchwall] matugen failed (exit $matugen_status); keeping the previous colors." >&2
        deactivate
        return 1
    fi
    if [[ $generated_colors_status -eq 0 ]] \
        && grep -Eq '^\$onBackground: #[[:xdigit:]]{6};$' "$generated_colors_tmp"; then
        # Kept only once it has passed the same check the live copy has to pass,
        # so a half-written stylesheet can never be served back later.
        if [[ -n "$scss_cache_file" && ! -s "$scss_cache_file" ]]; then
            mkdir -p "${scss_cache_file%/*}" 2>/dev/null \
                && cp -f "$generated_colors_tmp" "$scss_cache_file.tmp" 2>/dev/null \
                && mv -f "$scss_cache_file.tmp" "$scss_cache_file" 2>/dev/null \
                || rm -f "$scss_cache_file.tmp" 2>/dev/null
            ls -1t "$CACHE_DIR/user/generated/palette-scss"/*.scss 2>/dev/null \
                | tail -n "+$((PALETTE_CACHE_KEEP + 1))" | xargs -r rm -f 2>/dev/null
        fi
        mv "$generated_colors_tmp" "$STATE_DIR"/user/generated/material_colors.scss
    else
        rm -f "$generated_colors_tmp"
        echo "[switchwall] Failed to generate material_colors.scss; keeping the previous colors." >&2
        deactivate
        return 1
    fi
    deactivate
    "$SCRIPT_DIR"/applycolor.sh

    # Pass screen width, height, and wallpaper path to post_process
    max_width_desired="$(hyprctl monitors -j | jq '([.[].width] | min)' | xargs)"
    max_height_desired="$(hyprctl monitors -j | jq '([.[].height] | min)' | xargs)"
    post_process "$max_width_desired" "$max_height_desired" "$imgpath"
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    config_staged_flag=""
    picture_only_flag=""
    keep_slideshow_flag=""
    stop_slideshow=""

    get_type_from_config() {
        jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        local color="$1"
        config_jq --arg color "$color" '.appearance.palette.accentColor = $color'
    }

    detect_scheme_type_from_image() {
        local img="$1"
        # The answer is one of two scheme names decided by a single number
        # measured off the picture, so it can't change while the file doesn't.
        # Arriving at it means starting a Python interpreter and decoding the
        # image at full size, and the same unchanged wallpaper gets asked about
        # on every theme apply and every light/dark toggle, so keep the last
        # answer and the file it belongs to.
        local cache="$STATE_DIR/user/generated/scheme-for-image.cache"
        local key
        key="$(cache_key_for "$img")"
        if cache_get "$cache" "$key"; then
            printf '%s' "$cache_value"
            return 0
        fi

        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
        local detected
        detected="$("$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n')"
        deactivate

        [[ -n "$detected" ]] && cache_put "$cache" "$key" "$detected"
        printf '%s' "$detected"
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                shift 2
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --image)
                imgpath="$2"
                shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                shift
                ;;
            # "I have already written wallpaperPath myself; don't write it
            # again." Only apply-theme.sh, which stages the whole config.
            --config-staged)
                config_staged_flag="1"
                shift
                ;;
            --picture-only)
                picture_only_flag="1"
                shift
                ;;
            # Everything that changes the wallpaper without the user having
            # chosen it passes this: the rotation's own ticks, the re-apply of a
            # video wallpaper as the shell comes up, and the first-run seed.
            --keep-slideshow)
                keep_slideshow_flag="1"
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    # If accentColor is set in config, use it
    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    # A picked accent normally routes switch() down the colour branch, which
    # never reaches the code that records the wallpaper. Nothing here is going
    # to generate colours anyway, so drop it and take the image branch — which
    # also leaves the accent itself untouched, since only the colour path
    # clears it.
    if [[ -n "$picture_only_flag" ]]; then
        color_flag=""
        color=""
    fi

    # If type_flag is not set, get it from config
    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    # Validate type_flag (allow 'auto' as well)
    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" && -z "$picture_only_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
        imgpath="$(zenity --file-selection --filename="$PWD/" --title='Choose wallpaper')"
    fi

    # Settle on which file is actually going to be used before anything reads
    # it. This used to run after the scheme had already been worked out, so a
    # wallpaper with a matching -dark or -light sibling had its colours taken
    # from whichever one the caller happened to name rather than the one that
    # ends up on screen.
    # If mode_flag is dark or light, try to find a variant with that mode suffix
    if [[ "$mode_flag" == "dark" || "$mode_flag" == "light" ]]; then
        # Get directory, filename without extension, and extension
        local imgdir="$(dirname "$imgpath")"
        local imgbase="$(basename "$imgpath")"
        local imgname="${imgbase%.*}"
        local imgext="${imgbase##*.}"

        # Strip existing -dark or -light suffix
        local stripped_name="${imgname%-dark}"
        stripped_name="${stripped_name%-light}"

        # Construct the new path with the requested mode suffix
        local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
        local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

        # If the variant exists, use it
        if [[ -f "$new_imgpath" ]]; then
            imgpath="$new_imgpath"
        elif [[ -f "$new_stripped_imgpath" ]]; then
            imgpath="$new_stripped_imgpath"
        fi
    fi

    if [[ -n "$imgpath" && -z "$noswitch_flag" && -z "$picture_only_flag" ]]; then
        # Recorded rather than written here: the write happens next to the
        # wallpaper path so the two land together and the shell reads the file
        # once instead of twice.
        clear_accent_color=1
        color_flag=""
        color=""
    fi

    # A picture chosen on purpose is the end of a rotation. Kept apart from the
    # accent rule above so the rotation's own ticks, which do want the accent
    # cleared when they regenerate the palette, are not caught by it.
    if [[ -n "$imgpath" && -z "$noswitch_flag" && -z "$picture_only_flag" && -z "$keep_slideshow_flag" ]]; then
        stop_slideshow=1
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color"
}

main "$@"
