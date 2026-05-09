import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

WindowDialog {
    id: root
    // 400 is a comfortable middle: wide enough to keep the time
    // pickers' ± buttons from overlapping the digits and the AM/PM
    // combos from truncating, narrow enough that the dialog still
    // visually reads as a sidebar accessory rather than a settings
    // page. Height covers the fully-expanded "Set hours" content
    // (Enable + Schedule + Turn on/Turn off + Intensity + Details/
    // Done buttons) without clipping.
    backgroundWidth: 400
    backgroundHeight: 400

    WindowDialogTitle {
        text: Translation.tr("Eye protection")
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Night Light")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    // Same controls + bindings as DisplayConfig.qml's Night Light
    // section — single source of truth (Hyprsunset service +
    // Config.options.light.night) means edits in either UI
    // propagate to the other. Widget widths are trimmed vs the
    // settings page so the row fits the narrower dialog without
    // the ± / AM-PM clipping seen in earlier attempts.
    ColumnLayout {
        Layout.topMargin: -16
        Layout.fillWidth: true
        spacing: 6

        // Single dropdown rolls the old "Enable now" toggle and the
        // schedule mode picker into one control. Mirrors DisplayConfig's
        // Night Light section so edits in either UI propagate.
        //   Disabled  → filter off, schedule off
        //   Automatic → schedule on, sunrise/sunset window
        //   Set hours → schedule on, user-defined from/to (read-only here)
        //   Enabled   → filter on, schedule off (always-on override)
        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "schedule"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Schedule night light")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                Layout.preferredWidth: 150
                Layout.fillWidth: false
                model: [
                    Translation.tr("Disabled"),
                    Translation.tr("Automatic"),
                    Translation.tr("Set hours"),
                    Translation.tr("Enabled"),
                ]
                // Same `mode`-driven design as DisplayConfig — see the
                // longer comment there for why we don't derive from
                // runtime fields.
                readonly property var modeIndex: ({
                    "disabled": 0, "automatic": 1, "manual": 2, "enabled": 3
                })
                readonly property var indexMode: [
                    "disabled", "automatic", "manual", "enabled"
                ]
                currentIndex: modeIndex[Config.options.light.night.mode] ?? 0
                onActivated: index => Hyprsunset.applyNightLightMode(indexMode[index])
            }
        }

        // Schedule details: revealed only when scheduleMode === "manual".
        // Read-only summary of the configured times — editing happens
        // in the full Settings → Display page (Details button below).
        // The from/to values stay stored as "HH:mm" 24-hour because
        // Hyprsunset's parsing depends on it; formatTime() converts
        // the stored value into a user-friendly "h:MM AM/PM" display
        // (handles 12-AM = 00:00 and 12-PM = 12:00 edge cases).
        ColumnLayout {
            id: nightSchedule
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.topMargin: visible ? 8 : 0
            spacing: 4
            visible: Config.options.light.night.mode === "manual"

            function formatTime(timeStr) {
                const parts = (timeStr ?? "").split(":");
                const h24 = parseInt(parts[0], 10);
                const m   = parseInt(parts[1], 10);
                if (isNaN(h24) || isNaN(m)) return "—";
                let hour12, period;
                if (h24 === 0)        { hour12 = 12;      period = "AM"; }
                else if (h24 < 12)    { hour12 = h24;     period = "AM"; }
                else if (h24 === 12)  { hour12 = 12;      period = "PM"; }
                else                  { hour12 = h24 - 12; period = "PM"; }
                return hour12 + ":" + String(m).padStart(2, "0") + " " + period;
            }

            // "Turn on" — read-only display.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Turn on")
                    color: Appearance.colors.colOnLayer1
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: nightSchedule.formatTime(Config.options.light.night.from)
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            // "Turn off" — read-only display.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Turn off")
                    color: Appearance.colors.colOnLayer1
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: nightSchedule.formatTime(Config.options.light.night.to)
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            // Tail spacer — preserves about half the vertical breathing
            // room the removed "Click Details to change these times."
            // hint used to reserve, so the Intensity slider below
            // doesn't sit flush against "Turn off".
            Item {
                Layout.fillWidth: true
                implicitHeight: 10
            }
        }

        // Intensity (colour temperature) — at the bottom, mirroring
        // DisplayConfig's ordering. WindowDialogSlider here keeps the
        // visual language consistent with other dialog controls.
        // Hyprsunset.onColorTemperatureChanged dispatches `hyprctl
        // hyprsunset temperature` live whenever the filter is active,
        // so dragging updates the screen tint immediately when on.
        WindowDialogSlider {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            text: Translation.tr("Intensity")
            from: 6500
            to: 1200
            stopIndicatorValues: [5000, to]
            value: Config.options.light.night.colorTemperature
            onMoved: Config.options.light.night.colorTemperature = value
            tooltipContent: `${Math.round(value)}K`
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        // Opens the full Settings → Display page (Night Light section
        // at the bottom). Same launch pattern as BluetoothDialog /
        // WifiDialog: spawn a new Quickshell process pointed at the
        // shared settings.qml with QS_SETTINGS_PAGE preselected to
        // Display's index (7). Closes the right sidebar afterward so
        // the settings window isn't hidden behind it.
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                const settingsPath = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/settings.qml";
                Quickshell.execDetached(["sh", "-c", "QS_SETTINGS_PAGE=7 quickshell -p '" + settingsPath + "'"]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
