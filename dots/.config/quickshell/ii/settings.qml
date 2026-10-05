//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
// The Background page previews the wallpaper transitions; pages load by path,
// so the module has to be named here for the scanner to find it.
import qs.modules.ii.background

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    property var pages: [
        {
            group: 1,
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            group: 1,
            name: "Wi-Fi",
            icon: "wifi",
            component: "modules/settings/WifiConfig.qml"
        },
        {
            group: 1,
            name: Translation.tr("Bluetooth"),
            icon: "bluetooth",
            component: "modules/settings/BluetoothConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Dock"),
            // The bar's glyph the other way up, so the two entries are one
            // shape distinguished only by which edge it sits on.
            icon: "toast",
            component: "modules/settings/DockConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Decorations"),
            icon: "palette",
            component: "modules/settings/DecorationsConfig.qml"
        },
        {
            group: 2,
            name: Translation.tr("Themes"),
            icon: "style",
            component: "modules/settings/ThemesConfig.qml"
        },
        {
            group: 3,
            name: Translation.tr("Display"),
            icon: "monitor",
            component: "modules/settings/DisplayConfig.qml",
            // The Display page is by far the heaviest entry in this settings
            // app — multiple monitors × per-monitor sections × ~400 widgets
            // each. Synchronous load froze the page-swap animation while
            // every monitor section materialised. Loader.asynchronous offloads
            // the page's QML compilation + initial binding pass to a worker
            // thread so the swap stays smooth. Only this page is opted-in;
            // other pages stay sync because their layouts don't tolerate
            // having a 0-width parent during the brief async-loading window.
            asynchronous: true
        },
        {
            group: 3,
            name: Translation.tr("Layouts"),
            icon: "view_quilt",
            component: "modules/settings/LayoutsConfig.qml"
        },
        {
            group: 3,
            name: Translation.tr("Keyboard"),
            icon: "keyboard",
            component: "modules/settings/KeyboardConfig.qml"
        },
        {
            group: 3,
            name: Translation.tr("Mouse"),
            icon: "mouse",
            component: "modules/settings/MouseConfig.qml"
        },
        {
            group: 3,
            name: Translation.tr("Power"),
            icon: "bolt",
            component: "modules/settings/PowerConfig.qml"
        },
        {
            group: 3,
            name: Translation.tr("Gaming"),
            icon: "sports_esports",
            component: "modules/settings/GamingConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Accounts"),
            icon: "manage_accounts",
            component: "modules/settings/AccountsConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Sharing"),
            icon: "folder_shared",
            component: "modules/settings/SharingConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Manage"),
            icon: "apps",
            component: "modules/settings/ManageAppsConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Update"),
            icon: "system_update_alt",
            component: "modules/settings/UpdateConfig.qml"
        },
        {
            group: 4,
            name: Translation.tr("Recovery"),
            icon: "healing",
            component: "modules/settings/RecoverConfig.qml"
        },
        {
            group: 5,
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]
    
    function pageIndex(name) {
        return root.pages.findIndex(page => page.component.endsWith(name));
    }
    // By file or by position, so a new window and one already open read a page alike.
    function resolvePage(name) {
        const named = root.pageIndex(name);
        const position = parseInt(name);
        return named !== -1 ? named : (position >= 0 && position < root.pages.length ? position : -1);
    }
    function showPage(name) {
        root.requestPage(root.pageIndex(name));
    }

    // Every page change asks first whether an update has replaced this
    // window's files, since the page would load from them.
    function requestPage(index) {
        if (root.restarting || index < 0 || index >= root.pages.length)
            return;
        root.pendingPage = index;
        root.checkFiles();
    }

    // Set once an update has replaced the code this window runs. A page loaded
    // after that could mix versions, so Settings starts again instead.
    property bool filesReplaced: false
    // The tree as this window found it, read from the files rather than the
    // clock, which can be hours off after a dual boot or before a time sync.
    property string filesBaseline: ""
    // The update that replaced them is still running and may still be copying.
    property bool updateLive: false
    property bool restarting: false
    property bool restartRefused: false
    // The new window never came up, so this one stays and stops restarting unasked.
    property bool restartFailed: false
    property int pendingPage: -1
    property bool restartAsked: false
    // Services a page here has started. Asking one that never started would
    // start it, and its startup work with it.
    property bool sharingUsed: !!Quickshell.env("QS_SHARING_FOLDER")
    property bool appsUsed: false

    function checkFiles() {
        // A check under way answers this request too.
        if (!filesCheck.running)
            filesCheck.running = true;
        checkWatchdog.restart();
    }

    function requestRestart() {
        root.restartAsked = true;
        root.checkFiles();
    }

    function takeCheck(answer) {
        checkWatchdog.stop();
        if (answer.startsWith("base ")) {
            root.filesBaseline = answer.slice(5);
            answer = "same";
        }
        if (answer === "replaced" || answer === "updating") {
            root.updateLive = answer === "updating";
            if (!root.updateLive)
                root.filesReplaced = true;
        }
        const target = root.pendingPage;
        const asked = root.restartAsked;
        root.pendingPage = -1;
        root.restartAsked = false;
        if (root.restarting)
            return;
        const moving = target !== -1 && target !== root.currentPage;
        // Only a page change or the Restart button restarts. Focus or the end
        // of a run raises the banner alone, since the user may be typing.
        if (root.filesReplaced && (asked || (moving && !root.restartFailed))) {
            if (!root.restartBlocked()) {
                root.restartInto(moving ? target : root.currentPage);
                return;
            }
            if (asked)
                root.restartRefused = true;
        } else if (root.restartRefused && !root.restartBlocked()) {
            root.restartRefused = false;
        }
        if (moving)
            root.currentPage = target;
    }

    // Flags the pages already keep for work under way, some on rows inside
    // the page, and for an open editor or prompt whose input would be lost.
    readonly property var busyFlags: ["isRunning", "busy", "working", "applying", "applyInFlight",
        "ioBusy", "countingDown", "revertPending", "countryApplying", "isConnecting",
        "show", "editorOpen", "saveDialogOpen", "exportDialogOpen", "changingPassword", "renaming",
        "showChangePassword", "showChangeName", "isAskingPassword"]

    function isTextEntry(item) {
        return !!item && typeof item.cursorPosition === "number" && item.readOnly === false
            && typeof item.text === "string";
    }

    function restartBlocked() {
        if (root.updateLive || Config.writePending || Config.themeApplyInProgress)
            return true;
        if (root.sharingUsed && FileSharing.busy)
            return true;
        if (root.appsUsed && (DefaultApps.busyRole !== "" || AutostartApps.busyId !== ""))
            return true;
        const focused = root.activeFocusItem;
        if (root.isTextEntry(focused) && focused.text.length > 0)
            return true;
        const stack = pageLoader.item ? [pageLoader.item] : [];
        const seen = new Set();
        while (stack.length > 0) {
            const item = stack.pop();
            if (!item || seen.has(item))
                continue;
            seen.add(item);
            if (root.busyFlags.some(flag => item[flag] === true))
                return true;
            // A typed password is kept nowhere a new window could read it back.
            if (root.isTextEntry(item) && item.echoMode !== undefined
                    && item.echoMode !== TextInput.Normal && item.text.length > 0)
                return true;
            for (const list of [item.children, item.resources]) {
                for (let i = 0; i < (list?.length ?? 0); i++)
                    stack.push(list[i]);
            }
            // A popup's content sits in the window overlay, not under the page.
            if (item.contentItem)
                stack.push(item.contentItem);
        }
        return false;
    }

    function restartInto(index) {
        root.restarting = true;
        const signalPath = `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/mainstream-settings-restart-${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
        Quickshell.execDetached({
            command: ["qs", "-p", Quickshell.shellPath("settings.qml")],
            // Of what this window was opened for, only a section not yet shown goes with it.
            environment: ({
                "QS_SETTINGS_PAGE": root.pages[index].component.split("/").pop(),
                "QS_SETTINGS_SECTION": root.pendingSettingsSection || null,
                "QS_SETTINGS_TAB": null,
                "QS_SHARING_FOLDER": null,
                "QS_SETTINGS_SIZE": `${Math.round(root.width)}x${Math.round(root.height)}`,
                "QS_SETTINGS_RESTART_SIGNAL": signalPath
            })
        });
        restartWait.command = ["bash", "-c",
            'for i in $(seq 150); do [ -e "$0" ] && { rm -f "$0"; echo up; exit 0; }; sleep 0.1; done; echo timeout',
            signalPath];
        restartWait.running = true;
    }

    // This window stays until the new one is up, so a version that cannot
    // start leaves Settings open, still showing what it showed.
    Process {
        id: restartWait
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "up") {
                    Qt.quit();
                    return;
                }
                root.restarting = false;
                root.restartFailed = true;
            }
        }
    }

    // A window a restart opened tells the old one, once it is up, to go.
    property bool restartSignalSent: false
    function signalRestarted() {
        const signalPath = Quickshell.env("QS_SETTINGS_RESTART_SIGNAL");
        if (!signalPath || !Config.ready || root.restartSignalSent)
            return;
        root.restartSignalSent = true;
        Quickshell.execDetached(["touch", signalPath]);
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.signalRestarted();
        }
    }

    readonly property string updatePidPath: Directories.updateStateDir + "/update.pid"

    // Whether the tree differs from the one this window started on, and whether an update
    // is still copying it. Once replaced it cannot match again, so only the update is asked.
    Process {
        id: filesCheck
        command: ["bash", "-c",
            '[ "$1" = replaced ] || {'
            + ' h=$(find -H "$0" -type f \\( -name "*.qml" -o -name "*.js" -o -name qmldir \\) -printf "%i %C@ %P\\n" 2>/dev/null | md5sum);'
            + ' h=${h%% *}; [ -z "$1" ] && { echo "base $h"; exit 0; }; [ "$h" = "$1" ] && { echo same; exit 0; }; };'
            + ' bash "$2" "$3" "$4" && { echo updating; exit 0; }; echo replaced',
            Quickshell.shellPath(""), root.filesReplaced ? "replaced" : root.filesBaseline,
            Quickshell.shellPath("scripts/update/update-busy.sh"),
            root.updatePidPath,
            Directories.dotfilesClone + "/.update-lock"]
        stdout: StdioCollector {
            onStreamFinished: root.takeCheck(this.text.trim())
        }
    }

    // A check that never answers must not leave a page change waiting.
    Timer {
        id: checkWatchdog
        interval: 1000
        onTriggered: root.takeCheck("")
    }

    onActiveChanged: {
        if (active)
            root.checkFiles();
    }
    onCurrentPageChanged: root.restartRefused = false

    // The end of a run is when an update has just replaced these files. The
    // pause lets the update's own processes exit before the check.
    Connections {
        target: pageLoader.item
        ignoreUnknownSignals: true
        function onIsRunningChanged() {
            if (!pageLoader.item.isRunning)
                runEndCheck.restart();
        }
    }
    Timer {
        id: runEndCheck
        interval: 1500
        onTriggered: root.checkFiles()
    }

    // Read deep-linking from environment variables (set by dialogs)
    // A page may be named by its component file (UpdateConfig.qml) instead of
    // its position, so callers don't have to track this list's ordering.
    property int initialPage: {
        const envPage = Quickshell.env("QS_SETTINGS_PAGE");
        return envPage ? Math.max(root.resolvePage(envPage), 0) : 0;
    }
    property int initialTab: {
        const envTab = Quickshell.env("QS_SETTINGS_TAB");
        return envTab ? parseInt(envTab) : 0;
    }
    // Handed to the next page loaded and cleared once it has looked, so later
    // page visits start at the top as usual.
    property string pendingSettingsSection: Quickshell.env("QS_SETTINGS_SECTION") || ""
    property int currentPage: initialPage

    visible: true
    // A successful run's record goes once the Update page has marked it seen and the window
    // closes (not restarts); a run still going, or one that failed, has no mark and stays.
    onClosing: {
        if (!root.restarting) {
            Quickshell.execDetached(["bash", "-c",
                '[ -f "$0/update.seen" ] && rm -f "$0/update.log" "$0/update.exit" "$0/update.seen"',
                Directories.updateStateDir]);
        }
        Qt.quit();
    }
    title: Translation.tr("Mainstream Settings")

    // Re-center on the active screen after a monitor scale apply.
    //
    // Why hyprctl instead of Screen.*: on Hyprland/Wayland the QScreen
    // attached properties don't reliably notify when the compositor changes
    // a per-monitor scale at runtime, so reading Screen.width/height after a
    // reload returns the *previous* logical size. That made a 167%→100%
    // change land the window at the old (smaller) centre — visibly up-left
    // of the new true centre — and a 167%→200% change overshoot down-right.
    //
    // hyprctl monitors -j is the source of truth: pixel `width`/`height`
    // plus `scale` give the logical compositor size (width/scale), and
    // `x`/`y` give the monitor origin in the multi-monitor virtual desktop.
    function recenter() {
        recenterProc.running = false;
        recenterProc.running = true;
    }

    Process {
        id: recenterProc
        command: ["hyprctl", "monitors", "-j"]
        // Collected whole. A parser with an empty marker hands over each raw
        // pipe read as it arrives, so on a machine with several screens the
        // JSON arrived in pieces and every piece failed to parse.
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let mons = JSON.parse(this.text);
                    if (!mons || mons.length === 0) return;
                    let mon = mons.find(m => m.focused) || mons[0];
                    let scale = mon.scale || 1.0;
                    // Hyprland's transform values 1, 3, 5, 7 are 90°/270°
                    // rotations — swap width/height in those cases so the
                    // logical orientation matches the visible one.
                    let rot = (mon.transform || 0) % 2 === 1;
                    let pxW = rot ? mon.height : mon.width;
                    let pxH = rot ? mon.width  : mon.height;
                    let logicalW = pxW / scale;
                    let logicalH = pxH / scale;
                    let tx = Math.round(mon.x + (logicalW - root.width)  / 2);
                    let ty = Math.round(mon.y + (logicalH - root.height) / 2);
                    // Asking for a position it already asked for is what let a
                    // resize become a move become another resize, forking two
                    // hyprctl processes each time round.
                    if (tx === root.lastRecenterX && ty === root.lastRecenterY)
                        return;
                    root.lastRecenterX = tx;
                    root.lastRecenterY = ty;
                    // Wayland xdg-shell does not allow clients to set their
                    // own x/y after creation — assigning root.x/root.y is a
                    // no-op on Hyprland. Ask the compositor to move us via
                    // a hyprctl dispatch keyed on our (translated) title.
                    let titleRegex = (root.title || "")
                        .replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
                    if (!titleRegex) return;
                    recenterMoveProc.command = [
                        "hyprctl", "dispatch",
                        `hl.dsp.window.move({ x = ${tx}, y = ${ty}, window = [[title:^${titleRegex}$]] })`
                    ];
                    recenterMoveProc.running = false;
                    recenterMoveProc.running = true;
                } catch (e) {
                    console.log("settings: could not read monitors for recenter:", e);
                }
            }
        }
    }

    Process { id: recenterMoveProc; command: [] }

    // Where the last move asked for, so the same request is not made twice.
    property int lastRecenterX: -100000
    property int lastRecenterY: -100000

    // Debounce — give hyprctl reload a beat to land before we query so we
    // don't read the pre-apply geometry.
    Timer {
        id: recenterTimer
        interval: 220
        repeat: false
        onTriggered: root.recenter()
    }

    Screen.onWidthChanged:  recenterTimer.restart()
    Screen.onHeightChanged: recenterTimer.restart()
    onWidthChanged:  recenterTimer.restart()
    onHeightChanged: recenterTimer.restart()

    // The Loader below swaps in DisplayConfig.qml when the user opens the
    // Display page. DisplayConfig emits scaleApplied() after its reloadProc
    // exits, which is the only deterministic "apply has fully landed"
    // signal — Screen.* changes are unreliable on Wayland scale apply.
    Connections {
        target: pageLoader.item
        ignoreUnknownSignals: true
        function onScaleApplied() { recenterTimer.restart() }
    }

    Component.onCompleted: {
        // Off so an update copying this tree cannot reload the window and kill its child
        // processes, the update among them; filesCheck restarts onto the new version instead.
        Quickshell.watchFiles = false
        root.checkFiles()
        root.signalRestarted()
        MaterialThemeLoader.reapplyTheme()
        ThemeLibrary.load()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        recenterTimer.restart()
        // Files opens the Sharing page naming the folder that should be
        // shared once sharing is set up.
        const sharingFolder = Quickshell.env("QS_SHARING_FOLDER")
        if (sharingFolder)
            FileSharing.requestFolder(sharingFolder)
    }

    // By pid, since a restart's two windows share the title until the old one goes.
    function bringForward() {
        Quickshell.execDetached(["hyprctl", "dispatch",
            `hl.dsp.focus({ window = "pid:${Quickshell.processId}" })`]);
    }

    IpcHandler {
        target: "settings"
        // QS_SETTINGS_PAGE and QS_SETTINGS_SECTION for a window already open.
        // "restarting" has the caller ask again, reaching the window that stays.
        function openPage(page: string, section: string): string {
            if (root.restarting)
                return "restarting";
            const index = page ? root.resolvePage(page) : -1;
            if (index !== -1) {
                root.pendingSettingsSection = section;
                // Even for the page shown, so it overrides an earlier request still being checked.
                root.requestPage(index);
                if (index === root.currentPage && pageLoader.status === Loader.Ready) {
                    // A page still loading takes the section in onLoaded instead.
                    if (section && pageLoader.item.scrollToSection)
                        pageLoader.item.scrollToSection(section);
                    root.pendingSettingsSection = "";
                }
            }
            root.bringForward();
            return "ok";
        }
        // For callers that bring the window forward themselves, such as the welcome installer.
        function showPage(name: string): void {
            root.showPage(name);
        }
        // What QS_SHARING_FOLDER does for a new window, for one already open:
        // qs ipc -p <this file> call settings shareFolder <absolute path>
        // It exits nonzero when no Settings window is running. The window is
        // brought forward here, since the caller has no address for it. It
        // stays void: Files takes any output as an older Settings without
        // this function and opens a new window instead.
        function shareFolder(path: string): void {
            root.sharingUsed = true;
            FileSharing.requestFolder(path);
            root.showPage("SharingConfig.qml");
            root.bringForward();
        }
    }

    // An update under way is what the person opening Settings most likely
    // wants to see, so it is shown unless a page was asked for by name.
    Process {
        running: !Quickshell.env("QS_SETTINGS_PAGE")
        // The pid has to name a live process. A run that was killed, or a
        // machine that lost power, leaves the file behind for good, and
        // existence alone would then force this page open on every launch
        // for the rest of the machine's life.
        command: ["bash", "-c",
            'bash "$0" "$1" >/dev/null 2>&1 && [ ! -f "$2" ]',
            Quickshell.shellPath("scripts/update/update-live.sh"),
            root.updatePidPath,
            Directories.updateStateDir + "/update.exit"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.showPage("UpdateConfig.qml")
        }
    }

    minimumWidth: 750
    minimumHeight: 500
    // A restart opens the new window at the old one's size.
    readonly property var startSize: (Quickshell.env("QS_SETTINGS_SIZE") || "").split("x").map(Number)
    width: root.startSize[0] >= root.minimumWidth ? root.startSize[0] : 1100
    height: root.startSize[1] >= root.minimumHeight ? root.startSize[1] : 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                // From a page change still being checked, so quick presses add up.
                const from = root.pendingPage !== -1 ? root.pendingPage : root.currentPage;
                if (event.key === Qt.Key_PageDown) {
                    root.requestPage(Math.min(from + 1, root.pages.length - 1))
                    event.accepted = true;
                } 
                else if (event.key === Qt.Key_PageUp) {
                    root.requestPage(Math.max(from - 1, 0))
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.requestPage((from + 1) % root.pages.length);
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.requestPage((from - 1 + root.pages.length) % root.pages.length);
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                // Close button suppressed — use Super+Q (or the window
                // manager's own close gesture) to dismiss the window.
                RippleButton {
                    visible: false
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.filesReplaced
            materialIcon: "update"
            text: root.restarting ? Translation.tr("Restarting Settings…")
                : root.restartRefused ? Translation.tr("Something is still running or unsaved. Finish it, then restart Settings.")
                : root.restartFailed ? Translation.tr("Settings could not restart. You can keep using this window, or try again.")
                : Translation.tr("Settings was updated. Restart it to use the new version.")

            Item {
                Layout.fillWidth: true
            }
            RippleButtonWithIcon {
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                colBackground: CF.ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                enabled: !root.restarting
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restart")
                onClicked: root.requestRestart()
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: 150
                Flickable {
                    id: navRailFlickable
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: navRail.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                ColumnLayout {
                    id: navRail
                    width: navRailFlickable.width
                    spacing: 0

                    Repeater {
                        model: root.pages
                        delegate: ColumnLayout {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0

                            // Divider whenever the group changes — driven off each
                            // page's `group`, so pages can be added, removed, or
                            // reordered without touching hardcoded indices.
                            Rectangle {
                                visible: index > 0 && root.pages[index - 1].group !== modelData.group
                                Layout.fillWidth: true
                                Layout.margins: 12
                                implicitHeight: 1
                                opacity: 0.3
                                color: Appearance.m3colors.m3outlineVariant
                            }

                            SettingsNavButton {
                                toggled: root.currentPage === index
                                onPressed: root.requestPage(index)
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation ?? 0
                                buttonText: modelData.name
                            }
                        }
                    }
                } // ColumnLayout navRail
                } // Flickable
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    source: Config.ready ? root.pages[root.currentPage].component : ""
                    // Per-page opt-in (see the page entries above) — currently
                    // only DisplayConfig flips this on. Async loads avoid the
                    // page-swap stutter on heavy pages but break layouts that
                    // assume the Loader's content is sized synchronously, so
                    // we don't apply it as a blanket setting.
                    asynchronous: Config.ready
                        && (root.pages[root.currentPage]?.asynchronous ?? false)

                    onLoaded: {
                        const loadedPage = root.pages[root.currentPage].component;
                        if (loadedPage.endsWith("SharingConfig.qml"))
                            root.sharingUsed = true;
                        else if (loadedPage.endsWith("ManageAppsConfig.qml"))
                            root.appsUsed = true;
                        if (!root.pendingSettingsSection) return;
                        if (!item?.scrollToSection) {
                            root.pendingSettingsSection = "";
                            return;
                        }
                        const name = root.pendingSettingsSection;
                        const page = item;
                        // After layout: section positions are not final inside onLoaded.
                        Qt.callLater(() => {
                            if (page !== pageLoader.item)
                                return;
                            page.scrollToSection(name);
                            // A request that came in meanwhile keeps its own section.
                            if (root.pendingSettingsSection === name)
                                root.pendingSettingsSection = "";
                        });
                    }

                    function reloadCurrentPage() {
                        if (!Config.ready)
                            return;

                        const currentSource = root.pages[root.currentPage].component;
                        source = "";
                        source = currentSource;
                    }

                    Connections {
                        target: Appearance
                        function onThemeRevisionChanged() {
                            // The Update page is left standing: its colors
                            // follow Appearance on their own, and rebuilding it
                            // replays the whole run record and asks for the
                            // pending list again, on every wallpaper change.
                            if (root.pages[root.currentPage].component.endsWith("UpdateConfig.qml"))
                                return;
                            pageLoader.reloadCurrentPage();
                        }
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }

    // Inline nav button for settings — same visual style as NavigationRailButton
    // in expanded mode but without states/transitions to avoid animation on first open.
    component SettingsNavButton: TabButton {
        id: navBtn
        property bool toggled: false
        property string buttonIcon
        // A glyph that only reads correctly one way up, the bar's among them,
        // is turned here. NavigationRailButton has carried this for its own
        // rows all along; this one had the value passed to it and nowhere to
        // put it, so the bar's icon sat upside down.
        property real buttonIconRotation: 0
        property string buttonText

        readonly property real baseSize: 56
        readonly property real visualWidth: baseSize + 20 + navBtnText.implicitWidth

        Layout.fillWidth: true
        implicitHeight: baseSize
        padding: 0
        background: null
        PointingHandInteraction {}

        contentItem: Item {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            implicitWidth: navBtn.visualWidth

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                implicitWidth: navBtn.visualWidth
                radius: Appearance.rounding.full
                color: navBtn.toggled ?
                    (navBtn.down ? Appearance.colors.colSecondaryContainerActive : navBtn.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer) :
                    (navBtn.down ? Appearance.colors.colLayer1Active : navBtn.hovered ? Appearance.colors.colLayer1Hover : CF.ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            Item {
                id: navBtnIconArea
                implicitWidth: navBtn.baseSize
                implicitHeight: 32
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 24
                    fill: navBtn.toggled ? 1 : 0
                    font.weight: (navBtn.toggled || navBtn.hovered) ? Font.DemiBold : Font.Normal
                    text: navBtn.buttonIcon
                    rotation: navBtn.buttonIconRotation
                    color: navBtn.toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            StyledText {
                id: navBtnText
                anchors {
                    left: navBtnIconArea.right
                    verticalCenter: navBtnIconArea.verticalCenter
                }
                text: navBtn.buttonText
                font.pixelSize: 14
                color: Appearance.colors.colOnLayer1
            }
        }
    }
}
