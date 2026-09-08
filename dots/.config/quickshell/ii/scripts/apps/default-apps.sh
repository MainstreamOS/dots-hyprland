#!/usr/bin/env bash
# default-apps.sh — the app a role opens with, read and written in one place.
#
# A role is a job a person names rather than a MIME type they never see: the
# web browser, the file manager, the terminal. Each role owns the MIME types
# that make it real, so picking one app writes every type at once instead of
# leaving photos opening in one viewer and screenshots in another.
#
# Roles the keybinds launch (SUPER + B and friends) also get a file under
# hypr/custom/, which hyprland/variables.lua reads on every reload, so the key
# and the double click reach the same app.
#
#   roles                     one role per line: key, label, lua global
#   get                       one line per role: key, desktop id
#   candidates <role>         rank and desktop id, best fit first
#   set <role> <desktop id>   make it the default
set -uo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CUSTOM_DIR="${MAINSTREAM_APPS_CUSTOM_DIR:-$XDG_CONFIG_HOME/hypr/custom}"

# ── The roles ───────────────────────────────────────────────────────────────
# Each role names the Lua global its keybind reads (empty when no key launches
# it), the desktop categories and the one MIME type that identify an app able
# to do the job, and the MIME types a pick writes.
#
# The write lists are the same ones the installer seeds, so choosing an app
# here lands exactly where a fresh install would have put it.

role_lua() {
    case "$1" in
        browser)    echo browser ;;
        fileManager) echo fileManager ;;
        terminal)   echo terminal ;;
        textEditor) echo textEditor ;;
        codeEditor) echo codeEditor ;;
        *)          echo "" ;;
    esac
}

# Categories that say what an app is. An app that calls itself an image
# viewer is offered for photos ahead of a browser that merely knows how to
# display a PNG, which is what the two ranks below are for.
role_categories() {
    case "$1" in
        browser)     echo "WebBrowser" ;;
        email)       echo "Email" ;;
        fileManager) echo "FileManager" ;;
        terminal)    echo "TerminalEmulator" ;;
        textEditor)  echo "TextEditor" ;;
        codeEditor)  echo "IDE" ;;
        music)       echo "AudioPlayer Music Player" ;;
        video)       echo "Video" ;;
        photos)      echo "ImageViewer RasterGraphics 2DGraphics" ;;
        pdf)         echo "" ;;
        *)           echo "" ;;
    esac
}

# The types an app declares it can open. They stand in for a category an app
# never claimed, and they are the whole story for a role like PDF documents
# that no category describes.
role_probe_mimes() {
    case "$1" in
        browser)     echo "x-scheme-handler/http x-scheme-handler/https" ;;
        email)       echo "x-scheme-handler/mailto" ;;
        fileManager) echo "inode/directory" ;;
        terminal)    echo "" ;;
        textEditor)  echo "text/plain" ;;
        codeEditor)  echo "text/x-csrc text/x-python text/x-java" ;;
        music)       echo "audio/mpeg audio/flac" ;;
        video)       echo "video/mp4 video/x-matroska" ;;
        photos)      echo "image/png image/jpeg" ;;
        pdf)         echo "application/pdf" ;;
        *)           echo "" ;;
    esac
}

# The MIME type read back to say which app holds the role today. A role with
# none of its own (the terminal, the code editor) is remembered in its file
# under hypr/custom/ instead.
role_primary_mime() {
    case "$1" in
        browser)     echo "x-scheme-handler/https" ;;
        email)       echo "x-scheme-handler/mailto" ;;
        fileManager) echo "inode/directory" ;;
        textEditor)  echo "text/plain" ;;
        music)       echo "audio/mpeg" ;;
        video)       echo "video/mp4" ;;
        photos)      echo "image/png" ;;
        pdf)         echo "application/pdf" ;;
        *)           echo "" ;;
    esac
}

role_write_mimes() {
    case "$1" in
        browser)
            echo "x-scheme-handler/http x-scheme-handler/https text/html
                  application/xhtml+xml x-scheme-handler/about
                  x-scheme-handler/unknown"
            ;;
        email)
            echo "x-scheme-handler/mailto message/rfc822"
            ;;
        fileManager)
            echo "inode/directory"
            ;;
        textEditor)
            echo "text/plain text/markdown text/csv text/x-log text/x-readme
                  text/x-changelog text/x-copying text/x-makefile text/x-patch
                  text/x-diff text/x-qml text/xml application/xml
                  application/json"
            ;;
        music)
            echo "audio/mpeg audio/mp4 audio/flac audio/ogg audio/x-vorbis+ogg
                  audio/opus audio/x-opus+ogg audio/wav audio/x-wav
                  audio/aac audio/x-m4a audio/x-aiff audio/midi
                  audio/x-matroska audio/webm audio/x-ms-wma"
            ;;
        video)
            echo "video/3gp video/3gpp video/3gpp2 video/avi video/divx video/dv
                  video/fli video/flv video/mkv video/mp2t video/mp4 video/mp4v-es
                  video/mpeg video/msvideo video/ogg video/quicktime video/vnd.avi
                  video/vnd.divx video/vnd.mpegurl video/vnd.rn-realvideo video/webm
                  video/x-avi video/x-flc video/x-flic video/x-flv video/x-m4v
                  video/x-matroska video/x-mpeg2 video/x-mpeg3 video/x-ms-afs
                  video/x-ms-asf video/x-msvideo video/x-ms-wmv video/x-ms-wmx
                  video/x-ms-wvxvideo video/x-ogm video/x-ogm+ogg video/x-theora
                  video/x-theora+ogg application/x-matroska application/x-ogm
                  application/x-ogm-video application/vnd.rn-realmedia
                  application/vnd.rn-realmedia-vbr"
            ;;
        photos)
            echo "image/apng image/bmp image/gif image/jp2 image/jpeg image/png
                  image/qoi image/tiff image/vnd.microsoft.icon image/webp
                  image/x-dds image/x-exr image/x-portable-anymap
                  image/x-portable-bitmap image/x-portable-graymap
                  image/x-portable-pixmap image/x-qoi image/x-tga
                  image/x-win-bitmap image/x-xbitmap image/x-xpixmap
                  image/svg+xml image/svg+xml-compressed image/avif image/heic
                  image/jxl"
            ;;
        pdf)
            # The whole family the install hands to the document viewer, so
            # picking a different one here moves all of it rather than leaving
            # comics and DjVu behind on the old app.
            echo "application/pdf application/x-bzpdf application/x-gzpdf
                  application/x-xzpdf application/postscript
                  application/x-bzpostscript application/x-gzpostscript
                  image/x-eps application/x-dvi application/x-bzdvi
                  application/x-gzdvi image/vnd.djvu+multipage
                  application/oxps application/vnd.ms-xpsdocument
                  application/vnd.comicbook+zip application/vnd.comicbook-rar
                  application/x-cbz application/x-cbr application/x-cb7
                  application/x-cbt"
            ;;
        *)
            echo ""
            ;;
    esac
}

ROLE_KEYS="browser email fileManager terminal textEditor codeEditor music video photos pdf"

# ── Desktop entries ─────────────────────────────────────────────────────────
# Every applications directory, most specific first, the way the spec orders
# them: what the user installed outranks what the system ships.
app_dirs() {
    printf '%s\n' "$XDG_DATA_HOME/applications"
    local d
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        [ -n "$d" ] && printf '%s\n' "$d/applications"
    done
}

# Reads one desktop file's [Desktop Entry] group and prints the fields the
# picker needs. Values are printed even when empty so the column count never
# moves, separated by the unit separator rather than a tab: a tab is
# whitespace, and a reader splitting on whitespace swallows the empty fields
# between two of them and slides every later value one column left.
read_entry() {
    awk -F= '
        /^\[/ { group = ($0 == "[Desktop Entry]") ; next }
        !group { next }
        {
            key = $1
            sub(/[ \t]+$/, "", key)
            value = substr($0, index($0, "=") + 1)
            sub(/^[ \t]+/, "", value)
            if (key == "Name" && name == "") name = value
            else if (key == "Icon" && icon == "") icon = value
            else if (key == "Exec" && exec == "") exec = value
            else if (key == "Categories") categories = value
            else if (key == "MimeType") mimetypes = value
            else if (key == "NoDisplay") nodisplay = value
            else if (key == "Hidden") hidden = value
            else if (key == "Terminal") terminal = value
            else if (key == "Type") type = value
        }
        END {
            printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n",
                name, icon, exec, categories, mimetypes,
                nodisplay, hidden, terminal, type
        }
    ' "$1" 2>/dev/null
}

# The id a desktop file is known by: its path under the applications
# directory with the separators turned into dashes, per the spec.
entry_id() {
    local dir="$1" file="$2" rel
    rel="${file#"$dir"/}"
    rel="${rel%.desktop}"
    printf '%s\n' "${rel//\//-}"
}

find_entry_file() {
    local id="$1" dir candidate
    while read -r dir; do
        [ -d "$dir" ] || continue
        candidate="$dir/$id.desktop"
        [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done < <(app_dirs)
    # An id carrying dashes may be a file in a subdirectory.
    while read -r dir; do
        [ -d "$dir" ] || continue
        while IFS= read -r candidate; do
            [ "$(entry_id "$dir" "$candidate")" = "$id" ] && { printf '%s\n' "$candidate"; return 0; }
        done < <(find "$dir" -name '*.desktop' -type f 2>/dev/null)
    done < <(app_dirs)
    return 1
}

# The command a keybind runs: the Exec line with the placeholders the spec
# reserves for files and urls taken out, since a keybind opens the app with
# nothing in its hands.
exec_command() {
    local exec="$1"
    exec="${exec//%U/}"; exec="${exec//%u/}"
    exec="${exec//%F/}"; exec="${exec//%f/}"
    exec="${exec//%i/}"; exec="${exec//%c/}"
    exec="${exec//%k/}"; exec="${exec//%D/}"
    exec="${exec//%v/}"; exec="${exec//%m/}"
    exec="${exec//%%/%}"
    # Collapse the gaps the removals leave behind.
    exec="$(printf '%s\n' "$exec" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    printf '%s\n' "$exec"
}

list_contains() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_roles() {
    local key
    for key in $ROLE_KEYS; do
        printf '%s\t%s\n' "$key" "$(role_lua "$key")"
    done
}

# The app holding a role right now. The system answers for every role that
# owns MIME types; a role no type speaks for is remembered in its own file,
# and so is one whose app has not been chosen here yet.
role_current() {
    local key="$1" mime id file
    id=""
    mime="$(role_primary_mime "$key")"
    if [ -n "$mime" ]; then
        id="$(xdg-mime query default "$mime" 2>/dev/null | head -n 1)"
        id="${id%.desktop}"
    fi
    if [ -z "$id" ]; then
        file="$CUSTOM_DIR/apps.$key"
        [ -r "$file" ] && id="$(head -n 1 "$file" 2>/dev/null)"
    fi
    printf '%s\n' "$id"
}

cmd_get() {
    local key
    for key in $ROLE_KEYS; do
        printf '%s\t%s\n' "$key" "$(role_current "$key")"
    done
}

cmd_candidates() {
    local role="${1:-}" dir file id fields name categories mimetypes nodisplay hidden terminal type
    local -a cats probes
    [ -n "$role" ] || { echo "default-apps.sh: candidates needs a role" >&2; return 2; }
    read -r -a cats <<< "$(role_categories "$role")"
    read -r -a probes <<< "$(role_probe_mimes "$role")"

    local seen=" "
    # The app holding the role now leads the list, and leads it whether or not
    # it would pass the filters below.
    local current
    current="$(role_current "$role")"
    if [ -n "$current" ]; then
        seen="$seen$current "
        printf '0\t%s\n' "$current"
    fi

    while read -r dir; do
        [ -d "$dir" ] || continue
        while IFS= read -r file; do
            id="$(entry_id "$dir" "$file")"
            case "$seen" in *" $id "*) continue ;; esac
            seen="$seen$id "
            IFS=$'\037' read -r name _icon _exec categories mimetypes nodisplay hidden terminal type <<< "$(read_entry "$file")"
            [ -n "$name" ] || continue
            [ -z "$type" ] || [ "$type" = "Application" ] || continue
            [ "$hidden" = "true" ] && continue
            # Entries kept out of the menus are the url handlers apps install
            # beside themselves, not apps in their own right. The one exception
            # is the app already holding the role, emitted above whatever it
            # says about itself, so a choice can always be made again.
            [ "$nodisplay" = "true" ] && continue
            # An app that only runs inside a terminal window cannot be handed a
            # keybind or a double click without one, so it is not offered.
            [ "$terminal" = "true" ] && continue

            # 1 for an app that is the thing, 2 for one that can merely open
            # the files. The page shows the first kind first.
            local matched=0 want
            local IFS=';'
            # shellcheck disable=SC2206
            local -a have_cats=($categories)
            # shellcheck disable=SC2206
            local -a have_mimes=($mimetypes)
            unset IFS
            for want in "${cats[@]}"; do
                [ -n "$want" ] || continue
                list_contains "$want" "${have_cats[@]}" && { matched=1; break; }
            done
            if [ "$matched" -eq 0 ]; then
                for want in "${probes[@]}"; do
                    [ -n "$want" ] || continue
                    list_contains "$want" "${have_mimes[@]}" && { matched=2; break; }
                done
            fi
            [ "$matched" -eq 0 ] && continue
            printf '%s\t%s\n' "$matched" "$id"
        done < <(find "$dir" -name '*.desktop' -type f 2>/dev/null)
    done < <(app_dirs)
}

cmd_set() {
    local role="${1:-}" id="${2:-}"
    [ -n "$role" ] && [ -n "$id" ] || { echo "default-apps.sh: set needs a role and a desktop id" >&2; return 2; }
    id="${id%.desktop}"

    local file
    file="$(find_entry_file "$id")" || { echo "default-apps.sh: no desktop entry named $id" >&2; return 1; }

    local mimes lua rc=0
    read -r -a mimes <<< "$(role_write_mimes "$role" | tr -s '[:space:]' ' ')"
    if [ "${#mimes[@]}" -gt 0 ] && [ -n "${mimes[0]}" ]; then
        # One call per type: xdg-mime takes several, but a type it dislikes
        # would take the whole list down with it.
        local mime
        for mime in "${mimes[@]}"; do
            xdg-mime default "$id.desktop" "$mime" 2>/dev/null || rc=1
        done
    fi
    # The browser is the one role with a setting of its own, and desktops that
    # read that instead of the MIME list are the reason to write both.
    if [ "$role" = browser ]; then
        xdg-settings set default-web-browser "$id.desktop" 2>/dev/null || true
    fi

    lua="$(role_lua "$role")"
    if [ -n "$lua" ]; then
        local fields name exec command
        IFS=$'\037' read -r name _icon exec _categories _mimetypes _nodisplay _hidden _terminal _type <<< "$(read_entry "$file")"
        command="$(exec_command "$exec")"
        [ -n "$command" ] || { echo "default-apps.sh: $id has no command to run" >&2; return 1; }
        mkdir -p "$CUSTOM_DIR"
        # The id on the first line for the page to read back, the command on
        # the second for variables.lua, so one file answers both.
        printf '%s\n%s\n' "$id" "$command" > "$CUSTOM_DIR/apps.$role"
        # A run pointed at another custom directory is not talking to the
        # session on screen, so it leaves that session alone.
        [ -n "${MAINSTREAM_APPS_CUSTOM_DIR:-}" ] || hyprctl reload >/dev/null 2>&1 || true
    fi
    return "$rc"
}

case "${1:-}" in
    roles)      shift; cmd_roles "$@" ;;
    get)        shift; cmd_get "$@" ;;
    candidates) shift; cmd_candidates "$@" ;;
    set)        shift; cmd_set "$@" ;;
    *)
        echo "usage: default-apps.sh roles|get|candidates <role>|set <role> <desktop id>" >&2
        exit 2
        ;;
esac
