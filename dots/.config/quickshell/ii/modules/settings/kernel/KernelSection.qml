import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.security

// Mainstream's own kernels beside the standard one, and which of them the
// boot menu starts next.
ContentSection {
    id: root
    objectName: "kernel"
    icon: "developer_board"
    title: Translation.tr("Kernel")

    // One confirmation is open at a time: "install:<kernel>" or "remove:<kernel>".
    property string openPanel: ""

    // "shown" and "about" rather than "title" and "description", which the
    // settings search would read as this section's own.
    readonly property var cards: [
        {
            name: "linux",
            icon: "shield",
            shown: Translation.tr("Standard"),
            about: Translation.tr("Arch's kernel. It stays installed as the fallback.")
        },
        {
            name: "linux-mainstream",
            icon: "developer_board",
            shown: Translation.tr("Mainstream"),
            about: Translation.tr("Mainstream's build of the same kernel version. New installs start it by default.")
        },
        {
            name: "linux-mainstream-performance",
            icon: "speed",
            shown: Translation.tr("Mainstream Performance"),
            about: Translation.tr("Tuned for games and a responsive desktop.")
        }
    ]

    function togglePanel(name) {
        root.openPanel = root.openPanel === name ? "" : name;
    }

    function closePanel() {
        root.openPanel = "";
    }

    Component.onCompleted: {
        SystemKernels.watch();
        // The results of a change are shown through SystemSecurity's messages.
        SystemSecurity.watch();
    }
    Component.onDestruction: {
        SystemKernels.unwatch();
        SystemSecurity.unwatch();
    }

    Connections {
        target: SystemKernels
        function onActionSucceeded(action, kernel) {
            root.closePanel();
        }
        function onBusyChanged() {
            if (SystemKernels.busy)
                root.closePanel();
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Mainstream's own kernels install beside the standard one, and the boot menu lists every installed kernel. Nothing changes until you restart.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: SystemKernels.closeRefused || SystemKernels.probeFailed || SystemKernels.unsupportedText.length > 0
        spacing: 4

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemKernels.closeRefused
            materialIcon: "lock"
            text: Translation.tr("Settings stays open until the change in progress finishes.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemKernels.probeFailed
            materialIcon: "sync_problem"
            text: Translation.tr("Kernel status could not be read. Try Refresh.")

            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                materialIcon: "refresh"
                caption: Translation.tr("Refresh")
                onClicked: SystemKernels.refresh(true)
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: SystemKernels.unsupportedText.length > 0
            materialIcon: "block"
            text: SystemKernels.unsupportedText
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: SystemKernels.stateKnown && !SystemKernels.helper
        materialIcon: "system_update_alt"
        text: Translation.tr("Update Mainstream to manage kernels.")
    }

    Repeater {
        model: root.cards

        SecurityCard {
            id: card
            required property var modelData
            readonly property string kernel: card.modelData.name
            readonly property var info: SystemKernels.info(card.kernel)
            readonly property bool standard: card.kernel === SystemKernels.standardKernel
            readonly property bool installed: card.info.installed
            readonly property bool startsNext: SystemKernels.nextKernel === card.kernel
            readonly property bool confirmingInstall: root.openPanel === "install:" + card.kernel && !card.installed
            readonly property bool confirmingRemove: root.openPanel === "remove:" + card.kernel && card.installed
            readonly property bool showInstall: !card.standard && !card.installed && !card.confirmingInstall
            readonly property bool showNext: card.installed && !card.startsNext
            readonly property bool showRemove: !card.standard && card.installed && !card.confirmingRemove
            // Why this kernel cannot be installed here, or nothing.
            readonly property string installBlocked: {
                if (!card.info.cpuSupported)
                    return Translation.tr("This processor cannot run this kernel. It needs AVX2 (Intel from about 2013, AMD from about 2015).");
                if (!card.info.available)
                    return Translation.tr("Not available yet.");
                if (SystemKernels.roomShort)
                    return Translation.tr("The boot partition does not have room for another kernel.");
                return "";
            }
            // Why the boot menu cannot be told to start this kernel, or nothing.
            readonly property string nextBlocked: {
                if (!SystemKernels.canChooseNext)
                    return Translation.tr("Choose it in the boot menu when the computer starts.");
                if (card.info.driverMissing)
                    return Translation.tr("The graphics driver is not built for this kernel. Keep using the kernel you are on.");
                return "";
            }

            available: SystemKernels.loaded
            icon: card.modelData.icon
            title: card.modelData.shown
            pillText: {
                if (!SystemKernels.loaded)
                    return SystemKernels.pendingPill;
                if (card.info.running)
                    return Translation.tr("Running");
                return card.installed ? Translation.tr("Installed") : Translation.tr("Not installed");
            }
            pillTone: {
                if (!SystemKernels.loaded)
                    return "neutral";
                if (card.info.running)
                    return "success";
                return card.installed ? "accent" : "neutral";
            }
            description: card.modelData.about
            detailVisible: card.confirmingInstall || card.confirmingRemove

            StyledText {
                Layout.fillWidth: true
                visible: SystemKernels.loaded && card.installed && card.startsNext
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
                text: Translation.tr("The boot menu starts this kernel next.")
            }

            StyledText {
                Layout.fillWidth: true
                visible: SystemKernels.loaded && !card.standard && !card.installed && card.installBlocked.length > 0
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: card.installBlocked
            }

            StyledText {
                Layout.fillWidth: true
                visible: SystemKernels.loaded && card.installed && !card.startsNext && card.nextBlocked.length > 0
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: card.nextBlocked
            }

            StyledText {
                Layout.fillWidth: true
                visible: SystemKernels.loaded && !card.standard && card.installed && card.info.running
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Restart with another kernel before removing this one.")
            }

            StyledText {
                Layout.fillWidth: true
                visible: SystemKernels.busyAction === "install" && SystemKernels.busyKernel === card.kernel
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Downloading and installing. This can take several minutes.")
            }

            Flow {
                // An empty row would leave a blank band in the card.
                visible: SystemKernels.loaded && (card.showInstall || card.showNext || card.showRemove)
                Layout.fillWidth: true
                spacing: 8

                ActionButton {
                    visible: card.showInstall
                    variant: "primary"
                    materialIcon: "download"
                    caption: Translation.tr("Install")
                    busyCaption: Translation.tr("Installing…")
                    busy: SystemKernels.busyAction === "install" && SystemKernels.busyKernel === card.kernel
                    enabled: SystemKernels.canChange && card.installBlocked.length === 0
                    onClicked: root.togglePanel("install:" + card.kernel)
                }

                ActionButton {
                    visible: card.showNext
                    variant: card.standard ? "tonal" : "primary"
                    materialIcon: "restart_alt"
                    caption: Translation.tr("Use at next start")
                    busyCaption: Translation.tr("Saving…")
                    busy: SystemKernels.busyAction === "next" && SystemKernels.busyKernel === card.kernel
                    enabled: SystemKernels.canChange && card.nextBlocked.length === 0
                    onClicked: SystemKernels.useNext(card.kernel)
                }

                ActionButton {
                    visible: card.showRemove
                    materialIcon: "delete"
                    caption: Translation.tr("Remove")
                    busyCaption: Translation.tr("Removing…")
                    busy: SystemKernels.busyAction === "remove" && SystemKernels.busyKernel === card.kernel
                    enabled: SystemKernels.canChange && !card.info.running
                    onClicked: root.togglePanel("remove:" + card.kernel)
                }
            }

            detail: [
                ConfirmRow {
                    visible: card.confirmingInstall
                    prompt: card.info.downloadBytes > 0
                        ? Translation.tr("Install the %1 kernel? The download is about %2 MB. It is added to the boot menu beside the kernels you have.")
                            .arg(card.modelData.shown).arg(Math.max(1, Math.round(card.info.downloadBytes / 1048576)))
                        : Translation.tr("Install the %1 kernel? It is added to the boot menu beside the kernels you have.")
                            .arg(card.modelData.shown)
                    actionVariant: "primary"
                    actionIcon: "download"
                    actionText: Translation.tr("Install")
                    actionEnabled: SystemKernels.canChange && card.installBlocked.length === 0
                    onCanceled: root.closePanel()
                    onConfirmed: {
                        root.closePanel();
                        SystemKernels.install(card.kernel);
                    }
                },
                ConfirmRow {
                    visible: card.confirmingRemove
                    prompt: Translation.tr("Remove the %1 kernel? The other kernels stay installed.").arg(card.modelData.shown)
                    actionIcon: "delete"
                    actionText: Translation.tr("Remove")
                    actionEnabled: SystemKernels.canChange && !card.info.running
                    onCanceled: root.closePanel()
                    onConfirmed: {
                        root.closePanel();
                        SystemKernels.remove(card.kernel);
                    }
                }
            ]
        }
    }

    ScopeMessage {
        forScope: SystemKernels.messageScope
    }
}
