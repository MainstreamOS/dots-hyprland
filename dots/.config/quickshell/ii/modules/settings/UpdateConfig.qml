import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property string outputText: ""
    property bool isRunning: false
    property bool userStopped: false

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
        lines.push((flagSkipAur         ? "✗" : "✓") + "  AUR                (yay -Sua)");
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
        // Snapshot the password and clear the visible field so it
        // doesn't sit on screen for the rest of the run.
        pendingPassword = passwordField.text;
        passwordField.text = "";
        helperProc.command = buildHelperArgs();
        helperProc.stdinEnabled = true;
        helperProc.running = true;
        isRunning = true;
    }

    function stopUpdate() {
        if (!isRunning) return;
        userStopped = true;
        if (helperProc.running) helperProc.signal(15);
    }

    // Single privileged helper process. The helper at
    // /usr/local/bin/mainstream-update-helper handles topgrade, the
    // drop-to-user AUR step, the Quickshell ABI rebuild, and the
    // pacman db.lck cleanup on stop — all inside one sudo invocation
    // so the user only authenticates once.
    Process {
        id: helperProc
        stdout: SplitParser {
            onRead: data => { root.outputText += data + "\n"; }
        }
        stderr: SplitParser {
            onRead: data => { root.outputText += data + "\n"; }
        }
        onRunningChanged: {
            // When the process flips from idle → running, push the
            // password into stdin so `sudo -S` can authenticate, then
            // immediately close the stdin stream — the helper doesn't
            // read further input, and leaving the pipe open holds the
            // process group open in some edge cases. This is the same
            // pattern disk-mounter.qml uses.
            if (running && root.pendingPassword.length > 0) {
                write(root.pendingPassword + "\n");
                root.pendingPassword = "";
                stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isRunning = false;
            // Drop any straggler password from QML state, even on
            // error paths where pendingPassword may still be set.
            root.pendingPassword = "";
            // Strip trailing whitespace before appending the completion
            // line. SplitParser tends to emit an empty trailing chunk
            // when the stream ends in a newline (`printf "...\n"`), and
            // the stdout handler re-adds another \n to that empty —
            // result is 1-2 extra blank lines after the helper's
            // Summary block. Normalising here keeps the auto-scrolled
            // viewport landing on the actual Summary text, not on
            // dead whitespace.
            root.outputText = root.outputText.replace(/\s+$/, "");
            if (root.userStopped) {
                root.outputText += "\n\n" + Translation.tr("Update stopped by user.");
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
            // Exit code 100 is the helper's "primary path ok but
            // developer-tool extras failed" signal. We deliberately
            // render it the same as a full success: the Summary block
            // above already marks the failed extras step as
            // "FAILED (rc=N)", so power users who use those tools
            // (cargo, pipx, npm, nix, …) see the failure when they
            // scroll through the log. Regular users — who likely
            // don't have those toolchains installed at all — aren't
            // alarmed by an extras pass that errored on tools they
            // never touch.
            if (exitCode === 0 || exitCode === 100) {
                root.outputText += "\n\n" + Translation.tr("Update completed successfully.");
            } else {
                root.outputText += "\n\n" + Translation.tr("Update finished with exit code %1.").arg(exitCode);
            }
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

                onContentHeightChanged: {
                    if (root.isRunning) {
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

        // Show-advanced toggle on its own row, left-aligned above the
        // password / Start row. ConfigSwitch is wider than a button so
        // pinning it alongside the password field made the row crowded.
        ConfigRow {
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
                onClicked: root.outputText = ""
            }
        }

        ContentSubsection {
            title: Translation.tr("Advanced")
            visible: advancedToggle.checked

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
                    buttonIcon: "block"
                    text: Translation.tr("Disable AUR (yay/paru)")
                    checked: root.flagSkipAur
                    onCheckedChanged: root.flagSkipAur = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the AUR update step. On by default — Mainstream doesn't use the AUR and ships no AUR helper. Untick only if you installed yay or paru yourself and want AUR packages updated too.")
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "deployed_code"
                    text: Translation.tr("Skip Flatpak apps")
                    checked: root.flagSkipFlatpak
                    onCheckedChanged: root.flagSkipFlatpak = checked
                }
                ConfigSwitch {
                    buttonIcon: "developer_mode"
                    text: Translation.tr("Skip extras (topgrade)")
                    checked: root.flagSkipExtras
                    onCheckedChanged: root.flagSkipExtras = checked
                    StyledToolTip {
                        text: Translation.tr("After the primary update, topgrade catches developer-tool ecosystems (cargo, pipx, npm, nix, JetBrains, VS Code, ...). Turn this on to skip that pass — useful if you don't use those tools or topgrade itself is failing for you.")
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Skip firmware updates")
                    checked: root.flagSkipFirmware
                    onCheckedChanged: root.flagSkipFirmware = checked
                    StyledToolTip {
                        text: Translation.tr("Only applies when developer extras runs. Firmware updates (fwupd) can prompt polkit and time out non-interactively.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "code"
                    text: Translation.tr("Skip dotfiles")
                    checked: root.flagSkipDotfiles
                    onCheckedChanged: root.flagSkipDotfiles = checked
                    StyledToolTip {
                        text: Translation.tr("Skip the Mainstream dotfiles refresh step (updatems). Dotfiles update only when a new release tag is published upstream; turn this on to manage them manually.")
                    }
                }
            }
            ConfigRow {
                uniform: true
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
