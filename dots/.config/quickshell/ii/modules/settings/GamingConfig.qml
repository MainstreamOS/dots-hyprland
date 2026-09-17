import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property bool helperPresent: false
    property bool schedulerInstalled: false
    property bool schedulerSupported: false
    property bool schedulerOn: false
    property bool schedulerActive: false
    property bool kernelOptsAvailable: false
    property string kernelCmdline: ""
    property string runningCmdline: ""
    // The huge pages mode the kernel is running with, from sysfs. With no
    // token on the boot line that is the kernel's own default, which is what
    // the switch has to show rather than "no token".
    property string runningThp: ""
    // Held false while a read is in flight so a restored switch snaps into
    // place instead of sliding across every time the page is opened.
    property bool ready: false
    // A kernel switch rebuilds the boot image, which takes a while; the
    // switches wait for it rather than take a second change underneath it.
    property bool applying: false
    property string lastError: ""

    // The kernel takes the last occurrence of a key, so the scan runs from
    // the end.
    function tokenValue(cmdline, key) {
        const toks = cmdline.split(" ");
        for (let i = toks.length - 1; i >= 0; i--) {
            if (toks[i].indexOf(key + "=") === 0)
                return toks[i].substring(key.length + 1);
        }
        return "";
    }

    readonly property bool splitLockOff: root.tokenValue(root.kernelCmdline, "split_lock_detect") === "off"
    readonly property bool splitLockOffRunning: root.tokenValue(root.runningCmdline, "split_lock_detect") === "off"
    // What the next boot will use: the token if there is one, else the
    // default the kernel is running with now.
    readonly property string configuredThp: root.tokenValue(root.kernelCmdline, "transparent_hugepage") || root.runningThp
    readonly property bool hugePagesOn: root.configuredThp === "always"
    readonly property bool hugePagesOnRunning: root.runningThp === "always"
    // Compared against what the kernel was actually started with, so the
    // hint survives closing and reopening Settings.
    readonly property bool rebootPending: root.ready
        && (root.splitLockOff !== root.splitLockOffRunning || root.hugePagesOn !== root.hugePagesOnRunning)

    function refresh() {
        root.ready = false;
        probeProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: probeProc
        command: ["sh", "-c",
            "test -x /usr/local/bin/gaming-tuning && echo helper=1 || echo helper=0; "
            + "test -x /usr/bin/scx_lavd && echo installed=1 || echo installed=0; "
            + "test -d /sys/kernel/sched_ext && echo supported=1 || echo supported=0; "
            + "systemctl is-enabled mainstream-scx-lavd.service >/dev/null 2>&1 && echo enabled=1 || echo enabled=0; "
            + "systemctl is-active mainstream-scx-lavd.service >/dev/null 2>&1 && echo active=1 || echo active=0; "
            + "test -f /etc/kernel/cmdline && command -v limine-update >/dev/null 2>&1 && echo kernelopts=1 || echo kernelopts=0; "
            + "echo \"thp=$(grep -o '\\[[a-z]*\\]' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | tr -d '[]')\"; "
            + "echo \"cmdline=$(cat /etc/kernel/cmdline 2>/dev/null)\"; "
            + "echo \"running=$(cat /proc/cmdline 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text;
                // Each answer is matched on its own line. The command lines
                // are in this output too, and a kernel parameter ending in
                // "enabled=1" must not read as the scheduler being on.
                const flag = k => new RegExp("^" + k + "=1$", "m").test(out);
                const val = k => {
                    const m = out.match(new RegExp("^" + k + "=(.*)$", "m"));
                    return m ? m[1].trim() : "";
                };
                root.helperPresent = flag("helper");
                root.schedulerInstalled = flag("installed");
                root.schedulerSupported = flag("supported");
                root.schedulerOn = flag("enabled");
                root.schedulerActive = flag("active");
                root.kernelOptsAvailable = flag("kernelopts");
                root.runningThp = val("thp");
                root.kernelCmdline = val("cmdline");
                root.runningCmdline = val("running");
                root.ready = true;
                // A click breaks the binding, so a refused or cancelled
                // authentication would otherwise leave a switch showing a
                // change that never happened.
                schedSwitch.checked = root.schedulerOn;
                splitSwitch.checked = root.splitLockOff;
                hugeSwitch.checked = root.hugePagesOn;
            }
        }
    }

    // The helper's exit and its last words arrive separately; the outcome
    // is read once both are in.
    property int applyExit: -1
    property bool applyErrDone: false

    Process {
        id: applyProc
        stderr: StdioCollector {
            id: applyErr
            onStreamFinished: {
                root.applyErrDone = true;
                root.applyFinished();
            }
        }
        onExited: (code) => {
            root.applyExit = code;
            root.applyFinished();
        }
    }

    function apply(args) {
        root.lastError = "";
        root.applyExit = -1;
        root.applyErrDone = false;
        root.applying = true;
        applyProc.command = ["pkexec", "/usr/local/bin/gaming-tuning"].concat(args);
        applyProc.running = true;
    }

    function applyFinished() {
        if (root.applyExit < 0 || !root.applyErrDone)
            return;
        root.applying = false;
        if (root.applyExit === 126) {
            root.lastError = Translation.tr("The change was not made: authentication was cancelled.");
        } else if (root.applyExit === 127) {
            root.lastError = Translation.tr("The change was not made: the gaming stack is not fully installed.");
        } else if (root.applyExit !== 0) {
            const lines = applyErr.text.trim().split("\n").filter(l => l.length > 0);
            root.lastError = lines.length > 0
                ? lines[lines.length - 1].replace(/^gaming-tuning: /, "")
                : Translation.tr("The change could not be applied.");
        }
        root.refresh();
    }

    // Everything on this page goes through one helper; without it there is
    // nothing to switch.
    StyledText {
        Layout.fillWidth: true
        visible: root.ready && !root.helperPresent
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("The gaming stack is not fully installed on this machine. Run an update, then come back.")
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.lastError.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.m3colors.m3error
        text: root.lastError
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Responsiveness")

        ContentSubsection {
            title: Translation.tr("Responsive scheduler")
            tooltip: Translation.tr("Tunes the kernel for responsiveness rather than raw throughput.\nGames stay smooth while something heavy runs behind them.\nLong compiles and video encodes finish slower.")

            ConfigSwitch {
                id: schedSwitch
                buttonIcon: "bolt"
                text: Translation.tr("Keep games smooth under load")
                enabled: root.ready && root.helperPresent && root.schedulerInstalled && root.schedulerSupported && !root.applying
                animateChanges: root.ready
                checked: root.schedulerOn
                onCheckedChanged: {
                    if (!root.ready || checked === root.schedulerOn)
                        return;
                    root.apply(["scheduler", checked ? "on" : "off"]);
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.ready && root.helperPresent && !root.schedulerInstalled
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Install the gaming stack to use this.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.ready && root.schedulerInstalled && !root.schedulerSupported
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("This kernel does not support it.")
            }
            // Enabled is not running: a scheduler the kernel refused exits at
            // once and the unit is left failed, which the switch alone would
            // never show.
            StyledText {
                Layout.fillWidth: true
                visible: root.ready && root.schedulerOn && !root.schedulerActive
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
                text: Translation.tr("The scheduler is switched on but could not start. The standard one is running. Check the system log.")
            }
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Kernel options")

        ContentSubsection {
            title: Translation.tr("Per game, worth testing")
            tooltip: Translation.tr("Neither of these helps every game.\nTurn one on, play the game that was stuttering, and turn it back off if nothing changed.")

            ConfigSwitch {
                id: splitSwitch
                buttonIcon: "lock_open"
                text: Translation.tr("Skip split lock detection")
                enabled: root.ready && root.helperPresent && root.kernelOptsAvailable && !root.applying
                animateChanges: root.ready
                checked: root.splitLockOff
                tooltipText: Translation.tr("Removes a stutter in some older games on Intel processors.\nAlso removes a protection against one program stalling the machine.")
                onCheckedChanged: {
                    if (!root.ready || checked === root.splitLockOff)
                        return;
                    root.apply(["kernelopt", "splitlock", checked ? "on" : "off"]);
                }
            }

            ConfigSwitch {
                id: hugeSwitch
                buttonIcon: "database"
                text: Translation.tr("Always use huge memory pages")
                enabled: root.ready && root.helperPresent && root.kernelOptsAvailable && !root.applying
                animateChanges: root.ready
                checked: root.hugePagesOn
                tooltipText: Translation.tr("Some games load faster and run smoother.\nOthers gain nothing and use more memory. Off asks for them only where a program requests them.")
                onCheckedChanged: {
                    if (!root.ready || checked === root.hugePagesOn)
                        return;
                    root.apply(["kernelopt", "hugepages", checked ? "on" : "off"]);
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.ready && root.helperPresent && !root.kernelOptsAvailable
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Only available when Mainstream manages the boot menu.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.applying
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Rebuilding the boot image. This takes a moment.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.rebootPending && !root.applying
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Restart to apply.")
            }
        }
    }
}
