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

    // The bar as it ships. Declared here rather than inside the adapter so the
    // settings page's "Reset to defaults" and a first run can't drift apart —
    // they were separate copies, and adding a widget meant editing both.
    //
    // Weather and the release chip sit at the end of the center rather than the
    // start of the right: that is where they appeared all along, held there by
    // the spacer that used to divide the right section. Without it the right
    // section packs to the screen edge and they would ride against the tray, so
    // the layout now says the position the spacer used to fake.
    readonly property var defaultBarLayout: ({
        "left": [
            { "widgets": [ {"id": "sidebarButton", "enabled": true}, {"id": "activeWindow", "enabled": true} ] },
            { "widgets": [ {"id": "activeWindowPill", "enabled": false} ] }
        ],
        "center": [
            { "widgets": [ {"id": "resources", "enabled": false}, {"id": "media", "enabled": true} ] },
            { "widgets": [ {"id": "workspaces", "enabled": true} ] },
            { "widgets": [ {"id": "clock", "enabled": true}, {"id": "utilButtons", "enabled": true}, {"id": "battery", "enabled": true} ] },
            { "widgets": [ {"id": "weather", "enabled": true}, {"id": "releaseUpdates", "enabled": true} ] }
        ],
        "right": [
            { "widgets": [ {"id": "timers", "enabled": true}, {"id": "tray", "enabled": true}, {"id": "volume", "enabled": true}, {"id": "indicators", "enabled": true} ] }
        ]
    })
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    // True while apply-theme.sh is mid-run. Read from a shared state file so
    // the settings window (a separate quickshell process) also blocks its own
    // writeAdapter() — otherwise it races the script's jq/mv writes and
    // reverts wallpaperPath or other just-applied fields.
    property bool themeApplyInProgress: false

    // Applying a theme rewrites this file and then regenerates the colours a
    // second or so later. Reacting to each write as it lands repaints the whole
    // desktop twice — once restyled but still wearing the old palette, then
    // again once the new palette arrives. Hold the reload until the run reports
    // itself finished so the change is seen once.
    property bool _reloadDeferred: false

    // Guard to suppress the self-echo: FileView.reload() mutates adapter
    // properties which fires adapterUpdated, which would otherwise schedule a
    // writeAdapter() of content we *just read from disk*. Harmless in isolation
    // but the resulting write generates an fs-event that races concurrent
    // writers like switchwall.sh.
    property bool _reloading: false

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

    // Which widgets the bar shows used to be decided by a switch per widget.
    // It is decided by the bar's layout now, and a settings file written before
    // that changed has the old switches and no layout at all — so an update
    // would quietly hand everyone the stock arrangement, taking away a widget
    // someone had turned on and giving back one they had turned off. Carry
    // their answers into the layout the once, recognising an older file by its
    // missing layout. Every later write includes one, so this cannot repeat.
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

    // Ids the bar has stopped drawing. A layout saved while one was still a
    // widget goes on listing it, and the bar renders nothing in its place — so
    // the room it used to hold vanishes and everything beside it slides over.
    // The editor drops them from any section it writes, but only once someone
    // opens it, which leaves the bar looking rearranged until they do.
    readonly property var retiredBarModules: ["spacer"]

    function scrubRetiredBarModules() {
        const sections = {}
        for (const s of ["left", "center", "right"])
            sections[s] = JSON.parse(JSON.stringify(root.options.bar.layout[s] ?? []))

        // A group may still be a bare string, or carry `items` where this one
        // carries `widgets` — the bar and its editor both read all three forms.
        // Reading `widgets` alone sees an empty group where there is a full one,
        // and everything downstream then treats it as empty.
        function holdsSpacer(g) {
            return ObjectUtils.layoutGroupWidgets(g)
                .some(w => root.retiredBarModules.indexOf(w.id) !== -1)
        }
        let changed = false

        // A spacer alone in a side section stood between groups and pushed the
        // ones on its inward side back toward the middle, where they read as
        // part of the center however the layout listed them. Deleting it on its
        // own would let those groups fall against the screen edge, so they move
        // to the center instead and go on rendering where they always appeared.
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
                // Nothing retired in it: hand back the group exactly as it was
                // read, in whichever form it was written. Rewriting one this
                // pass has no business touching is how a layout gets lost.
                if (remaining.length === widgets.length) { kept.push(group); continue }
                changed = true
                // A group that held nothing else goes with it, rather than
                // staying on as a slot with nothing to show.
                if (remaining.length === 0) continue
                // Only now is the group rewritten, and it settles on the one
                // form so `items` cannot survive alongside a stale `widgets`.
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

    // Watcher for the shared theme-apply state file written by apply-theme.sh.
    // QFileSystemWatcher (used by FileView) can only watch existing files, so
    // onLoadFailed creates it with "idle" on first run to bootstrap watching.
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

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: {
            if (root.blockWrites || root.themeApplyInProgress) return
            configFileView.writeAdapter()
        }
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites || root.themeApplyInProgress
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: {
            if (root._reloading) return
            fileWriteTimer.restart()
        }
        onLoaded: {
            root.ready = true
            // The migrations run here, where _reloading may still be set and would
            // swallow the write that onAdapterUpdated would otherwise schedule, so
            // the save is asked for directly. Each only fires for a file an older
            // release wrote — one lacking bar.layout, one still naming a retired
            // widget — and a fresh install is neither, which matters because
            // nothing else may write this file at startup. A first login seeds the
            // wallpaper path from outside a moment later, and that write only
            // survives because it is the last one.
            const seeded = root.seedBarLayoutFromLegacySwitches()
            const scrubbed = root.scrubRetiredBarModules()
            if (seeded || scrubbed) fileWriteTimer.restart()
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            property string panelFamily: "ii" // "ii", "waffle"

            property JsonObject policies: JsonObject {
                property int ai: 0 // 0: No | 1: Yes | 2: Local
                property int weeb: 0 // 0: No | 1: Open | 2: Closet
            }

            property JsonObject ai: JsonObject {
                property string systemPrompt: "## Style\n- Use casual tone, don't be formal!\n- Always be brief and to the point, unless asked otherwise\n- Don't repeat the user's question\n- Be approachable: Avoid using overly complicated, domain-specific terms and provide analogies when asked to explain a concept\n\n## Context (ignore when irrelevant)\n- You are a helpful and inspiring sidebar assistant on a {DISTRO} Linux system\n- Desktop environment: {DE}\n- Current date & time: {DATETIME}\n- Focused app: {WINDOWCLASS}\n\n## Presentation\n- Use Markdown features in your response: \n  - **Bold** text to **highlight keywords** in your response\n  - **Split long information into small sections** with h2 headers and a relevant emoji at the start of it (for example `## 🐧 Linux`). Bullet points are preferred over long paragraphs, unless you're offering writing support or instructed otherwise by the user.\n- Asked to compare different options? You should firstly use a table to compare the main aspects, then elaborate or include relevant comments from online forums *after* the table. Make sure to provide a final recommendation for the user's use case!\n- Use LaTeX formatting for mathematical and scientific notations whenever appropriate. Enclose all LaTeX '$$' delimiters. NEVER generate LaTeX code in a latex block unless the user explicitly asks for it. DO NOT use LaTeX for regular documents (resumes, letters, essays, CVs, etc.).\n\nThanks!\n"
                property string tool: "functions" // search, functions, or none
                property list<var> extraModels: [
                    {
                        "api_format": "openai", // Most of the time you want "openai". Use "gemini" for Google's models
                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is DeepSeek R1 Distill LLaMA 70B",
                        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
                        "homepage": "https://openrouter.ai/deepseek/deepseek-r1-distill-llama-70b:free", // Not mandatory
                        "icon": "spark-symbolic", // Not mandatory
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
                // Lives here rather than in the Hyprland config so a saved
                // theme carries it. Palette mode holds role names, which are
                // re-read from whatever palette is current so the border
                // follows the wallpaper the way the rest of the desktop does;
                // custom mode holds the two colours literally and ignores it.
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
                // Day/Night Themes scheduler: ThemeManager auto-applies daySlug
                // or nightSlug depending on `mode` and the current time. When
                // mode is "nightlight" it follows Hyprsunset.shouldBeOn (so
                // theme changes line up with the Night Light filter); when
                // "manual" it uses dayFrom / nightFrom as the day-window
                // boundaries (HH:mm 24-hour, parsed by ThemeManager). "off"
                // disables auto-apply entirely. Default daySlug/nightSlug
                // are empty until the user picks them in Settings → Themes.
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
                property JsonObject widgets: JsonObject {
                    property JsonObject clock: JsonObject {
                        property bool enable: true
                        property bool showOnlyWhenLocked: false
                        property string placementStrategy: "leastBusy" // "free", "leastBusy", "mostBusy"
                        property real x: 100
                        property real y: 100
                        property string style: "digital"        // Options: "cookie", "digital"
                        property string styleLocked: "digital"  // Options: "cookie", "digital"
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
                        property JsonObject quote: JsonObject {
                            property bool enable: false
                            property string text: ""
                        }
                    }
                    property JsonObject weather: JsonObject {
                        property bool enable: false
                        property string placementStrategy: "free" // "free", "leastBusy", "mostBusy"
                        property real x: 400
                        property real y: 100
                    }
                }
                property string wallpaperPath: ""
                property string thumbnailPath: ""
                property bool hideWhenFullscreen: true
                // Rotates wallpaperPath through `folder` on a timer. These keys
                // ride along in a saved theme's config.json snapshot, so the
                // slideshow belongs to whichever theme is currently on — a
                // single-wallpaper theme taking over turns it off, and the
                // Day/Night pair hand their own rotations back and forth.
                // An empty folder means the stock Wallpapers directory.
                // `recolor` regenerates the whole palette on every change;
                // left off, a rotation only swaps the picture.
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
                property int cornerStyle: 1 // 0: Hug | 1: Float | 2: Plain rectangle
                property bool floatStyleShadow: true // Show shadow behind bar when cornerStyle == 1 (Float)
                // Hot-corner-related settings. Currently only the
                // top-left trigger uses this.
                property JsonObject hotCorners: JsonObject {
                    // What the top-left hot corner opens. Recognized values:
                    //   "scrolloverview" — the niri-style scrolling overview
                    //                      plugin (default; only fires the
                    //                      ripple cascade for this option,
                    //                      and only when the plugin is
                    //                      actually loaded)
                    //   "default"        — the built-in dots overview
                    //                      (workspaces + app drawer + search,
                    //                      driven by GlobalStates.overviewOpen)
                    //   "off"            — the corner is disabled entirely;
                    //                      left-clicks fall through to the
                    //                      bar's left-side area
                    property string trigger: "scrolloverview"
                    // Whether the ripple animation plays at all (only
                    // relevant when trigger == "scrolloverview"). When
                    // false the hot-corner cascade is suppressed and
                    // Bar.qml's pre-overview delay collapses to 0ms, so
                    // the corner-trigger dispatches the overview
                    // immediately.
                    property bool animationEnabled: true
                }
                property bool borderless: false // true for no grouping of items
                property string topLeftIcon: "spark" // Options: "distro" or any icon name in ~/.config/quickshell/ii/assets/icons
                property bool showBackground: true
                // How solid each of the bar's two surfaces is, as plain opacity:
                // 0 is gone, 1 is fully solid. Below zero means the interface
                // decides, which is where both start — the strip lands near
                // solid and the widget groups near a tenth, so the sliders open
                // at different points while still meaning the same thing.
                property real backgroundOpacity: -1
                property real widgetOpacity: -1
                // A filled slot is the whole decision: empty means the palette
                // decides, anything else is the user's own. One slot per mode,
                // because everything a color sits against flips with the mode:
                // a pill picked against a dark palette is a dark-mode
                // decision that goes unreadable against light surfaces.
                property string widgetColorDark: ""
                property string widgetColorLight: ""
                property string backgroundColorDark: ""
                property string backgroundColorLight: ""
                // Shape follows the same rule as the sliders above: below zero
                // the interface decides. The pill radius reaches every widget
                // group on either bar; the float radius only means anything
                // while the bar floats, so it keeps quiet the rest of the time.
                property real widgetRadius: -1
                property real floatRadius: -1
                property bool verbose: true
                property bool vertical: false
                // Per-section widget layout. Each section is an ordered list
                // of groups; each group is one pill and holds an ordered list
                // of widgets ({ id, enabled }). Widgets in the same group share
                // a pill (combined); separate groups are separate pills. In the
                // center, the middle group is kept screen-centered. Recognized
                // ids: sidebarButton, activeWindow, activeWindowPill,
                // resources, media, workspaces, clock, utilButtons, battery,
                // indicators, volume, tray, timers, weather, releaseUpdates.
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

                    // Overlay widget GPU display settings
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

                    // Bar popup GPU settings
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
                    property bool useUSCS: true // Instead of metric (SI) units
                    property int fetchInterval: 10 // minutes
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
                // What the bar indicator's hover popup reveals. Time is on by
                // default; power draw and health are opt-in (power-user info).
                property JsonObject popup: JsonObject {
                    property bool showTime: true
                    property bool showPower: false
                    property bool showHealth: false
                }
                // Test mode: force the battery indicator visible with synthetic
                // values, regardless of whether a real laptop battery exists.
                // Lets desktop users preview/customise the bar widget + popup.
                property bool testMode: false
                property int testPercentage: 50            // 0–100
                property bool testCharging: false
                property int testTimeMinutes: 90           // drives time-to-full (charging) / time-to-empty (discharging)
                property real testPowerWatts: 12.5         // drives energy rate (Charging: / Discharging: W row)
                property real testHealthPercentage: 92.0   // drives the Health row
            }

            // Window-state restore. Gates scripts/session/: a resident watcher
            // keeps the saved session current while you work, and restore.sh
            // replays it at login. On by default — brings back the windows that
            // were open, on the workspaces they were on.
            property JsonObject session: JsonObject {
                property bool restoreEnabled: true
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
                property bool useFnSymbol: false
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
                // "bottom" | "top" | "left" | "right". The dock yields if the
                // bar is moved onto this edge; asking for the bar's edge from
                // the dock's own setting moves the bar across instead.
                property string position: "bottom"
                property bool monochromeIcons: false
                property real height: 60
                property real hoverRegionHeight: 2
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true // When false, only reveals on empty workspace
                property list<string> pinnedApps: [ // IDs of pinned entries.
                    // Pin ids must resolve a desktop entry directly (byId), so a
                    // pinned button can launch before the app has ever run:
                    //   - Most native apps: the lowercase entry id (kitty, mpv).
                    //   - GNOME apps: the reverse-DNS app-id (org.gnome.Nautilus),
                    //     identical whether native or Flatpak.
                    //   - spotify-launcher: the entry id; the running client
                    //     reports class "spotify", which TaskbarApps.resolveAppId
                    //     maps back to this pin.
                    // Keep this in sync with the Default Apps preselect in
                    // netinstall.conf so the dock has launchers for the apps a fresh
                    // install actually ships.
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
                    // `mode` is the unified dropdown's source of truth —
                    // one of "disabled" / "automatic" / "manual" / "enabled".
                    // We persist it explicitly rather than deriving the
                    // dropdown state from runtime fields like
                    // Hyprsunset.temperatureActive, because that runtime
                    // value flips with the schedule and clock and can't
                    // distinguish "user set Disabled" from "user set
                    // Enabled but filter happens to be off right now".
                    // The action handlers in DisplayConfig and the right-
                    // sidebar NightLightDialog write `mode` and ALSO
                    // propagate to `automatic` / `scheduleMode` /
                    // Hyprsunset.toggleTemperature so the runtime
                    // behaviour matches.
                    //
                    // Default "disabled" — fresh installs land on index 0
                    // of the dropdown without the user having to opt out
                    // of anything.
                    property string mode: "disabled"
                    // Remembers the most recent non-disabled mode the user
                    // picked, so the right-sidebar Night Light toggle
                    // button can restore that state when toggled back on
                    // from "disabled" instead of always landing in the
                    // same default. Updated by Hyprsunset.applyNightLightMode.
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

                // Enable/disable resource monitoring globally
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

                    // Overlay widget GPU display settings
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

                    // Bar popup GPU settings
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
                property real size: 100 // Percent of the largest grid that fits the screen (100 = fill)
                property real rows: 2
                property real columns: 5
                property bool orderRightLeft: false
                property bool orderBottomUp: false
                property bool centerIcons: true
                // Keep the wlr-layer-shell surface mapped while the overview
                // is closed. Default ON makes opens instant even on a busy
                // compositor (e.g. running a game at 4K@144Hz). Turn OFF to
                // free the Overlay-layer surface and restore direct scanout
                // for exclusive-fullscreen games, at the cost of a ~1s wait
                // the first time the overview is opened while the
                // compositor is busy.
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
                // File + folder search backed by `fd`. Walks ~/ live (no DB
                // rebuild), passes the query as argv (no shell injection),
                // hardcoded excludes for the obvious noise dirs. Streams
                // results into the launcher with XDG MIME icons resolved
                // against the user's active icon theme.
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

                property JsonObject release: JsonObject {
                    // Set from the bar widget's right-click menu. Whether the
                    // widget is there at all is the bar layout's business.
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

            property JsonObject workSafety: JsonObject {
                property JsonObject enable: JsonObject {
                    property bool wallpaper: false
                    property bool clipboard: false
                }
                property JsonObject triggerCondition: JsonObject {
                    property list<string> networkNameKeywords: ["airport", "cafe", "college", "company", "eduroam", "free", "guest", "public", "school", "university"]
                    property list<string> fileKeywords: ["anime", "booru", "ecchi", "hentai", "yande.re", "konachan", "breast", "nipples", "pussy", "nsfw", "spoiler", "girl"]
                    property list<string> linkKeywords: ["hentai", "porn", "sukebei", "hitomi.la", "rule34", "gelbooru", "fanbox", "dlsite"]
                }
            }

            property JsonObject waffles: JsonObject {
                // Some spots are kinda janky/awkward. Setting the following to
                // false will make (some) stuff also be like that for accuracy. 
                // Example: the right-click menu of the Start button
                property JsonObject tweaks: JsonObject {
                    property bool switchHandlePositionFix: true
                    property bool smootherMenuAnimations: true
                    property bool smootherSearchBar: true
                }
                property JsonObject bar: JsonObject {
                    property bool bottom: true
                    property bool leftAlignApps: false
                }
                property JsonObject actionCenter: JsonObject {
                    property list<string> toggles: [ "network", "bluetooth", "easyEffects", "powerProfile", "idleInhibitor", "nightLight", "darkMode", "antiFlashbang", "cloudflareWarp", "mic", "musicRecognition", "notifications", "onScreenKeyboard", "gameMode", "screenSnip", "colorPicker" ]
                }
                property JsonObject calendar: JsonObject {
                    property bool force2CharDayOfWeek: true
                }
            }
        }
    }
}
