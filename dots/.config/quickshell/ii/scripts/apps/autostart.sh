#!/usr/bin/env bash
# autostart.sh — the apps that start when you log in, listed and switched.
#
# Starting an app at login is a desktop entry in an autostart directory, which
# systemd turns into a unit at the start of the session. Yours in
# ~/.config/autostart come first; a file there with the same name as one the
# system ships replaces it, which is how an app the system starts is switched
# off without root: a stub carrying Hidden=true stands in its place.
#
#   list                 one line per app: id, where it came from, on or off,
#                        name, icon, description
#   enable <id>          start it at login
#   disable <id>         stop starting it at login
#   add <desktop id>     start an installed app at login
#   remove <id>          drop an app that was added here
#
# A change lands in the session that follows: the units are built at login, so
# nothing here starts or stops an app that is already running.
set -uo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
USER_DIR="$XDG_CONFIG_HOME/autostart"
DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"

system_dirs() {
    local d
    local IFS=:
    for d in ${XDG_CONFIG_DIRS:-/etc/xdg}; do
        [ -n "$d" ] && printf '%s\n' "$d/autostart"
    done
}

app_dirs() {
    printf '%s\n' "$XDG_DATA_HOME/applications"
    local d
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        [ -n "$d" ] && printf '%s\n' "$d/applications"
    done
}

# Prints one desktop file's fields, always the same count. The separator is
# the unit separator rather than a tab, because a tab is whitespace and a
# reader splitting on whitespace swallows the empty fields between two of them,
# sliding every later value one column to the left.
read_entry() {
    awk -F= '
        /^\[/ { group = ($0 == "[Desktop Entry]") ; next }
        !group { next }
        {
            key = $1
            sub(/[ \t]+$/, "", key)
            value = substr($0, index($0, "=") + 1)
            sub(/^[ \t]+/, "", value)
            gsub(/[\t\037]/, " ", value)
            if (key == "Name" && name == "") name = value
            else if (key == "Icon" && icon == "") icon = value
            else if (key == "Comment" && comment == "") comment = value
            else if (key == "Exec" && exec == "") exec = value
            else if (key == "Hidden") hidden = value
            else if (key == "NoDisplay") nodisplay = value
            else if (key == "OnlyShowIn") onlyshowin = value
            else if (key == "NotShowIn") notshowin = value
            else if (key == "Type") type = value
        }
        END {
            printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n",
                name, icon, comment, exec, hidden, nodisplay,
                onlyshowin, notshowin, type
        }
    ' "$1" 2>/dev/null
}

# Whether a semicolon separated desktop list names the session we are in.
names_this_desktop() {
    local list="$1" item
    local IFS=';'
    for item in $list; do
        [ "$item" = "$DESKTOP" ] && return 0
    done
    return 1
}

find_app_file() {
    local id="$1" dir candidate
    while read -r dir; do
        [ -d "$dir" ] || continue
        candidate="$dir/$id.desktop"
        [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done < <(app_dirs)
    return 1
}

find_system_file() {
    local id="$1" dir candidate
    while read -r dir; do
        [ -d "$dir" ] || continue
        candidate="$dir/$id.desktop"
        [ -f "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done < <(system_dirs)
    return 1
}

reload_units() {
    # The generator reads the directories fresh, so the change shows up in the
    # unit list right away even though it takes hold at the next login.
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

cmd_list() {
    local dir file id seen=" "
    local u_name u_icon u_comment u_exec u_hidden u_nodisplay u_only u_not u_type
    local s_name s_icon s_comment s_exec s_hidden s_nodisplay s_only s_not s_type
    local system_file name icon comment source enabled

    # Yours first, then the system's, so a file of yours standing in for one of
    # theirs is the one that answers for the pair.
    {
        [ -d "$USER_DIR" ] && find "$USER_DIR" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null
        while read -r dir; do
            [ -d "$dir" ] || continue
            find "$dir" -maxdepth 1 -name '*.desktop' -type f 2>/dev/null
        done < <(system_dirs)
    } | while IFS= read -r file; do
        id="$(basename "$file" .desktop)"
        case "$seen" in *" $id "*) continue ;; esac
        seen="$seen$id "

        IFS=$'\037' read -r u_name u_icon u_comment u_exec u_hidden u_nodisplay u_only u_not u_type <<< "$(read_entry "$file")"

        # A stub of yours carries nothing but the switch, so the name, the icon
        # and the description come from the entry it stands in front of.
        system_file=""
        if [ "${file#"$USER_DIR"/}" != "$file" ]; then
            source=added
            system_file="$(find_system_file "$id" || true)"
            [ -n "$system_file" ] && source=system
        else
            source=system
            system_file="$file"
        fi

        s_name=""; s_icon=""; s_comment=""; s_exec=""
        s_hidden=""; s_nodisplay=""; s_only=""; s_not=""; s_type=""
        if [ -n "$system_file" ] && [ "$system_file" != "$file" ]; then
            IFS=$'\037' read -r s_name s_icon s_comment s_exec s_hidden s_nodisplay s_only s_not s_type <<< "$(read_entry "$system_file")"
        fi

        name="${u_name:-$s_name}"
        icon="${u_icon:-$s_icon}"
        comment="${u_comment:-$s_comment}"
        local type="${u_type:-$s_type}"
        local nodisplay="${u_nodisplay:-$s_nodisplay}"
        local exec="${u_exec:-$s_exec}"
        local only="${u_only:-$s_only}"
        local not="${u_not:-$s_not}"

        [ -n "$name" ] || continue
        [ -n "$exec" ] || continue
        [ -z "$type" ] || [ "$type" = "Application" ] || continue
        # The pieces that hold the desktop together are kept out of the list:
        # they say so themselves, and a switch beside them would only invite
        # someone to break their own session.
        [ "$nodisplay" = "true" ] && continue
        [ -n "$only" ] && ! names_this_desktop "$only" && continue
        [ -n "$not" ] && names_this_desktop "$not" && continue

        enabled=1
        [ "$u_hidden" = "true" ] && enabled=0

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$source" "$enabled" "$name" "$icon" "$comment"
    done
}

# Rewrites a file of yours with Hidden set the way it is asked for, keeping
# everything else the file says.
set_hidden() {
    local file="$1" value="$2" tmp
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    awk -v value="$value" '
        BEGIN { done = 0 }
        /^\[/ {
            if (group && !done) { print "Hidden=" value; done = 1 }
            group = ($0 == "[Desktop Entry]")
            print
            next
        }
        /^[ \t]*Hidden[ \t]*=/ {
            if (group) { print "Hidden=" value; done = 1; next }
        }
        { print }
        END { if (group && !done) print "Hidden=" value }
    ' "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

cmd_disable() {
    local id="${1:-}"
    [ -n "$id" ] || { echo "autostart.sh: disable needs an id" >&2; return 2; }
    local user_file="$USER_DIR/$id.desktop" system_file name
    mkdir -p "$USER_DIR"
    if [ -f "$user_file" ]; then
        set_hidden "$user_file" true || return 1
    else
        system_file="$(find_system_file "$id")" || { echo "autostart.sh: nothing named $id starts at login" >&2; return 1; }
        IFS=$'\037' read -r name _ _ _ _ _ _ _ _ <<< "$(read_entry "$system_file")"
        # A stub is enough to stand in front of the system's entry, and leaving
        # it at that keeps the system's own copy the thing being described.
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "${name:-$id}" > "$user_file"
    fi
    reload_units
}

cmd_enable() {
    local id="${1:-}"
    [ -n "$id" ] || { echo "autostart.sh: enable needs an id" >&2; return 2; }
    local user_file="$USER_DIR/$id.desktop" exec
    [ -f "$user_file" ] || { reload_units; return 0; }
    IFS=$'\037' read -r _ _ _ exec _ _ _ _ _ <<< "$(read_entry "$user_file")"
    if [ -z "$exec" ] && find_system_file "$id" >/dev/null; then
        # Nothing of yours to keep: the stub goes and the system's entry is
        # back in charge.
        rm -f "$user_file"
    else
        set_hidden "$user_file" false || return 1
    fi
    reload_units
}

cmd_add() {
    local id="${1:-}"
    [ -n "$id" ] || { echo "autostart.sh: add needs a desktop id" >&2; return 2; }
    id="${id%.desktop}"
    local source
    source="$(find_app_file "$id")" || { echo "autostart.sh: no app named $id" >&2; return 1; }
    mkdir -p "$USER_DIR"
    local target="$USER_DIR/$id.desktop"
    # The app's own entry travels across so its name and icon come with it.
    # What is dropped is everything that would keep it from starting: the
    # switch, the do-not-show flag, and the lists naming other desktops, since
    # this copy exists because it was asked for by name.
    grep -vE '^[ \t]*(Hidden|NoDisplay|OnlyShowIn|NotShowIn|X-GNOME-Autostart-enabled)[ \t]*=' "$source" > "$target" || return 1
    reload_units
}

cmd_remove() {
    local id="${1:-}"
    [ -n "$id" ] || { echo "autostart.sh: remove needs an id" >&2; return 2; }
    local user_file="$USER_DIR/$id.desktop"
    if find_system_file "$id" >/dev/null; then
        echo "autostart.sh: $id comes with the system and can only be switched off" >&2
        return 1
    fi
    rm -f "$user_file"
    reload_units
}

case "${1:-}" in
    list)    shift; cmd_list "$@" ;;
    enable)  shift; cmd_enable "$@" ;;
    disable) shift; cmd_disable "$@" ;;
    add)     shift; cmd_add "$@" ;;
    remove)  shift; cmd_remove "$@" ;;
    *)
        echo "usage: autostart.sh list|enable <id>|disable <id>|add <desktop id>|remove <id>" >&2
        exit 2
        ;;
esac
