pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter

    // The bar as it ships, shared by first run and "Reset to defaults".
    readonly property var defaultBarLayout: ({
        "left": [
            { "widgets": [ {"id": "resources", "enabled": false} ] },
            { "widgets": [ {"id": "network", "enabled": false} ] },
            { "widgets": [ {"id": "workspaces", "enabled": true} ] },
            { "widgets": [ {"id": "tray", "enabled": true} ] },
            { "widgets": [ {"id": "activeWindowPill", "enabled": false}, {"id": "activeWindow", "enabled": false} ] },
            { "widgets": [ {"id": "sidebarButton", "enabled": true} ] }
        ],
        "center": [
            { "widgets": [ {"id": "utilButtons", "enabled": true} ] },
            { "widgets": [ {"id": "clock", "enabled": true} ] },
            { "widgets": [ {"id": "battery", "enabled": true}, {"id": "weather", "enabled": true}, {"id": "releaseUpdates", "enabled": true} ] }
        ],
        "right": [
            { "widgets": [ {"id": "timers", "enabled": true} ] },
            { "widgets": [ {"id": "media", "enabled": true} ] },
            { "widgets": [ {"id": "volume", "enabled": true}, {"id": "indicators", "enabled": true} ] }
        ]
    })
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    // Set while apply-theme.sh runs. Read from a shared state file so the
    // settings window (its own process) also holds writes that would race the script.
    property bool themeApplyInProgress: false

    // A theme apply rewrites this file before regenerating the colors; holding
    // the reload until the run finishes repaints the desktop once, not twice.
    property bool _reloadDeferred: false

    // Suppresses the self-echo: FileView.reload() fires adapterUpdated, and writing
    // back what was just read races other writers like switchwall.sh.
    property bool _reloading: false

    // Set when the file is rewritten from outside (a theme apply or delete) while writes
    // are held; the held write is then dropped so it cannot undo that edit.
    property bool _writeStale: false

    readonly property string _applyStatePath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
        return `${runtime}/quickshell-theme-apply.state`
    }

    function setNestedValue(nestedKey, value) {
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Convert value to correct type using JSON.parse when safe
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try {
                    convertedValue = JSON.parse(trimmed);
                } catch (e) {
                    convertedValue = value;
                }
            }
        }

        obj[keys[keys.length - 1]] = convertedValue;
    }

    // Files from before bar.layout chose widgets with these switches. Their
    // choices are carried into the layout once; every later write has a layout.
    readonly property var _legacyBarSwitches: ({
        "resources": ["resources", "enable"],
        "volume": ["volumeControl", "enable"]
    })

    function seedBarLayoutFromLegacySwitches() {
        let stored = null
        try {
            stored = JSON.parse(configFileView.text())
        } catch (e) {
            return false
        }
        if (!stored || !stored.bar || stored.bar.layout !== undefined) return false

        let changed = false
        for (const section of ["left", "center", "right"]) {
            const groups = JSON.parse(JSON.stringify(root.options.bar.layout[section] ?? []))
            let touched = false
            for (const group of groups) {
                for (const widget of (group.widgets ?? [])) {
                    const path = root._legacyBarSwitches[widget.id]
                    if (!path) continue
                    const wanted = stored.bar[path[0]]?.[path[1]]
                    if (typeof wanted !== "boolean" || widget.enabled === wanted) continue
                    widget.enabled = wanted
                    touched = true
                }
            }
            if (touched) {
                root.options.bar.layout[section] = groups
                changed = true
            }
        }
        return changed
    }

    // Widget ids the bar does not draw. The editor drops them only when opened,
    // so a saved layout still listing one is scrubbed at load.
    readonly property var retiredBarModules: ["spacer"]

    function scrubRetiredBarModules() {
        const sections = {}
        for (const s of ["left", "center", "right"])
            sections[s] = JSON.parse(JSON.stringify(root.options.bar.layout[s] ?? []))

        // A group may be a bare string or carry `items` instead of `widgets`;
        // reading `widgets` alone would see a full group as empty.
        function holdsSpacer(g) {
            return ObjectUtils.layoutGroupWidgets(g)
                .some(w => root.retiredBarModules.indexOf(w.id) !== -1)
        }
        let changed = false

        // Groups inward of a side spacer rendered beside the center. Move them there
        // so removing the spacer does not drop them against the screen edge.
        for (const side of ["left", "right"]) {
            const groups = sections[side]
            const marks = groups.map(holdsSpacer)
            const at = side === "right" ? marks.indexOf(true) : marks.lastIndexOf(true)
            if (at === -1) continue
            const inward = side === "right" ? groups.slice(0, at) : groups.slice(at + 1)
            if (inward.length === 0) continue
            sections[side] = side === "right" ? groups.slice(at) : groups.slice(0, at + 1)
            sections.center = side === "right" ? sections.center.concat(inward)
                : inward.concat(sections.center)
            changed = true
        }

        for (const s of ["left", "center", "right"]) {
            const kept = []
            for (const group of sections[s]) {
                const widgets = ObjectUtils.layoutGroupWidgets(group)
                const remaining = widgets.filter(w => root.retiredBarModules.indexOf(w.id) === -1)
                // Untouched groups are kept exactly as read; rewriting them is how a
                // layout gets lost.
                if (remaining.length === widgets.length) { kept.push(group); continue }
                changed = true
                if (remaining.length === 0) continue
                // Settle on the `widgets` form alone so no leftover `items` lingers.
                const next = (typeof group === "object" && group !== null) ? group : {}
                delete next.items
                next.widgets = remaining
                kept.push(next)
            }
            sections[s] = kept
        }

        if (changed)
            for (const s of ["left", "center", "right"]) root.options.bar.layout[s] = sections[s]
        return changed
    }

    // Carries a stored useUSCS false into `units` for files that predate it; a stored
    // true was the shipped default, so it may not be a choice. Reads the file, not the
    // adapter: a file that has `units` was already migrated and must not be revisited.
    function migrateWeatherUnits() {
        let stored = null
        try {
            stored = JSON.parse(configFileView.text())
        } catch (e) {
            return false
        }
        const weather = stored?.bar?.weather
        if (!weather || weather.units !== undefined || weather.useUSCS !== false) return false
        if (root.options.bar.weather.units !== "auto") return false
        root.options.bar.weather.units = "metric"
        return true
    }

    // Files from before simpleMenu keep the full session menu their owner knows.
    // Fresh installs write the key with the other defaults and never get here.
    function keepFullSessionMenu() {
        let stored = null
        try {
            stored = JSON.parse(configFileView.text())
        } catch (e) {
            return false
        }
        if (!stored || stored.session?.simpleMenu !== undefined) return false
        root.options.session.simpleMenu = false
        return true
    }

    function reloadFromFile() {
        root._reloading = true
        configFileView.reload()
        Qt.callLater(() => { root._reloading = false })
    }

    onThemeApplyInProgressChanged: {
        if (root.themeApplyInProgress) {
            applyWatchdogTimer.restart()
            return
        }
        applyWatchdogTimer.stop()
        if (root._reloadDeferred) {
            root._reloadDeferred = false
            root.reloadFromFile()
        }
    }

    // A run that is killed outright never reports itself finished, which would
    // otherwise leave reads and writes held back for the rest of the session.
    Timer {
        id: applyWatchdogTimer
        interval: 60000
        repeat: false
        onTriggered: root.themeApplyInProgress = false
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            if (root.themeApplyInProgress) {
                root._reloadDeferred = true
                return
            }
            root.reloadFromFile()
        }
    }

    // Written by apply-theme.sh. FileView can only watch an existing file, so
    // onLoadFailed creates it as "idle" on first run.
    FileView {
        id: applyStateView
        path: root._applyStatePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const s = applyStateView.text().trim()
            root.themeApplyInProgress = (s === "applying")
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                applyStateView.setText("idle")
                root.themeApplyInProgress = false
            }
        }
    }

    // A window running as its own process waits for this before it quits, or
    // the change that started the countdown below would never reach the file.
    readonly property bool writePending: fileWriteTimer.running

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            // Held writes are re-armed, not dropped, so a setting changed or a migration
            // run during a theme apply still reaches the file.
            if (root.blockWrites || root.themeApplyInProgress) {
                fileWriteTimer.restart()
                return
            }
            if (root._writeStale) {
                root._writeStale = false
                return
            }
            configFileView.writeAdapter()
        }
    }

    // No blockLoading: ready must be false while a soft reload matches objects, or
    // the new shell, which starts unlocked, takes over the session lock and unlocks it.
    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites || root.themeApplyInProgress
        onFileChanged: {
            if (root.blockWrites || root.themeApplyInProgress) root._writeStale = true
            fileReloadTimer.restart()
        }
        onAdapterUpdated: {
            if (root._reloading) return
            fileWriteTimer.restart()
        }
        onLoaded: {
            root.ready = true
            // Memory matches disk again, so later writes are not stale.
            root._writeStale = false
            // _reloading may still be set here and swallow onAdapterUpdated's write, so the
            // save is requested directly. Each migration fires only for an older file: a startup
            // write would overwrite the wallpaper path a first login seeds from outside.
            const seeded = root.seedBarLayoutFromLegacySwitches()
            const scrubbed = root.scrubRetiredBarModules()
            const united = root.migrateWeatherUnits()
            const kept = root.keepFullSessionMenu()
            if (seeded || scrubbed || united || kept) fileWriteTimer.restart()
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property JsonObject policies: JsonObject {
                property int ai: 0 // 0: No | 1: Yes | 2: Local
                property int weeb: 0 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string mode: "safe"
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "deepseek-symbolic", // Not mandatory
                        "key_get_link": "https://openrouter.ai/settings/keys", // Not mandatory
                        "key_id": "openrouter",
                        "model": "deepseek/deepseek-r1-distill-llama-70b:free",
                        "name": "Custom: DS R1 Dstl. LLaMA 70B",
                        "requires_key": true
                    }
                ]
            }

            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                // Bar, dock and launcher content adapts to its surface: light or dark, and
                // firmer where a color or transparency would lose it. Off keeps the palette's
                // own tones. Nothing on screen sets it; it is for setups the judgment gets wrong.
                property bool autoIconContrast: true
                // Here rather than in the Hyprland config so a saved theme carries it.
                // from/to are palette role names that follow the current palette; custom
                // mode uses customFrom/customTo instead.
                property JsonObject borderGradient: JsonObject {
                    property bool enable: false
                    property string from: "primary"
                    property string to: "tertiary"
                    property bool custom: false
                    property string customFrom: "#8ab4f8"
                    property string customTo: "#c58af9"
                    property int angle: 90
                    property int opacity: 50
                }
                property JsonObject borderGradientInactive: JsonObject {
                    property bool enable: false
                    property string from: "primary"
                    property string to: "tertiary"
                    property bool custom: false
                    property string customFrom: "#8ab4f8"
                    property string customTo: "#c58af9"
                    property int angle: 90
                    property int opacity: 15
                }
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen
                // What the Rounded Corners switch turns back on to; -1 is nothing
                // remembered. See services/RoundedCorners.qml.
                property JsonObject roundCornersRestore: JsonObject {
                    property int barCornerStyle: -1
                    property int fakeScreenRounding: -1
                    property int windowRounding: -1
                }
                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }
                property JsonObject transparency: JsonObject {
                    property bool enable: true
                    property bool automatic: true
                    property real backgroundTransparency: 0.11
                    property real contentTransparency: 0.57
                }
                property JsonObject wallpaperTheming: JsonObject {
                    property bool enableAppsAndShell: true
                    property bool enableQtApps: true
                    property bool enableTerminal: true
                    property JsonObject terminalGenerationProps: JsonObject {
                        property real harmony: 0.6
                        property real harmonizeThreshold: 100
                        property real termFgBoost: 0.35
                        property bool forceDarkMode: true
                    }
                }
                property JsonObject palette: JsonObject {
                    property string type: "auto" // Allowed: auto, scheme-content, scheme-expressive, scheme-fidelity, scheme-fruit-salad, scheme-monochrome, scheme-neutral, scheme-rainbow, scheme-tonal-spot
                    property string accentColor: ""
                }
                // ThemeManager applies daySlug or nightSlug: "nightlight" follows
                // Hyprsunset.shouldBeOn, "manual" splits the day at dayFrom/nightFrom (HH:mm).
                property JsonObject themeSchedule: JsonObject {
                    property string mode: "off"   // "off" | "nightlight" | "manual"
                    property string daySlug: ""
                    property string nightSlug: ""
                    property string dayFrom: "06:00"
                    property string nightFrom: "20:00"
                }
            }

            property JsonObject audio: JsonObject {
                // Values in %
                property JsonObject protection: JsonObject {
                    // Prevent sudden bangs
                    property bool enable: false
                    property real maxAllowedIncrease: 10
                    property real maxAllowed: 99
                }
            }

            property JsonObject apps: JsonObject {
                property string bluetooth: "blueman-manager"
                property string changePassword: "kitty -1 --hold=yes fish -i -c 'passwd'"
                property string network: "nm-connection-editor"
                property string manageUser: "gnome-control-center"
                property string networkEthernet: "nm-connection-editor"
                property string taskManager: "resources"
                property string terminal: "kitty -1" // This is only for shell actions
                property string update: "kitty -1 --hold=yes fish -i -c 'pkexec pacman -Syu'"
                property string volumeMixer: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"`
            }

            property JsonObject background: JsonObject {
                // x and y put a widget's center across the screen, 0 to 1, so a theme lays them out alike on every monitor.
                property JsonObject widgets: JsonObject {
                    // Frosted glass behind widget cards; loaded on demand, so off builds nothing.
                    property JsonObject blur: JsonObject {
                        property bool enable: false
                        property real radius: 24
                    }
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 0.2
                        property real y: 0.2
                        property string style: "digital"        // Options: "cookie", "digital", "pixel"
                        property string styleLocked: "digital"  // Options: "cookie", "digital", "pixel"
                        property JsonObject cookie: JsonObject {
                            property bool aiStyling: false
                            property int sides: 14
                            property string dialNumberStyle: "numbers"   // Options: "dots" , "numbers", "full" , "none"
                            property string hourHandStyle: "fill"     // Options: "classic", "fill", "hollow", "hide"
                            property string minuteHandStyle: "medium" // Options "classic", "thin", "medium", "bold", "hide"
                            property string secondHandStyle: "dot"    // Options: "dot", "line", "classic", "hide"
                            property string dateStyle: "bubble"       // Options: "border", "rect", "bubble" , "hide"
                            property bool timeIndicators: false
                            property bool hourMarks: false
                            property bool dateInClock: true
                            property bool constantlyRotate: false
                            property bool useSineCookie: false
                        }
                        property JsonObject digital: JsonObject {
                            property bool adaptiveAlignment: true
                            property bool showDate: true
                            property bool animateChange: true
                            property bool vertical: false
                            property JsonObject font: JsonObject {
                                property string family: "Google Sans Flex"
                                property real weight: 350
                                property real width: 100
                                property real size: 90
                                property real roundness: 100
                            }
                        }
                        property JsonObject pixel: JsonObject {
                            property string orientation: "vertical" // "vertical", "horizontal"
                        }
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                            property bool followClock: false
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 0.25
                        property real y: 0.2
                    }
                    property JsonObject calendar: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                        property string sizeMode: "2x2"
                    }
                    property JsonObject worldClock: JsonObject {
                        property bool enable: false
                        property list<string> timezones: ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"]
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                        property string sizeMode: "2x2"
                        property int clockCount: 4
                    }
                    property JsonObject notes: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                    }
                    property JsonObject todo: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                    }
                    property JsonObject visualizer: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.5
                        property real y: 1
                    }
                    property JsonObject customImage: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                        property string path: ""
                        property string shape: "Cookie4Sided"
                        property real size: 200
                    }
                    property JsonObject resources: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                        property bool vertical: false
                    }
                    property JsonObject timers: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free"
                        property real x: 0.25
                        property real y: 0.2
                        property bool vertical: false
                    }
                    property JsonObject media: JsonObject {
                        property bool enable: false
                        property bool showLyrics: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 0.5
                        property real y: 0.5
                        property string sizeMode: "1x3"
                    }
                }
                property bool widgetsLocked: false
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                // A name from the TransitionEffects catalog, or "random".
                property string wallpaperTransition: "ripple"
                // Video wallpaper fps cap, saving power; 0 keeps the file's own rate.
                property int videoFrameRate: 0
                property bool hideWhenFullscreen: true
                // Rotates wallpaperPath through `folder` (empty: the stock Wallpapers folder).
                // Saved themes carry these keys, so the slideshow belongs to the current theme.
                // `recolor` regenerates the palette on every change.
                property JsonObject slideshow: JsonObject {
                    property bool enable: false
                    property string folder: ""
                    property int intervalMinutes: 30
                    property bool shuffle: true
                    property bool recolor: false
                }
                property JsonObject parallax: JsonObject {
                    property bool vertical: false
                    property bool autoVertical: false
                    property bool enableWorkspace: true
                    property real workspaceZoom: 1.0 // Relative to wallpaper size
                    property bool enableSidebar: true
                    property real widgetsFactor: 1.2
                }
            }

            property JsonObject bar: JsonObject {
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int hoverRegionWidth: 2
                    property bool pushWindows: false
                    property JsonObject showWhenPressingSuper: JsonObject {
                        property bool enable: true
                        property int delay: 140
                    }
                }
                property bool bottom: false // Instead of top
                property int cornerStyle: 1 // 0: Hug | 1: Float | 2: Plain rectangle | 3: Notch
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle is 1 (Float) or 3 (Notch)
                property JsonObject hotCorners: JsonObject {
                    // Top-left hot corner: "scrolloverview" (the scrolling overview plugin), "default"
                    // (built-in overview) or "off" (clicks fall through to the bar).
                    property string trigger: "scrolloverview"
                    // Off skips the corner ripple and the wait for it, so the overview opens immediately.
                    property bool animationEnabled: true
                }
                property bool borderless: false // true for no grouping of items
                property string topLeftIcon: "spark" // "spark" shows the logo of the AI model picked in the sidebar, and no button while AI is off; or "distro", or any icon name in ~/.config/quickshell/ii/assets/icons
                property bool showBackground: true
                // Opacity of the bar strip and its widget groups, 0 to 1. Below zero the
                // interface decides.
                property real backgroundOpacity: -1
                property real widgetOpacity: -1
                // Empty lets the palette decide. One slot per mode, since a color picked
                // against dark surfaces goes unreadable on light ones.
                property string widgetColorDark: ""
                property string widgetColorLight: ""
                property string backgroundColorDark: ""
                property string backgroundColorLight: ""
                // Below zero the interface decides. widgetRadius rounds every widget group;
                // floatRadius rounds the Float and Notch strips.
                property real widgetRadius: -1
                property real floatRadius: -1
                // Floating strip width as a percent of the screen; below zero spans it all.
                // The end clusters move inward with the edges.
                property real floatWidth: -1
                // Float as three strips (left, middle, right). floatWidth then sets how far
                // the outer two sit from the middle one.
                property bool floatSplit: false
                // The notch shares the split switch and roundness with the floating strip but
                // keeps its own width, since the two reach different distances.
                property real notchWidth: -1
                property bool verbose: true
                property bool vertical: false
                // Per section, ordered groups; each group is one pill holding ordered
                // widgets ({ id, enabled }). The center's middle group stays screen-centered.
                property JsonObject layout: JsonObject {
                    property list<var> left: root.defaultBarLayout.left
                    property list<var> center: root.defaultBarLayout.center
                    property list<var> right: root.defaultBarLayout.right
                }
                property string layoutEditorMode: "simple" // "simple" or "custom"
                property JsonObject resources: JsonObject {
                    property bool alwaysShowSwap: true
                    property bool alwaysShowCpu: false
                    property bool alwaysShowGPU: false
                    property int gpuLayout : -1 // -1: Disable GPU Querries | 0: dGPU | 1: iGPU | 2: Hybrid

                    property JsonObject gpu: JsonObject {
                    // Manual card override (e.g., "card1" for AMD_GPU_CARD/INTEL_GPU_CARD)
                    property string dgpuCard: ""
                    property string igpuCard: ""

                    // Manual GPU name override (if empty, uses detected name)
                    property string dgpuName: ""
                    property string igpuName: ""

                    property JsonObject overlay: JsonObject {
                        property bool showDGpu: true
                        property bool showIGpu: true

                        property JsonObject dGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                            property bool showTempJunction: false  // AMD only
                            property bool showTempMem: false       // AMD only
                            property bool showFan: true
                            property bool showPower: true
                        }

                        property JsonObject iGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }
                    }

                    property JsonObject bar: JsonObject {
                        property bool showDGpu: true
                        property bool showIGpu: true

                        property JsonObject dGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }

                        property JsonObject iGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }
                    }
                }

                    property int memoryWarningThreshold: 95
                    property int swapWarningThreshold: 85
                    property int cpuWarningThreshold: 90
                    property int gpuWarningThreshold: 90
                }
                property list<string> screenList: [] // List of names, like "eDP-1", find out with 'hyprctl monitors' command
                property JsonObject utilButtons: JsonObject {
                    property bool showScreenSnip: true
                    property bool showColorPicker: false
                    property bool showMicToggle: true
                    property bool showKeyboardToggle: false
                    property bool showDarkModeToggle: false
                    property bool showPerformanceProfileToggle: false
                    property bool showScreenRecord: true
                }
                property JsonObject workspaces: JsonObject {
                    property bool monochromeIcons: true
                    property int shown: 10
                    property bool showAppIcons: true
                    property bool circleAppIcons: false
                    property bool alwaysShowNumbers: false
                    property int showNumberDelay: 300 // milliseconds
                    property list<string> numberMap: ["1", "2"] // Characters to show instead of numbers on workspace indicator
                    property bool useNerdFont: false
                }
                property JsonObject weather: JsonObject {
                    property bool enable: true
                    property bool enableGPS: true // gps based location
                    property string city: "" // When 'enableGPS' is false
                    // "auto" follows the location; any other value is the user's choice.
                    property string units: "auto" // "auto", "metric", "uscs"
                    // Read by nothing; kept in step so a rollback to a release without `units`
                    // still finds the chosen unit.
                    property bool useUSCS: true
                    property int fetchInterval: 10 // minutes
                }
                property JsonObject claudeUsage: JsonObject {
                    property bool enable: true // Show Claude (Pro/Max) subscription usage meters in the AI sidebar
                    property bool defaultWeekly: false // Start on the 7-day window; click the gauge to switch session <-> week
                    property int warningThreshold: 90 // Turn the gauge red at/above this utilization (%)
                    property int fetchInterval: 5 // minutes
                }
                property JsonObject codexUsage: JsonObject {
                    property bool enable: true // Show ChatGPT subscription usage meters in the AI sidebar
                    property int warningThreshold: 90 // Turn the gauge red at/above this utilization (%)
                    property int fetchInterval: 5 // minutes
                }
                property JsonObject indicators: JsonObject {
                    property JsonObject notifications: JsonObject {
                        property bool showUnreadCount: false
                    }
                }
                property JsonObject tooltips: JsonObject {
                    property bool clickToShow: false
                }
                property JsonObject volumeControl: JsonObject {
                }
            }

            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 5
                property int full: 101
                property bool automaticSuspend: true
                property int suspend: 3
                property JsonObject popup: JsonObject {
                    property bool showTime: true
                    property bool showPower: false
                    property bool showHealth: false
                }
                // Shows the battery indicator with the test values below, even without a
                // battery, to preview the widget and popup.
                property bool testMode: false
                property int testPercentage: 50            // 0–100
                property bool testCharging: false
                property int testTimeMinutes: 90           // drives time-to-full (charging) / time-to-empty (discharging)
                property real testPowerWatts: 12.5         // drives energy rate (Charging: / Discharging: W row)
                property real testHealthPercentage: 92.0   // drives the Health row
            }

            // restoreEnabled gates scripts/session/: a watcher keeps the saved session
            // current and restore.sh replays it at login.
            property JsonObject session: JsonObject {
                property bool restoreEnabled: true
                // One row of Lock, Logout, Reboot and Shutdown; off shows the full grid.
                property bool simpleMenu: true
            }

            property JsonObject brightness: JsonObject {
                // brightnessctl device, e.g. "intel_backlight"; empty lets it choose. Set it
                // when a hybrid laptop exposes a dead second backlight brightnessctl may pick.
                // DDC monitors are unaffected.
                property string device: ""
            }

            property JsonObject calendar: JsonObject {
                property string locale: "en-GB"
            }

            property JsonObject cheatsheet: JsonObject {
                // Use a nerdfont to see the icons
                // 0: 󰖳  | 1: 󰌽 | 2: 󰘳 | 3:  | 4: 󰨡
                // 5:  | 6:  | 7: 󰣇 | 8:  | 9: 
                // 10:  | 11:  | 12:  | 13:  | 14: 󱄛
                property string superKey: ""
                property bool useMacSymbol: false
                property bool splitButtons: false
                property bool useMouseSymbol: false
                property bool useFnSymbol: true
                property JsonObject fontSize: JsonObject {
                    property int key: Appearance.font.pixelSize.smaller
                    property int comment: Appearance.font.pixelSize.smaller
                }
            }

            property JsonObject conflictKiller: JsonObject {
                property bool autoKillNotificationDaemons: false
                property bool autoKillTrays: false
            }

            property JsonObject crosshair: JsonObject {
                // Valorant crosshair format. Use https://www.vcrdb.net/builder
                property string code: "0;P;d;1;0l;10;0o;2;1b;0"
            }

            property JsonObject cursor: JsonObject {
                property string shakeMode: "off" // "off" | "zoom" (magnifier) | "grow" (cursor icon)
                property real shakeZoomFactor: 2.0
                property real shakeGrowFactor: 2.5
            }

            property JsonObject dock: JsonObject {
                property bool enable: true
                // The bar's rules: below zero the interface decides, an empty color leaves it
                // to the palette, and colors are kept per mode.
                property bool showBackground: true
                property real backgroundOpacity: -1
                property string backgroundColorDark: ""
                property string backgroundColorLight: ""
                property real iconSize: -1
                property real radius: -1
                // Settings labels "hug" as Notch and "span" as Hug. hug sits flush with its
                // edge corners curving outward; span runs the whole edge facing the bar.
                // Any other value is drawn as rect.
                property string cornerStyle: "float" // "float" | "hug" | "rect" | "span"
                // Corners facing the desktop; below zero they follow radius. The edge pair's
                // shape comes from the style.
                property real topRadius: -1
                // Each style's last roundness, restored on moving back to it (span keeps none).
                // Below -1 means that style was never left, so the values above stand.
                property real radiusFloat: -2
                property real radiusNotch: -2
                property real topRadiusRect: -2
                property real topRadiusNotch: -2
                // A hidden end button takes its neighboring separator with it.
                property bool showOverviewButton: true
                property bool showPinButton: true
                // "none" | "dashes" | "dots" | "badge". Dashes tighten to dots past three;
                // the badge shows the count.
                property string indicatorStyle: "dashes"
                // Per mode like the other color slots; empty uses the accent.
                property string badgeColorDark: ""
                property string badgeColorLight: ""
                property string badgeTextColorDark: ""
                property string badgeTextColorLight: ""
                // "bottom" | "top" | "left" | "right". The dock yields an edge the bar moves
                // onto, and choosing the bar's edge here moves the bar instead. Styled span,
                // the dock takes the edge facing the bar and moves with it.
                property string position: "bottom"
                property bool monochromeIcons: false
                // "magnify" | "glow" | "off"
                property string hoverEffect: "glow"
                // Percent grown on hover, per effect; -1 uses the effect's own default.
                property real hoverMagnify: -1
                property real glowMagnify: -1
                // The halo's paint and reach; "" and -1 take the palette's own.
                property string glowColorDark: ""
                property string glowColorLight: ""
                property real glowIntensity: -1
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries.
                    // Ids must resolve a desktop entry via byId so a pin launches before the app
                    // has run (TaskbarApps.resolveAppId maps spotify's class back to its pin).
                    // Keep in sync with the Default Apps preselect in netinstall.conf.
                    "chromium", "org.gnome.Nautilus", "org.gnome.TextEditor", "mpv", "spotify-launcher", "settings", "kitty", "org.gnome.Software",]
                property list<string> ignoredAppRegexes: []
                property JsonObject contextMenuVolume: JsonObject {
                    property bool enable: true
                    property string grouping: "perApp" // "perApp" (one bar controlling all of the app's streams) | "perStream" (one bar per audio stream/window)
                }
                property int launchAnimation: DockLaunchAnims.AnimType.Bounce
            }

            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false // Enable faster scrolling with touchpad
                    property int mouseScrollDeltaThreshold: 120 // delta >= this then it gets detected as mouse scroll rather than touchpad
                    property int mouseScrollFactor: 120
                    property int touchpadScrollFactor: 450
                }
                property JsonObject deadPixelWorkaround: JsonObject { // Hyprland leaves out 1 pixel on the right for interactions
                    property bool enable: false
                }
            }

            property JsonObject gestures: JsonObject { // Touchpad gestures; values map to hl.gesture() blocks in hypr/hyprland/general.lua
                property string swipe3: "move" // "move" | "workspace" | "resize" | "none"
                property string pinch3: "float" // "float" | "fullscreen" | "close" | "none"
                property string horizontal4: "workspace" // "workspace" | "special" | "none"
                property string up4: "overviewOpen" // "overviewOpen" | "fullscreen" | "special" | "none"
                property string down4: "overviewClose" // "overviewClose" | "close" | "none"
            }

            property JsonObject language: JsonObject {
                property string ui: "auto" // UI language. "auto" for system locale, or specific language code like "zh_CN", "en_US"
                property JsonObject translator: JsonObject {
                    property string engine: "auto" // Run `trans -list-engines` for available engines. auto should use google
                    property string targetLanguage: "auto" // Run `trans -list-all` for available languages
                    property string sourceLanguage: "auto"
                }
            }

            property JsonObject launcher: JsonObject {
                property list<string> pinnedApps: [ "org.gnome.Nautilus", "kitty", "cmake-gui"]
            }

            property JsonObject light: JsonObject {
                property JsonObject night: JsonObject {
                    // Persisted dropdown state ("disabled", "automatic", "manual", "enabled"):
                    // runtime fields flip with the schedule and cannot tell these apart. Writers
                    // also update automatic, scheduleMode and Hyprsunset.
                    property string mode: "disabled"
                    // Last non-disabled mode, restored by the sidebar Night Light toggle. Set by
                    // Hyprsunset.applyNightLightMode.
                    property string lastActiveMode: "automatic"
                    property bool automatic: false
                    property string scheduleMode: "manual"
                    property string from: "19:00" // Format: "HH:mm", 24-hour time
                    property string to: "06:30"   // Format: "HH:mm", 24-hour time
                    property int colorTemperature: 5000
                }
                property JsonObject antiFlashbang: JsonObject {
                    property bool enable: false
                }
            }

            property JsonObject lock: JsonObject {
                property bool useHyprlock: false
                property bool launchOnStartup: false
                property JsonObject blur: JsonObject {
                    property bool enable: true
                    property real radius: 100
                    property real extraZoom: 1.1
                }
                property bool centerClock: true
                property bool showLockedText: true
                property JsonObject security: JsonObject {
                    property bool unlockKeyring: true
                    property bool requirePasswordToPower: false
                }
                property bool materialShapeChars: true
            }

            property JsonObject media: JsonObject {
                // Attempt to remove dupes (the aggregator playerctl one and browsers' native ones when there's plasma browser integration)
                property bool filterDuplicatePlayers: true
                // The media popup lists only the most recently active players;
                // per-tab browser bridges would otherwise grow it unbounded.
                property int maxShownPlayers: 3
            }

            property JsonObject networking: JsonObject {
                property string userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
            }

            property JsonObject notifications: JsonObject {
                property int timeout: 7000
                // "top_left" | "top_center" | "top_right" | "bottom_left" | "bottom_center" | "bottom_right"
                property string position: "top_right"
                property JsonObject forceMonitor: JsonObject {
                    property bool enable: false
                    property string name: "" // Name of the monitor to show notifications on, like "eDP-1". Find out with 'hyprctl monitors' command
                }
            }

            property JsonObject osd: JsonObject {
                property int timeout: 1000
            }

            property JsonObject osk: JsonObject {
                property string layout: "qwerty_full"
                property bool pinnedOnStartup: false
            }

            property JsonObject overlay: JsonObject {
                property bool openingZoomAnimation: true
                property bool darkenScreen: true
                property real clickthroughOpacity: 0.8
                property JsonObject floatingImage: JsonObject {
                    property string imageSource: "https://media.tenor.com/H5U5bJzj3oAAAAAi/kukuru.gif"
                    property real scale: 0.5
                }
            }

            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
                property bool openTaskManagerOnClick: false

                property bool enableCpu: true
                property bool enableGpu: true // this is the only working so far iirc
                property bool enableRam: true
                property bool enableSwap: true

                property JsonObject gpu: JsonObject {
                    // Manual card override (e.g., "card1" for AMD_GPU_CARD/INTEL_GPU_CARD)
                    property string dgpuCard: ""
                    property string igpuCard: ""

                    // Manual GPU name override (if empty, uses detected name)
                    property string dgpuName: ""
                    property string igpuName: ""

                    property JsonObject overlay: JsonObject {
                        property bool showDGpu: true
                        property bool showIGpu: true

                        property JsonObject dGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                            property bool showTempJunction: false  // AMD only
                            property bool showTempMem: false       // AMD only
                            property bool showFan: true
                            property bool showPower: true
                        }

                        property JsonObject iGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }
                    }

                    property JsonObject bar: JsonObject {
                        property bool showDGpu: true
                        property bool showIGpu: true

                        property JsonObject dGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }

                        property JsonObject iGpu: JsonObject {
                            property bool showUsage: true
                            property bool showVram: true
                            property bool showTemp: true
                        }
                    }
                }
            }

            property JsonObject overview: JsonObject {
                property bool enable: true
                property bool showAllAppsWhenOff: true
                property real size: 100 // Percent of the largest grid that fits the screen (100 = fill)
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool centerIcons: true
                // Keeps the overlay surface mapped so opens are instant on a busy compositor.
                // Off restores direct scanout for fullscreen games, at the cost of a ~1s
                // first open while the compositor is busy.
                property bool keepSurfaceAlive: true
            }

            property JsonObject regionSelector: JsonObject {
                property JsonObject targetRegions: JsonObject {
                    property bool windows: true
                    property bool layers: false
                    property bool content: false
                    property bool showLabel: false
                    property real opacity: 0.3
                    property real contentRegionOpacity: 0.8
                    property int selectionPadding: 5
                }
                property JsonObject rect: JsonObject {
                    property bool showAimLines: true
                }
                property JsonObject circle: JsonObject {
                    property int strokeWidth: 6
                    property int padding: 10
                }
                property JsonObject annotation: JsonObject {
                    property bool useSatty: false
                }
            }




            property JsonObject tray: JsonObject {
                property bool monochromeIcons: false
                property bool showItemId: false
                property bool invertPinnedItems: true // Makes the below a whitelist for the tray and blacklist for the pinned area
                property list<var> pinnedItems: [ "Fcitx" ]
                property bool filterPassive: true
            }

            property JsonObject musicRecognition: JsonObject {
                property int timeout: 16
                property int interval: 4
            }

            property JsonObject search: JsonObject {
                property int nonAppResultDelay: 30 // This prevents lagging when typing
                property string engineBaseUrl: "https://www.google.com/search?q="
                property list<string> excludedSites: ["quora.com", "facebook.com"]
                property bool sloppy: false // Uses levenshtein distance based scoring instead of fuzzy sort. Very weird.
                property JsonObject prefix: JsonObject {
                    property bool showDefaultActionsWithoutPrefix: true
                    property string action: "/"
                    property string app: ">"
                    property string clipboard: ";"
                    property string emojis: ":"
                    property string math: "="
                    property string shellCommand: "$"
                    property string webSearch: "?"
                }
                property JsonObject imageSearch: JsonObject {
                    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
                    property bool useCircleSelection: false
                }
                // File and folder search under ~/ via `fd`.
                property JsonObject fileSearch: JsonObject {
                    property bool enable: true
                    property int maxResults: 30
                }
            }

            property JsonObject sidebar: JsonObject {
                property bool keepRightSidebarLoaded: true
                property JsonObject translator: JsonObject {
                    property bool enable: false
                    property int delay: 300 // Delay before sending request. Reduces (potential) rate limits and lag.
                }
                property JsonObject media: JsonObject {
                    property bool enable: true
                    // Sends title and artist to lrclib.net only while lyrics are on screen.
                    property bool showLyrics: true
                    property bool artColors: true
                    property bool blurredBackground: true
                }
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                }
                property JsonObject booru: JsonObject {
                    property bool allowNsfw: false
                    property string defaultProvider: "yandere"
                    property int limit: 20
                    property JsonObject zerochan: JsonObject {
                        property string username: "[unset]"
                    }
                }
                property JsonObject cornerOpen: JsonObject {
                    property bool enable: true
                    property bool bottom: false
                    property bool valueScroll: true
                    property bool clickless: false
                    property int cornerRegionWidth: 250
                    property int cornerRegionHeight: 5
                    property bool visualize: false
                    property bool clicklessCornerEnd: true
                    property int clicklessCornerVerticalOffset: 1
                }

                property JsonObject quickToggles: JsonObject {
                    property string style: "android" // Options: classic, android
                    property JsonObject android: JsonObject {
                        property int columns: 5
                        property list<var> toggles: [
                            { "size": 2, "type": "network" },
                            { "size": 2, "type": "bluetooth"  },
                            { "size": 1, "type": "idleInhibitor" },
                            { "size": 1, "type": "mic" },
                            { "size": 2, "type": "audio" },
                            { "size": 2, "type": "nightLight" }
                        ]
                    }
                }

                property JsonObject quickSliders: JsonObject {
                    property bool enable: false
                    property bool showMic: false
                    property bool showVolume: true
                    property bool showBrightness: true
                }
            }

            property JsonObject screenRecord: JsonObject {
                property string savePath: Directories.videos.replace("file://","") // strip "file://"
            }

            property JsonObject screenSnip: JsonObject {
                property string savePath: FileUtils.trimFileProtocol(Directories.pictures + "/Screenshots")
            }

            property JsonObject sounds: JsonObject {
                property bool battery: true
                property bool pomodoro: true
                property bool timer: true
                property bool update: false
                property string theme: "freedesktop"
            }

            property JsonObject time: JsonObject {
                // https://doc.qt.io/qt-6/qtime.html#toString
                property string format: "h:mm AP"
                property string shortDateFormat: "MM/dd"
                property string dateWithYearFormat: "MM/dd/yyyy"
                property string dateFormat: "ddd, MM/dd"
                property JsonObject pomodoro: JsonObject {
                    property int breakTime: 300
                    property int cyclesBeforeLongBreak: 4
                    property int focus: 1500
                    property int longBreak: 900
                }
                property bool secondPrecision: false
            }

            property JsonObject updates: JsonObject {
                property bool enableCheck: true
                property int checkInterval: 120 // minutes
                property int adviseUpdateThreshold: 75 // packages
                property int stronglyAdviseUpdateThreshold: 200 // packages

                // The Update page's advanced switches, kept from one update to the next.
                property JsonObject advanced: JsonObject {
                    property bool skipSystem: false
                    // AUR skipped by default: Mainstream avoids the AUR over supply-chain concerns.
                    property bool skipAur: true
                    property bool skipFlatpak: false
                    property bool skipDotfiles: false
                    property bool skipExtras: false
                    // Firmware updates can prompt polkit and time out unattended.
                    property bool skipFirmware: true
                    property bool autoRebuildQuickshell: true
                    property bool edge: false
                }

                property JsonObject release: JsonObject {
                    // Set from the bar widget's right-click menu; the bar layout decides if it shows.
                    property string notify: "both" // both | tray | notification
                    property int checkIntervalHours: 6
                    property string manifestUrl: "https://mainstreamos.org/releases.json"
                }
            }
            
            property JsonObject wallpaperSelector: JsonObject {
                property bool useSystemFileDialog: false
            }
            
            property JsonObject windows: JsonObject {
                property bool showTitlebar: true // Client-side decoration for shell apps
                property bool centerTitle: true
            }

            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 20 // milliseconds
            }
        }
    }
}
