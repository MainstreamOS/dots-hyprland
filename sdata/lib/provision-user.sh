#!/usr/bin/env bash
# provision-user.sh — everything a Mainstream account needs before its owner
# first logs in. Sourced, never executed.
#
# Installed to /usr/local/lib/mainstream-provision-user.sh.
#
# One implementation, two callers: the installer runs it for the account
# Calamares creates, and /usr/local/bin/user-manager runs it for an account
# made later from Settings. They used to be separate, and the Settings copy
# drifted until a new user got a desktop the installer would never have
# produced.
#
# What it deliberately does NOT do is copy anything out of another user's
# home. useradd -m seeds the new home from /etc/skel, and the running release
# is then laid over it from this machine's dotfiles clone. Copying a live home
# instead would hand the new user someone else's wallpaper and, worse, someone
# else's already-consumed first-login trigger.
#
# Set PROVISION_CJK_IME before calling to lay down the input-method glue; the
# installer does this when the chosen locale needs it.

# Everything provisioning does lands here, because the account being built is
# not the account that can watch it happen: by the time anyone notices a new
# user cannot log in, the session is gone and so is its journal. One file,
# appended to, readable afterwards.
PROVISION_LOG=/var/log/mainstream/user-provision.log

_pu_log() {
    local line
    printf -v line '%s [%s] %s' "$(date '+%Y-%m-%d %H:%M:%S')" "${PROVISION_STEP:-provision}" "$*"
    mkdir -p "$(dirname "$PROVISION_LOG")" 2>/dev/null || true
    printf '%s\n' "$line" >> "$PROVISION_LOG" 2>/dev/null || true
    printf '%s\n' "$line" >&2
}

_pu_warn() {
    _pu_log "WARN: $*"
    # A host that has its own way of reporting hears about this as well. The
    # installer's warn appends to the install health manifest its self-check
    # reads afterwards, and a step that could not finish has to stay visible
    # there rather than only in this file.
    declare -F warn >/dev/null 2>&1 && warn "$*"
    return 0
}


# Runs a step, records how long it took and whether it worked, and never lets
# one failed step abort the rest: a home missing its font cache is worth
# finishing, and the log says what was skipped.
_pu_step() {  # $1 = label, rest = command
    local label="$1"; shift
    local start rc
    start=$(date +%s)
    PROVISION_STEP="$label"
    _pu_log "start"
    if "$@"; then rc=0; else rc=$?; fi
    local took=$(( $(date +%s) - start ))
    if [[ $rc -eq 0 ]]; then _pu_log "ok in ${took}s"
    else _pu_warn "FAILED rc=$rc after ${took}s"; PROVISION_FAILED+=" $label"; fi
    PROVISION_STEP=""
    return 0
}

# Steps whose failure leaves an account that should not be handed to anyone:
# without them the home is not the user's, has no desktop config, or will
# never run its first-login setup. A missing virtualenv or plugin is repaired
# on first login instead, so neither is grounds for refusing the account.
PROVISION_REQUIRED_STEPS="groups desktop own firstrun"

provision_home_of() {  # $1 = user
    getent passwd "$1" | cut -d: -f6
}

# The per-machine parts of a home: built rather than copied. The virtualenv
# records absolute paths, the plugin binaries carry a build stamp good for one
# compositor version, and the greeted marker decides whether the welcome
# screen appears. build.sh leaves the same set out when it seeds the image.
PROVISION_SKEL_EXCLUDES=(
    '/.bash_profile'
    '/.bashrc'
    '/.bash_logout'
    '/.zshrc'
    '/.profile'
    '/.config/gtk-3.0/settings.ini'
    '/.config/gtk-4.0/settings.ini'
    '/.local/share/hyprland/plugins/'
    '/.local/share/icons/hicolor/scalable/apps/auto-drive-mount.svg'
    '/.local/share/quickshell/sdata/uv/'
    '/.local/state/quickshell/.venv/'
    '/.local/state/quickshell/user/first_run.txt'
)

# The clone of the release this machine is actually running. updatems keeps it
# current, and it is the same tree the installer lays down, so it answers
# "what would a fresh install of this version give you" better than skel can:
# skel is only a snapshot of it taken on the day the machine was installed.
# Root reads this tree and copies it into somebody's home, so it has to come
# from an account that could already change the system. A clone sitting in a
# standard user's home is not that, and a symlink or a tree others can write
# is how a checkout that looks like a release turns into something else on the
# way in.
_pu_trusted_dir() {  # $1 = directory
    local d="$1" owner
    [[ -d "$d" && ! -L "$d" ]] || return 1
    owner="$(stat -c %U "$d" 2>/dev/null)" || return 1
    if [[ "$owner" != root ]]; then
        id -nG "$owner" 2>/dev/null | tr ' ' '\n' | grep -qx wheel || return 1
    fi
    [[ $(( 8#$(stat -c %a "$d" 2>/dev/null || echo 777) & 8#022 )) -eq 0 ]]
}

_pu_clone_usable() {  # $1 = clone directory
    [[ -f "$1/dots/.config/quickshell/ii/shell.qml" ]] && _pu_trusted_dir "$1"
}

provision_dots_dir() {
    local d best="" caller="" caller_clone=""
    if [[ -n "${MAINSTREAM_DOTS_DIR:-}" ]]; then
        if [[ -f "$MAINSTREAM_DOTS_DIR/.config/quickshell/ii/shell.qml" ]] \
           && _pu_trusted_dir "$MAINSTREAM_DOTS_DIR"; then
            printf '%s\n' "$MAINSTREAM_DOTS_DIR"
            return 0
        fi
        _pu_warn "MAINSTREAM_DOTS_DIR is not a usable dotfiles tree, ignoring it"
    fi

    # The administrator who asked for this comes first. Theirs is the clone
    # this machine has been updating from, and naming it makes the answer the
    # same every time instead of whichever home happens to sort first.
    caller="$(id -un "${PKEXEC_UID:-}" 2>/dev/null || true)"
    if [[ -n "$caller" ]]; then
        caller_clone="$(getent passwd "$caller" | cut -d: -f6)/.cache/dots-hyprland"
        if _pu_clone_usable "$caller_clone"; then
            printf '%s\n' "$caller_clone/dots"
            return 0
        fi
    fi

    for d in /root/.cache/dots-hyprland /home/*/.cache/dots-hyprland; do
        _pu_clone_usable "$d" || continue
        [[ -z "$best" || "$d/.git" -nt "$best/.git" ]] && best="$d"
    done
    [[ -n "$best" ]] || return 1
    printf '%s\n' "$best/dots"
}

# A home seeded from skel is only as current as the day the machine was
# installed: an older bar layout, plugins built for a compositor that has since
# moved on, and none of the fixes in between. Laying the running release over
# it means someone added today gets today's desktop on a machine of any age.
#
# Only for an account whose owner has never finished a first login. Over a home
# in use this would overwrite the settings its owner had chosen.
# Whether anyone has ever opened a session as this account. A repair run must
# not lay the release over a home in use, and when the answer cannot be read
# the cautious reading is the one that leaves the home alone.
provision_has_logged_in() {  # $1 = user
    local row
    if command -v lastlog2 >/dev/null 2>&1; then
        # lastlog2 prints a row for the account either way, and says so in
        # words, so the row's presence answers nothing: only its content does.
        row="$(lastlog2 -u "$1" 2>/dev/null | awk -v u="$1" '$1 == u')"
        [[ -n "$row" ]] || return 1
        [[ "$row" == *"Never logged in"* ]] && return 1
        return 0
    fi
    if command -v last >/dev/null 2>&1; then
        # Compared as a whole field rather than matched as a pattern, since a
        # login name may end in the dollar sign useradd allows.
        last -w -n1 "$1" 2>/dev/null | awk -v u="$1" '$1 == u {found=1} END {exit !found}' && return 0
        return 1
    fi
    return 0
}

provision_dotfiles() {  # $1 = user  $2 = "fresh" when the account was just created
    local u="$1" fresh="${2:-}" home src ex args=()
    home="$(provision_home_of "$u")"
    # Checked in every step that writes under it rather than trusted from the
    # one that looked first: an empty answer aims this at the filesystem root,
    # and this step would then mirror a tree over it with deletions on.
    [[ -n "$home" && -d "$home" && "$home" != "/" ]] || { _pu_warn "no home for $u"; return 1; }
    if [[ "$fresh" != fresh && "${PROVISION_FORCE_DOTFILES:-0}" != 1 ]] \
       && provision_has_logged_in "$u"; then
        _pu_log "$u has been logged into; leaving its settings alone"
        return 0
    fi
    command -v rsync >/dev/null 2>&1 || { _pu_warn "rsync is missing; the home stays as skel left it"; return 0; }
    if ! src="$(provision_dots_dir)"; then
        _pu_warn "no dotfiles clone on this machine; the home stays as skel left it"
        return 0
    fi
    for ex in "${PROVISION_SKEL_EXCLUDES[@]}"; do args+=( --exclude="$ex" ); done

    # A home that useradd seeded moments ago holds nothing but skel's copy of
    # it, so a file skel has and the release does not is stale rather than the
    # owner's, and deleting it is what makes the account match the release
    # exactly. Excluded paths are protected from the delete, which is what
    # keeps the virtualenv and the plugin binaries. Any other home keeps
    # everything it has.
    if [[ "$fresh" == fresh ]] && ! provision_has_logged_in "$u"; then
        args+=( --delete )
        _pu_log "new account, so anything skel left behind goes too"
    fi

    _pu_log "laying $src over $home"
    # The file list goes nowhere: a delete that stops at an excluded path says
    # so on stdout, which is expected here and is not worth the noise. Real
    # trouble still arrives on stderr and in the exit code.
    rsync -a "${args[@]}" "$src/" "$home/" >/dev/null || { _pu_warn "could not lay the dotfiles over $home"; return 1; }
    chown -R "$u:$u" "$home"

    # skel is what the next account is seeded from, so bring it along rather
    # than leaving the next user to land in the same place.
    if rsync -a --delete "${args[@]}" "$src/" /etc/skel/ >/dev/null 2>&1; then
        chown -R root:root /etc/skel 2>/dev/null || true
        _pu_log "/etc/skel refreshed to match"
    else
        _pu_warn "could not refresh /etc/skel"
    fi
}

# Groups the desktop cannot work without: video and render for the GPU, i2c
# for external-monitor brightness over DDC/CI, input for the virtual input
# devices, and the rest for sound, networking, printing and removable media.
# wheel is not among them, because being an administrator is a choice someone
# makes about an account rather than part of setting one up.
provision_groups() {  # $1 = user
    local u="$1" g
    id "$u" >/dev/null 2>&1 || { _pu_warn "no such user: $u"; return 1; }
    for g in render video i2c; do groupadd -f "$g"; done
    for g in network audio video input power storage lp optical render i2c; do
        getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$u" || true
    done
    # Administrator is the caller's decision, not a consequence of being set
    # up: granting it here would make the Accounts page's own switch mean
    # nothing and would quietly promote a standard account on every repair.
    # The installer's first account sets PROVISION_ADMIN; Settings uses the
    # set-admin subcommand.
    if [[ "${PROVISION_ADMIN:-0}" == 1 ]] && getent group wheel >/dev/null 2>&1; then
        usermod -aG wheel "$u" || true
        _pu_log "granted administrator"
    fi
    # ddcutil reaches an external monitor's brightness over the DDC/CI bus,
    # which needs the i2c-dev module present from boot.
    echo i2c-dev > /etc/modules-load.d/i2c-dev.conf
    if [[ -x /usr/bin/zsh ]]; then
        _pu_log "Setting default shell to Zsh for $u..."
        chsh -s /usr/bin/zsh "$u" >/dev/null 2>&1 || _pu_warn "could not change the shell for $u"
    fi
}

# A virtualenv records absolute paths through its bin/ scripts and
# pyvenv.cfg, and skel's carries a placeholder rather than any real home, so
# it has to be rewritten per account. uv puts that path on line 2 of a
# console script, which is why this cannot be anchored to the shebang.
provision_venv() {  # $1 = user
    local u="$1" home venv target_ver baked_ver
    home="$(provision_home_of "$u")"
    [[ -n "$home" && -d "$home" && "$home" != "/" ]] || { _pu_warn "no home for $u"; return 1; }
    venv="$home/.local/state/quickshell/.venv"
    [[ -d "$venv" ]] || return 0

    if [[ -r /usr/local/lib/mainstream-venv-common.sh ]]; then
        # shellcheck source=/dev/null
        source /usr/local/lib/mainstream-venv-common.sh
        repair_venv_paths "$venv"
    fi

    # A venv built against a Python that has since moved on cannot be
    # repaired by rewriting paths, so it is thrown away and first-login
    # rebuilds it rather than leaving a subtly broken one in place.
    target_ver="$(/usr/bin/python3.12 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
    baked_ver="$(cat "$venv/.python-version" 2>/dev/null || true)"
    # An interpreter that is not there at all is the other way this venv goes
    # stale, and it reads as an empty version rather than a different one.
    if [[ -z "$target_ver" ]]; then
        _pu_warn "venv: /usr/bin/python3.12 is missing, rebuilding $venv from the system python"
        rm -rf "$venv"
        return 0
    elif [[ -n "$baked_ver" && "$baked_ver" != "$target_ver" ]]; then
        rm -rf "$venv"
        return 0
    fi
    chown -R "$u:$u" "$venv"
}

# Two gates stand between a new account and a themed desktop. first_run.txt
# ships inside skel already written, which tells the shell it has greeted
# this user; removing it lets the shell generate colors on its own if the
# script below never runs. The marker is what dotfiles-first-login checks
# before it will do anything at all.
provision_first_run() {  # $1 = user
    local u="$1" home
    home="$(provision_home_of "$u")"
    [[ -n "$home" && -d "$home" && "$home" != "/" ]] || { _pu_warn "no home for $u"; return 1; }
    # Only an account that has never logged in gets the marker. Re-arming it on
    # an established home makes the next login run first-login setup again,
    # which ends by deleting the dotfiles directory it thinks it created, and
    # that is $HOME/dots-hyprland for anyone who followed upstream's README.
    if provision_has_logged_in "$u"; then
        _pu_log "first run: $u has logged in before, leaving the marker alone"
        return 0
    fi
    rm -f "$home/.local/state/quickshell/user/first_run.txt"
    touch "$home/.dotfiles-pending-user-setup"
    chown "$u:$u" "$home/.dotfiles-pending-user-setup"
}

# Hyprland refuses a plugin whose .builtfor stamp does not name the Hyprland
# it is loading into, and an unstamped .so counts as unknown provenance. A home
# seeded from a skel older than the installed compositor therefore gets plugins
# that stop the session starting at all, which presents as being bounced back
# to the login screen with nothing to read.
#
# A matching pair is copied from an account that already has one. Where none
# exists the plugin is removed rather than left in place: a desktop without
# title bars is a far better outcome than an account nobody can log in to.
provision_plugins() {  # $1 = user
    local u="$1" home want dir so stamp src found unit
    home="$(provision_home_of "$u")"
    [[ -n "$home" && -d "$home" && "$home" != "/" ]] || { _pu_warn "no home for $u"; return 1; }
    dir="$home/.local/share/hyprland/plugins"
    [[ -d "$dir" ]] || { _pu_log "no plugin directory, nothing to check"; return 0; }

    # Judged exactly the way plugins.lua judges it at login: the first line of
    # each file, from the same version file the guard reads. A stamp carries
    # the source commit on its second line, so comparing whole files never
    # matches and every plugin looks stale.
    want="$(head -n1 /var/lib/hyprland-plugins/hyprland-version 2>/dev/null || true)"
    [[ -n "$want" ]] || want="$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')"
    if [[ -z "$want" ]]; then
        _pu_log "no recorded hyprland version, leaving plugins alone"
        return 0
    fi
    _pu_log "hyprland is $want"

    for so in "$dir"/*.so; do
        [[ -e "$so" ]] || continue
        stamp="$(head -n1 "$so.builtfor" 2>/dev/null || true)"
        if [[ "$stamp" == "$want" ]]; then
            _pu_log "$(basename "$so"): stamped $stamp, keeping"
            continue
        fi
        _pu_log "$(basename "$so"): stamp is ${stamp:-absent}, wanted $want"
        found=""
        local caller caller_home
        caller="$(id -un "${PKEXEC_UID:-}" 2>/dev/null || true)"
        caller_home="${caller:+$(provision_home_of "$caller")}"
        # The administrator's own build first, so the new account runs the
        # plugin this machine is actually running rather than whichever home
        # sorts first with a matching version.
        for src in ${caller_home:+"$caller_home/.local/share/hyprland/plugins/$(basename "$so")"} \
                   /home/*/.local/share/hyprland/plugins/"$(basename "$so")"; do
            [[ -e "$src" ]] || continue
            [[ "$(head -n1 "$src.builtfor" 2>/dev/null || true)" == "$want" ]] || continue
            found="$src"; break
        done
        if [[ -n "$found" ]]; then
            install -Dm755 -o "$u" -g "$u" "$found"            "$so"
            install -Dm644 -o "$u" -g "$u" "$found.builtfor"   "$so.builtfor"
            _pu_log "$(basename "$so"): replaced from $found"
        else
            rm -f "$so" "$so.builtfor"
            _pu_log "$(basename "$so"): no matching build anywhere, removed so the session can start"
            # Nobody on this machine has a usable copy, so ask the rebuild that
            # owns this plugin to run now rather than leaving the account
            # without it until the timer's next daily tick. Started without
            # blocking, because that rebuild clones and compiles and an account
            # should not be held open for minutes waiting on it.
            unit="$(basename "$so" .so)-rebuild.service"
            if command -v systemctl >/dev/null 2>&1 && systemctl cat "$unit" >/dev/null 2>&1; then
                systemctl start --no-block "$unit" 2>/dev/null \
                    && _pu_log "$unit asked to rebuild it" \
                    || _pu_warn "could not ask $unit to run"
            fi
        fi
    done
}

provision_desktop() {  # $1 = user
    local u="$1" home
    home="$(provision_home_of "$u")"
    [[ -n "$home" && -d "$home" && "$home" != "/" ]] || { _pu_warn "no home for $u"; return 1; }
    # Everything below is declared here because this file is sourced into
    # other scripts: a name left global would reach into whatever sourced it.
    local _cjk_ime="${PROVISION_CJK_IME:-}" _kb=""
    local _ime_env _ime_execs _ime_profile _ime_layout _gtkv _gtkini mime
    local EXECS_LUA SYSTEMD_USER_DIR AUTOSTART_DIR
    local IMAGE_TYPES VIDEO_TYPES AUDIO_TYPES TEXT_TYPES WEB_TYPES DOCUMENT_TYPES
    local _lang

    # The console keymap, read here rather than passed in: the variable that
    # used to carry it belonged to the installer.
    _kb="$(grep -oP 'XkbLayout"?\s+"\K[^"]+' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null | head -1 || true)"
    [[ -n "$_kb" ]] || _kb="$(grep -oP '^KEYMAP=\K.*' /etc/vconsole.conf 2>/dev/null | tr -d '"' | head -1 || true)"

    # Worked out from the machine when the caller did not say. The installer
    # names the engine it chose for the first account; nothing else knew to,
    # so a second account on a Japanese, Korean or Chinese machine was left
    # unable to type its own language while the first one could.
    if [[ -z "$_cjk_ime" ]]; then
        _lang="$(grep -oP '^LANG=\K.*' /etc/locale.conf 2>/dev/null | tr -d '"')"
        case "$_lang" in
            ja_*) _cjk_ime=mozc ;;
            ko_*) _cjk_ime=hangul ;;
            zh_*) _cjk_ime=pinyin ;;
        esac
        [[ -n "$_cjk_ime" ]] || case "$_kb" in
            jp*) _cjk_ime=mozc ;;
            kr*) _cjk_ime=hangul ;;
            cn*) _cjk_ime=pinyin ;;
        esac
    fi
    # An install that does not use CJK has had the whole stack removed, so
    # there is nothing for this to configure.
    if [[ -n "$_cjk_ime" ]] && ! command -v fcitx5 >/dev/null 2>&1; then
        _pu_log "no fcitx5 on this machine, leaving the $_cjk_ime input method alone"
        _cjk_ime=""
    fi

# The CJK input method chosen above only helps if the session loads it.
# Env vars follow the fcitx5 Wayland guidance: no GTK_IM_MODULE, since
# GTK talks text-input-v3 natively and the module causes the blinking
# candidate window; X11 GTK apps get the module through settings.ini.
# GLFW speaks only the ibus protocol, which fcitx5 serves, and the
# wrong value there is a documented way to break input entirely.
if [[ -n "$_cjk_ime" ]]; then
    _pu_log "Configuring the $_cjk_ime input method for $u..."
    _ime_env="$home/.config/hypr/custom/env.lua"
    if [[ -f "$_ime_env" ]] && ! grep -q 'im=fcitx' "$_ime_env"; then
        cat >> "$_ime_env" << 'IMEENVEOF'
hl.env({ name = "XMODIFIERS", value = "@im=fcitx" })
hl.env({ name = "QT_IM_MODULE", value = "fcitx" })
hl.env({ name = "QT_IM_MODULES", value = "wayland;fcitx" })
hl.env({ name = "SDL_IM_MODULE", value = "fcitx" })
hl.env({ name = "GLFW_IM_MODULE", value = "ibus" })
IMEENVEOF
        chown "$u:$u" "$_ime_env"
    fi
    _ime_execs="$home/.config/hypr/custom/execs.lua"
    if [[ -f "$_ime_execs" ]] && ! grep -q 'fcitx5' "$_ime_execs"; then
        echo 'hl.on("hyprland.start", function() hl.exec_cmd("fcitx5 -d") end)' >> "$_ime_execs"
        chown "$u:$u" "$_ime_execs"
    fi
    for _gtkv in gtk-3.0 gtk-4.0; do
        _gtkini="$home/.config/$_gtkv/settings.ini"
        if [[ -f "$_gtkini" ]]; then
            grep -q '^gtk-im-module=' "$_gtkini" || sed -i '/^\[Settings\]/a gtk-im-module=fcitx' "$_gtkini"
        else
            printf '[Settings]\ngtk-im-module=fcitx\n' > "$_gtkini"
        fi
        chown "$u:$u" "$_gtkini"
    done
    # A profile with the engine already in the group is the difference
    # between typing at first boot and a trip through the config tool.
    _ime_profile="$home/.config/fcitx5/profile"
    _ime_layout=us
    case "$_kb" in jp*) _ime_layout=jp ;; kr*) _ime_layout=kr ;; esac
    if [[ ! -f "$_ime_profile" ]]; then
        install -d -o "$u" -g "$u" "$home/.config/fcitx5"
        cat > "$_ime_profile" << IMEPROFEOF
[Groups/0]
Name=Default
Default Layout=$_ime_layout
DefaultIM=$_cjk_ime

[Groups/0/Items/0]
Name=keyboard-$_ime_layout
Layout=

[Groups/0/Items/1]
Name=$_cjk_ime
Layout=

[GroupOrder]
0=Default
IMEPROFEOF
        chown "$u:$u" "$_ime_profile"
    fi
fi

# Add hyprpolkitagent autostart if not already present in dotfiles
EXECS_LUA="$home/.config/hypr/custom/execs.lua"
if [[ -f "$EXECS_LUA" ]] && ! grep -q "hyprpolkitagent" "$EXECS_LUA"; then
    _pu_log "Adding hyprpolkitagent to Hyprland autostart..."
    echo 'hl.on("hyprland.start", function() hl.exec_cmd("hyprpolkitagent") end)' >> "$EXECS_LUA"
elif [[ ! -f "$EXECS_LUA" ]]; then
    _pu_warn "Could not find $EXECS_LUA — hyprpolkitagent will not autostart."
fi

# ---------------------------------------------------------------------------
# Deploy dotfiles-first-login using Hyprland + user systemd.
# XDG autostart depends on a session helper being present and running; the
# one thing we know the installed desktop will parse is Hyprland's exec-once.
# Hyprland starts the user service so the setup has journal visibility, and
# falls back to the script directly if the user systemd manager is not ready.
# ---------------------------------------------------------------------------
if [[ -f /usr/local/bin/dotfiles-first-login ]]; then
    _pu_log "Deploying dotfiles-first-login first-session triggers..."
    SYSTEMD_USER_DIR="$home/.config/systemd/user"
    mkdir -p "$SYSTEMD_USER_DIR"
    cat > "$SYSTEMD_USER_DIR/dotfiles-first-login.service" << 'SERVICEEOF'
[Unit]
Description=Dotfiles first graphical login setup
Documentation=man:systemd.service(5)
ConditionPathExists=%h/.dotfiles-pending-user-setup
After=graphical-session.target

[Service]
Type=oneshot
KillMode=process
Environment=DOTFILES_FIRST_LOGIN_FOREGROUND=1
ExecStart=/usr/local/bin/dotfiles-first-login
SERVICEEOF
    chown -R "$u:$u" "$SYSTEMD_USER_DIR"

    EXECS_LUA="$home/.config/hypr/custom/execs.lua"
    mkdir -p "$(dirname "$EXECS_LUA")"
    touch "$EXECS_LUA"
    sed -i \
        -e '\|dotfiles-first-login.service|d' \
        -e '\|/usr/local/bin/dotfiles-first-login|d' \
        "$EXECS_LUA" 2>/dev/null || true
    cat >> "$EXECS_LUA" << 'EXECSEOF'
hl.on("hyprland.start", function() hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user start dotfiles-first-login.service || /usr/local/bin/dotfiles-first-login") end)
EXECSEOF
    chown "$u:$u" "$EXECS_LUA"

    # Keep an XDG autostart entry as a harmless backup for sessions that do
    # run an autostart helper.
    AUTOSTART_DIR="$home/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/dotfiles-first-login.desktop" << 'AUTOSTARTEOF'
[Desktop Entry]
Type=Application
Name=Dotfiles First-Login Setup
Exec=sh -c 'dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE && systemctl --user start dotfiles-first-login.service || /usr/local/bin/dotfiles-first-login'
X-GNOME-Autostart-enabled=true
NoDisplay=true
AUTOSTARTEOF
    chown -R "$u:$u" "$AUTOSTART_DIR"
else
    _pu_warn "dotfiles-first-login not found in /usr/local/bin — skipping first-session trigger deploy."
fi

# ---------------------------------------------------------------------------
# Fix Nautilus home directory and set as default file manager
# ---------------------------------------------------------------------------
_pu_log "Configuring Nautilus as default file manager..."

# Generate XDG user directories (creates ~/Downloads, ~/Documents etc.)
# Run as the real user so paths resolve correctly
su -s /bin/bash "$u" -c "xdg-user-dirs-update --force" || true

# Set Nautilus as default file manager
su -s /bin/bash "$u" -c "xdg-mime default org.gnome.Nautilus.desktop inode/directory" || true

# Set Loupe as default image viewer for all common image types.
# xdg-mime takes a list, and one call per type meant a hundred-odd forks of su,
# a login shell and xdg-mime's own shell-outs for every account created.
IMAGE_TYPES=(
    image/png image/jpeg image/gif image/bmp image/webp image/tiff
    image/svg+xml image/svg+xml-compressed image/x-icon image/vnd.microsoft.icon
    image/avif image/heif image/heic image/jxl
)
su -s /bin/bash "$u" -c "xdg-mime default org.gnome.Loupe.desktop ${IMAGE_TYPES[*]}" || true
_pu_log "Loupe set as default image viewer."

# Set mpv as default video player for all the video types it handles
VIDEO_TYPES=(
    video/3gp video/3gpp video/3gpp2 video/avi video/divx video/dv
    video/fli video/flv video/mkv video/mp2t video/mp4 video/mp4v-es
    video/mpeg video/msvideo video/ogg video/quicktime video/vnd.avi
    video/vnd.divx video/vnd.mpegurl video/vnd.rn-realvideo video/webm
    video/x-avi video/x-flc video/x-flic video/x-flv video/x-m4v
    video/x-matroska video/x-mpeg2 video/x-mpeg3 video/x-ms-afs
    video/x-ms-asf video/x-msvideo video/x-ms-wmv video/x-ms-wmx
    video/x-ms-wvxvideo video/x-ogm video/x-ogm+ogg video/x-theora
    video/x-theora+ogg
    application/x-matroska application/x-ogm application/x-ogm-video
    application/vnd.rn-realmedia application/vnd.rn-realmedia-vbr
)
su -s /bin/bash "$u" -c "xdg-mime default mpv.desktop ${VIDEO_TYPES[*]}" || true
_pu_log "mpv set as default video player."

# Audio too. Left unset the type falls to whatever desktop entry claims it,
# which on a machine with Spotify installed is a streaming client being
# handed a local file it cannot really play.
AUDIO_TYPES=(
    audio/aac audio/ac3 audio/flac audio/mp4 audio/mpeg audio/ogg
    audio/opus audio/vorbis audio/wav audio/webm audio/x-aac audio/x-aiff
    audio/x-ape audio/x-flac audio/x-m4a audio/x-matroska audio/x-mp3
    audio/x-mpeg audio/x-ms-wma audio/x-musepack audio/x-opus+ogg
    audio/x-scpls audio/x-vorbis+ogg audio/x-wav audio/x-wavpack
)
su -s /bin/bash "$u" -c "xdg-mime default mpv.desktop ${AUDIO_TYPES[*]}" || true
_pu_log "mpv set as default audio player."

# The setup run has always done this one and the installed system never did,
# so a text file opened in whatever had claimed it.
TEXT_TYPES=(
    text/plain text/markdown text/csv text/x-log text/x-readme
    text/x-changelog text/x-copying text/x-makefile text/x-patch
    text/x-diff text/x-qml text/xml application/xml application/json
)
su -s /bin/bash "$u" -c "xdg-mime default org.gnome.TextEditor.desktop ${TEXT_TYPES[*]}" || true
_pu_log "GNOME Text Editor set as default text editor."

# Nothing set a browser on either install path, so https and mailto went to
# whichever entry registered them first, and whatever browser that was
# became the mail client too.
WEB_TYPES=(
    x-scheme-handler/http x-scheme-handler/https
    text/html application/xhtml+xml
)
su -s /bin/bash "$u" -c "xdg-settings set default-web-browser chromium.desktop" || true
su -s /bin/bash "$u" -c "xdg-mime default chromium.desktop ${WEB_TYPES[*]}" || true
_pu_log "Chromium set as default browser."

# Set Papers as default document viewer. Without this a PDF opens in the
# browser, which is what claims the type when nothing else does.
DOCUMENT_TYPES=(
    application/pdf application/x-bzpdf application/x-gzpdf application/x-xzpdf
    application/postscript application/x-bzpostscript application/x-gzpostscript
    image/x-eps application/x-dvi application/x-bzdvi application/x-gzdvi
    image/vnd.djvu+multipage
    application/oxps application/vnd.ms-xpsdocument
    application/vnd.comicbook+zip application/vnd.comicbook-rar
    application/x-cbz application/x-cbr application/x-cb7 application/x-cbt
)
su -s /bin/bash "$u" -c "xdg-mime default org.gnome.Papers.desktop ${DOCUMENT_TYPES[*]}" || true
_pu_log "Papers set as default document viewer."

# Compile dconf system database so dark mode is default before first login
dconf update 2>/dev/null || true

# Set gsettings defaults — dark mode + Nautilus preferences.
# /run/user/<uid> does not exist for an account that has never logged in, so a
# session bus address pointing there leaves dconf unable to commit and every
# write below silently lost. dbus-run-session gives the batch a bus of its own;
# the keys land in the user's own dconf database either way. The batch goes
# through a file so the quoting survives two levels of shell.
_gs_script="$(mktemp)"
cat > "$_gs_script" << 'GSETTINGSEOF'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
gsettings set org.gnome.desktop.interface document-font-name 'Readex Pro 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono NF 11'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
gsettings set org.gnome.desktop.interface cursor-size 24
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'icon-view'
gsettings set org.gnome.nautilus.preferences show-hidden-files false
GSETTINGSEOF
chmod 0644 "$_gs_script"
if su -s /bin/bash "$u" -c "dbus-run-session -- bash '$_gs_script'" 2>/dev/null; then
    _pu_log "desktop settings written for $u"
else
    _pu_warn "desktop settings could not be written for $u"
fi
rm -f "$_gs_script"
}

# The order matters. Groups and the venv first because they are cheap and
# root-only, then the desktop files, then ownership, and the first-run gates
# last so nothing arms a login before the home is ready for one.
provision_user_home() {  # $1 = user  $2 = "fresh" when the account was just created
    local u="$1" fresh="${2:-}" home
    home="$(provision_home_of "$u")"
    if [[ -z "$home" || ! -d "$home" ]]; then
        PROVISION_STEP="provision"; _pu_log "no home for $u, refusing to provision"
        return 1
    fi
    PROVISION_STEP="provision"
    PROVISION_FAILED=""
    _pu_log "=== provisioning $u ($home) ==="
    _pu_log "shell=$(getent passwd "$u" | cut -d: -f7) uid=$(id -u "$u")"

    _pu_step dotfiles provision_dotfiles "$u" "$fresh"
    _pu_step groups   provision_groups   "$u"
    _pu_step venv     provision_venv     "$u"
    _pu_step plugins  provision_plugins  "$u"
    _pu_step desktop  provision_desktop  "$u"
    _pu_step own      chown -R "$u:$u" "$home"
    _pu_step firstrun provision_first_run "$u"

    # A short account of what the new user will actually find, so a session
    # that fails to start can be compared against a home that was built right.
    PROVISION_STEP="verify"
    _pu_log "groups: $(id -nG "$u" 2>/dev/null)"
    local f
    for f in .config/hypr/hyprland.lua .config/hypr/custom/execs.lua \
             .config/quickshell/ii/shell.qml .local/state/quickshell/.venv/bin/python \
             .dotfiles-pending-user-setup; do
        if [[ -e "$home/$f" ]]; then
            _pu_log "present  $f  ($(stat -c '%U:%G %a' "$home/$f" 2>/dev/null))"
        else
            _pu_log "MISSING  $f"
        fi
    done
    _pu_log "root-owned paths left in home: $(find "$home" ! -user "$u" -printf . 2>/dev/null | wc -c)"
    local so
    for so in "$home"/.local/share/hyprland/plugins/*.so; do
        [[ -e "$so" ]] && _pu_log "plugin   $(basename "$so") builtfor=$(head -n1 "$so.builtfor" 2>/dev/null || echo NONE)"
    done
    # The caller decides what to do about a half-built home, and it can only
    # decide if it is told. Until this said so, a provision that failed
    # outright still came back as success and the account was handed over.
    local failed_required="" step
    for step in $PROVISION_FAILED; do
        case " $PROVISION_REQUIRED_STEPS " in
            *" $step "*) failed_required+=" $step" ;;
        esac
    done
    if [[ -n "$failed_required" ]]; then
        _pu_log "=== FAILED $u: required step(s)$failed_required did not complete ==="
        PROVISION_STEP=""
        return 1
    fi
    [[ -n "$PROVISION_FAILED" ]] && _pu_log "finished with recoverable failures:$PROVISION_FAILED"
    _pu_log "=== done $u ==="
    PROVISION_STEP=""
    return 0
}
