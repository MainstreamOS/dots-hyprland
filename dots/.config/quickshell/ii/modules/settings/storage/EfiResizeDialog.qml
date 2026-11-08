pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Grows the EFI system partition through mainstream-efi-resize, showing its progress.
Popup {
    id: root

    property Item targetArea: null
    property var efiData: null
    property int selectedSizeMb: 2048
    property bool isResizing: false
    property real progressPercent: 0
    property string progressMessage: ""
    property string resizeError: ""
    property bool resizeSuccess: false

    signal resizeCompleted()

    readonly property string helperPath: "/usr/local/bin/mainstream-efi-resize"

    readonly property int currentPartMb: {
        if (!root.efiData) return 0;
        const raw = root.efiData.part_bytes ?? root.efiData.total ?? 0;
        return Math.round(raw / (1024 * 1024));
    }
    readonly property bool layoutCanResize: root.sizeOptions.some(option => root.isOptionSelectable(option.mb))
    readonly property var selectedPlan: root.planFor(root.selectedSizeMb)
    readonly property string resizeReason: root.selectedPlan?.reason ?? root.efiData?.reason ?? ""

    readonly property var sizeOptions: [
        { mb: 1024, label: "1 GB", desc: Translation.tr("Standard") },
        { mb: 2048, label: "2 GB", desc: Translation.tr("Recommended") },
        { mb: 4096, label: "4 GB", desc: Translation.tr("Multi-kernel") },
        { mb: 8192, label: "8 GB", desc: Translation.tr("Snapshots+") }
    ]

    function isOptionCurrent(mb) {
        return !root.isOptionSelectable(mb) && Math.abs(root.currentPartMb - mb) <= 64;
    }

    function planFor(mb) {
        return root.efiData?.resize_plans?.find(plan => mb === plan.target_mb) ?? null;
    }

    function isOptionSelectable(mb) {
        return root.planFor(mb) !== null;
    }

    function pickDefaultTarget() {
        for (let i = 0; i < root.sizeOptions.length; ++i) {
            const candidate = root.sizeOptions[i].mb;
            if (root.isOptionSelectable(candidate)) {
                root.selectedSizeMb = candidate;
                return;
            }
        }
        root.selectedSizeMb = 0;
    }

    onOpened: {
        root.resizeError = "";
        root.resizeSuccess = false;
        root.progressPercent = 0;
        root.progressMessage = "";
        root.pickDefaultTarget();
    }

    parent: Overlay.overlay
    modal: true
    dim: true
    closePolicy: isResizing ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    padding: 24
    // Built around its text, so it gets room as the text grows, as the Settings window does.
    implicitWidth: Math.round(500 * Appearance.font.roomGrowth)

    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0

    Overlay.modal: Rectangle {
        color: Appearance.colors.colScrim
    }

    background: Item {
        StyledRectangularShadow { target: bg }
        Rectangle {
            anchors.fill: bg
            radius: bg.radius
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer0Base, 1.0)
        }
        Rectangle {
            id: bg
            anchors.fill: parent
            radius: 24
            color: ColorUtils.applyAlpha(Appearance.m3colors.m3surfaceContainerHigh, 1.0)
        }
    }

    function startResize() {
        if (root.isResizing || root.selectedSizeMb <= 0 || !root.isOptionSelectable(root.selectedSizeMb))
            return;
        root.isResizing = true;
        root.resizeError = "";
        root.resizeSuccess = false;
        root.progressPercent = 2;
        root.progressMessage = Translation.tr("Requesting administrator authorization...");
        resizeProc.command = ["pkexec", root.helperPath, "resize", String(root.selectedSizeMb)];
        resizeProc.running = true;
    }

    Process {
        id: resizeProc
        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (!trimmed) return;
                try {
                    const msg = JSON.parse(trimmed);
                    if (msg.error || msg.step === "error") {
                        root.resizeError = msg.message || Translation.tr("EFI partition expansion failed.");
                        root.isResizing = false;
                        return;
                    }
                    if (msg.percent !== undefined) root.progressPercent = msg.percent;
                    if (msg.message) root.progressMessage = msg.message;
                    if (msg.step === "done") {
                        root.resizeSuccess = true;
                        root.isResizing = false;
                        root.resizeCompleted();
                    }
                } catch (e) {
                    // Ignore non-JSON pkexec chatter
                }
            }
        }
        stderr: StdioCollector { id: resizeErrors }
        onExited: (exitCode) => {
            if (root.isResizing) {
                root.isResizing = false;
                if (exitCode !== 0 && !root.resizeError)
                    root.resizeError = HelperUtils.failureMessage(exitCode, HelperUtils.helperReason(resizeErrors.text, "mainstream-efi-resize"));
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 18

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                implicitWidth: 40
                implicitHeight: 40
                radius: 14
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "developer_board"
                    iconSize: 22
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Expand EFI boot partition")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("More boot space prevents Unified Kernel Image (UKI) and recovery snapshot failures.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── Current Partition Tonal Capsule ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: summaryLayout.implicitHeight + 28
            radius: 17
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: summaryLayout
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Wraps rather than pushing the usage past the box when the text is large.
                    StyledText {
                        Layout.fillWidth: true
                        text: root.efiData ? `${root.efiData.device} on ${root.efiData.mount}` : "/boot/efi"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        text: Translation.tr("%1 of %2 used")
                            .arg(root.targetArea.formatSize(root.efiData ? root.efiData.used : 0))
                            .arg(root.targetArea.formatSize(root.efiData ? (root.efiData.part_bytes ?? root.efiData.total) : 0))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                // Edge-matched usage bar
                Item {
                    id: curUsageTrack
                    Layout.fillWidth: true
                    implicitHeight: 12

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Appearance.surfaces.row
                    }

                    Rectangle {
                        readonly property real ratio: (root.efiData && root.efiData.total > 0)
                            ? Math.min(1, root.efiData.used / root.efiData.total)
                            : 0
                        width: Math.max(8, curUsageTrack.width * ratio)
                        height: parent.height
                        radius: 6
                        color: Appearance.colors.colPrimary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.resizeReason.length > 0

                    MaterialSymbol {
                        text: root.layoutCanResize ? "verified_user" : "info"
                        iconSize: 16
                        color: root.layoutCanResize ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        Layout.alignment: Qt.AlignTop
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.resizeReason
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ── Coupled Segmented Target Size Capsule ───────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !root.isResizing && !root.resizeSuccess

            StyledText {
                text: Translation.tr("Target capacity")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: root.sizeOptions

                    delegate: Rectangle {
                        id: segCard
                        required property var modelData
                        required property int index

                        readonly property bool isCurrent: root.isOptionCurrent(modelData.mb)
                        readonly property bool selectable: root.isOptionSelectable(modelData.mb)
                        readonly property bool selected: selectable && (root.selectedSizeMb === modelData.mb)

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 68

                        // Coupled asymmetric corner radii: 17px outer sweep + 5px coupled inner seam
                        topLeftRadius: index === 0 ? 17 : 5
                        bottomLeftRadius: index === 0 ? 17 : 5
                        topRightRadius: index === (root.sizeOptions.length - 1) ? 17 : 5
                        bottomRightRadius: index === (root.sizeOptions.length - 1) ? 17 : 5

                        opacity: selectable ? 1.0 : 0.48
                        color: selected
                            ? Appearance.colors.colPrimaryContainer
                            : (segMouse.containsMouse && selectable ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

                        Behavior on color {
                            ColorAnimation { duration: 140 }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: segCard.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: segCard.selected ? Font.DemiBold : Font.Medium
                                color: segCard.selected
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: segCard.isCurrent
                                    ? Translation.tr("Current")
                                    : (!segCard.selectable && segCard.modelData.mb < root.currentPartMb
                                        ? Translation.tr("Smaller")
                                        : segCard.modelData.desc)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: segCard.selected
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                            }
                        }

                        MouseArea {
                            id: segMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: segCard.selectable
                            cursorShape: segCard.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.selectedSizeMb = segCard.modelData.mb
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.selectedPlan?.strategy === "tail_btrfs_relocate"
                text: Translation.tr("Boot files and Limine UKI hashes are verified on the new partition before switching /etc/fstab, keeping your existing boot partition intact until cutover.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        // ── Live Progress Capsule ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.isResizing
            implicitHeight: progCol.implicitHeight + 28
            radius: 17
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: progCol
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: root.progressMessage || Translation.tr("Expanding EFI partition...")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        text: `${Math.round(root.progressPercent)}%`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }

                Item {
                    id: progTrack
                    Layout.fillWidth: true
                    implicitHeight: 8

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Appearance.surfaces.row
                    }

                    Rectangle {
                        width: Math.max(8, progTrack.width * (root.progressPercent / 100))
                        height: parent.height
                        radius: 4
                        color: Appearance.colors.colPrimary
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        // ── Result / Error Tonal Pill ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.resizeError !== "" || root.resizeSuccess
            implicitHeight: statusRow.implicitHeight + 24
            radius: 14
            color: root.resizeError !== ""
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colSecondaryContainer

            RowLayout {
                id: statusRow
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10

                MaterialSymbol {
                    text: root.resizeError !== "" ? "error" : "check_circle"
                    iconSize: 20
                    color: root.resizeError !== ""
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.resizeError !== "" ? root.resizeError : root.progressMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.resizeError !== ""
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnSecondaryContainer
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── Action Row ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item { Layout.fillWidth: true }

            RippleButton {
                implicitHeight: 38
                implicitWidth: 104
                enabled: !root.isResizing
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.close()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.resizeSuccess ? Translation.tr("Done") : Translation.tr("Cancel")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
            }

            RippleButton {
                visible: !root.resizeSuccess
                implicitHeight: 38
                implicitWidth: 164
                enabled: !root.isResizing && root.selectedSizeMb > 0 && root.isOptionSelectable(root.selectedSizeMb)
                opacity: enabled ? 1.0 : 0.45
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: root.startResize()

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.selectedSizeMb > 0
                        ? Translation.tr("Expand to %1 GB").arg(root.selectedSizeMb / 1024)
                        : Translation.tr("Unavailable")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
