import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// What Easy Anti-Cheat on Linux checks before a protected game starts, and
// how each item stands in this session.
ContentSection {
    id: root
    objectName: "antiCheat"
    icon: "sports_esports"
    title: Translation.tr("Anti-Cheat Games")

    // Epic's published list for Easy Anti-Cheat on Linux, in the order a
    // person can act on it: what Settings and the firmware menu can turn on
    // first, then what a start sets.
    readonly property var checks: [
        {
            met: SystemSecurity.secureBoot,
            what: Translation.tr("Secure Boot is on"),
            fix: Translation.tr("Set it up in the Secure Boot section.")
        },
        {
            met: SystemSecurity.tpm2,
            what: Translation.tr("Security chip is on (TPM 2.0)"),
            fix: Translation.tr("Turn on the TPM in UEFI setup. It may be called fTPM, PTT or Security Device.")
        },
        {
            met: SystemSecurity.iommu && !SystemSecurity.iommuPassthrough,
            what: Translation.tr("Devices cannot read game memory (IOMMU)"),
            fix: SystemSecurity.iommu
                ? Translation.tr("IOMMU is in passthrough mode for this start.")
                : Translation.tr("Turn on IOMMU in UEFI setup. It may be called AMD-Vi, VT-d or DMA protection.")
        },
        {
            met: SystemSecurity.measuredBoot,
            what: Translation.tr("Startup is recorded by the security chip (measured boot)"),
            fix: Translation.tr("Nothing was recorded for this start.")
        },
        {
            met: SystemSecurity.bpfLsm,
            what: Translation.tr("Games can guard their own memory (BPF)"),
            fix: Translation.tr("Not set for this start.")
        },
        {
            met: SystemSecurity.lockedDown,
            what: Translation.tr("Kernel is locked against changes (lockdown)"),
            fix: Translation.tr("Not set for this start.")
        },
        {
            met: SystemSecurity.kexecDisabled,
            what: Translation.tr("Kernel cannot be swapped while running (kexec off)"),
            fix: Translation.tr("Not set for this start.")
        },
        {
            // Met once Epic lists Mainstream's key.
            met: false,
            what: Translation.tr("Kernel is signed by a maker games trust"),
            fix: SystemSecurity.acStartedThroughIt
                ? Translation.tr("This start is signed by Mainstream. Games accept it once Epic adds Mainstream's key to its list.")
                : Translation.tr("Use the anti-cheat start below. Games accept it once Epic adds Mainstream's key to its list.")
        }
    ]
    readonly property int metCount: root.checks.filter(check => check.met).length

    // One confirmation is open at a time.
    property string openPanel: ""

    function togglePanel(name) {
        root.openPanel = root.openPanel === name ? "" : name;
    }

    function closePanel() {
        root.openPanel = "";
    }

    // Why the anti-cheat start cannot be set up here, or nothing.
    readonly property string startBlocked: {
        if (!SystemSecurity.uefi)
            return Translation.tr("The anti-cheat start needs UEFI firmware.");
        if (!SystemSecurity.sbctlKeysExist)
            return Translation.tr("Set up Secure Boot in the Secure Boot section first.");
        if (!SystemSecurity.acKernelInstalled)
            return Translation.tr("Install the Mainstream Anti-Cheat kernel in the Kernel section first.");
        return "";
    }

    Connections {
        target: SystemSecurity
        function onBusyChanged() {
            if (SystemSecurity.busy)
                root.closePanel();
        }
    }

    Component.onCompleted: SystemSecurity.watch()
    Component.onDestruction: SystemSecurity.unwatch()

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Some online games only start when they can confirm how this computer was started. This list follows what Epic has published for Easy Anti-Cheat on Linux. The game makes the final check when it starts.")
    }

    SecurityCard {
        available: SystemSecurity.loaded
        icon: "shield"
        title: Translation.tr("Easy Anti-Cheat")
        pillText: SystemSecurity.loaded
            ? Translation.tr("%1 of %2 met").arg(root.metCount).arg(root.checks.length)
            : SystemSecurity.pendingPill
        description: Translation.tr("A protected game starts only when every item is met in the same session.")

        Repeater {
            model: SystemSecurity.loaded ? root.checks : []

            RowLayout {
                id: checkRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: checkRow.modelData.met ? "check_circle" : "radio_button_unchecked"
                    iconSize: Appearance.font.pixelSize.larger
                    color: checkRow.modelData.met ? Appearance.m3colors.m3success : Appearance.colors.colSubtext
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        text: checkRow.modelData.what
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !checkRow.modelData.met
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: checkRow.modelData.fix
                    }
                }
            }
        }
    }

    SecurityCard {
        id: startCard
        readonly property bool confirmingStart: root.openPanel === "ac-start"
        readonly property bool confirmingRemove: root.openPanel === "ac-remove"

        available: SystemSecurity.loaded
        icon: "rocket_launch"
        title: Translation.tr("Anti-cheat start")
        pillText: {
            if (!SystemSecurity.loaded)
                return SystemSecurity.pendingPill;
            if (SystemSecurity.acStartedThroughIt)
                return Translation.tr("In use");
            return SystemSecurity.acStartReady ? Translation.tr("Ready") : Translation.tr("Not set up");
        }
        pillTone: SystemSecurity.acStartedThroughIt ? "success" : SystemSecurity.acStartReady ? "accent" : "neutral"
        description: Translation.tr("A separate start for protected games: the anti-cheat kernel, started by a boot manager Mainstream signed, with the settings Epic asks for. Your everyday start stays as it is, and the next restart after this one returns to it.")
        detailVisible: startCard.confirmingStart || startCard.confirmingRemove

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemSecurity.acStartSkipped
            materialIcon: "info"
            text: Translation.tr("The computer started your everyday start instead. Turn off Fast Boot in UEFI setup and restart into it again, or choose Mainstream OS (Anti-Cheat) in the firmware's boot menu as the computer starts: F12 on Gigabyte boards, F8 on ASUS, F11 on MSI and ASRock.")
        }

        StyledText {
            Layout.fillWidth: true
            visible: !SystemSecurity.acStartReady && root.startBlocked.length > 0
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: root.startBlocked
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            ActionButton {
                visible: !SystemSecurity.acStartReady
                variant: "primary"
                materialIcon: "rocket_launch"
                caption: Translation.tr("Set up")
                busyCaption: Translation.tr("Setting up…")
                busy: SystemSecurity.busyAction === "ac-setup"
                enabled: SystemSecurity.canChangeBoot && root.startBlocked.length === 0
                onClicked: SystemSecurity.setUpAntiCheat()
            }

            ActionButton {
                visible: SystemSecurity.acStartReady && !SystemSecurity.acStartedThroughIt
                variant: "primary"
                materialIcon: "restart_alt"
                caption: Translation.tr("Restart into it")
                enabled: SystemSecurity.canChangeBoot
                onClicked: root.togglePanel("ac-start")
            }

            ActionButton {
                visible: SystemSecurity.acStartReady
                materialIcon: "delete"
                caption: Translation.tr("Remove")
                busyCaption: Translation.tr("Removing…")
                busy: SystemSecurity.busyAction === "ac-remove"
                enabled: SystemSecurity.canChangeBoot && !SystemSecurity.acStartedThroughIt
                onClicked: root.togglePanel("ac-remove")
            }
        }

        detail: [
            ConfirmRow {
                visible: startCard.confirmingStart
                prompt: Translation.tr("Restart into the anti-cheat start now? Save any open work first.")
                actionVariant: "primary"
                actionIcon: "restart_alt"
                actionText: Translation.tr("Restart now")
                actionEnabled: SystemSecurity.canChangeBoot
                onCanceled: root.closePanel()
                onConfirmed: {
                    root.closePanel();
                    SystemSecurity.startAntiCheat();
                }
            },
            ConfirmRow {
                visible: startCard.confirmingRemove
                prompt: Translation.tr("Remove the anti-cheat start? The anti-cheat kernel stays installed, and your everyday start is not changed.")
                actionIcon: "delete"
                actionText: Translation.tr("Remove")
                actionEnabled: SystemSecurity.canChangeBoot
                onCanceled: root.closePanel()
                onConfirmed: {
                    root.closePanel();
                    SystemSecurity.removeAntiCheat();
                }
            }
        ]
    }

    ScopeMessage {
        forScope: "antiCheat"
    }
}
