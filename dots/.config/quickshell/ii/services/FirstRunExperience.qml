pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string firstRunFilePath: `${Directories.state}/user/first_run.txt`
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string firstRunNotifSummary: "Welcome!"
    property string firstRunNotifBody: "Hit Super+/ for a list of keybinds"
    property string defaultWallpaperPath: FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`)
    property string welcomeQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("welcome-tutorial.qml"))

    function load() {
        firstRunFileView.reload()
    }

    function enableNextTime() {
        Quickshell.execDetached(["rm", "-f", root.firstRunFilePath])
    }
    function disableNextTime() {
        Quickshell.execDetached(["bash", "-c", `echo '${root.firstRunFileContent}' > '${root.firstRunFilePath}'`])
    }

    function handleFirstRun() {
        // Idle priority: let the bar win the CPU/IO during startup; the theme
        // generation catches up a beat after the bar has painted.
        Quickshell.execDetached(["nice", "-n", "19", "ionice", "-c", "3", Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath])
        // Gate the welcome on the BAR's first paint. It launches as a second,
        // heavy quickshell process; starting it during the main shell's startup
        // races the paint and pops up over a blank/half-painted bar. Wait (up to
        // ~15s) for the bar's own layer surface — quickshell:bar (or
        // quickshell:verticalBar), NOT just any quickshell:* surface: lighter
        // ones like quickshell:background map before the themed bar paints on a
        // cold first boot, so a bare match races it. Settle a beat, then launch.
        Quickshell.execDetached(["bash", "-c",
            `for i in $(seq 1 150); do hyprctl layers -j 2>/dev/null | grep -Eq '"namespace": *"quickshell:(bar|verticalBar)"' && break; sleep 0.1; done; sleep 0.3; qs -p '${root.welcomeQmlPath}'`])
    }

    FileView {
        id: firstRunFileView
        path: Qt.resolvedUrl(firstRunFilePath)
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                firstRunFileView.setText(root.firstRunFileContent)
                root.handleFirstRun()
            }
        }
    }
}
