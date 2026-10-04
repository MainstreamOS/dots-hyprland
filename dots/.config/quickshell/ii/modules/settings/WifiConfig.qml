import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import "connectivity"

Item {
    id: root

    readonly property string countryHelper: "/usr/local/bin/mainstream-wifi-country"
    readonly property string countryConf: "/etc/conf.d/wireless-regdom"
    property bool countryReady: false
    property bool countryInstalled: false
    property bool countryApplying: false
    property string countryError: ""
    // iw's global domain: "00" none, "98" the choice intersected with the network's.
    property string countryRunning: ""
    property string countrySaved: ""
    // A country guessed from the time zone follows it until one is picked here.
    property bool countryGuessed: false
    // " 00 AD AE ... ", the codes regulatory.db has rules for (empty if unread).
    // The kernel drops any other code and stays on 00.
    property string countryRegdb: ""
    property var countryNames: ({})

    readonly property bool countryCanChange: root.countryReady && root.countryInstalled && !root.countryApplying
    readonly property var countries: Object.keys(root.countryNames)
        .filter(code => root.countryHasRules(code))
        .map(code => ({ displayName: root.countryNames[code], icon: "", value: code }))
        .sort((a, b) => a.displayName.localeCompare(b.displayName))
    // Every row carries an icon, even an empty one: StyledComboBox reads a
    // missing one as undefined and warns on each change.
    readonly property var countryModel: {
        const list = [{ displayName: Translation.tr("Not set"), icon: "", value: "" }];
        if (root.countrySaved.length > 0 && !root.countries.some(c => c.value === root.countrySaved))
            list.push({ displayName: root.countryName(root.countrySaved), icon: "", value: root.countrySaved });
        return list.concat(root.countries);
    }
    readonly property int countryIndex: Math.max(0, root.countryModel.findIndex(c => c.value === root.countrySaved))

    function countryHasRules(code) {
        return root.countryRegdb.length === 0 || root.countryRegdb.includes(" " + code + " ");
    }

    function countryName(code) {
        return root.countryNames[code] ?? code;
    }

    // A pick or a model swap leaves the box on an index the binding never
    // re-evaluates, so it is pointed back at the saved country.
    function syncCountryCombo() {
        countryCombo.currentIndex = Qt.binding(() => root.countryIndex);
    }

    function refreshCountry() {
        countryProbe.running = true;
    }

    function chooseCountry(code) {
        if ((code === root.countrySaved && !root.countryGuessed) || (code.length > 0 && !root.countries.some(c => c.value === code))) {
            root.syncCountryCombo();
            return;
        }
        root.countryError = "";
        root.countryApplying = true;
        countryApplyProc.command = code.length > 0
            ? ["pkexec", root.countryHelper, "set", code]
            : ["pkexec", root.countryHelper, "clear"];
        countryApplyProc.running = true;
    }

    function countryApplied(code) {
        if (code === 0) {
            // The kernel switches domains a moment after `iw reg set` returns.
            countrySettle.restart();
            return;
        }
        const reason = HelperUtils.helperReason(countryApplyErr.text, "mainstream-wifi-country");
        root.countryError = HelperUtils.failureMessage(code, reason.charAt(0).toUpperCase() + reason.slice(1));
        root.refreshCountry();
    }

    // regulatory.db: "RGDB", a version, then one 4-byte row per country (two
    // letters and a pointer) up to a row whose pointer is zero.
    function parseRegdb(text) {
        let row = 0;
        let codes = " ";
        for (const line of text.split("\n")) {
            const trimmed = line.trim();
            if (trimmed.length === 0)
                continue;
            const r = trimmed.split(/\s+/).map(h => parseInt(h, 16));
            if (row === 0 && r.join(" ") !== "82 71 68 66")
                return "";
            if (row++ < 2)
                continue;
            if (r.length !== 4 || r.some(isNaN))
                return "";
            if (r[2] === 0 && r[3] === 0)
                return codes;
            codes += String.fromCharCode(r[0], r[1]) + " ";
        }
        return "";
    }

    Component.onCompleted: root.refreshCountry()

    FileView {
        id: countryTable
        path: "/usr/share/zoneinfo/iso3166.tab"
        printErrors: false
        onLoaded: {
            // tzdata files these under names people do not scroll to.
            const renamed = { GB: "United Kingdom", KP: "North Korea", KR: "South Korea" };
            const names = {};
            for (const line of countryTable.text().split("\n")) {
                const code = line.substring(0, 2);
                if (/^[A-Z]{2}\t/.test(line))
                    names[code] = renamed[code] ?? line.substring(3).trim();
            }
            root.countryNames = names;
        }
    }

    Process {
        id: countryProbe
        command: ["sh", "-c",
            "test -x \"$1\" && test -f \"$2\" && ! test -L \"$2\" && echo installed=1 || echo installed=0; "
            + "echo '--iw--'; iw reg get 2>/dev/null; "
            + "echo '--regdb--'; od -An -v -tx1 -w4 -N4096 /usr/lib/firmware/regulatory.db 2>/dev/null; "
            + "echo '--regdom--'; cat \"$2\" 2>/dev/null; "
            + "echo '--stamp--'; cat /var/lib/mainstream/wifi-country 2>/dev/null",
            "sh", root.countryHelper, root.countryConf]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split(/^--(?:iw|regdb|regdom|stamp)--$/m);
                const iwOut = parts[1] ?? "";
                // The global domain comes first, under "global"; cards that
                // manage their own follow it. An older iw prints it alone.
                const running = /^global$/m.test(iwOut)
                    ? iwOut.match(/^global\n\s*country (\w\w):/m)
                    : iwOut.match(/^country (\w\w):/m);
                // The file is sourced by a shell, so the last assignment wins.
                let saved = "";
                for (const line of (parts[3] ?? "").split("\n")) {
                    const m = line.match(/^\s*(?:export\s+)?WIRELESS_REGDOM=["']?(\w*)["']?\s*$/);
                    if (m)
                        saved = m[1].toUpperCase();
                }
                root.countryInstalled = /^installed=1$/m.test(parts[0] ?? "");
                root.countryRunning = running ? running[1] : "";
                root.countryRegdb = root.parseRegdb(parts[2] ?? "");
                root.countrySaved = /^[A-Z]{2}$/.test(saved) ? saved : "";
                root.countryGuessed = /^seeded/.test((parts[4] ?? "").trim());
                root.countryReady = true;
                root.countryApplying = false;
                root.syncCountryCombo();
            }
        }
    }

    Process {
        id: countryApplyProc
        stderr: StdioCollector { id: countryApplyErr }
        onExited: code => root.countryApplied(code)
    }

    Timer {
        id: countrySettle
        interval: 1000
        onTriggered: root.refreshCountry()
    }

    ShownWifiNetworks {
        id: shownNetworks
    }

    component WifiNotice: SubtleNoticeBox {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 4
        Layout.bottomMargin: 4
    }

    component CountryNote: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        visible: text.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: true

        ContentSection {
            icon: "wifi"
            title: "Wi-Fi"

            headerExtra: [
                RippleButton {
                    visible: Network.wifiEnabled
                    implicitWidth: 90
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Network.rescanWifi()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "refresh"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Scan")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            ]

            ConfigRow {
                ConfigSwitch {
                    text: Translation.tr("Enable Wi-Fi")
                    checked: Network.wifiEnabled
                    onCheckedChanged: {
                        Network.enableWifi(checked, true);
                    }
                }
            }

            WifiNotice {
                visible: Network.frameAdapterPresent
                materialIcon: "view_in_ar"
                text: Translation.tr("Turning Wi-Fi off also turns off the wireless adapter for the Steam Frame (experimental), so the headset cannot stream through it until Wi-Fi is back on.")
            }

            StyledIndeterminateProgressBar {
                visible: Network.wifiScanning
                Layout.fillWidth: true
            }
        }

        // Connected network
        ContentSection {
            icon: "wifi"
            title: Translation.tr("Connected")
            visible: Network.wifiEnabled && shownNetworks.active !== null

            ConnectivityWifiItem {
                wifiNetwork: shownNetworks.active
                Layout.fillWidth: true
            }
        }

        // Saved networks (not active)
        ContentSection {
            icon: "bookmark"
            title: Translation.tr("Saved Networks")
            visible: Network.wifiEnabled && shownNetworks.savedNetworks.length > 0

            Repeater {
                model: ScriptModel {
                    values: shownNetworks.savedNetworks
                }

                ConnectivityWifiItem {
                    required property var modelData
                    wifiNetwork: modelData
                    Layout.fillWidth: true
                }
            }

            WifiNotice {
                // From the rows above, so it stays beside a Steam row a prompt holds there.
                visible: shownNetworks.savedNetworks.some(n => n?.frameProfile)
                materialIcon: "view_in_ar"
                text: Translation.tr("%1 is the link Steam makes to the Steam Frame (experimental), and Steam connects it by itself. If the headset will not pair, forgetting it and pairing again can help.").arg(Network.frameProfileName)
            }
        }

        ContentSection {
            icon: "wifi_find"
            title: Translation.tr("Available Networks")
            visible: Network.wifiEnabled

            // Empty state
            ColumnLayout {
                visible: shownNetworks.availableNetworks.length === 0 && !Network.wifiScanning
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 32
                    color: Appearance.colors.colLayer3

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "wifi_find"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No new networks found")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Click Scan to search for networks")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            // Network list (available = not saved)
            Repeater {
                model: ScriptModel {
                    values: shownNetworks.availableNetworks
                }

                ConnectivityWifiItem {
                    required property var modelData
                    wifiNetwork: modelData
                    Layout.fillWidth: true
                }
            }
        }

        ContentSection {
            icon: "wifi_add"
            title: Translation.tr("Hidden Network")
            visible: Network.wifiEnabled

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialTextField {
                    id: hiddenSsidField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Network name (SSID)")
                }

                MaterialTextField {
                    id: hiddenPasswordField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Password (optional)")
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                }

                RippleButton {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 140
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    enabled: hiddenSsidField.text.length > 0
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover

                    onClicked: {
                        const ssid = hiddenSsidField.text;
                        const password = hiddenPasswordField.text;
                        if (password.length > 0) {
                            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid, "password", password]);
                        } else {
                            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid]);
                        }
                        hiddenSsidField.text = "";
                        hiddenPasswordField.text = "";
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "add"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Connect")
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "public"
            title: Translation.tr("Wi-Fi Country")

            ConfigRow {
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                OptionalMaterialSymbol {
                    icon: "flag"
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 6
                    text: Translation.tr("Country")
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledComboBox {
                    id: countryCombo
                    textRole: "displayName"
                    Layout.fillWidth: false
                    Layout.preferredWidth: 220
                    enabled: root.countryCanChange
                    model: root.countryModel
                    currentIndex: root.countryIndex
                    onModelChanged: root.syncCountryCombo()
                    // With the list closed, Qt also activates on arrow keys and
                    // typed letters, so only a pick from the open list counts.
                    onActivated: index => {
                        if (countryCombo.popup.visible)
                            root.chooseCountry(root.countryModel[index].value);
                        else
                            root.syncCountryCombo();
                    }
                }
            }

            CountryNote {
                color: Appearance.m3colors.m3error
                text: root.countryError
            }

            CountryNote {
                text: root.countryReady && !root.countryInstalled
                    ? Translation.tr("Wi-Fi country support is not installed on this machine. Run an update, then come back.") : ""
            }

            CountryNote {
                text: {
                    const saved = root.countrySaved;
                    const running = root.countryRunning;
                    if (!root.countryReady || root.countryApplying)
                        return "";
                    if (saved.length > 0 && !root.countryHasRules(saved))
                        return Translation.tr("Wi-Fi has no rules for %1, so it keeps the worldwide settings.").arg(root.countryName(saved));
                    if (root.countryGuessed && saved.length > 0 && (running.length === 0 || running === saved))
                        return Translation.tr("%1 was guessed from your time zone and follows it. Pick a country to keep it.").arg(root.countryName(saved));
                    if (running.length === 0 || running === saved)
                        return "";
                    const runningCountry = /^[A-Z]{2}$/.test(running);
                    if (saved.length === 0)
                        return runningCountry ? Translation.tr("No country is saved. Wi-Fi is using %1 for now, as your network or card asks.").arg(root.countryName(running)) : "";
                    if (running === "98")
                        return Translation.tr("Your network names another country, so Wi-Fi uses only the channels both countries allow.");
                    if (runningCountry)
                        return Translation.tr("Wi-Fi is using %1 for now, as your network or card asks. %2 stays saved.").arg(root.countryName(running)).arg(root.countryName(saved));
                    return Translation.tr("%1 is saved and takes effect after a restart.").arg(root.countryName(saved));
                }
            }

            WifiNotice {
                text: Translation.tr("Set this to the country you are in, so Wi-Fi uses the channels allowed there. Cards that manage their own country, such as most Intel ones, report their own. USB adapters, such as the one for the Steam Frame (experimental), use the one set here.")
            }
        }
    }
}
