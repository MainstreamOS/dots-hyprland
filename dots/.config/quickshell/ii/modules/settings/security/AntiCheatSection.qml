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
            met: false,
            what: Translation.tr("Kernel is signed by a maker games trust"),
            fix: Translation.tr("Not available on Mainstream yet. Games do not accept keys made on this computer.")
        }
    ]
    readonly property int metCount: root.checks.filter(check => check.met).length

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
}
