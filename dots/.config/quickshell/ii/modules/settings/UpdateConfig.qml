import QtQuick
import QtQuick.Controls
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

    property string outputText: ""
    property bool isRunning: false
    property bool userStopped: false

    // The update runs in its own session and writes here; this page only views it.
    // A result stays on disk until it has been seen and the window closed.
    readonly property string stateDir: Directories.updateStateDir
    readonly property string logPath: stateDir + "/update.log"
    readonly property string exitPath: stateDir + "/update.exit"
    readonly property string pidPath: stateDir + "/update.pid"
    readonly property string seenPath: stateDir + "/update.seen"
    // Lets the reboot reminder outlive the record. Stale once the machine has
    // booted since it was written.
    readonly property string rebootMarkPath: stateDir + "/update.reboot"
    readonly property string launcher: Quickshell.shellPath("scripts/update/run-detached.sh")
    // The launcher ends the log with this once the helper has exited.
    readonly property string exitSentinel: "@@MAINSTREAM-UPDATE-EXIT "
    // Helper markers: what the run will replace (judged before installing) and what it did.
    readonly property string rebootPlanMarker: "@@MAINSTREAM-UPDATE-REBOOT-PLAN "
    readonly property string rebootMarker: "@@MAINSTREAM-UPDATE-REBOOT "
    readonly property string rebootCheck: Quickshell.shellPath("scripts/update/reboot-check.sh")
    // The boot menu would not start the system as updated, so no reboot is
    // offered. 3 after the marker: it starts a kernel no longer installed.
    readonly property string bootBrokenMarker: "@@MAINSTREAM-UPDATE-BOOT-BROKEN"
    property bool bootBroken: false
    property bool bootOldKernel: false
    // Kept apart so a replayed record cannot silence a fresh prediction: rebootPredicted
    // is what a run started now would do; rebootVerdict is a finished run's.
    property bool rebootPredicted: false
    property bool rebootVerdict: false
    readonly property bool rebootRequired: root.rebootVerdict && !root.bootBroken
    readonly property bool awaitingReboot: !root.isRunning && root.rebootRequired
    property bool recordPredatesBoot: false
    // Set while a finished record is replayed; its plan marker predicts nothing now.
    property bool replaying: false

    // Batched so a burst of lines costs one text layout, not one per line.
    property var pendingLines: []
    // The view keeps only the newest part; Copy reads the full record on disk.
    readonly property int outputKeepChars: 250000
    property bool outputTrimmed: false
    // The helper's first line. A run without it was refused by sudo, which tells
    // a wrong password from a later failure in any language.
    readonly property string startMarker: "@@MAINSTREAM-UPDATE-HELPER-START"
    property bool helperStarted: false
    // Whether the installed helper prints that line. An older one also exits 1
    // on a failed package step, so then only sudo's own words prove a wrong password.
    property bool helperMarksStart: false
    // The root half (updatems-system) installs the update tools, so a copy differing from
    // the clone's means it never ran. The relogin note marks changes that only load at login.
    property bool systemHalfPending: false
    property bool reloginNeeded: false
    // A launcher that fails to start reports only through runningChanged, with
    // no exited; this records whether exited fired.
    property bool launcherExited: false
    readonly property string liveCheck: Quickshell.shellPath("scripts/update/update-live.sh")
    property bool snapshotsAvailable: true
    Process {
        running: true
        // The pre-update snapshot needs the snapshot service set up for root, not just Btrfs.
        command: ["sh", "-c", "test -f /etc/limine-snapper-sync.conf && test -f /etc/snapper/configs/root"]
        onExited: (code) => root.snapshotsAvailable = (code === 0)
    }

    // Mainstream ships no AUR helper, so the AUR switch only shows when yay or paru is installed.
    property bool aurHelperPresent: false

    property bool flagSkipSystem: false
    // AUR skipped by default: Mainstream avoids the AUR over supply-chain concerns.
    property bool flagSkipAur: true
    property bool flagSkipFlatpak: false
    property bool flagSkipDotfiles: false
    property bool flagSkipExtras: false
    // Firmware updates can prompt polkit and time out unattended.
    property bool flagSkipFirmware: true
    property bool flagAutoRebuildQuickshell: true
    property bool flagEdge: false
    property string customArgs: ""

    // Cleared as soon as it is written to the launcher's stdin.
    property string pendingPassword: ""

    function buildHelperArgs(finishing) {
        let args = ["sudo", "-S", "/usr/local/bin/mainstream-update-helper"];
        if (flagSkipSystem)            args.push("--skip-system");
        if (flagSkipAur)               args.push("--skip-aur");
        if (flagSkipFlatpak)           args.push("--skip-flatpak");
        // The root half runs after the dotfiles step, so finishing it cannot skip that step.
        if (flagSkipDotfiles && !finishing) args.push("--skip-dotfiles");
        if (flagSkipExtras)            args.push("--skip-extras");
        if (flagSkipFirmware)          args.push("--skip-firmware");
        if (flagAutoRebuildQuickshell) args.push("--auto-rebuild-quickshell");
        if (flagEdge)                  args.push("--edge");
        if (customArgs.trim().length > 0) {
            // For topgrade, after -- so the helper passes them on instead of taking them.
            let extra = customArgs.trim().split(/\s+/);
            args.push("--");
            for (let i = 0; i < extra.length; i++) args.push(extra[i]);
        }
        return args;
    }

    function commandPreview() {
        let lines = [];
        lines.push((flagSkipSystem      ? "✗" : "✓") + "  System packages    (pacman -Syu)");
        if (aurHelperPresent)
            lines.push((flagSkipAur     ? "✗" : "✓") + "  AUR                (yay -Sua)");
        lines.push((flagSkipFlatpak     ? "✗" : "✓") + "  Flatpak            (flatpak update --system + --user)");
        lines.push((flagSkipDotfiles    ? "✗" : "✓") + "  Mainstream dots    (updatems — on remote tag bump)");
        lines.push((flagSkipExtras      ? "✗" : "✓") + "  Developer extras   (topgrade — cargo, pipx, npm, nix, ...)");
        lines.push((flagAutoRebuildQuickshell ? "✓" : "✗") + "  Quickshell ABI check + rebuild if needed");
        return lines.join("\n");
    }

    function resetRunState() {
        outputText = "";
        pendingLines = [];
        outputTrimmed = false;
        helperStarted = false;
        rebootVerdict = false;
        rebootPredicted = false;
        bootBroken = false;
        bootOldKernel = false;
        recordPredatesBoot = false;
        userStopped = false;
        replaying = false;
        launcherExited = false;
    }

    function clearOutput() {
        resetRunState();
        clearProc.running = true;
    }

    function startUpdate(finishing) {
        if (isRunning) return;
        if (passwordField.text.length === 0) {
            outputText = Translation.tr("Enter your password to start the update.");
            return;
        }
        resetRunState();
        // The last run may have installed a newer helper.
        helperMarkCheck.running = true;
        pendingPassword = passwordField.text;
        passwordField.text = "";
        helperProc.command = ["bash", root.launcher, root.stateDir].concat(buildHelperArgs(finishing === true));
        helperProc.stdinEnabled = true;
        helperProc.running = true;
        isRunning = true;
    }

    // The notice already asks for the password, so an empty field only takes
    // focus. The output stays: it may record the run that left this undone.
    function finishPendingUpdate() {
        if (passwordField.text.length === 0) {
            passwordField.forceActiveFocus();
            return;
        }
        startUpdate(true);
    }

    function showStopFailed() {
        root.flushOutput();
        root.outputText += "\n" + Translation.tr("Nothing to stop: that update is no longer running.");
        root.isRunning = false;
        probeProc.running = true;
    }

    function stopUpdate() {
        if (!isRunning) return;
        // Marked stopped only once the signal lands: the launcher forks, so the
        // pid file can appear a moment after the run seems to start.
        stopProc.running = true;
    }

    // The run lives apart from this page, so the guard asks again whether anything is installing.
    function requestReboot() {
        if (!root.awaitingReboot || rebootGuard.running)
            return;
        rebootGuard.running = true;
    }

    function bootBrokenText() {
        if (root.recordPredatesBoot)
            return Translation.tr("The last update found that the boot menu could not start the system. Run the update again to check it.");
        if (root.bootOldKernel)
            return Translation.tr("Do not restart the computer yet. The boot menu still starts a kernel that is no longer installed, so the computer would start without its drivers. The message above says how to build the boot image for the installed kernel.");
        return Translation.tr("Do not restart the computer yet. The boot menu does not match the system's boot image, so the computer would not start, and it could not be repaired, usually because the EFI partition is too full. Free some space on the EFI partition, then run the update again: it repairs the boot menu first.");
    }

    // Runs once the helper has exited, whether watched live or found in the record.
    function finish(exitCode) {
        tailProc.running = false;
        root.isRunning = false;
        root.pendingPassword = "";
        root.flushOutput();
        // So the auto-scroll lands on the summary, not the log's trailing blank lines.
        root.outputText = root.outputText.replace(/\s+$/, "");
        // Whatever the run did, it may have finished what an earlier one left.
        leftoverCheck.running = true;
        if (exitCode === 106)
            root.bootBroken = true;
        if (root.userStopped || exitCode === 143 || exitCode === 130) {
            root.outputText += "\n\n" + Translation.tr("Update stopped by user.");
            if (root.bootBroken)
                root.outputText += "\n" + root.bootBrokenText();
            if (root.rebootRequired)
                root.outputText += "\n" + Translation.tr("Parts of the running desktop were already replaced. Reboot, then run the update again to finish it; until then some controls may not work.");
            return;
        }
        if (exitCode < 0) {
            root.outputText += "\n\n" + Translation.tr("The update did not finish. The record above stops where it stopped.");
            return;
        }
        // sudo refuses a standard account even with the right password, so it
        // must not be told the password was wrong.
        const sudoNotAllowed = root.outputText.indexOf("is not in the sudoers file") !== -1
            || root.outputText.indexOf("is not allowed to run sudo") !== -1;
        if (exitCode === 1 && !root.helperStarted && sudoNotAllowed) {
            root.outputText += "\n\n" + Translation.tr("This account cannot install updates. An administrator can run the update, or make this account an administrator in Settings > Accounts.");
            return;
        }
        // sudo exits 1 on a wrong password before the helper's first line. Its
        // message is localized, so it only decides for a helper without that line.
        const sudoRefused = root.outputText.indexOf("incorrect password") !== -1
            || root.outputText.indexOf("Sorry, try again") !== -1;
        const authFailed = exitCode === 1 && !root.helperStarted
            && (root.helperMarksStart || sudoRefused);
        if (authFailed) {
            root.outputText += "\n\n" + Translation.tr("Authentication failed — wrong password. Try again.");
            return;
        }
        // 100: snap or extras failed, or [mainstream] was switched off; shown as
        // success since the summary says so. 101: dotfiles failed, never a success.
        if (exitCode === 3) {
            root.outputText += "\n\n" + Translation.tr("Another update was already running, so this one did not start.");
        } else if (exitCode === 4) {
            // The desktop's Qt pin held pacman back; the other steps still ran.
            root.outputText += "\n\n" + Translation.tr("System packages were held back: Arch moved to a newer Qt than this desktop is built for. Flatpak, Snap and the system files still updated, and the rest goes through once the matching desktop update is published.");
        } else if (exitCode === 101) {
            root.outputText += "\n\n" + Translation.tr("Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above.");
        } else if (exitCode === 102) {
            // The root half ran but failed partway. It installs the update tools first, so
            // usually no Finish update notice follows; the next update runs it again.
            root.outputText += "\n\n" + Translation.tr("Update finished, but the system part of the Mainstream update did not finish. See the System bits line in the summary above.");
        } else if (exitCode === 105) {
            root.outputText += "\n\n" + Translation.tr("System packages were held back: the EFI partition, which holds the boot menu, is too full to rebuild the boot image safely. No system package was changed. Free some space on the EFI partition, then run the update again.");
        } else if (exitCode === 0 || exitCode === 100 || exitCode === 106) {
            // 106 set bootBroken above, so its message below stands in for this one.
            if (!root.bootBroken)
                root.outputText += "\n\n" + Translation.tr("Update completed successfully.");
        } else {
            root.outputText += "\n\n" + Translation.tr("Update finished with exit code %1.").arg(exitCode);
        }
        if (root.bootBroken)
            root.outputText += "\n\n" + root.bootBrokenText();
        if (root.rebootRequired)
            root.outputText += "\n" + Translation.tr("Parts of the running desktop were replaced. Reboot to finish the update; until then some controls may not work.");
        // Only a success is let go on close; failures, stops and a boot menu
        // that would not start stay to be reread.
        if ((exitCode === 0 || exitCode === 100) && !root.bootBroken) {
            if (root.rebootRequired)
                rebootMarkProc.running = true;
            seenProc.running = true;
        }
        rebootMarkCheck.running = true;
    }

    // "<0|1> [package ...]" from the check script or a marker line; only yes or no is used.
    function readRebootAnswer(text, kind) {
        const first = text.trim().split(/\s+/)[0];
        // Repositories unreachable: keep what was known rather than claim no reboot.
        if (first === "unknown")
            return;
        const yes = first === "1";
        if (kind === "verdict") {
            // A record from before this boot: its reboot already happened.
            root.rebootVerdict = yes && !root.recordPredatesBoot;
            // That run is over, so it predicts nothing about the next one.
            root.rebootPredicted = false;
        } else if (kind === "plan") {
            if (!root.replaying)
                root.rebootPredicted = yes;
        } else if (!root.isRunning) {
            // A run in flight knows more than the pending list does.
            root.rebootPredicted = yes;
        }
    }

    // Does anything pending own a file the running desktop has loaded?
    Process {
        id: predictProc
        // Waits for the probe: it costs a repository sync, and the page is
        // rebuilt on every visit because the settings pages share a loader.
        running: false
        command: ["bash", root.rebootCheck, "predict"]
        stdout: StdioCollector {
            onStreamFinished: root.readRebootAnswer(this.text.replace(/\n/g, " "), "predict")
        }
    }

    // Some tools color their output even into a file; the codes would show as text.
    function plainText(text) {
        if (text.indexOf("\x1b") === -1)
            return text;
        return text.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "");
    }

    // Usually one line. The exit sentinel is looked for anywhere in it, since the
    // parser can glue it to the blank line the launcher writes before it.
    function takeLine(line) {
        line = root.plainText(line);
        const plan = line.indexOf(root.rebootPlanMarker);
        if (plan !== -1) {
            root.readRebootAnswer(line.substring(plan + root.rebootPlanMarker.length), "plan");
            return;
        }
        const verdict = line.indexOf(root.rebootMarker);
        if (verdict !== -1) {
            root.readRebootAnswer(line.substring(verdict + root.rebootMarker.length), "verdict");
            return;
        }
        if (line.indexOf(root.startMarker) !== -1) {
            root.helperStarted = true;
            return;
        }
        const broken = line.indexOf(root.bootBrokenMarker);
        if (broken !== -1) {
            root.bootBroken = true;
            root.bootOldKernel = line.substring(broken + root.bootBrokenMarker.length).trim() === "3";
            return;
        }
        // An older helper without that line still prints step banners or ">>> " refusals, which
        // sudo never does. The record decides, since this run may have replaced the helper.
        if (!root.helperStarted && (line.indexOf("═══") !== -1 || line.indexOf(">>> ") === 0))
            root.helperStarted = true;
        const at = line.indexOf(root.exitSentinel);
        if (at === -1) {
            root.queueOutput(line + "\n");
            return;
        }
        if (at > 0) root.queueOutput(line.substring(0, at));
        const code = parseInt(line.substring(at + root.exitSentinel.length), 10);
        root.finish(isNaN(code) ? -1 : code);
    }

    function queueOutput(text) {
        root.pendingLines.push(text);
        if (!flushTimer.running)
            flushTimer.start();
    }

    function flushOutput() {
        flushTimer.stop();
        if (root.pendingLines.length === 0)
            return;
        let text = root.outputText + root.pendingLines.join("");
        root.pendingLines = [];
        if (text.length > root.outputKeepChars) {
            const from = text.length - root.outputKeepChars;
            const cut = text.indexOf("\n", from);
            text = text.substring(cut === -1 ? from : cut + 1);
            root.outputTrimmed = true;
        }
        root.outputText = text;
    }

    Timer {
        id: flushTimer
        interval: 60
        repeat: false
        onTriggered: root.flushOutput()
    }

    // Only launches the update; the helper runs detached in its own session, so
    // this exits once the password is handed on.
    Process {
        id: helperProc
        onRunningChanged: {
            // The launcher waits for exactly one stdin line, the password for sudo -S.
            if (running && root.pendingPassword.length > 0) {
                write(root.pendingPassword + "\n");
                root.pendingPassword = "";
                stdinEnabled = false;
                return;
            }
            // exited fires first on a normal end; stopping without it means the
            // launcher never ran at all.
            if (!running && root.isRunning && !root.launcherExited && !tailProc.running) {
                root.isRunning = false;
                root.pendingPassword = "";
                root.outputText = Translation.tr("The update could not be started.");
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.launcherExited = true;
            root.pendingPassword = "";
            if (exitCode !== 0) {
                root.isRunning = false;
                root.outputText = Translation.tr("The update could not be started (launcher exit code %1).").arg(exitCode);
                return;
            }
            tailProc.running = true;
        }
    }

    // From the first line, so a page opened mid-run shows everything so far.
    Process {
        id: tailProc
        command: ["tail", "-n", "+1", "-F", root.logPath]
        stdout: SplitParser { onRead: data => root.takeLine(data) }
    }

    // Signals the session leader's child (sudo, which relays it to the helper);
    // signaling the leader would only defer it until the helper finished.
    Process {
        id: stopProc
        // The live check rejects a stale pid file whose number now names a bystander.
        command: ["bash", "-c",
            'p=$(bash "$0" "$1") || exit 1; pkill -TERM -P "$p" || exit 1; exit 0',
            root.liveCheck, root.pidPath]
        onExited: (code) => {
            if (code === 0) {
                if (!root.userStopped) {
                    root.flushOutput();
                    root.outputText += "\n" + Translation.tr("Stopping. AUR builds and developer extras stop right away; any other step finishes first, so nothing is left half installed.");
                }
                root.userStopped = true;
            } else {
                // Nothing was signaled; say so rather than leave a Stop that seemed to work.
                root.showStopFailed();
            }
        }
    }

    // Exits 1 while this page's update, a pacman transaction or a dotfiles
    // update is running; a lock file alone may be left from a crash.
    Process {
        id: rebootGuard
        command: ["bash", "-c",
            'bash "$0" "$1" "$2" && exit 1; [ -e /var/lib/pacman/db.lck ] && pidof pacman >/dev/null && exit 1; exit 0',
            Quickshell.shellPath("scripts/update/update-busy.sh"), root.pidPath, Directories.dotfilesClone + "/.update-lock"]
        onExited: (code) => {
            if (code !== 0) {
                root.flushOutput();
                root.outputText += "\n\n" + Translation.tr("An update or package install is still running, so the computer was not restarted. Reboot once it finishes.");
                return;
            }
            // The page may have learned more while the check ran.
            if (root.awaitingReboot)
                Session.reboot();
        }
    }

    // Runs before a finished record is replayed, since reading its end depends
    // on this, and again as each run starts.
    property bool markChecked: false
    Process {
        id: helperMarkCheck
        running: true
        command: ["bash", "-c", 'grep -qsF -- "$0" /usr/local/bin/mainstream-update-helper', root.startMarker]
        onExited: (code) => {
            root.helperMarksStart = (code === 0);
            if (!root.markChecked) {
                root.markChecked = true;
                probeProc.running = true;
            }
        }
    }

    // Rechecked after each run: its dotfiles step writes the relogin note and
    // its root half settles the other.
    Process {
        id: leftoverCheck
        running: true
        command: ["bash", "-c",
            'c="$HOME/.cache/dots-hyprland";'
            + ' if [ -e "$c/.updatems-applied-tag" ] && { ! cmp -s /usr/local/bin/updatems-system "$c/sdata/update/updatems-system"'
            + ' || ! cmp -s /usr/local/bin/mainstream-update-helper "$c/sdata/update/mainstream-update-helper"; }; then echo system; fi;'
            + ' [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/mainstream/relogin-needed" ] && echo relogin; exit 0']
        stdout: StdioCollector {
            onStreamFinished: {
                const found = this.text.split("\n");
                root.systemHalfPending = found.indexOf("system") !== -1;
                root.reloginNeeded = found.indexOf("relogin") !== -1;
            }
        }
    }

    // On open: is a run under way, or is there a record of the last one to show?
    Process {
        id: probeProc
        command: ["bash", "-c",
            'if [ -f "$1" ]; then read up _ < /proc/uptime; s="";'
            + ' [ "$(stat -c %Y "$0")" -lt "$(( $(date +%s) - ${up%.*} ))" ] && s=" rebooted";'
            + ' echo "finished $(cat "$1")$s";'
            // A pid file outlives a killed run, so it only counts if it names a
            // live process; otherwise the page latches into a run that never ends.
            + ' elif bash "$3" "$2" >/dev/null 2>&1; then echo running;'
            + ' elif [ -s "$0" ]; then rm -f "$2"; echo "finished -1";'
            + ' else rm -f "$2"; echo none; fi',
            root.logPath, root.exitPath, root.pidPath, root.liveCheck]
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = this.text.trim();
                if (answer === "running") {
                    root.outputText = "";
                    root.helperStarted = false;
                    root.isRunning = true;
                    tailProc.running = true;
                    return;
                }
                if (answer.indexOf("finished ") === 0) {
                    const rest = answer.substring("finished ".length);
                    root.recordPredatesBoot = rest.indexOf(" rebooted") !== -1;
                    root.pendingExitCode = parseInt(rest, 10);
                    recordProc.running = true;
                    return;
                }
                // Nothing on disk, so only the pending list can predict a reboot.
                predictProc.running = true;
                rebootMarkCheck.running = true;
            }
        }
    }
    property int pendingExitCode: -1

    // The finished record, read whole; its sentinel goes through the same path
    // a live one does.
    Process {
        id: recordProc
        command: ["cat", root.logPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.outputText = "";
                root.replaying = true;
                // userStopped is not on disk, so it is read back from the exit code.
                root.userStopped = (root.pendingExitCode === 143 || root.pendingExitCode === 130);
                root.helperStarted = false;
                const lines = this.text.split("\n");
                let sawSentinel = false;
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf(root.exitSentinel) === 0) sawSentinel = true;
                    root.takeLine(lines[i]);
                    if (sawSentinel) break;
                }
                if (!sawSentinel) root.finish(isNaN(root.pendingExitCode) ? -1 : root.pendingExitCode);
                root.flushOutput();
                root.replaying = false;
                // No reboot pending, so still predict what a run started now would do.
                if (!root.rebootRequired)
                    predictProc.running = true;
            }
        }
    }

    // Also removes the record, so it does not return the next time the page opens.
    Process {
        id: clearProc
        command: ["rm", "-f", root.logPath, root.exitPath, root.pidPath, root.seenPath, root.rebootMarkPath]
    }

    Process {
        id: rebootMarkProc
        command: ["touch", root.rebootMarkPath]
    }

    // A marker older than this boot is stale. It can only add a reboot, never
    // overrule a run's own verdict.
    Process {
        id: rebootMarkCheck
        command: ["bash", "-c",
            '[ -f "$0" ] || { echo none; exit 0; }; read up _ < /proc/uptime;'
            + ' if [ "$(stat -c %Y "$0")" -ge "$(( $(date +%s) - ${up%.*} ))" ]; then echo pending;'
            + ' else rm -f "$0"; echo stale; fi',
            root.rebootMarkPath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "pending" && !root.isRunning)
                    root.rebootVerdict = true;
            }
        }
    }

    // Marks the result as shown; the window lets the record go when it closes.
    Process {
        id: seenProc
        command: ["touch", root.seenPath]
    }

    // Copy takes the whole record, which the text item may no longer hold.
    Process {
        id: copyProc
        command: ["cat", root.logPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const whole = root.plainText(this.text).split("\n").filter(l => l.indexOf("@@MAINSTREAM-UPDATE") !== 0).join("\n");
                Quickshell.clipboardText = whole.trim().length > 0 ? whole : root.outputText;
            }
        }
    }

    Process {
        id: aurHelperCheck
        command: ["sh", "-c", "command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.aurHelperPresent = (exitCode === 0);
        }
    }

    ContentSection {
        icon: "lightbulb"
        title: Translation.tr("Tips & Info")

        ContentSubsection {
            title: Translation.tr("Before & after the update")

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "checklist"
                text: Translation.tr("Before you click Update, take a moment to test anything important \u2014 printers, audio, external drives, browsers, or any apps you rely on daily. After the update completes, test those same things again. Most updates go smoothly, but it's good to know right away if something needs attention.")
            }
        }

        ContentSubsection {
            title: Translation.tr("How updating works")

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "sync"
                text: root.snapshotsAvailable
                    ? Translation.tr("Before anything installs, a snapshot of your entire system is saved automatically — this is your safety net. If something ever goes wrong after updating, the Recovery page will walk you through rolling back to exactly how your system was before the update.")
                    : Translation.tr("Snapshots were never set up on this install, so updates are not snapshotted first. Test what matters to you after each update, and keep a backup of anything you cannot replace.")
            }
        }

    }

    ContentSection {
        icon: "system_update_alt"
        title: Translation.tr("System Update")

        headerExtra: [
            // Shown before a run starts when the pending list can be read. Red once
            // a finished run asks for it; then a second click restarts, so a stray one cannot.
            RippleButtonWithIcon {
                id: rebootChip
                visible: (root.rebootPredicted || root.rebootRequired) && !root.bootBroken
                readonly property bool canReboot: root.awaitingReboot
                property bool armed: false
                onCanRebootChanged: if (!canReboot) armed = false
                readonly property color colOnChip: root.rebootRequired ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onTertiaryContainer
                colBackground: root.rebootRequired ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3tertiaryContainer
                colBackgroundHover: rebootChip.canReboot ? Appearance.colors.colErrorContainerHover : rebootChip.colBackground
                colRipple: Appearance.colors.colErrorContainerActive
                pointingHandCursor: rebootChip.canReboot
                rippleEnabled: rebootChip.canReboot
                contentItem: RowLayout {
                    spacing: 5
                    MaterialSymbol {
                        text: "restart_alt"
                        iconSize: Appearance.font.pixelSize.larger
                        fill: 1
                        color: rebootChip.colOnChip
                    }
                    StyledText {
                        text: rebootChip.armed ? Translation.tr("Click again to reboot") : Translation.tr("Reboot required")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: rebootChip.colOnChip
                    }
                }
                onClicked: {
                    if (!rebootChip.canReboot)
                        return;
                    if (!rebootChip.armed) {
                        rebootChip.armed = true;
                        chipDisarmTimer.restart();
                        return;
                    }
                    rebootChip.armed = false;
                    root.requestReboot();
                }
                Timer {
                    id: chipDisarmTimer
                    interval: 4000
                    onTriggered: rebootChip.armed = false
                }
                StyledToolTip {
                    extraVisibleCondition: rebootChip.visible
                    text: rebootChip.canReboot
                        ? Translation.tr("Reboot to finish the update. Open apps are asked to close first.")
                        : Translation.tr("This update replaces parts of the running desktop.")
                }
            },
            RippleButtonWithIcon {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy")
                onClicked: copyProc.running = true
            }
        ]

        // A normal run finishes it: the root half runs after the dotfiles step
        // even with no new release. Hidden during a pending reboot, like the password field.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.systemHalfPending && !root.isRunning && !root.awaitingReboot
            materialIcon: "update"
            text: Translation.tr("Part of the last update did not finish. Enter your password and press Finish update to complete it.")

            Item {
                Layout.fillWidth: true
            }
            RippleButtonWithIcon {
                Layout.fillWidth: false
                buttonRadius: Appearance.rounding.small
                colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                materialIcon: "play_arrow"
                mainText: Translation.tr("Finish update")
                onClicked: root.finishPendingUpdate()
            }
        }

        // A reboot logs in again as well, so its reminder covers this one.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.reloginNeeded && !root.rebootRequired
            materialIcon: "logout"
            text: Translation.tr("Log out and back in to finish updating.")
        }

        StyledText {
            visible: root.outputTrimmed
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Showing the end of a long run. Copy takes all of it.")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 200
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer0
            clip: true

            Flickable {
                id: outputFlickable
                anchors {
                    fill: parent
                    margins: 10
                }
                contentHeight: outputDisplay.implicitHeight
                clip: true
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                StyledText {
                    id: outputDisplay
                    width: outputFlickable.width
                    text: root.outputText || Translation.tr("Enter your password and press \"Start update\" to begin.")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.outputText ? Appearance.colors.colOnLayer0 : Appearance.m3colors.m3outlineVariant
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                // Follows the end unless the reader scrolls up. Not tied to isRunning,
                // since the result lines land after the run ends.
                property bool followTail: true
                onContentYChanged: followTail = atYEnd
                onContentHeightChanged: {
                    if (followTail) {
                        contentY = Math.max(0, contentHeight - height);
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }

            Rectangle {
                visible: root.isRunning
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 3
                color: Appearance.m3colors.m3primary
                radius: 2

                SequentialAnimation on opacity {
                    running: root.isRunning
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.3; to: 1.0; duration: 800 }
                    NumberAnimation { from: 1.0; to: 0.3; duration: 800 }
                }
            }
        }

        // Clear is offered here too since this state hides the row below; otherwise
        // the only way out of a reboot verdict would be rebooting.
        RowLayout {
            visible: root.awaitingReboot
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Clear output")
                onClicked: root.clearOutput()
            }

            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reboot Now")
                onClicked: root.requestReboot()
            }
        }

        ConfigRow {
            visible: !root.awaitingReboot
            ConfigSwitch {
                id: advancedToggle
                buttonIcon: "tune"
                text: Translation.tr("Show advanced options")
                checked: false
            }
            Item { Layout.fillWidth: true }
        }

        ConfigRow {
            id: startRow
            visible: !root.awaitingReboot
            // Required for every run, with no polkit dialog fallback; it reaches
            // sudo -S over stdin and is cleared on submit.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.color: passwordField.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                border.width: 1

                TextInput {
                    id: passwordField
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 12
                    }
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectByMouse: true
                    enabled: !root.isRunning
                    onAccepted: {
                        if (!root.isRunning) root.startUpdate();
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passwordField.text.length === 0 && !passwordField.activeFocus
                        text: Translation.tr("Password")
                        color: Appearance.m3colors.m3outlineVariant
                        font: passwordField.font
                    }
                }
            }

            RippleButtonWithIcon {
                materialIcon: root.isRunning ? "stop" : "play_arrow"
                mainText: root.isRunning ? Translation.tr("Stop") : Translation.tr("Start update")
                enabled: root.isRunning || passwordField.text.length > 0
                onClicked: {
                    if (root.isRunning) root.stopUpdate();
                    else root.startUpdate();
                }
            }
            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Clear output")
                enabled: !root.isRunning
                onClicked: root.clearOutput()
            }
        }

        ContentSubsection {
            title: Translation.tr("Advanced")
            visible: advancedToggle.checked && !root.awaitingReboot

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Skip system packages")
                    checked: root.flagSkipSystem
                    onCheckedChanged: root.flagSkipSystem = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the pacman -Syu step.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "deployed_code"
                    text: Translation.tr("Skip Flatpak apps")
                    checked: root.flagSkipFlatpak
                    onCheckedChanged: root.flagSkipFlatpak = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "developer_mode"
                    text: Translation.tr("Skip extras (topgrade)")
                    checked: root.flagSkipExtras
                    onCheckedChanged: root.flagSkipExtras = checked
                    StyledToolTip {
                        text: Translation.tr("After the primary update, topgrade catches developer-tool ecosystems (cargo, pipx, npm, nix, JetBrains, VS Code, ...). Turn this on to skip that pass — useful if you don't use those tools or topgrade itself is failing for you.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Skip firmware updates")
                    checked: root.flagSkipFirmware
                    onCheckedChanged: root.flagSkipFirmware = checked
                    StyledToolTip {
                        text: Translation.tr("Only applies when developer extras runs. Firmware updates (fwupd) can prompt polkit and time out non-interactively.")
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "code"
                    text: Translation.tr("Skip dotfiles")
                    checked: root.flagSkipDotfiles
                    onCheckedChanged: root.flagSkipDotfiles = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "build"
                    text: Translation.tr("Auto-rebuild Quickshell")
                    checked: root.flagAutoRebuildQuickshell
                    onCheckedChanged: root.flagAutoRebuildQuickshell = checked
                    StyledToolTip {
                        text: Translation.tr("If a Qt update breaks Quickshell's ABI, rebuild the owning package automatically after all other update steps finish.")
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "science"
                    text: Translation.tr("Edge updates")
                    checked: root.flagEdge
                    onCheckedChanged: root.flagEdge = checked
                    StyledToolTip {
                        text: Translation.tr("Follow the newest pushed work instead of the newest release. Fixes reach you before they are released, and so does anything still being worked on. Turning it off puts you back on the latest release.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "notifications_active"
                    text: Translation.tr("Sound when done")
                    checked: Config.options.sounds.update
                    onCheckedChanged: Config.options.sounds.update = checked
                    StyledToolTip {
                        text: Translation.tr("Play a sound when the update finishes, so you can step away while it runs")
                    }
                }
            }
            ConfigRow {
                uniform: true
                visible: root.aurHelperPresent
                ConfigSwitch {
                    buttonIcon: "block"
                    text: Translation.tr("Disable AUR (yay/paru)")
                    checked: root.flagSkipAur
                    onCheckedChanged: root.flagSkipAur = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the AUR update step. On by default — Mainstream doesn't use the AUR and ships no AUR helper. Untick only if you installed yay or paru yourself and want AUR packages updated too.")
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: customArgsField.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.color: Appearance.m3colors.m3outlineVariant
                border.width: 1

                TextInput {
                    id: customArgsField
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    text: root.customArgs
                    onTextChanged: root.customArgs = text
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    clip: true

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: customArgsField.text.length === 0 && !customArgsField.activeFocus
                        text: Translation.tr("e.g. --only cargo node")
                        color: Appearance.m3colors.m3outlineVariant
                        font: customArgsField.font
                    }
                }
            }

            StyledText {
                text: Translation.tr("Extra command-line arguments passed to topgrade")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3outlineVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: previewText.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                StyledText {
                    id: previewText
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    text: root.commandPreview()
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }

            StyledText {
                text: Translation.tr("Steps that will run")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3outlineVariant
            }
        }
    }

}
