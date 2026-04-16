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

    // Topgrade flags
    property bool flagYes: true
    property bool flagDisableSystem: false
    property bool flagDisableFlatpak: false
    property bool flagDisableFirmware: true
    property string customArgs: ""

    function buildCommand() {
        let args = ["bash", "-c", buildTopgradeCommand()];
        return args;
    }

    function buildTopgradeCommand() {
        let parts = ["topgrade", "--cleanup"];
        if (flagYes) parts.push("--yes");
        if (flagDisableSystem) { parts.push("--disable"); parts.push("system"); }
        if (flagDisableFlatpak) { parts.push("--disable"); parts.push("flatpak"); }
        if (flagDisableFirmware) { parts.push("--disable"); parts.push("firmware"); }
        if (customArgs.trim().length > 0) {
            parts.push(customArgs.trim());
        }
        // Acquire sudo upfront via askpass, then run topgrade
        return `sudo -A -v && ${parts.join(" ")}`;
    }

    function commandPreview() {
        let parts = ["topgrade", "--cleanup"];
        if (flagYes) parts.push("--yes");
        if (flagDisableSystem) { parts.push("--disable"); parts.push("system"); }
        if (flagDisableFlatpak) { parts.push("--disable"); parts.push("flatpak"); }
        if (flagDisableFirmware) { parts.push("--disable"); parts.push("firmware"); }
        if (customArgs.trim().length > 0) {
            parts.push(customArgs.trim());
        }
        return parts.join(" ");
    }

    function startUpdate() {
        if (isRunning) return;
        outputText = "";
        userStopped = false;
        topgradeProc.command = buildCommand();
        topgradeProc.running = true;
        isRunning = true;
    }

    function stopUpdate() {
        if (!isRunning) return;
        userStopped = true;
        topgradeProc.signal(15); // SIGTERM
    }

    Process {
        id: topgradeProc
        environment: ({
            "SUDO_ASKPASS": Directories.scriptPath.toString().replace("file://", "") + "/sudo-askpass.sh"
        })
        stdout: SplitParser {
            onRead: data => {
                root.outputText += data + "\n";
            }
        }
        stderr: SplitParser {
            onRead: data => {
                root.outputText += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isRunning = false;
            if (exitCode === 0) {
                root.outputText += "\n" + Translation.tr("Update completed successfully.");
            } else if (root.userStopped) {
                root.outputText += "\n" + Translation.tr("Update stopped by user. Cleaning up…");
                lockCleanupProc.running = true;
            } else {
                root.outputText += "\n" + Translation.tr("Update finished with exit code %1.").arg(exitCode);
            }
        }
    }

    Process {
        id: lockCleanupProc
        command: ["sudo", "-A", "rm", "-f", "/var/lib/pacman/db.lck"]
        environment: ({
            "SUDO_ASKPASS": Directories.scriptPath.toString().replace("file://", "") + "/sudo-askpass.sh"
        })
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.outputText += "\n" + Translation.tr("Pacman lock file removed.");
            } else {
                root.outputText += "\n" + Translation.tr("Could not remove pacman lock file. You may need to run: sudo rm /var/lib/pacman/db.lck");
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
            implicitHeight: 250
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

        ConfigRow {
            ConfigSwitch {
                id: advancedToggle
                buttonIcon: "tune"
                text: Translation.tr("Show advanced options")
                checked: false
            }
            RippleButtonWithIcon {
                materialIcon: root.isRunning ? "stop" : "play_arrow"
                mainText: root.isRunning ? Translation.tr("Stop") : Translation.tr("Start update")
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
                    buttonIcon: "check_circle"
                    text: Translation.tr("Auto-confirm prompts")
                    checked: root.flagYes
                    onCheckedChanged: root.flagYes = checked
                    StyledToolTip {
                        text: Translation.tr("Automatically say yes to prompts during update")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Skip system packages")
                    checked: root.flagDisableSystem
                    onCheckedChanged: root.flagDisableSystem = checked
                    StyledToolTip {
                        text: Translation.tr("Skip system package manager (pacman, apt, etc.)")
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "deployed_code"
                    text: Translation.tr("Skip Flatpak apps")
                    checked: root.flagDisableFlatpak
                    onCheckedChanged: root.flagDisableFlatpak = checked
                }
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("Skip firmware updates")
                    checked: root.flagDisableFirmware
                    onCheckedChanged: root.flagDisableFirmware = checked
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
                }
            }

            StyledText {
                text: Translation.tr("Command preview")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3outlineVariant
            }
        }
    }

}
