import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Secure Boot with this computer's own keys, which is what keeps the system
// starting once the firmware enforces it.
ContentSection {
    id: root
    objectName: "secureBoot"
    icon: "verified_user"
    title: Translation.tr("Secure Boot")

    // One confirmation is open at a time.
    property string openPanel: ""

    // "loading" | "legacy" | "enabled" | "setup" | "enrolled" | "restorable" | "disabled"
    readonly property string secureBootState: {
        if (!SystemSecurity.loaded)
            return "loading";
        if (!SystemSecurity.uefi)
            return "legacy";
        if (SystemSecurity.secureBoot)
            return "enabled";
        if (SystemSecurity.setupMode)
            return "setup";
        // Enrolling leaves Setup Mode, and Secure Boot reads off until it is
        // switched on in the firmware, so keys on disk tell the two apart.
        if (SystemSecurity.sbctlKeysExist)
            return "enrolled";
        // A snapshot from before the setup: the firmware has the keys, and
        // this system only has to be pointed at them again.
        return SystemSecurity.signingKeysKept ? "restorable" : "disabled";
    }

    function togglePanel(name) {
        root.openPanel = root.openPanel === name ? "" : name;
    }

    function closePanel() {
        root.openPanel = "";
    }

    Component.onCompleted: SystemSecurity.watch()
    Component.onDestruction: SystemSecurity.unwatch()

    Connections {
        target: SystemSecurity
        function onActionSucceeded(action) {
            root.closePanel();
        }
        function onBusyChanged() {
            if (SystemSecurity.busy)
                root.closePanel();
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Anti-cheat games need Secure Boot turned on. Setting it up here adds your own signing keys alongside Microsoft's, so Mainstream keeps starting, and Windows and hardware that rely on Microsoft's keys keep working.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: SystemSecurity.closeRefused || SystemSecurity.probeFailed || SystemSecurity.unsupportedText.length > 0
        spacing: 4

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemSecurity.closeRefused
            materialIcon: "lock"
            text: Translation.tr("Settings stays open until the change in progress finishes.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemSecurity.probeFailed
            materialIcon: "sync_problem"
            text: Translation.tr("Security status could not be read. Try Refresh.")

            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                materialIcon: "refresh"
                caption: Translation.tr("Refresh")
                onClicked: SystemSecurity.refresh(true)
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemSecurity.unsupportedText.length > 0
            materialIcon: "block"
            text: SystemSecurity.unsupportedText
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: SystemSecurity.stateKnown && !SystemSecurity.helper
        materialIcon: "system_update_alt"
        text: Translation.tr("Update Mainstream to manage Secure Boot.")
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: SystemSecurity.stateKnown
            && (SystemSecurity.windowsDetected || SystemSecurity.bitlockerDetected)
            && !SystemSecurity.secureBoot
        materialIcon: "warning"
        text: Translation.tr("Windows or BitLocker was found on this computer. Enrolling Secure Boot keys changes what BitLocker checks at startup (PCR 7) once: pause BitLocker in Windows or have your 48-digit BitLocker recovery key ready first. Microsoft's certificates stay enrolled, so Windows 11 and anti-cheat games on Windows keep working.")
    }

    SecurityCard {
        id: secureBootCard
        readonly property bool confirmingReboot: root.openPanel === "firmware-reboot"
            && (root.secureBootState === "disabled" || root.secureBootState === "enrolled")
        readonly property bool confirmingEnable: root.openPanel === "sb-enable" && root.secureBootState === "setup"
        // After restoring a snapshot from before Secure Boot was set up,
        // the firmware still enforces keys this system has lost sight of.
        readonly property bool keysMissing: SystemSecurity.secureBoot && !SystemSecurity.sbctlKeysExist
        readonly property bool canRestoreSigning: SystemSecurity.signingKeysKept
            && (secureBootCard.keysMissing || root.secureBootState === "restorable")

        available: SystemSecurity.loaded
        icon: {
            switch (root.secureBootState) {
            case "legacy":
                return "computer";
            case "enabled":
                return "verified_user";
            case "setup":
            case "enrolled":
            case "restorable":
                return "key";
            default:
                return "gpp_maybe";
            }
        }
        title: Translation.tr("Boot verification")
        pillText: {
            switch (root.secureBootState) {
            case "loading":
                return SystemSecurity.pendingPill;
            case "legacy":
                return Translation.tr("Legacy BIOS");
            case "enabled":
                return Translation.tr("Enabled");
            case "setup":
                return Translation.tr("Setup Mode ready");
            case "enrolled":
                return Translation.tr("Keys enrolled");
            case "restorable":
                return Translation.tr("Keys kept");
            default:
                return Translation.tr("Disabled");
            }
        }
        pillTone: {
            switch (root.secureBootState) {
            case "enabled":
                return "success";
            case "setup":
            case "enrolled":
                return "accent";
            default:
                return "neutral";
            }
        }
        description: {
            switch (root.secureBootState) {
            case "loading":
                return SystemSecurity.probeFailed ? "" : Translation.tr("Reading UEFI firmware state…");
            case "legacy":
                return Translation.tr("Secure Boot requires UEFI firmware and is not available in Legacy BIOS mode.");
            case "enabled":
                if (SystemSecurity.sbctlVerified)
                    return Translation.tr("Boot files verified");
                if (SystemSecurity.sbctlKeysExist)
                    return Translation.tr("Keys enrolled, signed status not checked");
                return Translation.tr("Firmware keys active");
            case "setup":
                return Translation.tr("The firmware is in Setup Mode and ready to enroll your keys.");
            case "enrolled":
                return Translation.tr("Your signing keys are enrolled. Turn on Secure Boot in UEFI setup to finish.");
            case "restorable":
                return Translation.tr("This system was restored from before Secure Boot was set up. Its signing keys were kept, so signing can be set up again without clearing anything in UEFI setup.");
            default:
                return Translation.tr("Clear the existing Secure Boot keys in UEFI setup to enter Setup Mode before enrolling.");
            }
        }
        detailVisible: root.secureBootState === "disabled" || root.secureBootState === "setup"
            || secureBootCard.confirmingReboot

        NoticeBox {
            Layout.fillWidth: true
            visible: secureBootCard.keysMissing
            materialIcon: "warning"
            text: SystemSecurity.signingKeysKept
                ? Translation.tr("Secure Boot is on, but this system was restored from before it was set up and is not signing its boot files. Its signing keys were kept: set up signing again now, before a system update leaves it unable to start.")
                : Translation.tr("Secure Boot is on, but this system no longer has its signing keys. This happens after restoring an older snapshot. A system update could leave it unable to start: turn Secure Boot off in UEFI setup, or clear its keys there and set it up again.")
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.secureBootState === "enabled"
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Snapshots taken before Secure Boot was set up cannot be started from the boot menu while it is on.")
        }

        Flow {
            visible: root.secureBootState === "enabled" || root.secureBootState === "enrolled"
                || root.secureBootState === "restorable"
            Layout.fillWidth: true
            spacing: 8

            ActionButton {
                visible: secureBootCard.canRestoreSigning
                variant: "primary"
                materialIcon: "key"
                caption: Translation.tr("Set up signing again")
                busyCaption: Translation.tr("Setting up signing…")
                busy: SystemSecurity.busyAction === "sb-restore"
                enabled: SystemSecurity.canChangeBoot
                onClicked: SystemSecurity.restoreSigning()
            }

            ActionButton {
                visible: root.secureBootState === "enrolled"
                variant: "primary"
                materialIcon: "restart_alt"
                caption: Translation.tr("Reboot to UEFI Setup")
                enabled: !SystemSecurity.busy
                onClicked: root.togglePanel("firmware-reboot")
            }

            ActionButton {
                visible: root.secureBootState !== "restorable"
                materialIcon: "verified"
                caption: Translation.tr("Re-sign boot files")
                busyCaption: Translation.tr("Re-signing…")
                busy: SystemSecurity.busyAction === "sb-sign"
                enabled: SystemSecurity.canChangeBoot && !secureBootCard.keysMissing
                onClicked: SystemSecurity.resignBoot()
            }
        }

        detail: [
            ColumnLayout {
                visible: root.secureBootState === "disabled"
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StatusPill {
                        caption: Translation.tr("Step 1")
                        tone: "accent"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Restart into UEFI setup, open the Secure Boot settings, and clear or delete the Secure Boot keys to enter Setup Mode.")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StatusPill {
                        caption: Translation.tr("Step 2")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Start Mainstream again and come back here to create and enroll your signing keys.")
                    }
                }

                ActionButton {
                    visible: !secureBootCard.confirmingReboot
                    materialIcon: "restart_alt"
                    caption: Translation.tr("Reboot to UEFI Setup")
                    enabled: !SystemSecurity.busy && SystemSecurity.unsupportedReason === ""
                    onClicked: root.togglePanel("firmware-reboot")
                }
            },
            ConfirmRow {
                visible: secureBootCard.confirmingReboot
                prompt: Translation.tr("Restart this computer into UEFI setup now? Save any open work first.")
                actionIcon: "restart_alt"
                actionText: Translation.tr("Reboot now")
                actionEnabled: !SystemSecurity.busy
                onCanceled: root.closePanel()
                onConfirmed: {
                    root.closePanel();
                    Session.rebootToFirmware();
                }
            },
            ColumnLayout {
                visible: root.secureBootState === "setup"
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("This installs sbctl if needed, creates your signing keys, enrolls them alongside Microsoft's and the manufacturer's keys, locks the boot menu against changes, and signs your boot files.")
                }

                ActionButton {
                    visible: !secureBootCard.confirmingEnable
                    variant: "primary"
                    materialIcon: "verified_user"
                    caption: Translation.tr("Create and enroll keys")
                    busyCaption: Translation.tr("Creating and enrolling keys…")
                    busy: SystemSecurity.busyAction === "sb-enable"
                    enabled: SystemSecurity.canChangeBoot
                    onClicked: root.togglePanel("sb-enable")
                }

                ConfirmRow {
                    visible: secureBootCard.confirmingEnable
                    prompt: SystemSecurity.windowsDetected || SystemSecurity.bitlockerDetected
                        ? Translation.tr("Create signing keys and enroll them in this computer's firmware? Boot files are signed and checked first. BitLocker will ask for its recovery key the next time Windows starts unless it is paused: pause it in Windows or have the 48-digit key ready.")
                        : Translation.tr("Create signing keys and enroll them in this computer's firmware? Boot files are signed and checked first.")
                    actionVariant: "primary"
                    actionIcon: "verified_user"
                    actionText: Translation.tr("Create and enroll")
                    actionEnabled: SystemSecurity.canChangeBoot
                    onCanceled: root.closePanel()
                    onConfirmed: {
                        root.closePanel();
                        SystemSecurity.enableSecureBoot();
                    }
                }
            }
        ]
    }

    ScopeMessage {
        forScope: "secureBoot"
    }
}
