pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Applies saved themes atomically in the main shell process so external writes
 * and the shell's own Config adapter can't race on config.json. Exposes an IPC
 * target so the settings app (separate process) can request an apply without
 * running bash itself.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/themes/apply-theme.sh`

    signal applied(string slug)
    signal applyFailed(string slug, string message)

    function load() {} // For forcing initialization

    function apply(slug) {
        if (!slug || slug.length === 0) return
        // Block the live adapter from racing with our staged write-and-move.
        Config.blockWrites = true
        applyProc.pendingSlug = slug
        applyProc.command = ["bash", root.scriptPath, slug]
        applyProc.running = false
        applyProc.running = true
    }

    Process {
        id: applyProc
        property string pendingSlug: ""
        onExited: (exitCode, exitStatus) => {
            Config.blockWrites = false
            // Force a re-read of the generated colors.json. Matugen writes via
            // rename which can leave QFileSystemWatcher tracking a stale inode,
            // so onFileChanged doesn't always fire.
            MaterialThemeLoader.reapplyTheme()
            if (exitCode === 0) {
                root.applied(applyProc.pendingSlug)
            } else {
                root.applyFailed(applyProc.pendingSlug, "exit " + exitCode)
            }
        }
    }

    IpcHandler {
        target: "themes"

        function apply(slug: string): void {
            root.apply(slug);
        }
    }
}
