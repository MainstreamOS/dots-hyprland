//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Gaming Mode Setup. Launched on the first Super+G (before the session switch) and
// re-openable with Ctrl+Super+G, both via `gaming-mode`:
//   GAMING_SETUP_MODE=firstrun|reconfig qs -p $HOME/.config/quickshell/ii/gaming-setup.qml
// Card 1 introduces the slow first launch and the Steam display tweaks; card 2 writes
// the three Gaming Mode preferences (return-to-desktop target, boot target, and when
// to open this menu) through the privileged `gaming-mode-switch set` path, where
// os-session-select and gaming-mode-arm-check read them back.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ApplicationWindow {
    id: root
    visible: true
    // Fixed, non-resizable (min == max); Hyprland floats it from the size hints.
    width: 780
    height: 700
    minimumWidth: 780
    minimumHeight: 700
    maximumWidth: 780
    maximumHeight: 700
    color: Appearance.m3colors.m3background
    title: Translation.tr("Gaming Mode Setup")

    // Exit the process when the window closes (button or Super+Q), so the
    // pgrep guard in gaming-mode's launch_setup doesn't see a lingering qs
    // process and refuse to reopen the menu on the next Super+G.
    onClosing: Qt.quit()

    // firstrun = the first ever Super+G (guided intro, ends on "Enter Gaming Mode").
    // reconfig = every later open (Ctrl+Super+G, or every Super+G under "Always open
    // setup"); it adds a "Start Gaming" button so the user can jump straight in.
    readonly property string mode: Quickshell.env("GAMING_SETUP_MODE") || "reconfig"
    readonly property bool firstRun: root.mode === "firstrun"

    property int currentCard: 0
    readonly property int cardCount: 2
    readonly property bool onLastCard: root.currentCard === root.cardCount - 1
    readonly property bool showStartGaming: !root.firstRun

    // Per-user first-run marker (mirrors gaming-mode's state_dir). Written as the menu
    // opens on first run, so Super+G only routes here once.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/mainstream-gaming"

    // Live preferences. Loaded from the system prefs file, written back through the
    // scoped sudoers rule. Defaults match today's behavior, so an untouched menu is a
    // no-op: returning lands on the desktop and every boot is OS-first.
    property string returnTarget: "desktop"   // "desktop" | "greeter"
    property string bootTarget: "desktop"     // "desktop" | "gaming"
    property string openSetup: "remember"     // "remember" | "always"

    function setReturnTarget(v) {
        if (v === root.returnTarget) return;
        root.returnTarget = v;
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/gaming-mode-switch", "set", "return-target", v]);
    }
    function setBootTarget(v) {
        if (v === root.bootTarget) return;
        root.bootTarget = v;
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/gaming-mode-switch", "set", "boot-target", v]);
    }
    function setOpenSetup(v) {
        if (v === root.openSetup) return;
        root.openSetup = v;
        Quickshell.execDetached(["sudo", "-n", "/usr/bin/gaming-mode-switch", "set", "open-setup", v]);
    }

    function markSetupDone() {
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.stateDir}' && touch '${root.stateDir}/setup-done'`]);
    }
    function enterGamingMode() {
        // Write the marker and switch via `gaming-mode --play`, which bypasses the
        // setup-menu gate -- otherwise, under "Always open setup", the relaunch would
        // re-open this menu instead of switching.
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${root.stateDir}' && touch '${root.stateDir}/setup-done' && setsid -f /usr/bin/gaming-mode --play`]);
        root.close();
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        prefsView.reload();
        if (root.firstRun)
            root.markSetupDone();
    }

    // Current prefs (best-effort; defaults stand if the file is absent on first run).
    FileView {
        id: prefsView
        path: "/etc/mainstream-gaming/prefs.conf"
        onLoaded: {
            const t = prefsView.text();
            let m = t.match(/^return-target=(\w+)/m);
            if (m)
                root.returnTarget = m[1];
            m = t.match(/^boot-target=(\w+)/m);
            if (m)
                root.bootTarget = m[1];
            m = t.match(/^open-setup=(\w+)/m);
            if (m)
                root.openSetup = m[1];
        }
        onLoadFailed: error => {} // no file yet -> defaults
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: "sports_esports"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Gaming Mode Setup")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            Item { Layout.fillWidth: true }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Reopen anytime with Ctrl+Super+G")
            }
        }

        // Card stage
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.normal

            StackLayout {
                anchors.fill: parent
                anchors.margins: 20
                currentIndex: root.currentCard

                // ── Card 0 — what to expect ───────────────────────────────
                ColumnLayout {
                    spacing: 16

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.larger
                        text: Translation.tr("Gaming Mode hands the whole screen to Steam Big Picture, like a console. Two things to know before your first launch:")
                    }

                    NoticeBox {
                        Layout.fillWidth: true
                        materialIcon: "hourglass_top"
                        text: Translation.tr("The first launch takes a while. Steam and the 32-bit graphics drivers install the first time, and the very first boot into Big Picture can sit on a black screen for a minute or two. That's normal — don't power off.")
                    }

                    NoticeBox {
                        Layout.fillWidth: true
                        materialIcon: "display_settings"
                        text: Translation.tr("For a sharp, correct picture, open Steam → Settings → Display and turn OFF \"HDR\" and turn OFF \"Automatically Set Resolution\" (the gamescope scaling).")
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── Card 1 — preferences ──────────────────────────────────
                ColumnLayout {
                    spacing: 18

                    ChoiceRow {
                        Layout.fillWidth: true
                        heading: Translation.tr("When you choose “Return to Desktop” in Steam")
                        subtext: Translation.tr("Big Picture's power menu can drop you straight back into Mainstream, or out to the login screen — pick the login screen on a shared or public computer.")
                        current: root.returnTarget
                        valueA: "desktop";  labelA: Translation.tr("Back to desktop");   subA: Translation.tr("Jump right into Mainstream")
                        valueB: "greeter";  labelB: Translation.tr("Login screen");      subB: Translation.tr("Require a password")
                        onChosen: v => root.setReturnTarget(v)
                    }

                    ChoiceRow {
                        Layout.fillWidth: true
                        heading: Translation.tr("When this computer starts up")
                        subtext: Translation.tr("Boot into the normal desktop first, or go straight into Steam Big Picture like a console. A gamescope crash always falls back to the login screen, never a loop.")
                        current: root.bootTarget
                        valueA: "desktop";  labelA: Translation.tr("Desktop first");   subA: Translation.tr("Recommended")
                        valueB: "gaming";   labelB: Translation.tr("Gaming Mode");     subB: Translation.tr("Straight into Big Picture")
                        onChosen: v => root.setBootTarget(v)
                    }

                    ChoiceRow {
                        Layout.fillWidth: true
                        heading: Translation.tr("When you press Super+G")
                        subtext: Translation.tr("Once you're set up, jump straight into gaming, or open this menu every time to review or change your setup first.")
                        current: root.openSetup
                        valueA: "remember";  labelA: Translation.tr("Remember my setup");  subA: Translation.tr("Go straight to gaming")
                        valueB: "always";    labelB: Translation.tr("Always open setup");  subB: Translation.tr("Show this menu each time")
                        onChosen: v => root.setOpenSetup(v)
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                opacity: root.currentCard > 0 ? 1 : 0
                enabled: root.currentCard > 0
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 110
                implicitHeight: 38
                onClicked: root.currentCard--
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Back")
                    color: Appearance.colors.colOnLayer0
                }
            }
            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 8
                Repeater {
                    model: root.cardCount
                    delegate: Rectangle {
                        required property int index
                        readonly property bool active: index === root.currentCard
                        implicitWidth: active ? 28 : 10
                        implicitHeight: 10
                        radius: 5
                        color: active ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
                        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 220 } }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 10

                // Next (advance) / Done (close) / Enter Gaming Mode (first-run switch).
                // Filled primary on the first run; a secondary button afterwards, beside
                // the filled "Start Gaming".
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: (root.onLastCard && root.firstRun) ? 190 : 110
                    implicitHeight: 38
                    colBackground: root.firstRun ? Appearance.m3colors.m3primary : Appearance.m3colors.m3surfaceContainerHigh
                    colBackgroundHover: root.firstRun ? Appearance.m3colors.m3primary : Appearance.colors.colLayer1Hover
                    onClicked: {
                        if (!root.onLastCard) {
                            root.currentCard++;
                        } else if (root.firstRun) {
                            root.enterGamingMode();
                        } else {
                            root.markSetupDone();
                            root.close();
                        }
                    }
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: !root.onLastCard
                            ? Translation.tr("Next")
                            : (root.firstRun ? Translation.tr("Enter Gaming Mode") : Translation.tr("Done"))
                        color: root.firstRun ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                    }
                }

                // Start Gaming — second open onward (Always open setup, or Ctrl+Super+G),
                // so the user can jump straight into Big Picture from any card.
                RippleButton {
                    visible: root.showStartGaming
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: 160
                    implicitHeight: 38
                    colBackground: Appearance.m3colors.m3primary
                    colBackgroundHover: Appearance.m3colors.m3primary
                    onClicked: root.enterGamingMode()
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Start Gaming")
                        color: Appearance.m3colors.m3onPrimary
                    }
                }
            }
        }
    }

    // A two-option selector: a heading, a supporting line, and two side-by-side
    // tiles. The selected tile carries the primary outline + check.
    component ChoiceRow: ColumnLayout {
        id: choiceRow
        property string heading
        property string subtext
        property string current
        property string valueA
        property string labelA
        property string subA
        property string valueB
        property string labelB
        property string subB
        signal chosen(string value)
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.large
            text: choiceRow.heading
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: choiceRow.subtext
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 12
            ChoicePill {
                Layout.fillWidth: true
                label: choiceRow.labelA
                sublabel: choiceRow.subA
                selected: choiceRow.current === choiceRow.valueA
                onClicked: choiceRow.chosen(choiceRow.valueA)
            }
            ChoicePill {
                Layout.fillWidth: true
                label: choiceRow.labelB
                sublabel: choiceRow.subB
                selected: choiceRow.current === choiceRow.valueB
                onClicked: choiceRow.chosen(choiceRow.valueB)
            }
        }
    }

    component ChoicePill: Rectangle {
        id: pill
        property string label
        property string sublabel
        property bool selected: false
        signal clicked
        implicitHeight: 70
        radius: Appearance.rounding.normal
        color: pill.selected
            ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.86)
            : Appearance.m3colors.m3surfaceContainerHigh
        border.width: pill.selected ? 2 : 1
        border.color: pill.selected ? Appearance.m3colors.m3primary : Appearance.colors.colOutlineVariant
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: pill.label
                    color: pill.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: pill.sublabel
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            MaterialSymbol {
                visible: pill.selected
                text: "check_circle"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
