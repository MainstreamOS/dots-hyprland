pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
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
        closeAllWindows();
        Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
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
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
    }

    function reboot() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
    }

    function rebootToFirmware() {
        closeAllWindows();
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
    }
}
