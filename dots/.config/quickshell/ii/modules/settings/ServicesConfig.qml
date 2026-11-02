import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.services

ContentPage {
    forceWidth: true

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    // ── Language ──────────────────────────────────────────────────────────────
    ContentSection {
        icon: "language"
        title: Translation.tr("Language")

        ContentSubsection {
            title: Translation.tr("Interface Language")
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")

            StyledComboBox {
                id: languageSelector
                buttonIcon: "language"
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Auto (System)"),
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: lang,
                            value: lang
                        };
                    })]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Generate translation with Gemini")
            tooltip: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")

            ConfigRow {
                MaterialTextArea {
                    id: localeInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                    text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                }
                RippleButtonWithIcon {
                    id: generateTranslationBtn
                    Layout.fillHeight: true
                    nerdIcon: ""
                    enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                    mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                    onClicked: {
                        translationProc.locale = localeInput.text.trim();
                        translationProc.running = false;
                        translationProc.running = true;
                    }
                }
            }
        }
    }

    ContentSection {
        id: dateTime
        icon: "schedule"
        title: Translation.tr("Date & time")

        property bool loaded: false
        property string timezone: ""
        property bool automatic: false
        property bool canAutomatic: false
        property bool inSync: false
        property var zones: []
        property string problem: ""
        property date now: new Date()

        // timedatectl asks systemd, which asks for an administrator through the
        // polkit agent, so no helper of our own is involved.
        function change(args) {
            dateTime.problem = "";
            timeChanger.command = ["timedatectl"].concat(args);
            timeChanger.running = true;
        }
        function zoneLabel(zone) {
            const parts = zone.split("/");
            const city = parts[parts.length - 1].replace(/_/g, " ");
            return parts.length > 1 ? `${city} (${parts.slice(0, -1).join(" / ").replace(/_/g, " ")})` : city;
        }

        Component.onCompleted: {
            timeState.running = true;
            zoneList.running = true;
        }

        Timer {
            interval: 1000
            running: dateTime.visible
            repeat: true
            onTriggered: dateTime.now = new Date()
        }

        Process {
            id: timeState
            command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP", "-p", "CanNTP", "-p", "NTPSynchronized"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const values = {};
                    for (const line of text.split("\n")) {
                        const at = line.indexOf("=");
                        if (at > 0) values[line.slice(0, at)] = line.slice(at + 1);
                    }
                    dateTime.timezone = values.Timezone ?? "";
                    dateTime.automatic = values.NTP === "yes";
                    dateTime.canAutomatic = values.CanNTP === "yes";
                    dateTime.inSync = values.NTPSynchronized === "yes";
                    dateTime.loaded = true;
                }
            }
        }

        Process {
            id: zoneList
            command: ["timedatectl", "list-timezones"]
            stdout: StdioCollector {
                onStreamFinished: dateTime.zones = text.split("\n").filter(zone => zone.length > 0)
                    .map(zone => ({ displayName: dateTime.zoneLabel(zone), value: zone }))
            }
        }

        Process {
            id: timeChanger
            stderr: StdioCollector { id: timeChangerErrors }
            onExited: (code) => {
                if (code !== 0)
                    dateTime.problem = timeChangerErrors.text.trim() || Translation.tr("The change was not made.");
                // A refused change leaves the switch where the click put it.
                automaticSwitch.checked = Qt.binding(() => dateTime.automatic);
                timeState.running = true;
                dateTime.now = new Date();
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            text: dateTime.now.toLocaleString(Qt.locale(), Locale.LongFormat)
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSecondaryContainer
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            visible: dateTime.loaded
            text: !dateTime.automatic ? Translation.tr("Set by hand")
                : dateTime.inSync ? Translation.tr("Kept in sync with internet time")
                : Translation.tr("Waiting to sync with internet time")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            id: automaticSwitch
            buttonIcon: "sync"
            text: Translation.tr("Set time automatically")
            enabled: dateTime.canAutomatic && !timeChanger.running
            checked: dateTime.automatic
            onClicked: dateTime.change(["set-ntp", dateTime.automatic ? "false" : "true"])
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "public"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Time zone")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 300
                enabled: !timeChanger.running && dateTime.zones.length > 0
                model: dateTime.zones
                currentIndex: dateTime.zones.findIndex(zone => zone.value === dateTime.timezone)
                onActivated: index => dateTime.change(["set-timezone", dateTime.zones[index].value])
            }
        }

        // By hand only while automatic time is off, since the next sync would undo it.
        ConfigRow {
            visible: dateTime.loaded && !dateTime.automatic
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "edit_calendar"
                Layout.alignment: Qt.AlignVCenter
            }
            MaterialTextField {
                id: dateField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Date (YYYY-MM-DD)")
                inputMethodHints: Qt.ImhDate
            }
            MaterialTextField {
                id: timeField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Time (HH:MM)")
                inputMethodHints: Qt.ImhTime
            }
            RippleButtonWithIcon {
                materialIcon: "check"
                mainText: Translation.tr("Set")
                enabled: !timeChanger.running && /^\d{4}-\d{2}-\d{2}$/.test(dateField.text.trim())
                    && /^\d{1,2}:\d{2}$/.test(timeField.text.trim())
                onClicked: dateTime.change(["set-time", `${dateField.text.trim()} ${timeField.text.trim()}:00`])
            }
            // Starts from the time it is now, so a small correction is a small edit.
            onVisibleChanged: if (visible) {
                dateField.text = Qt.formatDate(new Date(), "yyyy-MM-dd");
                timeField.text = Qt.formatTime(new Date(), "HH:mm");
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            visible: dateTime.problem.length > 0
            text: dateTime.problem
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: Config.options.policies.ai !== 0
        icon: "neurology"
        title: Translation.tr("AI Assistant")

        ContentSubsection {
            title: Translation.tr("Execution Mode")
            tooltip: Translation.tr("Controls how AI models and agent CLIs handle permissions and tools.\n• Ask: Asks for confirmation before executing commands.\n• Auto: Automatically approves tool execution, commands, and web fetching.\n• Plan: Focuses strictly on planning and architecture without running commands or edits.")

            ConfigSelectionArray {
                currentValue: AiModes.current
                onSelected: newValue => {
                    AiModes.set(newValue);
                }
                options: AiModes.ids.map(id => ({
                    displayName: AiModes.name(id),
                    icon: AiModes.icon(id),
                    value: id
                }))
            }
        }
    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }
    }

    ContentSection {
        icon: "cell_tower"
        title: Translation.tr("Networking")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent (for services that require it)")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }
    }
    /*
    ContentSection {
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
    }
    */

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot Path (default: ~/Pictures/Screenshots)")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")
        ConfigSwitch {
            text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
            checked: Config.options.search.sloppy
            onCheckedChanged: {
                Config.options.search.sloppy = checked;
            }
            StyledToolTip {
                text: Translation.tr("Could be better if you make a ton of typos,\nbut results can be weird and might not work with acronyms\n(e.g. \"GIMP\" might not give you the paint program)")
            }
        }

        ConfigSwitch {
            text: Translation.tr("File and folder search")
            checked: Config.options.search.fileSearch.enable
            onCheckedChanged: {
                Config.options.search.fileSearch.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Walks your home directory live via fd whenever you type in the launcher. Apps remain at the top of results; files and folders show below them with icons from your active theme.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Prefixes")
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }
        }
    }

    // There's no update indicator in ii for now so we shouldn't show this yet
    // ContentSection {
    //     icon: "deployed_code_update"
    //     title: Translation.tr("System updates (Arch only)")

    //     ConfigSwitch {
    //         text: Translation.tr("Enable update checks")
    //         checked: Config.options.updates.enableCheck
    //         onCheckedChanged: {
    //             Config.options.updates.enableCheck = checked;
    //         }
    //     }

    //     ConfigSpinBox {
    //         icon: "av_timer"
    //         text: Translation.tr("Check interval (mins)")
    //         value: Config.options.updates.checkInterval
    //         from: 60
    //         to: 1440
    //         stepSize: 60
    //         onValueChanged: {
    //             Config.options.updates.checkInterval = value;
    //         }
    //     }
    // }

    WeatherSection {
        icon: "weather_mix"
    }

    ContentSection {
        // Only worth a row when there is a real choice to make. A machine
        // with one backlight, or none at all, has nothing this can pick
        // between: Automatic already resolves to the only one there is. The
        // case it exists for is a laptop that reports a second, dead
        // backlight alongside the panel.
        visible: Brightness.availableDevices.length > 1
        icon: "brightness_medium"
        title: Translation.tr("Brightness")

        ContentSubsection {
            title: Translation.tr("Device")
            tooltip: Translation.tr("Which backlight to drive.\nAutomatic lets brightnessctl choose, which is usually right.\nLaptops with hybrid graphics can expose a second, non-functional backlight: if the brightness keys do nothing, pick the panel explicitly.\nMonitors controlled over DDC are unaffected.")

            ConfigSelectionArray {
                currentValue: Config.options.brightness.device
                onSelected: newValue => {
                    Config.options.brightness.device = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Automatic"),
                        icon: "auto_mode",
                        value: ""
                    },
                    ...Brightness.availableDevices.map(device => ({
                                displayName: device,
                                icon: "light_mode",
                                value: device
                            }))
                ]
            }
        }
    }
}
