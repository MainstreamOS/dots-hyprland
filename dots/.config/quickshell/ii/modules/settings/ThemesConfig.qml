import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 720

    // ── Paths ────────────────────────────────────────────────────────────────
    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string shellConfigPath: Directories.shellConfigPath
    readonly property string themesDir: ThemeLibrary.themesDir
    readonly property string lastAppliedPath: ThemeLibrary.lastAppliedPath

    // ── State ────────────────────────────────────────────────────────────────
    readonly property var themes: ThemeLibrary.themes
    readonly property string lastAppliedSlug: ThemeLibrary.lastAppliedSlug
    property var orderedThemes: {
        if (!root.lastAppliedSlug) return root.themes
        const first = root.themes.find(t => t.slug === root.lastAppliedSlug)
        if (!first) return root.themes
        return [first].concat(root.themes.filter(t => t.slug !== root.lastAppliedSlug))
    }
    property bool saveDialogOpen: false
    property bool countingDown: false
    property int  countdownMax: 1      // slider value 1–30
    property int  countdownLeft: 0
    property string saveThemeName: ""
    property string pendingUpdateSlug: ""   // when non-empty, save flow updates that slug
    property string lastSavedSlug: ""       // set in doCapture, consumed in saveProc.onExited
    property string statusMessage: ""
    property int  statusTimeoutMs: 4000

    // While an apply is in flight the card buttons are disabled so a user
    // can't pile-up successive applies before the previous one settles.
    //
    // applyingSlug can't carry that on its own: it is cleared by the process
    // that *asks* the shell to apply a theme, and that returns as soon as the
    // request has been accepted — a few tens of milliseconds into a run
    // lasting well over a second. The shared apply state tracks the run
    // itself, so between them the whole thing is covered.
    property string applyingSlug: ""
    property string requestedSlug: ""
    readonly property bool applyInFlight: root.applyingSlug.length > 0 || Config.themeApplyInProgress

    // An action that isn't available right now wears the unselected look from
    // the Clock style selector — secondary container at full strength — rather
    // than fading toward the background, so it still reads as a button you
    // could reach for once whatever is blocking it clears.
    readonly property color colUnavailable: Appearance.colors.colSecondaryContainer
    readonly property color colOnUnavailable: Appearance.colors.colOnSecondaryContainer

    // True whenever the Day/Night Themes scheduler is in charge of the
    // active theme (any mode other than "off"). When this is true:
    //   - the per-card "Apply" button in the theme grid is disabled so
    //     manual picks can't fight the scheduler (the scheduler would
    //     just revert the apply on the next clock tick or shouldBeOn
    //     change, producing the "I clicked it and it bounced back"
    //     experience)
    //   - the "Update" button on the active card stays enabled because
    //     that's a save, not an apply
    //   - the Day/Night dropdowns in the section below stay enabled
    //     because picking a slug there is part of configuring the
    //     schedule itself, not a manual override
    //   - saving new themes from the "Save current as theme" card stays
    //     enabled — themes can always be captured
    readonly property bool scheduleActive: (Config.options?.appearance?.themeSchedule?.mode ?? "off") !== "off"

    // ── Helpers ──────────────────────────────────────────────────────────────
    // A timeout of zero leaves the message up. Most of these are confirmations
    // worth a few seconds, but one asks the user to go and install something
    // and come back, which is no use if it has faded by the time they read it.
    // Leaving the page takes it away, since the page is rebuilt on return, and
    // applying a theme replaces it with news of that instead.
    function showStatus(msg, timeoutMs) {
        root.statusMessage = msg
        statusTimer.stop()
        const timeout = timeoutMs ?? root.statusTimeoutMs
        if (timeout > 0) {
            statusTimer.interval = timeout
            statusTimer.restart()
        }
    }
    function clearStatus() {
        statusTimer.stop()
        root.statusMessage = ""
    }
    Timer {
        id: statusTimer
        interval: root.statusTimeoutMs
        onTriggered: root.statusMessage = ""
    }

    function slugify(name) {
        const s = (name || "theme").toString().toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/^-+|-+$/g, "")
        return s || ("theme-" + Date.now())
    }

    // ── Day/Night helpers ───────────────────────────────────────────────────
    // True when the configured schedule says we're currently in the day
    // window. Used by the Day/Night dropdowns to decide whether picking a
    // slug should immediately become the active theme — same answer
    // ThemeManager._evaluateSchedule arrives at when it auto-applies in
    // the main shell. "off" mode never claims either window so the dropdown
    // just stores the choice without triggering an apply.
    function _isCurrentlyDay() {
        const s = Config.options.appearance.themeSchedule
        if (!s || s.mode === "off") return false
        if (s.mode === "nightlight") return !Hyprsunset.shouldBeOn
        // manual: check current clock against dayFrom / nightFrom
        const now = new Date()
        const t = now.getHours() * 60 + now.getMinutes()
        const dp = (s.dayFrom || "06:00").split(":")
        const np = (s.nightFrom || "20:00").split(":")
        const dm = (parseInt(dp[0], 10) || 0) * 60 + (parseInt(dp[1], 10) || 0)
        const nm = (parseInt(np[0], 10) || 0) * 60 + (parseInt(np[1], 10) || 0)
        return dm < nm ? (t >= dm && t < nm) : (t >= dm || t < nm)
    }
    function _isCurrentlyNight() {
        const s = Config.options.appearance.themeSchedule
        if (!s || s.mode === "off") return false
        return !root._isCurrentlyDay()
    }

    // ── Time helpers (Day/Night Themes section) ─────────────────────────────
    // Round-trip "HH:mm" 24-hour storage <-> 12-hour display so the SpinBox
    // pickers can show "1–12 AM/PM" without changing what we persist (Config
    // uses 24-hour throughout). Same pattern DisplayConfig's Night Light
    // section uses; kept inline here so this file doesn't depend on it.
    function tsParse12(timeStr) {
        const parts = (timeStr || "").split(":")
        const h24 = parseInt(parts[0], 10)
        const m   = parseInt(parts[1], 10)
        if (isNaN(h24) || isNaN(m))
            return { hour12: 12, minute: 0, period: "AM" }
        if (h24 === 0)        return { hour12: 12,      minute: m, period: "AM" }
        if (h24 < 12)         return { hour12: h24,     minute: m, period: "AM" }
        if (h24 === 12)       return { hour12: 12,      minute: m, period: "PM" }
        return { hour12: h24 - 12, minute: m, period: "PM" }
    }
    function tsTo24(hour12, minute, period) {
        let h24 = hour12 % 12
        if (period === "PM") h24 += 12
        return String(h24).padStart(2, "0") + ":" + String(minute).padStart(2, "0")
    }
    function tsWithHour(timeStr, hour12) {
        const p = tsParse12(timeStr)
        return tsTo24(hour12, p.minute, p.period)
    }
    function tsWithMinute(timeStr, minute) {
        const p = tsParse12(timeStr)
        return tsTo24(p.hour12, minute, p.period)
    }
    function tsWithPeriod(timeStr, period) {
        const p = tsParse12(timeStr)
        return tsTo24(p.hour12, p.minute, period)
    }

    // ── Save theme (capture) ────────────────────────────────────────────────
    Process { id: saveProc }
    function beginSave(updateSlug) {
        root.pendingUpdateSlug = updateSlug || ""
        root.saveThemeName = updateSlug
            ? (root.themes.find(t => t.slug === updateSlug)?.name || "")
            : ""
        root.countdownMax = 1
        root.countdownLeft = 0
        root.countingDown = false
        root.saveDialogOpen = true
    }

    property string hyprWindowAddr: ""
    property bool windowHiddenForShot: false

    NumberAnimation {
        id: fadeOutAnim
        property: "opacity"
        from: 1.0; to: 0.0
        duration: 200
        easing.type: Easing.OutQuad
        onFinished: {
            hideWindowProc.running = false
            hideWindowProc.running = true
        }
    }

    NumberAnimation {
        id: fadeInAnim
        property: "opacity"
        from: 0.0; to: 1.0
        duration: 200
        easing.type: Easing.InQuad
    }

    // Move the active window into a special workspace so it disappears from
    // the screenshot, and bring it back afterward. Hyprland 0.55 Lua mode:
    // hyprctl dispatch wraps args as `return hl.dispatch(<args>)`, so the
    // legacy hyprlang names `movetoworkspacesilent` and `focuswindow` can't
    // be used directly — the colon-and-bare-identifier syntax fails the Lua
    // parser. Equivalents live under hl.dsp.window.move and hl.dsp.focus.
    Process {
        id: hideWindowProc
        property string buf: ""
        command: ["bash", "-c",
            "ADDR=$(hyprctl activewindow -j | jq -r '.address') && " +
            "echo \"$ADDR\" && " +
            // Lua-mode dispatch: move the window-by-address into a special
            // workspace, no focus follow (silent). follow=false → silent=true
            // in hl.dsp.window.move's table-arg semantics
            // (LuaBindingsDispatchers.cpp:773-774).
            "hyprctl dispatch \"hl.dsp.window.move({workspace = 'special:themecap', follow = false, window = 'address:$ADDR'})\" >/dev/null"
        ]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => hideWindowProc.buf += data }
        onExited: {
            root.hyprWindowAddr = (hideWindowProc.buf || "").trim()
            root.windowHiddenForShot = true
        }
    }

    Process {
        id: restoreWindowProc
        onExited: fadeInAnim.start()
    }

    function hideWindowForShot() {
        const w = Window.window
        if (!w) return
        fadeOutAnim.target = w
        fadeInAnim.target = w
        fadeOutAnim.start()
    }

    function restoreWindowAfterShot() {
        if (!root.windowHiddenForShot || !root.hyprWindowAddr) return
        root.windowHiddenForShot = false
        // Lua-mode: move back to the active workspace WITH focus follow
        // (follow=true → silent=false), then explicit focus on the window
        // address to ensure it's the active client again. Two dispatchers
        // because the move alone doesn't always re-raise the address.
        restoreWindowProc.command = ["bash", "-c",
            "WS=$(hyprctl activeworkspace -j | jq -r '.id') && " +
            "hyprctl dispatch \"hl.dsp.window.move({workspace = '$WS', follow = true, window = 'address:" + root.hyprWindowAddr + "'})\" >/dev/null && " +
            "hyprctl dispatch \"hl.dsp.focus({window = 'address:" + root.hyprWindowAddr + "'})\" >/dev/null"
        ]
        restoreWindowProc.running = false
        restoreWindowProc.running = true
    }

    function startCountdownAndCapture() {
        if (!root.pendingUpdateSlug && !root.saveThemeName.trim()) return
        root.countdownLeft = root.countdownMax
        root.countingDown = true
        if (root.countdownMax > 0) root.hideWindowForShot()
        if (root.countdownLeft === 0) doCapture()
        else countdownTimer.start()
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdownLeft -= 1
            if (root.countdownLeft <= 0) { stop(); doCapture() }
        }
    }

    function doCapture() {
        const slug = root.pendingUpdateSlug || root.slugify(root.saveThemeName)
        const name = (root.saveThemeName || slug).trim() || slug
        // Saving a new theme onto a slug that already has one replaces it where
        // it stands, wallpaper and preview included, and the grid just shows the
        // card under its new name. Names are slugified down to lowercase and
        // digits, so "Green!", "green" and "Green" are all the same theme here
        // and the collision is easy to reach by accident. Updating an existing
        // theme is the one case where landing on its slug is the intention.
        if (!root.pendingUpdateSlug && ThemeLibrary.themes.some(t => t.slug === slug)) {
            root.countingDown = false
            root.saveDialogOpen = false
            root.restoreWindowAfterShot()
            root.showStatus(Translation.tr("You already have a theme called %1. Pick another name, or use Update on that theme.").arg(name), 10000)
            return
        }
        const wp = Config.options.background.wallpaperPath || ""
        const wpTrimmed = FileUtils.trimFileProtocol(wp)
        const modeStr = Appearance.m3colors.darkmode ? "dark" : "light"
        root.lastSavedSlug = slug
        // Build bash payload
        const bash =
            `set -e\n` +
            `SLUG='${StringUtils.shellSingleQuoteEscape(slug)}'\n` +
            `NAME='${StringUtils.shellSingleQuoteEscape(name)}'\n` +
            `MODE='${modeStr}'\n` +
            `THEMES='${root.themesDir}'\n` +
            `DIR="$THEMES/$SLUG"\n` +
            `mkdir -p "$DIR"\n` +
            // Snapshot the live config but strip user-level meta-state that
            // shouldn't ride along with a theme:
            //   - appearance.themeSchedule  (Day/Night picks span themes by
            //                                design)
            //   - light.night.*             (Night Light schedule / mode /
            //                                colour temp is a user preference;
            //                                if a theme baked in `automatic=true`
            //                                + a from/to window that included
            //                                "right now", applying that theme
            //                                during the night window would
            //                                flip Hyprsunset on, change
            //                                shouldBeOn, and bounce the
            //                                theme scheduler straight back
            //                                into the configured Night
            //                                theme — undoing the manual apply.
            //                                Treat the whole night block as
            //                                user-level state.)
            //   - bar.seededWidgets        (no longer written, but a theme
            //                                exported while it was would carry a
            //                                per-machine record onto a machine it
            //                                does not describe.)
            //   - apps.*                   (each of these is handed to `bash -c`
            //                                when its button is pressed. A theme
            //                                is a look; it has no business
            //                                naming the command the Updates
            //                                button runs.)
            //   - updates.*                (names the manifest the release
            //                                checker fetches. Where a machine
            //                                is told about updates is not
            //                                something a look decides.)
            // apply-theme.sh ALSO preserves these from the live config when
            // applying, so older themes that still carry these keys won't
            // poison the user's settings either.
            `jq 'del(.appearance.themeSchedule) | del(.light.night) | del(.cursor) | del(.bar.seededWidgets) | del(.apps) | del(.updates)' '${root.shellConfigPath}' > "$DIR/config.json"\n` +
            // Snapshot the four interface-look gsettings (App style / Icons /
            // Mouse cursor / cursor size) so a saved theme carries the whole
            // look. Shake-to-locate is user behavior, stripped above.
            `python3 - "$DIR/interface.json" <<'PYIF'\n` +
            `import subprocess, json, sys\n` +
            `def g(k):\n` +
            `    out = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", k], capture_output=True, text=True).stdout.strip()\n` +
            `    return out.strip("'")\n` +
            `cs = g("cursor-size")\n` +
            `try:\n` +
            `    cs = int(cs)\n` +
            `except ValueError:\n` +
            `    pass\n` +
            `json.dump({"cursorSize": cs, "gtkTheme": g("gtk-theme"), "iconTheme": g("icon-theme"), "cursorTheme": g("cursor-theme")}, open(sys.argv[1], "w"), indent=2)\n` +
            `PYIF\n` +
            // Updating the theme that is currently applied means the live
            // wallpaper already is this theme's own copy of it, and copying a
            // file over itself is an error rather than a no-op. Under `set -e`
            // that ended the save right here — after the config and the
            // interface look were written, but before the wallpaper, the
            // screenshot and the metadata — so an update changed some of the
            // theme and left the rest, including the preview, as it was.
            // The extension is read off the basename, since a wallpaper with no
            // dot in its name would otherwise take a slice of its own directory
            // path along with it and the copy would land nowhere.
            (wpTrimmed ? `WP='${StringUtils.shellSingleQuoteEscape(wpTrimmed)}'\n` +
                         `WP_BASE="\${WP##*/}"\n` +
                         `case "$WP_BASE" in *.*) EXT="\${WP_BASE##*.}" ;; *) EXT="img" ;; esac\n` +
                         `[ "$WP" -ef "$DIR/wallpaper.$EXT" ] || cp -f "$WP" "$DIR/wallpaper.$EXT"\n` +
                         `WP_FILE="wallpaper.$EXT"\n`
                       : `WP_FILE=""\n`) +
            // Screenshot of primary focused monitor. Always overwrites
            // preview.png — same path whether this is a brand-new save
            // or an Update on an existing theme.
            //
            // Downscaled on the way out rather than stored at monitor
            // resolution. Nothing ever draws this larger than the save card,
            // so a native-resolution grim was several megabytes and a few
            // hundred milliseconds of decode per theme, paid on every visit to
            // the page and carried into every export. `>` only ever shrinks, so
            // a small monitor's shot is left alone. If magick isn't there the
            // full-size shot stays rather than the save losing its preview.
            `FOCUSED=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)\n` +
            `if [ -n "$FOCUSED" ]; then grim -o "$FOCUSED" "$DIR/preview.png"; else grim "$DIR/preview.png"; fi\n` +
            `magick "$DIR/preview.png" -resize ${ThemeLibrary.previewMaxDimension}x${ThemeLibrary.previewMaxDimension}\\> "$DIR/preview.png" 2>/dev/null || true\n` +
            // Millisecond resolution so back-to-back Update saves (within
            // the same wall-clock second) still produce a distinct
            // `created` value. The grid's preview Image keys its
            // cache-bust URL off this — if two saves landed in the same
            // second, the URL wouldn't change and the QML Image cache
            // could keep showing the previous frame even though
            // preview.png on disk was already overwritten.
            `CREATED=$(date +%s%3N)\n` +
            // Written by a serialiser rather than pasted into a heredoc: the
            // name is whatever the user typed, and a quote or a backslash in it
            // used to produce a meta.json nothing could parse. The index rebuild
            // reads every theme's meta with `except Exception: pass`, so the
            // theme simply vanished from the grid while its directory, its
            // wallpaper copy and its preview stayed on disk unreachable.
            `python3 - "$DIR/meta.json" "$SLUG" "$NAME" "$WP_FILE" "$MODE" "$CREATED" <<'PYMETA'\n` +
            `import json, sys\n` +
            `out, slug, name, wp, mode, created = sys.argv[1:7]\n` +
            `json.dump({"slug": slug, "name": name, "wallpaperFile": wp,\n` +
            `           "mode": mode, "created": int(created)}, open(out, "w"))\n` +
            `PYMETA\n` +
            // Snapshot the decoration settings so applying this theme later
            // restores the look the user had at save time.
            `GENERAL='${root.homePath}/.config/hypr/hyprland/general.lua'\n` +
            `CUSTOM='${root.homePath}/.config/hypr/custom/general.lua'\n` +
            // Snapshot through the shared reader, so what a theme records and
            // what an apply puts back can never disagree about a key.
            `python3 '${root.homePath}/.config/quickshell/ii/scripts/themes/decorations.py' \\\n` +
            // On failure drop the file rather than leave `{}`: an empty object
            // now reads as "reset every decoration to stock" on apply, so a
            // failed snapshot must leave no file at all, which apply skips.
            `    read "$GENERAL" --flag-dir "$(dirname "$CUSTOM")" > "$DIR/decorations.json" \\\n` +
            `    || rm -f "$DIR/decorations.json"\n` +
            // A custom animation profile is a file, not a value: the snapshot
            // records its name, but on another machine the name points at
            // nothing. The file rides in the theme so the name means the same
            // thing wherever the theme lands. Shipped profiles stay out — every
            // install has them, and a theme is not how the stock set updates.
            `python3 - "$DIR" '${root.homePath}/.config/hypr/hyprland/animations' \\\n` +
            `    '${root.homePath}/.config/quickshell/ii/scripts/themes/decorations-schema.json' <<'PYANIM'\n` +
            `import json, os, re, shutil, sys\n` +
            `theme_dir, anim_dir, schema_path = sys.argv[1:4]\n` +
            `row = next(r for r in json.load(open(schema_path))["keys"] if r["key"] == "animationProfile")\n` +
            `shipped = set(row.get("shipped", []))\n` +
            `try:\n` +
            `    name = str(json.load(open(os.path.join(theme_dir, "decorations.json"))).get("animationProfile", ""))\n` +
            `except Exception:\n` +
            `    name = ""\n` +
            `dest = os.path.join(theme_dir, "animations")\n` +
            `shutil.rmtree(dest, ignore_errors=True)\n` +
            `src = os.path.join(anim_dir, name + ".lua")\n` +
            `if name and name not in shipped and re.fullmatch(r"[\\w-]+", name) and os.path.isfile(src):\n` +
            `    os.makedirs(dest, exist_ok=True)\n` +
            `    shutil.copy2(src, os.path.join(dest, name + ".lua"))\n` +
            `PYANIM\n` +
            // The window rules store is already the JSON a theme wants, so the
            // snapshot is a copy. Written even when there are no rules: an
            // empty list at save time is part of the look, and applying the
            // theme later puts exactly that back.
            `USERRULES='${root.homePath}/.config/hypr/hyprland/userrules.json'\n` +
            `if [ -f "$USERRULES" ]; then cp -f "$USERRULES" "$DIR/windowrules.json"; ` +
            `else printf '{"rules": []}\\n' > "$DIR/windowrules.json"; fi\n` +
            // Newly saved themes are treated as the currently applied theme.
            `printf '%s' "$SLUG" > '${root.lastAppliedPath}.tmp' && mv -f '${root.lastAppliedPath}.tmp' '${root.lastAppliedPath}'\n` +
            // Rebuild index
            `python3 - "$THEMES" <<'PY'\n` +
            `import json, os, sys\n` +
            `themes_dir = sys.argv[1]\n` +
            `out = []\n` +
            // An import stages into a dot-prefixed directory alongside the real
            // ones and only sanitises the archive's meta.json near the end, so a
            // run killed partway leaves a hidden directory holding whatever the
            // file claimed its slug was. Skipping dotted names keeps that out of
            // the index instead of publishing it as a theme.
            `for name in sorted(os.listdir(themes_dir)):\n` +
            `    if name.startswith("."): continue\n` +
            `    p = os.path.join(themes_dir, name)\n` +
            `    meta = os.path.join(p, "meta.json")\n` +
            `    if os.path.isdir(p) and os.path.isfile(meta):\n` +
            `        try:\n` +
            `            with open(meta) as f: out.append(json.load(f))\n` +
            `        except Exception: pass\n` +
            `with open(os.path.join(themes_dir, "index.json"), "w") as f:\n` +
            `    json.dump(out, f, indent=2)\n` +
            `PY\n`
        saveProc.command = ["bash", "-c", bash]
        saveProc.running = false
        saveProc.running = true
    }

    Connections {
        target: saveProc
        function onExited(exitCode, exitStatus) {
            root.countingDown = false
            root.saveDialogOpen = false
            root.pendingUpdateSlug = ""
            root.restoreWindowAfterShot()
            // The payload runs under `set -e` and can stop partway — an
            // unwritable directory, a wallpaper that vanished between being
            // chosen and being copied — so the library is pointed at the new
            // slug only once there is a directory behind it.
            if (exitCode !== 0) {
                root.lastSavedSlug = ""
                ThemeLibrary.refresh()
                root.showStatus(Translation.tr("Couldn't save that theme"), 8000)
                return
            }
            if (root.lastSavedSlug) ThemeLibrary.lastAppliedSlug = root.lastSavedSlug
            root.lastSavedSlug = ""
            ThemeLibrary.refresh()
            root.showStatus(Translation.tr("Theme saved"))
        }
    }

    // ── Apply theme (via shell IPC — atomic, race-free) ─────────────────────
    Process { id: ipcApplyProc }
    function applyTheme(theme) {
        if (root.applyInFlight) return
        root.applyingSlug = theme.slug
        root.requestedSlug = theme.slug
        ipcApplyProc.command = ["qs", "-c", "ii", "ipc", "call", "themes", "apply", theme.slug]
        ipcApplyProc.running = false
        ipcApplyProc.running = true
        // Optimistic UI update — the script also writes last-applied.txt.
        ThemeLibrary.lastAppliedSlug = theme.slug
        // Ends when the apply reports back rather than on a fixed timer, which
        // otherwise expires part-way through some runs and lingers after others.
        root.showStatus(Translation.tr("Applying theme: %1").arg(theme.name), 30000)
        applyLockoutTimer.restart()
    }
    Connections {
        target: ipcApplyProc
        // A non-zero exit means the request never reached the shell, so nothing
        // is running and the cards can go live again straight away. A clean exit
        // only means the run has started; the apply state below ends it.
        function onExited(exitCode) {
            if (exitCode !== 0) {
                root.applyingSlug = ""
                root.requestedSlug = ""
                root.showStatus(Translation.tr("Couldn't apply that theme — your previous one is still in place"), 8000)
            }
        }
    }
    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            root.applyingSlug = ""
            if (root.requestedSlug.length > 0) applyOutcomeTimer.restart()
        }
    }
    // If the run never reports itself finished the cards would stay disabled
    // for the rest of the session, so give up waiting eventually.
    Timer {
        id: applyLockoutTimer
        interval: 30000
        onTriggered: root.applyingSlug = ""
    }
    // Whether the theme took is decided by which slug the run left recorded: a
    // theme that fails validation is rolled back and the previous one restored.
    // The signals for this live in the shell process that does the applying,
    // not in this one, so the shared record is what carries the answer across.
    // It is written just before the run reports itself finished and reaches
    // this page through a file watcher, hence the pause before reading it.
    Timer {
        id: applyOutcomeTimer
        interval: 300
        onTriggered: {
            const wanted = root.requestedSlug
            root.requestedSlug = ""
            if (wanted.length === 0) return
            if (root.lastAppliedSlug === wanted)
                root.clearStatus()
            else
                root.showStatus(Translation.tr("Couldn't apply that theme — your previous one is still in place"), 8000)
        }
    }

    // ── Delete theme ────────────────────────────────────────────────────────
    Process {
        id: deleteProc
        // Track which slug is in-flight so onExited can clear lastAppliedSlug
        // if the user just deleted the currently active theme.
        property string deletingSlug: ""
    }
    function deleteTheme(theme) {
        // Block the QML config adapter from racing with our config.json patch
        // below — same pattern used by ThemeManager / apply-theme.sh.
        Config.blockWrites = true
        deleteProc.deletingSlug = theme.slug

        const safeSlug = StringUtils.shellSingleQuoteEscape(theme.slug)
        const bash =
            `set -e\n` +
            `SLUG='${safeSlug}'\n` +
            `THEME_DIR='${root.themesDir}'/"$SLUG"\n` +
            `CONF='${root.shellConfigPath}'\n` +
            // ── Preserve wallpaper before delete ─────────────────────────────
            // When a theme is applied, config.json's wallpaperPath is set to
            // the bundled copy inside the theme dir.  Deleting the dir without
            // relocating that file leaves a dead path in config.json, causing
            // blank previews everywhere and no wallpaper after reboot.
            `LIVE_WP=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('background',{}).get('wallpaperPath',''))" "$CONF" 2>/dev/null || true)\n` +
            `case "$LIVE_WP" in\n` +
            `    "$THEME_DIR"/*)\n` +
            `        EXT="\${LIVE_WP##*.}"\n` +
            `        SAVED_WP='${root.themesDir}'/last-wallpaper."$EXT"\n` +
            `        cp -f "$LIVE_WP" "$SAVED_WP"\n` +
            // Atomically patch wallpaperPath in config.json to the safe copy
            `        python3 - "$CONF" "$SAVED_WP" <<'PY'\n` +
            `import json, os, sys\n` +
            `conf, new_wp = sys.argv[1], sys.argv[2]\n` +
            `with open(conf) as f: data = json.load(f)\n` +
            `data.setdefault('background', {})['wallpaperPath'] = new_wp\n` +
            `tmp = conf + '.tmp'\n` +
            `with open(tmp, 'w') as f: json.dump(data, f, indent=2)\n` +
            `os.replace(tmp, conf)\n` +
            `PY\n` +
            `        ;;\n` +
            `esac\n` +
            // ── Clear last-applied marker if it pointed to this theme ─────────
            `if [ -f '${root.lastAppliedPath}' ] && [ "$(cat '${root.lastAppliedPath}')" = "$SLUG" ]; then\n` +
            `    rm -f '${root.lastAppliedPath}'\n` +
            `fi\n` +
            // ── Remove theme dir and rebuild index ────────────────────────────
            `rm -rf -- "$THEME_DIR"\n` +
            `python3 - '${root.themesDir}' <<'PY'\n` +
            `import json, os, sys\n` +
            `themes_dir = sys.argv[1]\n` +
            `out = []\n` +
            `for n in sorted(os.listdir(themes_dir)):\n` +
            `    if n.startswith("."): continue\n` +
            `    p = os.path.join(themes_dir, n); m = os.path.join(p, "meta.json")\n` +
            `    if os.path.isdir(p) and os.path.isfile(m):\n` +
            `        try:\n` +
            `            with open(m) as f: out.append(json.load(f))\n` +
            `        except: pass\n` +
            `open(os.path.join(themes_dir, "index.json"), "w").write(json.dumps(out, indent=2))\n` +
            `PY\n`
        deleteProc.command = ["bash", "-c", bash]
        deleteProc.running = false
        deleteProc.running = true
    }
    Connections {
        target: deleteProc
        function onExited() {
            // Unblock the config adapter — the file watcher will now pick up
            // any wallpaperPath change we wrote and reload Config automatically.
            Config.blockWrites = false
            // If the deleted theme was the one marked as active, clear the
            // in-memory marker so no ghost "active" highlight lingers.
            if (deleteProc.deletingSlug === root.lastAppliedSlug) {
                ThemeLibrary.lastAppliedSlug = ""
            }
            ThemeLibrary.refresh()
            root.showStatus(Translation.tr("Theme deleted"))
        }
    }

    // ── Export / import ─────────────────────────────────────────────────────
    // A theme travels as a single .mtheme file: a gzipped tar of the theme
    // directory, flat, so the receiving side never has to guess at layout.
    property bool ioBusy: false

    // Shared sanitiser for both directions. A saved theme's config.json is a
    // snapshot of the whole live config, which carries keys that describe the
    // machine rather than the look — absolute paths under one user's home, and
    // the same user-level meta-state doCapture() already strips. Sending those
    // to someone else would point their screenshots at a home directory that
    // doesn't exist, so they come out on export and are re-pointed at local
    // values on import. wallpaperPath goes too: apply-theme.sh recomputes it
    // from the bundled wallpaper, and import writes the local copy's path.
    readonly property string pyPortable: `
import json, os

FORMAT_VERSION = 2

STRIP = [("appearance", "themeSchedule"), ("light", "night"), ("cursor",),
         ("screenRecord", "savePath"), ("screenSnip", "savePath"),
         ("background", "thumbnailPath"), ("background", "wallpaperPath"),
         ("background", "slideshow", "folder"),
         # A theme file arrives from somewhere else. Every apps.* value is run
         # as a shell command by the button that owns it, and updates.* names
         # the manifest this machine trusts for release news -- neither is part
         # of a look, and neither may be carried in from outside.
         ("apps",), ("updates",)]

def theme_installed(kind, name, cursors=False):
    # kind is the shared-data subdirectory a look lives in ("themes" for widget
    # styles, "icons" for icon and cursor sets). A cursor set is an icon
    # directory that actually carries a cursors/ folder.
    home = os.path.expanduser("~")
    for base in ("/usr/share/" + kind,
                 os.path.join(home, ".local/share", kind),
                 os.path.join(home, "." + kind)):
        path = os.path.join(base, name)
        if os.path.isdir(path) and (not cursors or os.path.isdir(os.path.join(path, "cursors"))):
            return True
    return False

def drop(d, path):
    cur = d
    for p in path[:-1]:
        cur = cur.get(p) if isinstance(cur, dict) else None
        if not isinstance(cur, dict):
            return
    if isinstance(cur, dict):
        cur.pop(path[-1], None)

def portable(cfg):
    for p in STRIP:
        drop(cfg, p)
    return cfg

# What the rotation itself considers a wallpaper — kept in step with
# WallpaperSlideshow.extensions, and top level only, since it does not recurse.
SS_EXT = (".jpg", ".jpeg", ".png", ".webp", ".bmp", ".avif")

def slideshow_folder(cfg):
    ss = ((cfg.get("background") or {}).get("slideshow") or {})
    if not ss.get("enable"):
        return ""
    folder = str(ss.get("folder") or "").strip()
    if not folder:
        folder = os.path.join(os.path.expanduser("~"), "Pictures", "Wallpapers")
    return folder if os.path.isdir(folder) else ""

def slideshow_images(folder):
    if not folder:
        return []
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    out = []
    for n in names:
        p = os.path.join(folder, n)
        if os.path.isfile(p) and os.path.splitext(n)[1].lower() in SS_EXT:
            out.append(p)
    return out
`

    Process {
        id: exportProc
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => exportProc.buf += data }
        onExited: {
            root.ioBusy = false
            const line = (exportProc.buf || "").trim().split("\n").filter(l => l.length).pop() || ""
            if (line.startsWith("OK|"))
                root.showStatus(Translation.tr("Theme exported to %1").arg(line.slice(3)))
            else if (line !== "CANCEL")
                root.showStatus(Translation.tr("Couldn't export that theme"))
        }
    }

    // The pictures a rotation draws from can outweigh the rest of a theme many
    // times over, so what they weigh is put in front of the person exporting
    // rather than decided for them. Counted before anything is asked, so a
    // theme with no rotation never sees the question at all.
    property bool exportDialogOpen: false
    property string exportSlug: ""
    property int exportImageCount: 0
    property real exportImageMib: 0

    Process {
        id: exportPreflightProc
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => exportPreflightProc.buf += data }
        onExited: {
            const parts = (exportPreflightProc.buf || "").trim().split(/\s+/)
            const count = parseInt(parts[0]) || 0
            const bytes = parseInt(parts[1]) || 0
            if (count <= 0) {
                root.runExport(false)
                return
            }
            root.exportImageCount = count
            root.exportImageMib = bytes / 1048576
            root.exportDialogOpen = true
        }
    }

    function exportTheme(theme) {
        if (root.ioBusy) return
        root.exportSlug = theme.slug
        exportPreflightProc.command = ["bash", "-c",
            `python3 - "$1" <<'PY'\n` + root.pyPortable + `import sys
theme_dir = sys.argv[1]
try:
    raw = json.load(open(os.path.join(theme_dir, "config.json")))
except Exception:
    raw = {}
images = slideshow_images(slideshow_folder(raw))
print("%d %d" % (len(images), sum(os.path.getsize(p) for p in images)))
` + `PY\n`,
            "export-preflight", `${root.themesDir}/${theme.slug}`]
        exportPreflightProc.running = false
        exportPreflightProc.running = true
    }

    function runExport(includeImages) {
        if (root.ioBusy) return
        root.ioBusy = true
        // Values reach bash as positional arguments, never spliced into the
        // script text, so a theme named with quotes can't break the command.
        const script =
            `SLUG="$1"\n` +
            `OUT=$(zenity --file-selection --save --confirm-overwrite ` +
            `--title="$3" --filename="$HOME/$SLUG.mtheme" ` +
            `--file-filter="Mainstream theme | *.mtheme" 2>/dev/null) || { echo CANCEL; exit 0; }\n` +
            `[ -n "$OUT" ] || { echo CANCEL; exit 0; }\n` +
            `case "$OUT" in *.mtheme) ;; *) OUT="$OUT.mtheme" ;; esac\n` +
            // zenity checked whatever was typed, and the extension is added
            // after, so the name it asked about is not always the name written.
            // Asked again here when they differ.
            `if [ -e "$OUT" ]; then\n` +
            `  zenity --question --title="$3" --text="$4" 2>/dev/null || { echo CANCEL; exit 0; }\n` +
            `fi\n` +
            `python3 - '${root.themesDir}'/"$SLUG" "$OUT" "$2" <<'PY'\n` +
            root.pyPortable +
            `import io, sys, tarfile
theme_dir, out_path, include = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
KEEP = ("interface.json", "decorations.json", "windowrules.json", "preview.png")

def entry(tar, name, obj):
    blob = json.dumps(obj, indent=2).encode()
    info = tarfile.TarInfo(name)
    info.size = len(blob)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(blob))

raw = json.load(open(os.path.join(theme_dir, "config.json")))
images = slideshow_images(slideshow_folder(raw)) if include else []
cfg = portable(raw)
meta = json.load(open(os.path.join(theme_dir, "meta.json")))
# Stamp the layout this archive was written against, so a future reader can
# recognise a theme it only partly understands instead of applying it blind.
# Only a bundle carrying pictures claims the newer layout, so a theme without
# one still lands cleanly on a build that predates them.
meta["formatVersion"] = FORMAT_VERSION if images else 1
with tarfile.open(out_path, "w:gz") as tar:
    entry(tar, "config.json", cfg)
    entry(tar, "meta.json", meta)
    for n in sorted(os.listdir(theme_dir)):
        p = os.path.join(theme_dir, n)
        if os.path.isfile(p) and (n in KEEP or n.startswith("wallpaper.")):
            tar.add(p, arcname=n)
    for p in images:
        tar.add(p, arcname="slideshow/" + os.path.basename(p))
    ANIM_OK = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    adir = os.path.join(theme_dir, "animations")
    if os.path.isdir(adir):
        for n in sorted(os.listdir(adir)):
            p = os.path.join(adir, n)
            stem = n[:-4] if n.endswith(".lua") else ""
            if stem and all(c in ANIM_OK for c in stem) and os.path.isfile(p) and os.path.getsize(p) <= 262144:
                tar.add(p, arcname="animations/" + n)
print("OK|" + out_path)
` +
            `PY\n`
        exportProc.command = ["bash", "-c", script, "export-theme",
            root.exportSlug,
            includeImages ? "1" : "0",
            Translation.tr("Export theme"),
            Translation.tr("A theme file of that name is already there. Replace it?")]
        exportProc.running = false
        exportProc.running = true
    }

    Process {
        id: importProc
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => importProc.buf += data }
        onExited: {
            root.ioBusy = false
            const line = (importProc.buf || "").trim().split("\n").filter(l => l.length).pop() || ""
            if (line.startsWith("OK|")) {
                ThemeLibrary.refresh()
                let result = null
                try { result = JSON.parse(line.slice(3)) } catch (e) { result = null }
                const name = result?.name ?? ""
                const missing = result?.missing ?? []
                // Overwriting a theme the user already had is the one outcome
                // they cannot undo, so it is said whatever else also happened —
                // it used to be the last branch of the chain and any missing
                // look, or a newer file, spoke instead of it.
                const over = result?.replaced
                    ? Translation.tr(" It replaced your saved copy.") : ""
                if (missing.length > 0) {
                    // Name what was left out and how to get the rest, rather
                    // than quietly importing a partial look.
                    const parts = missing.map(m => Translation.tr("%1 (%2)").arg(m.name).arg(m.what))
                    root.showStatus((missing.length === 1
                        ? Translation.tr("Imported %1 without %2 — not installed on this system. Install it, then import the file again for the complete theme.")
                        : Translation.tr("Imported %1 without %2 — not installed on this system. Install them, then import the file again for the complete theme."))
                        .arg(name).arg(parts.join(", ")) + over, 0)
                } else if (result?.newer) {
                    root.showStatus(Translation.tr("Imported %1. It was made by a newer version, so parts of it may not apply.").arg(name) + over, 12000)
                } else if (result?.replaced) {
                    root.showStatus(Translation.tr("Replaced your saved %1 with the imported one").arg(name))
                } else {
                    root.showStatus(Translation.tr("Theme imported: %1").arg(name))
                }
            } else if (line === "ERR|notatheme") {
                root.showStatus(Translation.tr("That file isn't a Mainstream theme"))
            } else if (line !== "CANCEL") {
                root.showStatus(Translation.tr("Couldn't import that theme"))
            }
        }
    }

    function importTheme() {
        if (root.ioBusy) return
        root.ioBusy = true
        const script =
            `IN=$(zenity --file-selection --title="Import theme" ` +
            `--file-filter="Mainstream theme | *.mtheme" ` +
            `--file-filter="All files | *" 2>/dev/null) || { echo CANCEL; exit 0; }\n` +
            `[ -n "$IN" ] || { echo CANCEL; exit 0; }\n` +
            `python3 - "$IN" '${root.themesDir}' '${root.shellConfigPath}' <<'PY'\n` +
            root.pyPortable +
            `import re, shutil, sys, tarfile, tempfile, time
archive, themes_dir, live_config = sys.argv[1], sys.argv[2], sys.argv[3]
EXACT = {"meta.json", "config.json", "interface.json", "decorations.json", "windowrules.json", "preview.png"}

def wanted(n):
    return n in EXACT or (n.startswith("wallpaper.") and len(n) > len("wallpaper."))

# A bundle can carry the pictures its rotation draws from. They are the only
# members allowed to sit in a subdirectory, and even then only the basename is
# kept — the archive still never picks where anything lands. The ceilings are
# there so a malicious file can't fill the disk on the way in.
MAX_SS_FILES = 500
MAX_SS_BYTES = 1024 * 1024 * 1024
MAX_ANIM_FILES = 20
MAX_ANIM_BYTES = 4 * 1024 * 1024
# A theme file arrives from somewhere else, and tar members declare their own
# size: a small archive can name an enormous one. These are what a theme's own
# parts plausibly weigh, so a file claiming more is rejected before anything is
# written rather than after the disk is full.
MAX_MEMBER_BYTES = 128 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024

ANIM_OK = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
def animation_name(name):
    parts = name.split("/")
    if len(parts) != 2 or parts[0] != "animations":
        return ""
    n = os.path.basename(parts[1])
    stem = n[:-4] if n.endswith(".lua") else ""
    return n if stem and all(c in ANIM_OK for c in stem) else ""

def slideshow_name(name):
    parts = name.split("/")
    if len(parts) != 2 or parts[0] != "slideshow":
        return ""
    n = os.path.basename(parts[1])
    if not n or n.startswith("."):
        return ""
    return n if os.path.splitext(n)[1].lower() in SS_EXT else ""

def fail():
    print("ERR|notatheme")
    sys.exit(0)

# Staged inside the themes directory so the final publish is a same-filesystem
# rename — a half-written theme never appears in the grid.
tmp = tempfile.mkdtemp(prefix=".importing-", dir=themes_dir)
try:
    try:
        tar = tarfile.open(archive, "r:*")
    except Exception:
        fail()
    with tar:
        picked, seen, total_bytes = [], set(), 0
        ss_picked, ss_seen, ss_bytes = [], set(), 0
        anim_picked, anim_seen, anim_bytes = [], set(), 0
        for m in tar.getmembers():
            if not m.isfile():
                continue
            raw = m.name[2:] if m.name.startswith("./") else m.name
            an = animation_name(raw)
            if an:
                if (an in anim_seen or len(anim_picked) >= MAX_ANIM_FILES
                        or anim_bytes + m.size > MAX_ANIM_BYTES):
                    continue
                anim_seen.add(an)
                anim_bytes += m.size
                m.name = "animations/" + an
                anim_picked.append(m)
                continue
            ss = slideshow_name(raw)
            if ss:
                if (ss in ss_seen or len(ss_picked) >= MAX_SS_FILES
                        or ss_bytes + m.size > MAX_SS_BYTES):
                    continue
                ss_seen.add(ss)
                ss_bytes += m.size
                m.name = "slideshow/" + ss
                ss_picked.append(m)
                continue
            # Anything else nested is dropped rather than flattened, so a
            # picture folder can't smuggle in a second meta.json.
            if "/" in raw:
                continue
            # Only ever write a basename we recognise, so nothing in the
            # archive can choose its own destination.
            n = os.path.basename(raw)
            if n in seen or not wanted(n):
                continue
            if m.size > MAX_MEMBER_BYTES:
                fail()
            total_bytes += m.size
            if total_bytes > MAX_TOTAL_BYTES:
                fail()
            seen.add(n)
            m.name = n
            picked.append(m)
        if "meta.json" not in seen or "config.json" not in seen:
            fail()
        tar.extractall(tmp, members=picked + ss_picked + anim_picked, filter="data")

    try:
        meta = json.load(open(os.path.join(tmp, "meta.json")))
        cfg = json.load(open(os.path.join(tmp, "config.json")))
    except Exception:
        fail()
    if not isinstance(meta, dict) or not isinstance(cfg, dict):
        fail()

    # A theme that matches one already saved replaces it. Importing the same
    # file twice, or a newer copy of a theme from another machine, is meant to
    # leave one entry rather than a row of near-identical names to tell apart.
    # Keyed on the name the same way saving one is, so a theme called the same
    # thing lands in the same place whatever the file happens to call its slug.
    name = str(meta.get("name") or meta.get("slug") or "theme").strip() or "theme"
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "theme"
    dest = os.path.join(themes_dir, slug)
    replaced = os.path.isdir(dest)

    try:
        live = json.load(open(live_config))
    except Exception:
        live = {}
    wp = next((f for f in sorted(os.listdir(tmp)) if f.startswith("wallpaper.")), "")

    # Replacing a theme swaps the whole directory, so anything the incoming file
    # doesn't carry would go out with the old copy. An archive exported without
    # its wallpaper is the ordinary case, and losing the picture -- and the
    # preview built from it -- is not what "import an update to this theme"
    # should mean. Carry them across so only what actually arrived is replaced.
    if replaced:
        for keep_name in ("preview.png",):
            src_keep = os.path.join(dest, keep_name)
            if os.path.isfile(src_keep) and not os.path.exists(os.path.join(tmp, keep_name)):
                shutil.copy2(src_keep, os.path.join(tmp, keep_name))
        if not wp:
            old_wp = next((f for f in sorted(os.listdir(dest)) if f.startswith("wallpaper.")), "")
            if old_wp:
                shutil.copy2(os.path.join(dest, old_wp), os.path.join(tmp, old_wp))
                wp = old_wp

    cfg = portable(cfg)
    if wp:
        cfg.setdefault("background", {})["wallpaperPath"] = os.path.join(dest, wp)
    else:
        keep = (live.get("background") or {}).get("wallpaperPath")
        if keep:
            cfg.setdefault("background", {})["wallpaperPath"] = keep
    for section, key in (("screenRecord", "savePath"), ("screenSnip", "savePath")):
        local = (live.get(section) or {}).get(key)
        if local:
            cfg.setdefault(section, {})[key] = local

    # The folder came out on export because it named a directory in someone
    # else's home. If the pictures travelled with the theme it is re-pointed at
    # the copy that just landed; if they didn't, the rotation is switched off
    # rather than left running over whatever this machine happens to keep in its
    # own wallpapers folder, which would be a different theme wearing this one's
    # name. Only touched when there is something to say, so a theme with no
    # rotation at all doesn't gain an empty one.
    ss = (cfg.get("background") or {}).get("slideshow")
    if ss_picked:
        cfg.setdefault("background", {}).setdefault("slideshow", {})["folder"] = \
            os.path.join(dest, "slideshow")
    elif isinstance(ss, dict) and ss.get("enable"):
        ss["enable"] = False

    # A look the machine doesn't have would otherwise be written into gsettings
    # as a name nothing can resolve, leaving the desktop on a fallback and, for
    # widget styles, stopping the light/dark switch from steering them at all.
    # Drop those entries so the importer keeps what already works, and say what
    # was left out.
    missing = []
    iface_path = os.path.join(tmp, "interface.json")
    if os.path.isfile(iface_path):
        try:
            iface = json.load(open(iface_path))
        except Exception:
            iface = None
        if isinstance(iface, dict):
            for key, kind, cursors, label in (("gtkTheme", "themes", False, "app style"),
                                              ("iconTheme", "icons", False, "icons"),
                                              ("cursorTheme", "icons", True, "cursor")):
                value = iface.get(key)
                if value and not theme_installed(kind, str(value), cursors):
                    missing.append({"what": label, "name": str(value)})
                    iface.pop(key, None)
            if missing:
                json.dump(iface, open(iface_path, "w"), indent=2)

    meta["slug"], meta["name"], meta["wallpaperFile"] = slug, name, wp
    meta["created"] = int(time.time() * 1000)
    try:
        newer = int(meta.get("formatVersion") or 0) > FORMAT_VERSION
    except (TypeError, ValueError):
        newer = False
    json.dump(meta, open(os.path.join(tmp, "meta.json"), "w"), indent=2)
    json.dump(cfg, open(os.path.join(tmp, "config.json"), "w"), indent=2)

    # Swap the finished copy in rather than writing over the old one where it
    # stands, so an import that dies partway can't leave a theme made of half
    # of each. The outgoing copy is only discarded once the new one is in place.
    previous = dest + ".replaced"
    shutil.rmtree(previous, ignore_errors=True)
    if os.path.isdir(dest):
        os.rename(dest, previous)
    try:
        os.rename(tmp, dest)
    except OSError:
        if os.path.isdir(previous):
            os.rename(previous, dest)
        raise
    shutil.rmtree(previous, ignore_errors=True)
    tmp = None

    index = []
    for d in sorted(os.listdir(themes_dir)):
        if d.startswith("."): continue
        mp = os.path.join(themes_dir, d, "meta.json")
        if os.path.isdir(os.path.join(themes_dir, d)) and os.path.isfile(mp):
            try:
                index.append(json.load(open(mp)))
            except Exception:
                pass
    json.dump(index, open(os.path.join(themes_dir, "index.json"), "w"), indent=2)
    print("OK|" + json.dumps({"name": name, "missing": missing, "newer": newer, "replaced": replaced}))
finally:
    if tmp and os.path.isdir(tmp):
        shutil.rmtree(tmp, ignore_errors=True)
` +
            `PY\n`
        importProc.command = ["bash", "-c", script, "import-theme"]
        importProc.running = false
        importProc.running = true
    }

    // ── UI ───────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "style"
        title: Translation.tr("Themes")
        Layout.fillWidth: true

        // Import acts on the collection rather than any one theme, so it
        // belongs on the section header beside the title, not in the grid.
        headerExtra: [
            RippleButtonWithIcon {
                materialIcon: "file_open"
                mainText: Translation.tr("Import theme")
                enabled: !root.ioBusy
                // Pair the container with the on-secondary icon and label the
                // component already uses, instead of the default dark layer.
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.importTheme()
            }
        ]

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 10
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("A theme is a snapshot of your current look — wallpaper, colors, UI changes, and window decorations. Tap \"Save current as theme\" to capture what's on screen, then switch between saved themes any time with one tap. Use \"Update\" on the active theme to overwrite it with your latest tweaks. You can also export a theme to a file and import it again later or on another computer. The wallpaper is included.")
        }

        // What just happened — a theme applied, saved, deleted, exported or
        // imported. Carried the same way as the Day/Night notice below so the
        // page has one voice for telling the user something, with its own icon
        // to separate a thing that has happened from a thing that is disabled.
        Rectangle {
            visible: root.statusMessage.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            radius: Appearance.rounding.small
            color: Qt.rgba(Appearance.m3colors.m3primary.r, Appearance.m3colors.m3primary.g, Appearance.m3colors.m3primary.b, 0.12)
            implicitHeight: statusRow.implicitHeight + 16
            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                MaterialSymbol {
                    text: "info"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: root.statusMessage
                }
            }
        }

        // Schedule-active lock banner. Tells the user why the Apply buttons
        // in the grid below are dimmed — without this, the buttons would
        // just silently refuse clicks and look broken. The "Off" word is
        // styled to match the Day/Night dropdown so it's obvious where
        // to go to unlock manual applies.
        Rectangle {
            visible: root.scheduleActive
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            radius: Appearance.rounding.small
            color: Qt.rgba(Appearance.m3colors.m3primary.r, Appearance.m3colors.m3primary.g, Appearance.m3colors.m3primary.b, 0.12)
            implicitHeight: lockRow.implicitHeight + 16
            RowLayout {
                id: lockRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                MaterialSymbol {
                    text: "lock"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Manual apply is disabled to honor your Day/Night Themes settings, but you can still save new themes and update the current theme with Day/Night Themes active. Set Day/Night Themes to \"Off\" below to apply themes manually.")
                }
            }
        }

        // 2-column grid: first cell is the "Save new theme" card, then existing themes
        GridLayout {
            id: themeGrid
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            // ── Save (new) card ──
            Rectangle {
                id: saveCard
                Layout.fillWidth: true
                // Preferred height grows to match the image when this card
                // is the only one in the grid (full row width → tall 9:16
                // image → card needs ~width*9/16+20 to contain it). Once
                // the user saves themes, the layout splits the row and the
                // card width drops by half, so the standard 260px is plenty
                // for the half-width image plus margins. Width-only
                // dependency, so no binding loop with the layout's height.
                Layout.preferredHeight: root.orderedThemes.length === 0
                    ? Math.round(saveCard.width * 9 / 16) + 20
                    : 260
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // 16:9 preview with camera overlay
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 9 / 16

                        ThumbnailImage {
                            id: saveWallpaper
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            // Same thumbnail, same size and fill mode as Quick
                            // Setup's preview, so the two share one cache entry
                            // rather than decoding the wallpaper twice.
                            sourcePath: Config.options.background.wallpaperPath || ""
                            sourceSize: Images.wallpaperPreviewSourceSize
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: saveWallpaper.width
                                    height: saveWallpaper.height
                                    radius: Appearance.rounding.small
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: Qt.rgba(Appearance.m3colors.m3surface.r, Appearance.m3colors.m3surface.g, Appearance.m3colors.m3surface.b, 0.4)
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "photo_camera"
                                iconSize: 40
                                color: Appearance.m3colors.m3onSurface
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Save current as theme")
                                color: Appearance.m3colors.m3onSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.beginSave("")
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Existing theme cards ──
            Repeater {
                model: root.orderedThemes
                delegate: Rectangle {
                    id: themeCard
                    required property var modelData
                    readonly property bool isActive: modelData.slug === root.lastAppliedSlug
                    readonly property bool busy: root.applyInFlight
                    Layout.fillWidth: true
                    Layout.preferredHeight: 260
                    radius: Appearance.rounding.normal
                    color: isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Preview 16:9
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 9 / 16

                            StyledImage {
                                id: themePreview
                                anchors.fill: parent
                                fillMode: ThemeLibrary.previewFillMode
                                source: ThemeLibrary.previewUrl(themeCard.modelData)
                                sourceSize: ThemeLibrary.previewSourceSize
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: themePreview.width
                                        height: themePreview.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: themeCard.modelData.name
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: themeCard.isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                        }

                        // Two buttons: Apply/Update + Delete — styled like the
                        // toggled/selected state of SelectionGroupButton (primary
                        // background + onPrimary content), keeping the existing
                        // rounded-corner shape instead of the pill shape.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                buttonRadius: Appearance.rounding.full
                                // The active card's button is "Update" (a save,
                                // see beginSave below) and stays enabled even
                                // when the scheduler is on — saving is always
                                // allowed. Non-active cards show "Apply" and
                                // get locked while root.scheduleActive is true
                                // to prevent the schedule from immediately
                                // reverting the user's pick.
                                readonly property bool gated: root.scheduleActive && !themeCard.isActive
                                enabled: !themeCard.busy && !gated
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                // RippleButton's default buttonColor fully
                                // transparentizes the container when enabled=
                                // false, which makes the Apply button vanish
                                // into the card background — confusing UX.
                                opacity: 1
                                buttonColor: enabled
                                    ? ColorUtils.transparentize(toggled
                                        ? (hovered ? colBackgroundToggledHover : colBackgroundToggled)
                                        : (hovered ? colBackgroundHover : colBackground), 0)
                                    : root.colUnavailable
                                onClicked: themeCard.isActive
                                    ? root.beginSave(themeCard.modelData.slug)
                                    : root.applyTheme(themeCard.modelData)
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: themeCard.isActive ? "refresh" : "check"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: themeCard.busy || (root.scheduleActive && !themeCard.isActive)
                                                ? root.colOnUnavailable
                                                : Appearance.colors.colOnPrimary
                                            fill: 1
                                        }
                                        StyledText {
                                            text: themeCard.isActive ? Translation.tr("Update") : Translation.tr("Apply")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: themeCard.busy || (root.scheduleActive && !themeCard.isActive)
                                                ? root.colOnUnavailable
                                                : Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }
                            // Icon-only so the two labelled actions keep the
                            // width they need; the tooltip carries the label.
                            RippleButton {
                                id: exportButton
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 34
                                buttonRadius: Appearance.rounding.full
                                enabled: !themeCard.busy && !root.ioBusy
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                opacity: 1
                                buttonColor: enabled
                                    ? (hovered ? colBackgroundHover : colBackground)
                                    : root.colUnavailable
                                onClicked: root.exportTheme(themeCard.modelData)
                                contentItem: Item {
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "upload"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: exportButton.enabled
                                            ? Appearance.colors.colOnPrimary
                                            : root.colOnUnavailable
                                        fill: 1
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Export theme to a file")
                                }
                            }
                            RippleButton {
                                id: deleteButton
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                buttonRadius: Appearance.rounding.full
                                enabled: !themeCard.busy && !root.ioBusy
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                opacity: 1
                                buttonColor: enabled
                                    ? (hovered ? colBackgroundHover : colBackground)
                                    : root.colUnavailable
                                onClicked: root.deleteTheme(themeCard.modelData)
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: deleteButton.enabled
                                                ? Appearance.colors.colOnPrimary
                                                : root.colOnUnavailable
                                            fill: 1
                                        }
                                        StyledText {
                                            text: Translation.tr("Delete")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: deleteButton.enabled
                                                ? Appearance.colors.colOnPrimary
                                                : root.colOnUnavailable
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Section divider ─────────────────────────────────────────────────────
    // Material 3 full-bleed Divider (1dp at outline-variant) marking the
    // hard break between Themes and Day/Night Themes — these are unrelated
    // enough that the eye should register them as separate pages of intent
    // rather than a continuous flow.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 24
        Layout.bottomMargin: 12
        implicitHeight: 1
        color: Appearance.m3colors.m3outlineVariant
    }

    // ── Day/Night Themes ────────────────────────────────────────────────────
    // Pairs two saved themes to time-of-day. "Off" leaves the user's current
    // selection alone; "Follow Night Light" keys on Hyprsunset.shouldBeOn so
    // theme transitions line up with the Night Light filter; "Set hours"
    // reveals 12-hour pickers under each card. Auto-apply itself lives in
    // ThemeManager so transitions still fire when this Settings window is
    // closed — the UI here just writes Config.options.appearance.themeSchedule.
    ContentSection {
        icon: "wb_twilight"
        title: Translation.tr("Day/Night Themes")
        Layout.fillWidth: true

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            // Bigger bottom margin pushes the description well clear of the
            // Day / Night card row so the cards don't hug the explainer.
            Layout.bottomMargin: 24
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Pair two of your saved themes to time of day. Pick a Day theme and a Night theme, then choose how the switch happens — follow the Night Light schedule or set your own day-start and night-start times. Off keeps whichever theme you applied last.")
        }

        // Card row: Day | + | Night, treated as three explicit sections so
        // the day and night cards always share an identical width and the
        // "+" sits in its own narrow column between them.
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // ── Day column ──────────────────────────────────────────────────
            ColumnLayout {
                id: dayCol
                // Both Day and Night columns share Layout.fillWidth + the
                // same Layout.preferredWidth so the layout splits any extra
                // space between them in equal halves regardless of which
                // column has the wider implicit content (e.g. AM/PM picker).
                // The "+" column has no fillWidth and gets only its own
                // implicit width.
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 6
                readonly property string slug: Config.options.appearance.themeSchedule.daySlug
                readonly property var theme: root.themes.find(t => t.slug === dayCol.slug) || null

                // Icon + title above the card, centred
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    MaterialSymbol {
                        text: "wb_sunny"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Day")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Screenshot of the picked theme; placeholder when unset.
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StyledImage {
                                id: dayPreview
                                anchors.fill: parent
                                fillMode: ThemeLibrary.previewFillMode
                                visible: dayCol.theme !== null
                                source: ThemeLibrary.previewUrl(dayCol.theme)
                                sourceSize: ThemeLibrary.previewSourceSize
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: dayPreview.width
                                        height: dayPreview.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: !dayPreview.visible
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "wb_sunny"
                                        iconSize: 32
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Translation.tr("Pick a theme")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }
                        }

                        // Theme dropdown UNDER the screenshot, centred.
                        StyledComboBox {
                            Layout.fillWidth: true
                            model: [Translation.tr("— None —")].concat(root.themes.map(t => t.name))
                            currentIndex: {
                                if (!dayCol.slug) return 0
                                const idx = root.themes.findIndex(t => t.slug === dayCol.slug)
                                return idx >= 0 ? idx + 1 : 0
                            }
                            onActivated: index => {
                                const slug = (index === 0) ? "" : root.themes[index - 1].slug
                                Config.options.appearance.themeSchedule.daySlug = slug
                                // If the schedule says it's currently day,
                                // pick this slug as the active theme right
                                // now — same outcome as clicking Apply on
                                // it in the Themes section above.
                                if (slug && root._isCurrentlyDay()) {
                                    const theme = root.themes.find(t => t.slug === slug)
                                    if (theme) root.applyTheme(theme)
                                }
                            }
                        }
                    }
                }

                // Day-start time picker, only visible in "manual" schedule mode.
                // Mirrors the Night Light "Turn on" / "Turn off" pickers in
                // DisplayConfig.qml — same ConfigSpinBox widget, same 70px
                // preferred width, same equality-guarded onValueChanged
                // round-trip — so the two pickers feel identical to the user.
                // AM is locked because the card is the Day side — letting the
                // user pick PM here would contradict the card's identity.
                // Any saved-PM time gets normalised to AM the moment the user
                // touches either spinner.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    visible: Config.options.appearance.themeSchedule.mode === "manual"
                    ConfigSpinBox {
                        Layout.preferredWidth: 70
                        from: 1
                        to: 12
                        value: root.tsParse12(Config.options.appearance.themeSchedule.dayFrom).hour12
                        onValueChanged: {
                            const m = root.tsParse12(Config.options.appearance.themeSchedule.dayFrom).minute
                            const next = root.tsTo24(value, m, "AM")
                            if (next !== Config.options.appearance.themeSchedule.dayFrom)
                                Config.options.appearance.themeSchedule.dayFrom = next
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: ":"
                        color: Appearance.colors.colOnLayer1
                    }
                    ConfigSpinBox {
                        Layout.preferredWidth: 70
                        from: 0
                        to: 59
                        value: root.tsParse12(Config.options.appearance.themeSchedule.dayFrom).minute
                        onValueChanged: {
                            const h = root.tsParse12(Config.options.appearance.themeSchedule.dayFrom).hour12
                            const next = root.tsTo24(h, value, "AM")
                            if (next !== Config.options.appearance.themeSchedule.dayFrom)
                                Config.options.appearance.themeSchedule.dayFrom = next
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "AM"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }

            // ── "+" between cards ───────────────────────────────────────────
            // No fillWidth — this column takes only its implicit width so
            // the Day and Night columns split the rest evenly. The leading
            // spacer matches the icon-title row above each card so the "+"
            // glyph aligns vertically with the screenshots, not the labels.
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 24
                spacing: 0
                Item { implicitHeight: 28 }   // matches icon-title row height
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 200
                    text: "add"
                    iconSize: Appearance.font.pixelSize.title
                    color: Appearance.colors.colSubtext
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // ── Night column ────────────────────────────────────────────────
            ColumnLayout {
                id: nightCol
                Layout.fillWidth: true
                Layout.preferredWidth: 1   // mirrors dayCol — see comment there
                spacing: 6
                readonly property string slug: Config.options.appearance.themeSchedule.nightSlug
                readonly property var theme: root.themes.find(t => t.slug === nightCol.slug) || null

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    MaterialSymbol {
                        text: "bedtime"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Night")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StyledImage {
                                id: nightPreview
                                anchors.fill: parent
                                fillMode: ThemeLibrary.previewFillMode
                                visible: nightCol.theme !== null
                                source: ThemeLibrary.previewUrl(nightCol.theme)
                                sourceSize: ThemeLibrary.previewSourceSize
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: nightPreview.width
                                        height: nightPreview.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: !nightPreview.visible
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "bedtime"
                                        iconSize: 32
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Translation.tr("Pick a theme")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }
                        }

                        StyledComboBox {
                            Layout.fillWidth: true
                            model: [Translation.tr("— None —")].concat(root.themes.map(t => t.name))
                            currentIndex: {
                                if (!nightCol.slug) return 0
                                const idx = root.themes.findIndex(t => t.slug === nightCol.slug)
                                return idx >= 0 ? idx + 1 : 0
                            }
                            onActivated: index => {
                                const slug = (index === 0) ? "" : root.themes[index - 1].slug
                                Config.options.appearance.themeSchedule.nightSlug = slug
                                if (slug && root._isCurrentlyNight()) {
                                    const theme = root.themes.find(t => t.slug === slug)
                                    if (theme) root.applyTheme(theme)
                                }
                            }
                        }
                    }
                }

                // Night-start time picker. PM is locked because the card is
                // the Night side — same rationale as the Day picker's locked
                // AM. See that picker for the full reasoning.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    visible: Config.options.appearance.themeSchedule.mode === "manual"
                    ConfigSpinBox {
                        Layout.preferredWidth: 70
                        from: 1
                        to: 12
                        value: root.tsParse12(Config.options.appearance.themeSchedule.nightFrom).hour12
                        onValueChanged: {
                            const m = root.tsParse12(Config.options.appearance.themeSchedule.nightFrom).minute
                            const next = root.tsTo24(value, m, "PM")
                            if (next !== Config.options.appearance.themeSchedule.nightFrom)
                                Config.options.appearance.themeSchedule.nightFrom = next
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: ":"
                        color: Appearance.colors.colOnLayer1
                    }
                    ConfigSpinBox {
                        Layout.preferredWidth: 70
                        from: 0
                        to: 59
                        value: root.tsParse12(Config.options.appearance.themeSchedule.nightFrom).minute
                        onValueChanged: {
                            const h = root.tsParse12(Config.options.appearance.themeSchedule.nightFrom).hour12
                            const next = root.tsTo24(h, value, "PM")
                            if (next !== Config.options.appearance.themeSchedule.nightFrom)
                                Config.options.appearance.themeSchedule.nightFrom = next
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: "PM"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }
        }

        // Schedule mode dropdown — centred under the card row.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Item { Layout.fillWidth: true }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("Schedule")
                color: Appearance.colors.colOnLayer1
            }
            StyledComboBox {
                Layout.preferredWidth: 200
                // "Follow Night Light" is only offered while Night Light
                // itself is enabled; a stored "nightlight" mode with Night
                // Light disabled displays as Off.
                readonly property bool nightLightAvailable: (Config.options.light.night.mode ?? "disabled") !== "disabled"
                model: nightLightAvailable
                    ? [Translation.tr("Off"), Translation.tr("Follow Night Light"), Translation.tr("Set hours")]
                    : [Translation.tr("Off"), Translation.tr("Set hours")]
                readonly property var indexMode: nightLightAvailable
                    ? ["off", "nightlight", "manual"]
                    : ["off", "manual"]
                currentIndex: Math.max(0, indexMode.indexOf(Config.options.appearance.themeSchedule.mode))
                onActivated: index => {
                    Config.options.appearance.themeSchedule.mode = indexMode[index]
                }
            }
            Item { Layout.fillWidth: true }
        }
    }

    // ── Export: include the slideshow pictures? ─────────────────────────────
    Rectangle {
        id: exportDialogScrim
        visible: root.exportDialogOpen
        parent: Overlay.overlay
        anchors.fill: parent
        color: Qt.rgba(Appearance.m3colors.m3scrim.r, Appearance.m3colors.m3scrim.g, Appearance.m3colors.m3scrim.b, 0.53)
        z: 1000
        MouseArea {
            anchors.fill: parent
            onClicked: root.exportDialogOpen = false
        }

        Rectangle {
            anchors.centerIn: parent
            implicitWidth: 420
            implicitHeight: exportDialogCol.implicitHeight + 40
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            MouseArea { anchors.fill: parent } // absorb click-through

            ColumnLayout {
                id: exportDialogCol
                anchors {
                    fill: parent
                    margins: 20
                }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    MaterialSymbol {
                        text: "photo_library"
                        iconSize: 28
                        fill: 1
                        color: Appearance.m3colors.m3primary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Include the slideshow wallpapers?")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WordWrap
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${root.exportImageCount} ${Translation.tr("images")} · ${root.exportImageMib.toFixed(0)} MB`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Without them the theme still carries its colors, fonts and decorations — the slideshow simply arrives switched off.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        padding: 10
                        onClicked: {
                            root.exportDialogOpen = false
                            root.runExport(false)
                        }
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Skip")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        padding: 10
                        colBackground: Appearance.m3colors.m3primary
                        onClicked: {
                            root.exportDialogOpen = false
                            root.runExport(true)
                        }
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Include")
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
            }
        }
    }

    // ── Save dialog (modal-style popup inside page) ─────────────────────────
    Rectangle {
        id: saveDialogScrim
        visible: root.saveDialogOpen
        parent: Overlay.overlay
        anchors.fill: parent
        color: Qt.rgba(Appearance.m3colors.m3scrim.r, Appearance.m3colors.m3scrim.g, Appearance.m3colors.m3scrim.b, 0.53)
        z: 1000
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!root.countingDown) root.saveDialogOpen = false
            }
        }

        Rectangle {
            id: saveDialog
            anchors.centerIn: parent
            implicitWidth: 420
            implicitHeight: saveDialogCol.implicitHeight + 40
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            MouseArea { anchors.fill: parent } // absorb click-through

            ColumnLayout {
                id: saveDialogCol
                anchors {
                    fill: parent
                    margins: 20
                }
                spacing: 14

                StyledText {
                    text: root.pendingUpdateSlug
                        ? Translation.tr("Update theme")
                        : Translation.tr("Save current as theme")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }

                // Name field
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.m3colors.m3outlineVariant

                    TextField {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: Translation.tr("Theme name")
                        background: null
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.m3colors.m3outline
                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.small
                            variableAxes: Appearance.font.variableAxes.main
                        }
                        text: root.saveThemeName
                        onTextChanged: root.saveThemeName = text
                        enabled: !root.countingDown
                    }
                }

                // Countdown slider
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: Translation.tr("Screenshot delay")
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: root.countingDown
                                ? Translation.tr("%1s…").arg(root.countdownLeft)
                                : Translation.tr("%1s").arg(root.countdownMax)
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    Slider {
                        id: countdownSlider
                        Layout.fillWidth: true
                        from: 1; to: 30; stepSize: 1
                        value: root.countdownMax
                        enabled: !root.countingDown
                        onMoved: root.countdownMax = Math.round(value)
                        background: Rectangle {
                            x: countdownSlider.leftPadding
                            y: countdownSlider.topPadding + countdownSlider.availableHeight / 2 - height / 2
                            width: countdownSlider.availableWidth; height: 3; radius: 2
                            color: Appearance.colors.colLayer3
                            Rectangle {
                                width: countdownSlider.visualPosition * parent.width
                                height: parent.height; radius: 2
                                color: Appearance.m3colors.m3primary
                            }
                        }
                        handle: Rectangle {
                            x: countdownSlider.leftPadding + countdownSlider.visualPosition * (countdownSlider.availableWidth - width)
                            y: countdownSlider.topPadding + countdownSlider.availableHeight / 2 - height / 2
                            width: 14; height: 14; radius: 7
                            color: countdownSlider.pressed ? Qt.lighter(Appearance.m3colors.m3primary, 1.2) : Appearance.m3colors.m3primary
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }
                    }
                    StyledText {
                        text: Translation.tr("Settings window hides during delay so the shot doesn't include it")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        padding: 10
                        enabled: !root.countingDown
                        onClicked: root.saveDialogOpen = false
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Cancel")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    RippleButton {
                        id: saveConfirmButton
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        padding: 10
                        colBackground: Appearance.m3colors.m3primary
                        enabled: !root.countingDown && (root.pendingUpdateSlug !== "" || root.saveThemeName.trim().length > 0)
                        opacity: 1
                        buttonColor: enabled
                            ? (hovered ? colBackgroundHover : colBackground)
                            : root.colUnavailable
                        onClicked: root.startCountdownAndCapture()
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: root.countingDown
                                ? Translation.tr("%1…").arg(root.countdownLeft)
                                : Translation.tr("Save")
                            color: saveConfirmButton.enabled
                                ? Appearance.m3colors.m3onPrimary
                                : root.colOnUnavailable
                        }
                    }
                }
            }
        }
    }
}
