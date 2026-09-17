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

    // The update runs in a session of its own and writes here, so this page
    // is only ever a viewer of it: a window that reloads or closes no longer
    // takes the update with it, and whatever it printed, including how it
    // ended, is still there to show the next time the page opens.
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/mainstream"
    readonly property string logPath: stateDir + "/update.log"
    readonly property string exitPath: stateDir + "/update.exit"
    readonly property string pidPath: stateDir + "/update.pid"
    readonly property string launcher: Quickshell.shellPath("scripts/update/run-detached.sh")
    // The launcher ends the log with this once the helper has exited.
    readonly property string exitSentinel: "@@MAINSTREAM-UPDATE-EXIT "
    // The helper's two answers about the running desktop: what this run is
    // about to replace, judged before it installs anything, and what it did.
    readonly property string rebootPlanMarker: "@@MAINSTREAM-UPDATE-REBOOT-PLAN "
    readonly property string rebootMarker: "@@MAINSTREAM-UPDATE-REBOOT "
    readonly property string rebootCheck: Quickshell.shellPath("scripts/update/reboot-check.sh")
    // Two different questions, kept apart. What a run started now would do is
    // predicted from the pending list, or stated by a live run's own plan;
    // what the finished run did is its verdict. Ranking them against each
    // other let a replayed record silence the fresh prediction, which is the
    // answer the person standing at the page actually wants.
    property bool rebootPredicted: false
    property bool rebootRequired: false
    // A finished run that replaced parts of the desktop leaves one thing to
    // do; the page leads with that until the reboot happens.
    readonly property bool awaitingReboot: !root.isRunning && root.rebootRequired && root.outputText.length > 0
    // A record older than this boot belongs to a run whose reboot happened.
    property bool recordPredatesBoot: false
    // True while a finished record is being replayed rather than tailed. A
    // replayed plan says what some earlier run was about to do, which is not
    // a prediction about anything now.
    property bool replaying: false

    // Whether an AUR helper (yay or paru) is actually installed. The AUR
    // update switch is only shown when one is — Mainstream ships none by
    // default, so for most users the toggle would be a no-op control for a
    // step that can't run. Detected once on load by aurHelperCheck below.
    property bool aurHelperPresent: false

    // Step skip-flags. The helper runs pacman + yay + flatpak directly
    // as the primary path and (by default) topgrade afterwards for the
    // developer-tool extras. Each --noconfirm/--yes is hard-coded in
    // the helper since an unattended GUI update isn't useful if it
    // stops at prompts. Defaults match what most users want: everything
    // runs except firmware (firmware updates can prompt polkit and
    // time out non-interactively).
    property bool flagSkipSystem: false
    // AUR is disabled by default: Mainstream installs ship no AUR helper
    // and don't use the AUR for system packages (recent AUR supply-chain
    // concerns). Users who installed yay/paru themselves can untick this.
    property bool flagSkipAur: true
    property bool flagSkipFlatpak: false
    property bool flagSkipDotfiles: false
    property bool flagSkipExtras: false
    property bool flagSkipFirmware: true
    property bool flagAutoRebuildQuickshell: true
    property bool flagEdge: false
    property string customArgs: ""

    // Held in QML state from the moment the user submits the password
    // until the helper process exits. Cleared from the visible field
    // immediately on submit, and from this property on helper exit.
    property string pendingPassword: ""

    function buildHelperArgs() {
        // The privileged work runs in /usr/local/bin/mainstream-update-helper
        // which writes a temporary NOPASSWD sudoers rule, runs pacman +
        // yay/paru + flatpak directly, then optionally tops up with
        // topgrade for developer-tool ecosystems.
        let args = ["sudo", "-S", "/usr/local/bin/mainstream-update-helper"];
        if (flagSkipSystem)            args.push("--skip-system");
        if (flagSkipAur)               args.push("--skip-aur");
        if (flagSkipFlatpak)           args.push("--skip-flatpak");
        if (flagSkipDotfiles)          args.push("--skip-dotfiles");
        if (flagSkipExtras)            args.push("--skip-extras");
        if (flagSkipFirmware)          args.push("--skip-firmware");
        if (flagAutoRebuildQuickshell) args.push("--auto-rebuild-quickshell");
        if (flagEdge)                  args.push("--edge");
        if (customArgs.trim().length > 0) {
            // Custom args are passed through to topgrade when extras runs.
            // Split on whitespace so multi-token args reach topgrade properly.
            let extra = customArgs.trim().split(/\s+/);
            for (let i = 0; i < extra.length; i++) args.push(extra[i]);
        }
        return args;
    }

    function commandPreview() {
        // List the steps the helper will run in order, marking each as
        // ✓ (will run) or ✗ (skipped). Tells the user what's about to
        // happen far more usefully than a single command line.
        let lines = [];
        lines.push((flagSkipSystem      ? "✗" : "✓") + "  System packages    (pacman -Syu)");
        // Only list the AUR step when a helper is actually installed —
        // otherwise it's a guaranteed no-op the user shouldn't have to read.
        if (aurHelperPresent)
            lines.push((flagSkipAur     ? "✗" : "✓") + "  AUR                (yay -Sua)");
        lines.push((flagSkipFlatpak     ? "✗" : "✓") + "  Flatpak            (flatpak update --system + --user)");
        lines.push((flagSkipDotfiles    ? "✗" : "✓") + "  Mainstream dots    (updatems — on remote tag bump)");
        lines.push((flagSkipExtras      ? "✗" : "✓") + "  Developer extras   (topgrade — cargo, pipx, npm, nix, ...)");
        lines.push((flagAutoRebuildQuickshell ? "✓" : "✗") + "  Quickshell ABI check + rebuild if needed");
        return lines.join("\n");
    }

    function startUpdate() {
        if (isRunning) return;
        if (passwordField.text.length === 0) {
            outputText = Translation.tr("Enter your password to start the update.");
            return;
        }
        outputText = "";
        userStopped = false;
        rebootRequired = false;
        rebootPredicted = false;
        recordPredatesBoot = false;
        replaying = false;
        // Snapshot the password and clear the visible field so it
        // doesn't sit on screen for the rest of the run.
        pendingPassword = passwordField.text;
        passwordField.text = "";
        helperProc.command = ["bash", root.launcher, root.stateDir].concat(buildHelperArgs());
        helperProc.stdinEnabled = true;
        helperProc.running = true;
        isRunning = true;
    }

    function showStopFailed() {
        root.outputText += "\n" + Translation.tr("Nothing to stop: that update is no longer running.");
        root.isRunning = false;
        probeProc.running = true;
    }

    function stopUpdate() {
        if (!isRunning) return;
        // Not marked as stopped until the signal has actually been delivered.
        // The launcher forks, so the pid can be written a moment after the
        // page thinks the run began; a Stop pressed in that window used to
        // report a stopped run over a summary showing every step succeeded.
        stopProc.running = true;
    }

    // Everything that happens once the helper has exited, whether this page
    // watched it end or found the record afterwards.
    function finish(exitCode) {
        tailProc.running = false;
        root.isRunning = false;
        root.pendingPassword = "";
        // Strip trailing whitespace before appending the completion line, so
        // the auto-scrolled viewport lands on the Summary text rather than on
        // the blank lines the log ends with.
        root.outputText = root.outputText.replace(/\s+$/, "");
        if (root.userStopped) {
            root.outputText += "\n\n" + Translation.tr("Update stopped by user.");
            return;
        }
        if (exitCode < 0) {
            root.outputText += "\n\n" + Translation.tr("The update did not finish. The record above stops where it stopped.");
            return;
        }
        // sudo exits 1 on auth failure with a specific stderr line;
        // surface a clearer message than a bare "exit code 1".
        const authFailed = root.outputText.indexOf("incorrect password") !== -1
            || root.outputText.indexOf("Sorry, try again") !== -1;
        if (authFailed) {
            root.outputText += "\n\n" + Translation.tr("Authentication failed — wrong password. Try again.");
            return;
        }
        // Exit code 100 is the helper's "primary path ok but developer-tool
        // extras failed" signal, rendered the same as a full success: the
        // Summary block already marks the failed extras step, and users who
        // do not have those toolchains are not alarmed by a pass that erred
        // on tools they never touch. 101 is the dotfiles step failing, which
        // leaves the machine on its old release and must not read as success.
        if (exitCode === 101) {
            root.outputText += "\n\n" + Translation.tr("Update finished, but the Mainstream dotfiles did not update. See the Dotfiles line in the summary above.");
        } else if (exitCode === 0 || exitCode === 100) {
            root.outputText += "\n\n" + Translation.tr("Update completed successfully.");
        } else {
            root.outputText += "\n\n" + Translation.tr("Update finished with exit code %1.").arg(exitCode);
        }
        if (root.rebootRequired)
            root.outputText += "\n" + Translation.tr("Parts of the running desktop were replaced. Reboot to finish the update; until then some controls may not work.");
    }

    // "<0|1> [package ...]", from the check script or a marker line. The
    // package names stay in the record; the page only says yes or no.
    function readRebootAnswer(text, kind) {
        const yes = text.trim().split(/\s+/)[0] === "1";
        if (kind === "verdict") {
            // A record written before this boot describes a run whose reboot
            // has already happened.
            root.rebootRequired = yes && !root.recordPredatesBoot;
            // That run is over, so it predicts nothing about the next one.
            root.rebootPredicted = false;
        } else if (kind === "plan") {
            // Only a run happening now says anything about what is pending.
            if (!root.replaying)
                root.rebootPredicted = yes;
        } else if (!root.isRunning) {
            // The on-open prediction never overrides a run in flight, which
            // knows more than the pending list does.
            root.rebootPredicted = yes;
        }
    }

    // Asked when the page opens: of what is pending, does anything own a
    // file the running desktop has loaded. checkupdates answers from a
    // fresh copy of the repositories; without it the last sync stands in.
    Process {
        id: predictProc
        // Held until the probe has said what is on disk. Predicting costs a
        // repository sync, which is wasted while a run is in flight or a
        // finished record is about to answer the same question, and the page
        // is rebuilt on every visit because the settings pages share a loader.
        running: false
        command: ["bash", root.rebootCheck, "predict"]
        stdout: StdioCollector {
            onStreamFinished: root.readRebootAnswer(this.text.replace(/\n/g, " "), "predict")
        }
    }

    // A chunk of the record, usually one line. The sentinel is the helper's
    // exit and is never shown; it is looked for anywhere in the chunk rather
    // than at its start, because the parser can hand it over glued to the
    // blank line the launcher writes before it.
    function takeLine(line) {
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
        const at = line.indexOf(root.exitSentinel);
        if (at === -1) {
            root.outputText += line + "\n";
            return;
        }
        if (at > 0) root.outputText += line.substring(0, at);
        const code = parseInt(line.substring(at + root.exitSentinel.length), 10);
        root.finish(isNaN(code) ? -1 : code);
    }

    // Launches the update and nothing more. The helper itself runs under
    // run-detached.sh in its own session; this process is over within a
    // moment, once the password has been handed on.
    Process {
        id: helperProc
        onRunningChanged: {
            // When the process flips from idle to running, push the password
            // into stdin so `sudo -S` can authenticate, then close the stream:
            // the launcher waits for exactly that one line.
            if (running && root.pendingPassword.length > 0) {
                write(root.pendingPassword + "\n");
                root.pendingPassword = "";
                stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.pendingPassword = "";
            if (exitCode !== 0) {
                root.isRunning = false;
                root.outputText = Translation.tr("The update could not be started (launcher exit code %1).").arg(exitCode);
                return;
            }
            tailProc.running = true;
        }
    }

    // Follows the record from its first line, so a page that opens part way
    // through a run shows everything the helper has said so far.
    Process {
        id: tailProc
        command: ["tail", "-n", "+1", "-F", root.logPath]
        stdout: SplitParser { onRead: data => root.takeLine(data) }
    }

    // The helper is the child of the recorded session leader. It is signalled
    // rather than the leader, which would only defer the signal until the
    // helper finished on its own.
    Process {
        id: stopProc
        // The pid has to still be the session the launcher recorded: a pid
        // file left by a killed run names a number the kernel has since handed
        // to something else, and signalling its children hits a bystander.
        command: ["bash", "-c",
            'p=$(cat "$0" 2>/dev/null) || exit 1;'
            + ' case "$p" in ""|*[!0-9]*) exit 1 ;; esac;'
            + ' kill -0 "$p" 2>/dev/null || exit 1;'
            + ' [ "$(cut -d" " -f6 /proc/$p/stat 2>/dev/null)" = "$p" ] || exit 1;'
            + ' pkill -TERM -P "$p"',
            root.pidPath]
        onExited: (code) => {
            if (code === 0) {
                root.userStopped = true;
            } else {
                // Nothing was signalled, so the run is still going or has
                // already ended on its own. Say so rather than leaving a
                // button that looks like it worked.
                root.showStopFailed();
            }
        }
    }

    // Asked once when the page opens: is a run under way, and if not, is there
    // a record of the last one to show.
    Process {
        id: probeProc
        running: true
        command: ["bash", "-c",
            'if [ -f "$1" ]; then read up _ < /proc/uptime; s="";'
            + ' [ "$(stat -c %Y "$0")" -lt "$(( $(date +%s) - ${up%.*} ))" ] && s=" rebooted";'
            + ' echo "finished $(cat "$1")$s";'
            // A pid file outlives a run that was killed or lost to a power
            // cut, so it has to name a live process to mean anything. Without
            // this the page latches into a run that can never end, and both
            // buttons that could clear it are disabled while it believes one
            // is in progress.
            + ' elif [ -f "$2" ] && kill -0 "$(cat "$2")" 2>/dev/null; then echo running;'
            + ' elif [ -s "$0" ]; then rm -f "$2"; echo "finished -1";'
            + ' else rm -f "$2"; echo none; fi',
            root.logPath, root.exitPath, root.pidPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = this.text.trim();
                if (answer === "running") {
                    root.outputText = "";
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
                // Nothing on disk, so the pending list is the only thing that
                // can answer whether a run started now would end in a reboot.
                predictProc.running = true;
            }
        }
    }
    property int pendingExitCode: -1

    // The finished record, read whole; its sentinel line goes through the
    // same path a live one does.
    Process {
        id: recordProc
        command: ["cat", root.logPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.outputText = "";
                // What follows describes a run that has already ended.
                root.replaying = true;
                // The flag that says the user stopped it lives only here,
                // while the record lives on disk, so it is read back from the
                // exit code the run left behind.
                root.userStopped = (root.pendingExitCode === 143 || root.pendingExitCode === 130);
                const lines = this.text.split("\n");
                let sawSentinel = false;
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf(root.exitSentinel) === 0) sawSentinel = true;
                    root.takeLine(lines[i]);
                    if (sawSentinel) break;
                }
                if (!sawSentinel) root.finish(isNaN(root.pendingExitCode) ? -1 : root.pendingExitCode);
                root.replaying = false;
                // The record said the last run needs no reboot, or its reboot
                // already happened. Either way nothing has answered what a run
                // started now would do, so ask.
                if (!root.rebootRequired)
                    predictProc.running = true;
            }
        }
    }

    // Clearing the output also lets go of the record, so it does not come
    // back the next time the page opens.
    Process {
        id: clearProc
        command: ["rm", "-f", root.logPath, root.exitPath, root.pidPath]
    }

    // One-shot probe for an AUR helper. Exit 0 = yay or paru is on PATH.
    Process {
        id: aurHelperCheck
        command: ["sh", "-c", "command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.aurHelperPresent = (exitCode === 0);
        }
    }

    // ── Tips & Info section ──
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
                text: Translation.tr("Before anything installs, a snapshot of your entire system is saved automatically — this is your safety net. If something ever goes wrong after updating, the Recovery page will walk you through rolling back to exactly how your system was before the update.")
            }
        }

    }

    // ── Output section ──
    ContentSection {
        icon: "system_update_alt"
        title: Translation.tr("System Update")

        headerExtra: [
            // Shown as soon as it is known, which is before the update starts
            // whenever the pending list can be read, so nobody starts a run
            // without knowing it ends in a reboot.
            // Cut like the buttons beside it (height, corner, padding, icon
            // size) so the row reads as one set; only the tint says it is a
            // notice rather than something to press.
            Rectangle {
                id: rebootChip
                visible: root.rebootPredicted || root.rebootRequired
                // The tooltip takes a parent without a hover state as always
                // hovered, so the chip has to report its own.
                property bool hovered: chipHover.hovered
                implicitWidth: rebootChipRow.implicitWidth + 20
                implicitHeight: 35
                radius: Appearance.rounding.small
                color: root.rebootRequired ? Appearance.m3colors.m3errorContainer : Appearance.m3colors.m3tertiaryContainer
                RowLayout {
                    id: rebootChipRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        text: "restart_alt"
                        iconSize: Appearance.font.pixelSize.larger
                        fill: 1
                        color: root.rebootRequired ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onTertiaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Reboot required")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.rebootRequired ? Appearance.m3colors.m3onErrorContainer : Appearance.m3colors.m3onTertiaryContainer
                    }
                }
                HoverHandler {
                    id: chipHover
                }
                StyledToolTip {
                    extraVisibleCondition: rebootChip.visible
                    text: Translation.tr("This update replaces parts of the running desktop.")
                }
            },
            RippleButtonWithIcon {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy")
                onClicked: {
                    Quickshell.clipboardText = root.outputText;
                }
            }
        ]
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
                    text: root.outputText || Translation.tr("No output yet. Press \"Start update\" to begin.")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.outputText ? Appearance.colors.colOnLayer0 : Appearance.m3colors.m3outlineVariant
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                // Keep the newest line in view unless the reader has scrolled
                // up to look at something, and come back to following once
                // they return to the end. This is not tied to the run being
                // under way, because the result lines land after it ends.
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

            // Running indicator
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

        // Clear sits beside the reboot button rather than only in the row
        // below, which this state hides: a verdict the user disagrees with,
        // or a run they want to try again, would otherwise have no way out
        // except actually rebooting.
        RowLayout {
            visible: root.awaitingReboot
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8

            Item { Layout.fillWidth: true }

            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Clear output")
                onClicked: {
                    root.outputText = "";
                    clearProc.running = true;
                    root.rebootRequired = false;
                    root.rebootPredicted = false;
                    root.recordPredatesBoot = false;
                }
            }

            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reboot Now")
                // The shared path, so windows are snapshotted for the next
                // login and clients are asked to close first. A bare systemctl
                // call did neither, and had no fallback when it was refused.
                onClicked: Session.reboot()
            }
        }

        // Show-advanced toggle on its own row, left-aligned above the
        // password / Start row. ConfigSwitch is wider than a button so
        // pinning it alongside the password field made the row crowded.
        ConfigRow {
            visible: !root.awaitingReboot
            ConfigSwitch {
                id: advancedToggle
                buttonIcon: "tune"
                text: Translation.tr("Show advanced options")
                checked: false
            }
            // Fill the rest of the row with empty space so the toggle
            // doesn't stretch — ConfigRow uses RowLayout, which would
            // otherwise distribute width.
            Item { Layout.fillWidth: true }
        }

        ConfigRow {
            id: startRow
            visible: !root.awaitingReboot
            // Password field on the left edge of the row. Captured at
            // submit, then passed to the helper via sudo -S over stdin
            // (see helperProc above). Visible field is cleared as soon
            // as the helper starts so it doesn't sit on screen for the
            // duration of a 30-minute upgrade. Always present, always
            // required — no popup polkit dialog as a fallback.
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
                onClicked: {
                    root.outputText = "";
                    clearProc.running = true;
                    root.rebootRequired = false;
                    root.rebootPredicted = false;
                    root.recordPredatesBoot = false;
                }
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
            // AUR switch lives last, and only when a helper is installed —
            // Mainstream ships none, so for most users this control would
            // toggle a step that can't run.
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    visible: root.aurHelperPresent
                    buttonIcon: "block"
                    text: Translation.tr("Disable AUR (yay/paru)")
                    checked: root.flagSkipAur
                    onCheckedChanged: root.flagSkipAur = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the AUR update step. On by default — Mainstream doesn't use the AUR and ships no AUR helper. Untick only if you installed yay or paru yourself and want AUR packages updated too.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "science"
                    text: Translation.tr("Edge updates")
                    checked: root.flagEdge
                    onCheckedChanged: root.flagEdge = checked
                    StyledToolTip {
                        text: Translation.tr("Follow the newest pushed work instead of the newest release. Fixes reach you before they are released, and so does anything still being worked on. Turning it off puts you back on the latest release.")
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
                        text: Translation.tr("e.g. --only system flatpak")
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
                    // Force plain-text rendering so the ✓ / ✗ characters
                    // and explicit \n separators render literally — without
                    // this AutoText might try to interpret the content as
                    // rich text.
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
