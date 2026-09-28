pragma Singleton
import Quickshell
import qs.modules.common

Singleton {
    id: root

    // Log out, restart and shut down go through scripts/session/end-session.sh,
    // which says what it does. Lid close, the power button and a killed
    // compositor bypass it; the session watcher keeps the snapshot current
    // for those.
    function endSession(action) {
        Quickshell.execDetached(["bash", Quickshell.shellPath("scripts/session/end-session.sh"), action]);
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
        root.endSession("logout");
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
        root.endSession("poweroff");
    }

    function reboot() {
        root.endSession("reboot");
    }

    function rebootToFirmware() {
        root.endSession("firmware");
    }
}
