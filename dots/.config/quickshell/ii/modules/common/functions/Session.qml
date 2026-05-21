pragma Singleton
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    // Capture the current window set for session/restore.sh to replay on the
    // next login. Called from logout / reboot / poweroff / rebootToFirmware
    // BEFORE closeAllWindows() so the snapshot sees the windows while they're
    // still mapped. Self-gates on Config.options.session.restoreEnabled — no
    // effect when the toggle is off. The hyprland.shutdown hook in
    // custom/execs.lua remains a safety net for code paths that bypass this
    // singleton (lid close, hardware power button, killed compositor).
    //
    // Implementation note: this MUST be synchronous w.r.t. the power command
    // that follows. Earlier versions used execDetached() and the snapshot
    // was killed by systemd's user-process teardown wave before its python
    // enrichment step finished writing last.json. We now use a Process and
    // queue the actual power action into _afterSnapshot, fired from
    // onExited so the chain is properly sequenced.
    property var _afterSnapshot: null

    Process {
        id: snapshotProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/session/snapshot.sh"]
        onExited: {
            const f = root._afterSnapshot;
            root._afterSnapshot = null;
            if (f) f();
        }
    }

    function snapshotThen(after) {
        // Replace any queued post-snapshot action with the new one (last
        // write wins). If a snapshot is already running, the existing
        // onExited will fire `after` when it finishes; no need to retrigger.
        root._afterSnapshot = after;
        if (!snapshotProc.running)
            snapshotProc.running = true;
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        snapshotThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
        });
    }

    function launchTaskManager() {
        // Bar Resources widget + session-screen Task Manager button both
        // land here. Three install paths to recognise, in this order:
        //
        //   1. Native `resources` binary in PATH — AUR install.
        //   2. Flatpak `net.nokyan.Resources` — Flathub install (the
        //      archiso netinstall default, and what mainstream-extras
        //      now pulls in). `flatpak info` checks installation
        //      regardless of whether /var/lib/flatpak/exports/bin is
        //      in PATH (some session-manager setups don't add it).
        //   3. Whatever the user set Config.options.apps.taskManager
        //      to — defaults to "resources" but can be "btop", a
        //      custom command, etc.
        Quickshell.execDetached(["bash", "-c",
            "if command -v resources >/dev/null 2>&1; then " +
            "    exec resources; " +
            "elif command -v flatpak >/dev/null 2>&1 && flatpak info net.nokyan.Resources >/dev/null 2>&1; then " +
            "    exec flatpak run net.nokyan.Resources; " +
            "else " +
            "    exec " + Config.options.apps.taskManager + "; " +
            "fi"
        ]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        snapshotThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
        });
    }

    function reboot() {
        snapshotThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
        });
    }

    function rebootToFirmware() {
        snapshotThen(() => {
            closeAllWindows();
            Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
        });
    }
}
