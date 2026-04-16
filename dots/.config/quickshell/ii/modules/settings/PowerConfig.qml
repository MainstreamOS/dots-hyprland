import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    property string powerProfile: "balanced"
    property string powerButtonAction: "suspend"
    property bool screenBlankEnabled: true
    property int screenBlankSecs: 300
    property bool autoSuspendEnabled: true
    property int autoSuspendSecs: 900
    property bool _readersFinished: false

    readonly property string hyprIdleConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hypridle.conf`

    Component.onCompleted: {
        powerProfileReader.running = true
        logindReader.running = true
        screenBlankReader.running = true
        autoSuspendReader.running = true
    }

    // ── Readers ──────────────────────────────────────────────────────────────

    Process {
        id: powerProfileReader
        command: ["powerprofilesctl", "get"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => powerProfileReader.buf += data }
        onExited: (code) => {
            if (code === 0) {
                const v = powerProfileReader.buf.trim()
                if (["performance", "balanced", "power-saver"].includes(v))
                    powerProfile = v
            }
        }
    }

    // Read HandlePowerKey from logind drop-in
    Process {
        id: logindReader
        command: ["bash", "-c",
            "awk -F= '/HandlePowerKey/{gsub(/[[:space:]]/,\"\",$2); print $2}' /etc/systemd/logind.conf.d/10-power-key.conf 2>/dev/null; true"
        ]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => logindReader.buf += data }
        onExited: (code) => {
            const v = logindReader.buf.trim()
            if (v.length > 0) powerButtonAction = v
        }
    }

    // Read DPMS timeout from hypridle.conf (targets the listener containing dpms off)
    Process {
        id: screenBlankReader
        command: ["awk",
            "/timeout[[:space:]]*=/{for(i=1;i<=NF;i++)if($i~/^[0-9]+$/){t=$i;break}} /on-timeout.*dpms off/{print t; exit}",
            hyprIdleConf
        ]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => screenBlankReader.buf += data }
        onExited: (code) => {
            const v = parseInt(screenBlankReader.buf.trim())
            if (!isNaN(v)) {
                if (v === 0 || v >= 599940) {
                    screenBlankEnabled = false
                } else {
                    screenBlankEnabled = true
                    screenBlankSecs = v
                }
            }
            if (!autoSuspendReader.running) _readersFinished = true
        }
    }

    // Read suspend timeout from hypridle.conf (targets the listener containing suspend)
    Process {
        id: autoSuspendReader
        command: ["awk",
            "/timeout[[:space:]]*=/{for(i=1;i<=NF;i++)if($i~/^[0-9]+$/){t=$i;break}} /on-timeout.*suspend/{print t; exit}",
            hyprIdleConf
        ]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => autoSuspendReader.buf += data }
        onExited: (code) => {
            const v = parseInt(autoSuspendReader.buf.trim())
            if (!isNaN(v)) {
                if (v === 0 || v >= 599940) {
                    autoSuspendEnabled = false
                } else {
                    autoSuspendEnabled = true
                    autoSuspendSecs = v
                }
            }
            if (!screenBlankReader.running) _readersFinished = true
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Write HandlePowerKey to logind drop-in and reload via polkit helper
    Process {
        id: powerButtonWriter
        property string pendingAction: ""
        command: ["pkexec", "power-key-helper", pendingAction]
        onExited: (code) => {
            if (code !== 0) console.warn("power-key-helper exited with code", code)
        }
    }
    function applyPowerButton(action) {
        const allowed = ["suspend", "hibernate", "poweroff", "ignore"]
        if (!allowed.includes(action)) return
        powerButtonWriter.pendingAction = action
        powerButtonWriter.running = true
    }

    // Update timeout for a specific listener block in hypridle.conf, identified
    // by a keyword in its on-timeout line (e.g. "dpms off" or "suspend").
    // Uses awk to find the matching block and only change the timeout there.
    function applyHyprIdleTimeout(keyword, enabled, secs) {
        const timeout = enabled ? secs : 599940 // ~7 days; hypridle treats 0 as "immediate"
        // mawk-compatible: no \s, no [[:space:]] in //, use $0 ~ for regex tests
        const awkProg = [
            "BEGIN{il=0; m=0}",
            "/^listener/ && /\\{/{il=1; m=0; block=$0; next}",
            "il{block=block\"\\n\"$0; if($0 ~ /on-timeout.*" + keyword + "/){m=1}; if($0 ~ /\\}/){if(m){sub(/timeout[ \\t]*=[ \\t]*[0-9]+/,\"timeout = " + timeout + "\",block)}; print block; il=0; next}}",
            "il==0{print}",
        ].join("; ")
        Quickshell.execDetached(["bash", "-c",
            "awk '" + awkProg + "' '" + hyprIdleConf + "' > '" + hyprIdleConf + ".tmp' && mv '" + hyprIdleConf + ".tmp' '" + hyprIdleConf + "' && pkill -x hypridle; hypridle &"
        ])
    }

    function applyScreenBlank(enabled, secs) {
        applyHyprIdleTimeout("dpms off", enabled, secs)
    }

    function applyAutoSuspend(enabled, secs) {
        applyHyprIdleTimeout("suspend", enabled, secs)
    }

    // ── Power Mode ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "bolt"
        title: Translation.tr("Power Mode")

        ConfigRow {
            ConfigSelectionArray {
                currentValue: powerProfile
                onSelected: newValue => {
                    powerProfile = newValue
                    Quickshell.execDetached(["powerprofilesctl", "set", newValue])
                }
                options: [
                    { displayName: Translation.tr("Performance"), icon: "speed",        value: "performance" },
                    { displayName: Translation.tr("Balanced"),    icon: "balance",       value: "balanced"    },
                    { displayName: Translation.tr("Power Saver"), icon: "battery_saver", value: "power-saver" }
                ]
            }
        }
    }

    // ── General ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "settings_power"
        title: Translation.tr("General")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 4
                ContentSubsectionLabel { text: Translation.tr("Power Button Behavior") }
                StyledComboBox {
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Suspend"),    value: "suspend"   },
                        { displayName: Translation.tr("Hibernate"),  value: "hibernate" },
                        { displayName: Translation.tr("Shut Down"),  value: "poweroff"  },
                        { displayName: Translation.tr("Do Nothing"), value: "ignore"    }
                    ]
                    currentIndex: {
                        const idx = model.findIndex(item => item.value === powerButtonAction)
                        return idx !== -1 ? idx : 0
                    }
                    onActivated: index => {
                        powerButtonAction = model[index].value
                        applyPowerButton(model[index].value)
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // ── Power Saving ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "battery_charging_full"
        title: Translation.tr("Power Saving")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            uniformCellSizes: true

            // Screen Blank column
            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "monitor"
                    text: Translation.tr("Automatic Screen Blank")
                    checked: screenBlankEnabled
                    onCheckedChanged: {
                        screenBlankEnabled = checked
                        if (_readersFinished) applyScreenBlank(checked, screenBlankSecs)
                    }
                }
                ConfigRow {
                    enabled: screenBlankEnabled
                    StyledText {
                        text: Translation.tr("Delay")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: screenBlankEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        Layout.fillWidth: true
                    }
                    StyledComboBox {
                        enabled: screenBlankEnabled
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("1 minute"),   seconds: 60   },
                            { displayName: Translation.tr("2 minutes"),  seconds: 120  },
                            { displayName: Translation.tr("5 minutes"),  seconds: 300  },
                            { displayName: Translation.tr("10 minutes"), seconds: 600  },
                            { displayName: Translation.tr("15 minutes"), seconds: 900  },
                            { displayName: Translation.tr("30 minutes"), seconds: 1800 }
                        ]
                        currentIndex: {
                            const idx = model.findIndex(item => item.seconds === screenBlankSecs)
                            return idx !== -1 ? idx : 2
                        }
                        onActivated: index => {
                            screenBlankSecs = model[index].seconds
                            applyScreenBlank(screenBlankEnabled, model[index].seconds)
                        }
                    }
                }
            }

            // Auto Suspend column
            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "bedtime"
                    text: Translation.tr("Automatic Suspend")
                    checked: autoSuspendEnabled
                    onCheckedChanged: {
                        autoSuspendEnabled = checked
                        if (_readersFinished) applyAutoSuspend(checked, autoSuspendSecs)
                    }
                }
                ConfigRow {
                    enabled: autoSuspendEnabled
                    StyledText {
                        text: Translation.tr("Delay")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: autoSuspendEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        Layout.fillWidth: true
                    }
                    StyledComboBox {
                        enabled: autoSuspendEnabled
                        textRole: "displayName"
                        model: [
                            { displayName: Translation.tr("5 minutes"),  seconds: 300  },
                            { displayName: Translation.tr("10 minutes"), seconds: 600  },
                            { displayName: Translation.tr("15 minutes"), seconds: 900  },
                            { displayName: Translation.tr("30 minutes"), seconds: 1800 },
                            { displayName: Translation.tr("1 hour"),     seconds: 3600 }
                        ]
                        currentIndex: {
                            const idx = model.findIndex(item => item.seconds === autoSuspendSecs)
                            return idx !== -1 ? idx : 2
                        }
                        onActivated: index => {
                            autoSuspendSecs = model[index].seconds
                            applyAutoSuspend(autoSuspendEnabled, model[index].seconds)
                        }
                    }
                }
            }
        }
    }

    // ── Battery ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Battery")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value
                }
            }
        }
        ConfigRow {
            uniform: false
            ConfigSwitch {
                buttonIcon: "pause"
                text: Translation.tr("Automatic suspend")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked
                }
                StyledToolTip {
                    text: Translation.tr("Automatically suspends the system when battery is low")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.suspend = value
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value
                }
            }
        }
    }

    // ── Sounds ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Sounds")

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                spacing: 4
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "battery_android_full"
                    text: Translation.tr("Battery")
                    checked: Config.options.sounds.battery
                    onCheckedChanged: {
                        Config.options.sounds.battery = checked
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
