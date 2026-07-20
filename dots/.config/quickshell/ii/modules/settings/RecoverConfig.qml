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
    property bool restoreSuccess: false

    // Held in QML state from the moment the user submits the password
    // until the restore process exits. Cleared from the visible field
    // immediately on submit, and from this property in onRunningChanged
    // / onExited so it doesn't linger longer than needed.
    property string pendingPassword: ""

    function startRestore() {
        if (isRunning) return;
        if (passwordField.text.length === 0) {
            outputText = Translation.tr("Enter your password to start the restore.");
            return;
        }
        outputText = "";
        restoreSuccess = false;
        pendingPassword = passwordField.text;
        passwordField.text = "";
        restoreProc.stdinEnabled = true;
        restoreProc.running = true;
        isRunning = true;
    }

    Process {
        id: rebootProc
        command: ["systemctl", "reboot"]
    }

    Process {
        id: restoreProc
        // sudo -S reads the password from stdin (written in
        // onRunningChanged below). Drops the SUDO_ASKPASS dance —
        // matches the Update panel's authentication pattern.
        command: ["sudo", "-S", "/usr/bin/limine-restore-auto"]
        stdout: SplitParser {
            onRead: data => { root.outputText += data + "\n"; }
        }
        stderr: SplitParser {
            onRead: data => { root.outputText += data + "\n"; }
        }
        onRunningChanged: {
            // When the process flips idle → running, push the password
            // into stdin and close the pipe so sudo's read returns
            // immediately. Same pattern as disk-mounter.qml.
            if (running && root.pendingPassword.length > 0) {
                write(root.pendingPassword + "\n");
                root.pendingPassword = "";
                stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.isRunning = false;
            // Defensive: clear any straggler password from QML state.
            root.pendingPassword = "";
            // sudo writes a recognisable line to stderr on auth failure;
            // surface a clearer message than a bare "exit code 1".
            const authFailed = root.outputText.indexOf("incorrect password") !== -1
                || root.outputText.indexOf("Sorry, try again") !== -1;
            if (authFailed) {
                root.outputText += "\n" + Translation.tr("Authentication failed — wrong password. Try again.");
                return;
            }
            if (exitCode === 0) {
                root.restoreSuccess = true;
            } else {
                root.outputText += "\n" + Translation.tr("Restore finished with exit code %1.").arg(exitCode);
            }
        }
    }

    ContentSection {
        icon: "healing"
        title: Translation.tr("If something breaks")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "restore"
            text: Translation.tr("Don't panic. Your pre-update snapshot is waiting for you. Simply reboot your computer to recover.")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: recoveryColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: recoveryColumn
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 6

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "menu_book"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        text: Translation.tr("Recovering from your boot screen (Limine)")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    wrapMode: Text.Wrap
                    textFormat: Text.RichText
                    text: Translation.tr(`1. Use the <b>arrow keys</b> to find <b>"Snapshots"</b> in the boot menu<br>2. Press <b>Enter</b> to expand the list of available snapshots<br>3. Choose the snapshot taken <b>before the update</b><br>4. Press <b>Enter</b> to boot into that snapshot<br>5. Test your system — if issues persist, try an earlier snapshot<br>6. When satisfied, return here and run <b>Restore Snapshot</b> to make it permanent<br>7. Reboot once more and use the normal <b>"linux"</b> boot entry`)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    lineHeight: 1.4
                }
            }
        }
    }

    ContentSection {
        icon: "system_update_alt"
        title: Translation.tr("System Restore")

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
                    text: root.outputText || Translation.tr("No output yet. Press \"Restore Snapshot\" to begin.")
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
            // Inline password field. Submitted via sudo -S stdin in
            // startRestore() \u2014 same UX as the Update panel. Visible
            // field clears the moment the user clicks Restore so the
            // password doesn't sit on screen during the restore.
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
                    passwordCharacter: "\u2022"
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectByMouse: true
                    enabled: !root.isRunning
                    onAccepted: {
                        if (!root.isRunning) root.startRestore();
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
                materialIcon: root.isRunning ? "hourglass_top" : "play_arrow"
                mainText: root.isRunning ? Translation.tr("Restoring\u2026") : Translation.tr("Restore Snapshot")
                enabled: !root.isRunning && passwordField.text.length > 0
                onClicked: root.startRestore()
            }
            RippleButtonWithIcon {
                materialIcon: "delete"
                mainText: Translation.tr("Clear output")
                enabled: !root.isRunning
                onClicked: root.outputText = ""
            }
        }
    }

    // Success overlay — parented to Overlay.overlay (the QtQuick.Controls
    // window-level layer) so it sits on top of all content regardless of how
    // ContentPage lays out its children internally.
    // Fills the full window and uses the window background color from settings.qml.
    Rectangle {
        parent: Overlay.overlay
        visible: root.restoreSuccess
        anchors.fill: parent
        color: Appearance.m3colors.m3background

        ColumnLayout {
            id: successCol
            anchors.centerIn: parent
            width: 320
            spacing: 16

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "check_circle"
                iconSize: 48
                color: Appearance.m3colors.m3primary
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("Your snapshot has been successfully restored!")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignHCenter
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reboot Now")
                onClicked: rebootProc.running = true
            }
        }
    }
}
