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
    property int  countdownMax: 5      // slider value 0–30
    property int  countdownLeft: 0
    property string saveThemeName: ""
    property string pendingUpdateSlug: ""   // when non-empty, save flow updates that slug
    property string lastSavedSlug: ""       // set in doCapture, consumed in saveProc.onExited
    property string statusMessage: ""
    property int  statusTimeoutMs: 4000

    // While an apply is in flight the card buttons are disabled so a user
    // can't pile-up successive applies before the previous one settles.
    property string applyingSlug: ""

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

    function refreshThemes() { loadIndexProc.running = false; loadIndexProc.running = true }

    // ── Save theme (capture) ────────────────────────────────────────────────
    Process { id: saveProc }
    function beginSave(updateSlug) {
        root.pendingUpdateSlug = updateSlug || ""
        root.saveThemeName = updateSlug
            ? (root.themes.find(t => t.slug === updateSlug)?.name || "")
            : ""
        root.countdownMax = 5
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

    Process {
        id: hideWindowProc
        property string buf: ""
        command: ["bash", "-c",
            "ADDR=$(hyprctl activewindow -j | jq -r '.address') && " +
            "echo \"$ADDR\" && " +
            "hyprctl dispatch movetoworkspacesilent \"special:themecap,address:$ADDR\" >/dev/null"
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
        restoreWindowProc.command = ["bash", "-c",
            "WS=$(hyprctl activeworkspace -j | jq -r '.id') && " +
            "hyprctl dispatch movetoworkspacesilent \"$WS,address:" + root.hyprWindowAddr + "\" >/dev/null && " +
            "hyprctl dispatch focuswindow \"address:" + root.hyprWindowAddr + "\" >/dev/null"
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
        const keepPreview = root.pendingUpdateSlug !== ""
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
            `cp -f '${root.shellConfigPath}' "$DIR/config.json"\n` +
            (wpTrimmed ? `WP='${wpTrimmed}'\n` +
                         `EXT="\${WP##*.}"\n` +
                         `cp -f "$WP" "$DIR/wallpaper.$EXT"\n` +
                         `WP_FILE="wallpaper.$EXT"\n`
                       : `WP_FILE=""\n`) +
            // Screenshot of primary focused monitor
            (keepPreview
                ? `# Keep existing preview on update\n`
                : `FOCUSED=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)\n` +
                  `if [ -n "$FOCUSED" ]; then grim -o "$FOCUSED" "$DIR/preview.png"; else grim "$DIR/preview.png"; fi\n`) +
            `CREATED=$(date +%s)\n` +
            `cat > "$DIR/meta.json" <<EOF\n` +
            `{"slug":"$SLUG","name":"$NAME","wallpaperFile":"$WP_FILE","mode":"$MODE","created":$CREATED}\n` +
            `EOF\n` +
            // Snapshot current decoration flags (same parsing logic as
            // InterfaceConfig.qml's decoReader) so applying this theme later
            // restores the look the user had at save time.
            `GENERAL='${root.homePath}/.config/hypr/hyprland/general.conf'\n` +
            `CUSTOM='${root.homePath}/.config/hypr/custom/general.conf'\n` +
            `python3 - "$DIR/decorations.json" "$GENERAL" "$CUSTOM" <<'PY'\n` +
            `import json, os, re, sys\n` +
            `out_path, general, custom = sys.argv[1], sys.argv[2], sys.argv[3]\n` +
            `def truthy(v): return v.lower() in ("true", "1", "yes", "on")\n` +
            `flags = {}\n` +
            `try:\n` +
            `    text = open(general).read()\n` +
            `    for key, block in (("animations", "animations"), ("blur", "blur"), ("shadow", "shadow")):\n` +
            `        m = re.search(block + r"\\s*\\{[^}]*?enabled\\s*=\\s*(\\w+)", text, re.S)\n` +
            `        if m: flags[key] = truthy(m.group(1))\n` +
            `    bm = re.search(r"^(\\s*)(#\\s*)?border_size\\s*=", text, re.M)\n` +
            `    flags["borders"] = bool(bm and not bm.group(2))\n` +
            `    rm = re.search(r"^\\s*rounding\\s*=\\s*(\\d+)", text, re.M)\n` +
            `    if rm: flags["roundCorners"] = int(rm.group(1)) > 0\n` +
            `except FileNotFoundError: pass\n` +
            `try:\n` +
            `    flags["titleBars"] = bool(re.search(r"^[ \\t]*plugin[ \\t]*=[ \\t]*.*hyprbars\\.so", open(custom).read(), re.M))\n` +
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
    Process { id: deleteProc }
    function deleteTheme(theme) {
        const bash =
            `set -e\n` +
            `rm -rf -- '${root.themesDir}/${theme.slug}'\n` +
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
        function onExited() { root.refreshThemes(); root.showStatus(Translation.tr("Theme deleted")) }
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
                Layout.preferredHeight: 260
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
                                source: "file://" + root.themesDir + "/" + themeCard.modelData.slug + "/preview.png"
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
                                enabled: !themeCard.busy
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
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
                                            color: Appearance.colors.colOnPrimary
                                            fill: 1
                                        }
                                        StyledText {
                                            text: themeCard.isActive ? Translation.tr("Update") : Translation.tr("Apply")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnPrimary
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
                        from: 0; to: 30; stepSize: 1
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
                        text: root.pendingUpdateSlug
                            ? Translation.tr("Update keeps the existing screenshot")
                            : Translation.tr("Settings window hides during delay so the shot doesn't include it")
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
