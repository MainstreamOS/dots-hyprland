#!/usr/bin/env bash
# Logs out, restarts, shuts down or switches to Gaming Mode the way a session
# manager does: the open windows are recorded for the next login, every app is
# asked to close so it can save its work or ask to, and the session only ends
# once they have gone. An app that stays open cancels the request, with a
# notification saying which, rather than the session ending under it or later,
# when it is closed.
#
#   end-session.sh logout|poweroff|reboot|firmware|gaming
#
# It runs apart from the shell, so a shell reload while apps are closing
# cannot drop the request.
set -uo pipefail

action="${1:-}"
case "$action" in
    logout)          summary_wait="Logging out";   summary_cancel="Log out canceled" ;;
    poweroff)        summary_wait="Shutting down"; summary_cancel="Shut down canceled" ;;
    reboot|firmware) summary_wait="Restarting";    summary_cancel="Restart canceled" ;;
    gaming)          summary_wait="Switching to Gaming Mode"; summary_cancel="Gaming Mode canceled" ;;
    *) echo "usage: end-session.sh logout|poweroff|reboot|firmware|gaming" >&2; exit 2 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
ENDING="$STATE_DIR/ending"
# Long enough to answer a "save changes?" question, short enough that a
# window that will never close does not leave the request hanging.
TIMEOUT=30

# A second click while the first is still closing apps asks for the same thing.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/mainstream-end-session.lock"
flock -n 9 || exit 0

# The windows as they are now, for the next login. Taken before anything
# closes, and waited for, since the session ending would cut it short.
bash "$DIR/snapshot.sh"

# The session watcher saves the desktop whenever a window closes, and apps
# closing one by one would otherwise be saved as a shrinking desktop over the
# snapshot just taken. It skips its saves while this file is fresh, so every
# way this run stops short of ending the session takes it away again.
mkdir -p "$STATE_DIR" && : > "$ENDING"
trap 'rm -f "$ENDING"' EXIT
trap 'exit 1' HUP INT TERM

windows_json="$(hyprctl clients -j 2>/dev/null)" || windows_json="[]"
want="$(jq -c '[.[].address]' <<<"$windows_json" 2>/dev/null)" || want="[]"

# An app with several windows is asked to quit once, as a whole. Closed one
# window at a time, a browser takes it as the person closing windows and
# remembers only the last, while the next login launches it once and counts on
# it to reopen the rest itself. A quit keeps them all. An app with a single
# window is closed through Hyprland, so it can ask about unsaved work first.
quit_pids=()
rest_pids=()
while IFS=$'\t' read -r how target pid; do
    if [[ "$how" == quit ]]; then
        [[ "$target" =~ ^[0-9]+$ ]] && kill -TERM "$target" 2>/dev/null && quit_pids+=("$target")
    elif [[ "$target" =~ ^0x[0-9a-fA-F]+$ ]]; then
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$target\" })" >/dev/null 2>&1
        [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] && rest_pids+=("$pid")
    fi
done < <(jq -r 'group_by(.pid)[]
    | if .[0].pid > 1 and length > 1 then "quit\t\(.[0].pid)"
      else .[] | "close\t\(.address)\t\(.pid)" end' <<<"$windows_json" 2>/dev/null)

# Whether any window asked to close is still open.
any_open() {
    hyprctl clients -j 2>/dev/null \
        | jq -e --argjson want "$want" 'any(.[]; .address as $a | $want | index($a))' >/dev/null 2>&1
}

# An app's name as its launcher shows it, from the desktop entry named after
# its window class or claiming it, so the message reads "Text Editor" rather
# than org.gnome.TextEditor.
app_name() {
    local class="$1" d f name="" IFS=:
    for d in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        f="$d/applications/$class.desktop"
        [[ -f "$f" ]] || f="$(grep -lsx "StartupWMClass=$class" "$d"/applications/*.desktop 2>/dev/null | head -n1)"
        [[ -n "$f" ]] && name="$(sed -n 's/^Name=//p' "$f" | head -n1)"
        [[ -n "$name" ]] && break
    done
    printf '%s' "${name:-${class##*.}}"
}

# The apps whose windows are still open, joined for a message.
open_names() {
    local class
    while IFS= read -r class; do
        app_name "$class"
        echo
    done < <(hyprctl clients -j 2>/dev/null | jq -r --argjson want "$want" '
        [.[] | select(.address as $a | $want | index($a))
             | (if (.class // "") != "" then .class else "app" end)]
        | unique | .[]' 2>/dev/null) | sort -u | paste -sd, | sed 's/,/, /g'
}

# Until none of the given processes is running, or the deadline (in SECONDS)
# comes first.
wait_gone() {
    local until="$1" pid
    shift
    for pid; do
        while kill -0 "$pid" 2>/dev/null; do
            (( SECONDS < until )) || return
            sleep 0.2
        done
    done
}

deadline=$((SECONDS + TIMEOUT))
notice_at=$((SECONDS + 3))
notice=""
while any_open; do
    if (( SECONDS >= deadline )); then
        replace=()
        [[ "$notice" =~ ^[0-9]+$ ]] && replace=(-r "$notice")
        notify-send "${replace[@]}" -a "Mainstream" "$summary_cancel" \
            "$(open_names) did not close. Save your work there, then try again." 2>/dev/null
        exit 1
    fi
    # Said only once closing takes long enough to notice, which is when an
    # app is most likely asking something.
    if [[ -z "$notice" ]] && (( SECONDS >= notice_at )); then
        notice="$(notify-send -p -a "Mainstream" "$summary_wait" \
            "Waiting for $(open_names) to close. If it is asking to save your work, answer it there." 2>/dev/null)" || notice="-"
    fi
    sleep 0.25
done

# A window going away is not the app being done: a browser is still writing
# down its tabs after its windows close, and the session ending under it
# makes it offer to recover them next time, the very thing closing apps
# first is for. The apps asked to quit get until the deadline. The rest get a
# moment, since an app that keeps running in the tray after its window closes
# would otherwise hold everything up.
wait_gone "$deadline" "${quit_pids[@]}"
wait_gone $((SECONDS + 3)) "${rest_pids[@]}"

# From here the session ends, and the watcher has to stay quiet while it does,
# so the file outlasts this run unless ending the session fails.
trap - EXIT
case "$action" in
    # Hyprland's own exit, rather than killing it, runs the shutdown hook that
    # stops the session's systemd target. Left running across a log out, the
    # next login finds it already up and starts none of the apps set to open
    # at login, such as a VPN whose kill switch then holds the network closed.
    logout)   hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || pkill -i Hyprland ;;
    poweroff) systemctl poweroff || loginctl poweroff ;;
    reboot)   systemctl reboot || loginctl reboot ;;
    firmware) systemctl reboot --firmware-setup || loginctl reboot --firmware-setup ;;
    # The gamescope session reuses this user manager, so the desktop's
    # displays leave it only now that the switch is going ahead, and come
    # back if the switch is refused.
    gaming)   systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY 2>/dev/null
              sudo -n /usr/bin/gaming-mode-switch gaming || {
                  systemctl --user import-environment WAYLAND_DISPLAY DISPLAY 2>/dev/null
                  notify-send -a "Mainstream" "$summary_cancel" "Couldn't switch sessions. A system update may be needed." 2>/dev/null
                  false; } ;;
esac || rm -f "$ENDING"
