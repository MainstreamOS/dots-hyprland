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
    readonly property string shellConfigDir: Directories.shellConfig
    readonly property string shellConfigPath: Directories.shellConfigPath
    readonly property string themesDir: homePath + "/.config/mainstream/themes"
    readonly property string themesIndex: themesDir + "/index.json"
    readonly property string lastAppliedPath: themesDir + "/last-applied.txt"

    // ── State ────────────────────────────────────────────────────────────────
    property var themes: []
    property string lastAppliedSlug: ""
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
    property string applyingSlug: ""

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
    function showStatus(msg) {
        root.statusMessage = msg
        statusTimer.restart()
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

    // ── Init ─────────────────────────────────────────────────────────────────
    Component.onCompleted: ensureDirsProc.running = true

    Process {
        id: ensureDirsProc
        command: ["bash", "-c",
            `mkdir -p '${root.themesDir}' && ` +
            `if [ ! -f '${root.themesIndex}' ]; then echo '[]' > '${root.themesIndex}'; fi`
        ]
        onExited: loadIndexProc.running = true
    }

    Process {
        id: loadIndexProc
        property string buf: ""
        command: ["cat", root.themesIndex]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => loadIndexProc.buf += data }
        onExited: {
            let parsed = []
            try { parsed = JSON.parse(loadIndexProc.buf || "[]") } catch (e) { parsed = [] }
            root.themes = parsed || []
            loadLastAppliedProc.running = false
            loadLastAppliedProc.running = true
        }
    }

    Process {
        id: loadLastAppliedProc
        property string buf: ""
        command: ["bash", "-c", `[ -f '${root.lastAppliedPath}' ] && cat '${root.lastAppliedPath}' || true`]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => loadLastAppliedProc.buf += data }
        onExited: root.lastAppliedSlug = (loadLastAppliedProc.buf || "").trim()
    }

    // Live-track last-applied.txt so this Settings page updates the
    // "active" highlight in the Themes section the moment any apply
    // happens — including ones the main shell's ThemeManager fires on
    // its own (clock-minute crossings, Hyprsunset schedule transitions).
    // Without this, the page only reflected applies it initiated itself.
    FileView {
        path: root.lastAppliedPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lastAppliedSlug = (text() || "").trim()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) root.lastAppliedSlug = ""
        }
    }

    function refreshThemes() { loadIndexProc.running = false; loadIndexProc.running = true }

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
        const wp = Config.options.background.wallpaperPath || ""
        const wpTrimmed = FileUtils.trimFileProtocol(wp)
        const modeStr = Appearance.m3colors.darkmode ? "dark" : "light"
        root.lastSavedSlug = slug
        // Build bash payload
        const bash =
            `set -e\n` +
            `SLUG='${String(slug).replace(/'/g, "'\\''")}'\n` +
            `NAME='${String(name).replace(/'/g, "'\\''")}'\n` +
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
            // apply-theme.sh ALSO preserves these from the live config when
            // applying, so older themes that still carry these keys won't
            // poison the user's settings either.
            `jq 'del(.appearance.themeSchedule) | del(.light.night)' '${root.shellConfigPath}' > "$DIR/config.json"\n` +
            (wpTrimmed ? `WP='${wpTrimmed}'\n` +
                         `EXT="\${WP##*.}"\n` +
                         `cp -f "$WP" "$DIR/wallpaper.$EXT"\n` +
                         `WP_FILE="wallpaper.$EXT"\n`
                       : `WP_FILE=""\n`) +
            // Screenshot of primary focused monitor. Always overwrites
            // preview.png — same path whether this is a brand-new save
            // or an Update on an existing theme.
            `FOCUSED=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)\n` +
            `if [ -n "$FOCUSED" ]; then grim -o "$FOCUSED" "$DIR/preview.png"; else grim "$DIR/preview.png"; fi\n` +
            // Millisecond resolution so back-to-back Update saves (within
            // the same wall-clock second) still produce a distinct
            // `created` value. The grid's preview Image keys its
            // cache-bust URL off this — if two saves landed in the same
            // second, the URL wouldn't change and the QML Image cache
            // could keep showing the previous frame even though
            // preview.png on disk was already overwritten.
            `CREATED=$(date +%s%3N)\n` +
            `cat > "$DIR/meta.json" <<EOF\n` +
            `{"slug":"$SLUG","name":"$NAME","wallpaperFile":"$WP_FILE","mode":"$MODE","created":$CREATED}\n` +
            `EOF\n` +
            // Snapshot current decoration flags (Lua-config syntax — same
            // parsing logic as InterfaceConfig.qml's decoReader). Applying
            // this theme later restores the look the user had at save time.
            `GENERAL='${root.homePath}/.config/hypr/hyprland/general.lua'\n` +
            `CUSTOM='${root.homePath}/.config/hypr/custom/general.lua'\n` +
            `python3 - "$DIR/decorations.json" "$GENERAL" "$CUSTOM" <<'PY'\n` +
            `import json, os, re, sys\n` +
            `out_path, general, custom = sys.argv[1], sys.argv[2], sys.argv[3]\n` +
            `def truthy(v): return v.lower() in ("true", "1", "yes", "on")\n` +
            `flags = {}\n` +
            `try:\n` +
            `    text = open(general).read()\n` +
            `    for key, block in (("animations", "animations"), ("blur", "blur"), ("shadow", "shadow")):\n` +
            `        m = re.search(block + r"\\s*=\\s*\\{[^}]*?enabled\\s*=\\s*(\\w+)", text, re.S)\n` +
            `        if m: flags[key] = truthy(m.group(1))\n` +
            `    bm = re.search(r"^(\\s*)(--\\s*)?border_size\\s*=", text, re.M)\n` +
            `    flags["borders"] = bool(bm and not bm.group(2))\n` +
            `    rm = re.search(r"^\\s*rounding\\s*=\\s*(\\d+)", text, re.M)\n` +
            `    if rm: flags["roundCorners"] = int(rm.group(1)) > 0\n` +
            `except FileNotFoundError: pass\n` +
            `try:\n` +
            `    flags["titleBars"] = bool(re.search(r"^[ \\t]*hl\\.plugin\\.load\\([^)]*hyprbars\\.so", open(custom).read(), re.M))\n` +
            `except FileNotFoundError: pass\n` +
            `with open(out_path, "w") as f: json.dump(flags, f, indent=2)\n` +
            `PY\n` +
            // Newly saved themes are treated as the currently applied theme.
            `printf '%s' "$SLUG" > '${root.lastAppliedPath}.tmp' && mv -f '${root.lastAppliedPath}.tmp' '${root.lastAppliedPath}'\n` +
            // Rebuild index
            `python3 - "$THEMES" <<'PY'\n` +
            `import json, os, sys\n` +
            `themes_dir = sys.argv[1]\n` +
            `out = []\n` +
            `for name in sorted(os.listdir(themes_dir)):\n` +
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
        function onExited() {
            root.countingDown = false
            root.saveDialogOpen = false
            root.pendingUpdateSlug = ""
            root.restoreWindowAfterShot()
            if (root.lastSavedSlug) root.lastAppliedSlug = root.lastSavedSlug
            root.lastSavedSlug = ""
            root.refreshThemes()
            root.showStatus(Translation.tr("Theme saved"))
        }
    }

    // ── Apply theme (via shell IPC — atomic, race-free) ─────────────────────
    Process { id: ipcApplyProc }
    function applyTheme(theme) {
        if (root.applyingSlug) return
        root.applyingSlug = theme.slug
        ipcApplyProc.command = ["qs", "-c", "ii", "ipc", "call", "themes", "apply", theme.slug]
        ipcApplyProc.running = false
        ipcApplyProc.running = true
        // Optimistic UI update — the script also writes last-applied.txt.
        root.lastAppliedSlug = theme.slug
        root.showStatus(Translation.tr("Applying theme: %1").arg(theme.name))
    }
    Connections {
        target: ipcApplyProc
        function onExited() {
            root.applyingSlug = ""
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

        const safeSlug = String(theme.slug).replace(/'/g, "\\'\\''")
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
                root.lastAppliedSlug = ""
            }
            root.refreshThemes()
            root.showStatus(Translation.tr("Theme deleted"))
        }
    }

    // ── UI ───────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "style"
        title: Translation.tr("Themes")
        Layout.fillWidth: true

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 10
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("A theme is a snapshot of your current look — wallpaper, colors, UI changes, and window decorations. Tap \"Save current as theme\" to capture what's on screen, then switch between saved themes any time with one tap. Use \"Update\" on the active theme to overwrite it with your latest tweaks.")
        }

        // Status line
        StyledText {
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            Layout.fillWidth: true
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

                        StyledImage {
                            id: saveWallpaper
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            source: Config.options.background.wallpaperPath || ""
                            sourceSize.width: parent.width
                            sourceSize.height: parent.height
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
                    required property int index
                    readonly property bool isActive: modelData.slug === root.lastAppliedSlug
                    readonly property bool busy: root.applyingSlug.length > 0
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
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                source: "file://" + root.themesDir + "/" + themeCard.modelData.slug + "/preview.png?v=" + (themeCard.modelData.created || 0)
                                sourceSize.width: parent.width
                                sourceSize.height: parent.height
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
                                // into the card background — confusing UX. Use
                                // the M3 filled-button disabled spec instead
                                // (onSurface tint at 12% alpha) so the button
                                // stays visibly a button, just clearly inactive.
                                buttonColor: enabled
                                    ? ColorUtils.transparentize(toggled
                                        ? (hovered ? colBackgroundToggledHover : colBackgroundToggled)
                                        : (hovered ? colBackgroundHover : colBackground), 0)
                                    : ColorUtils.applyAlpha(Appearance.m3colors.m3onSurface, 0.12)
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
                                            // Match the container's M3 disabled
                                            // treatment — neutral onSurface tint
                                            // when disabled (busy or gated by
                                            // schedule) instead of the bright
                                            // colOnPrimary that's only legible
                                            // on the primary background.
                                            color: themeCard.busy || (root.scheduleActive && !themeCard.isActive)
                                                ? Appearance.m3colors.m3onSurface
                                                : Appearance.colors.colOnPrimary
                                            fill: 1
                                        }
                                        StyledText {
                                            text: themeCard.isActive ? Translation.tr("Update") : Translation.tr("Apply")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: themeCard.busy || (root.scheduleActive && !themeCard.isActive)
                                                ? Appearance.m3colors.m3onSurface
                                                : Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }
                            RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                buttonRadius: Appearance.rounding.full
                                enabled: !themeCard.busy
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                onClicked: root.deleteTheme(themeCard.modelData)
                                contentItem: Item {
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "delete"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colOnPrimary
                                            fill: 1
                                        }
                                        StyledText {
                                            text: Translation.tr("Delete")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnPrimary
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
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                visible: dayCol.theme !== null
                                source: dayCol.theme
                                    ? "file://" + root.themesDir + "/" + dayCol.slug + "/preview.png?v=" + (dayCol.theme.created || 0)
                                    : ""
                                sourceSize.width: parent.width
                                sourceSize.height: parent.height
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
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                visible: nightCol.theme !== null
                                source: nightCol.theme
                                    ? "file://" + root.themesDir + "/" + nightCol.slug + "/preview.png?v=" + (nightCol.theme.created || 0)
                                    : ""
                                sourceSize.width: parent.width
                                sourceSize.height: parent.height
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
                model: [
                    Translation.tr("Off"),
                    Translation.tr("Follow Night Light"),
                    Translation.tr("Set hours"),
                ]
                readonly property var modeIndex: ({ "off": 0, "nightlight": 1, "manual": 2 })
                readonly property var indexMode: ["off", "nightlight", "manual"]
                currentIndex: modeIndex[Config.options.appearance.themeSchedule.mode] ?? 0
                onActivated: index => {
                    Config.options.appearance.themeSchedule.mode = indexMode[index]
                }
            }
            Item { Layout.fillWidth: true }
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
                        buttonRadius: Appearance.rounding.full
                        implicitHeight: 36
                        padding: 10
                        colBackground: Appearance.m3colors.m3primary
                        enabled: !root.countingDown && (root.pendingUpdateSlug !== "" || root.saveThemeName.trim().length > 0)
                        onClicked: root.startCountdownAndCapture()
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: root.countingDown
                                ? Translation.tr("%1…").arg(root.countdownLeft)
                                : Translation.tr("Save")
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
            }
        }
    }
}
