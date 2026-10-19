import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell

SheetBase {
    id: root

    readonly property var levels: Ai.getModelThinkingLevels(Ai.currentModel) || []

    function isCurrentLevel(id: string): bool {
        const current = (Ai.thinkingLevel || "").toLowerCase();
        if (id === "auto")
            return current === "" || current === "auto" || current === "default";
        return current === id;
    }

    function levelIcon(id: string): string {
        switch (id) {
            case "none": return "block";
            case "minimal": return "speed";
            case "low": return "speed";
            case "medium": return "tune";
            case "high": return "psychology";
            case "extra": return "bolt";
            case "max": return "workspace_premium";
            case "ultracode": return "auto_awesome";
            default: return "auto_mode";
        }
    }

    function open(): void {
        const idx = root.levels.findIndex(level => root.isCurrentLevel(level.id));
        levelListView.currentIndex = Math.max(0, idx);
        root.show(null);
    }

    function selectLevel(id: string): void {
        Ai.setThinkingLevel(id === "auto" ? "" : id, false);
        root.close();
    }

    maxCardHeight: 460
    icon: "psychology"
    title: Translation.tr("Reasoning Effort")
    subtitle: Translation.tr("Thinking depth for %1").arg(Ai.currentModel?.name ?? "AI")

    navList: levelListView

    onRowActivated: index => root.selectLevel(root.levels[index].id)

    // Reasoning Level List
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 14
        color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.55)
        StyledListView {
            id: levelListView
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            spacing: 6

            model: ScriptModel {
                values: root.levels
            }

            delegate: SheetOptionRow {
                required property var modelData

                iconName: root.levelIcon(modelData.id)
                name: modelData.name
                description: modelData.desc ?? ""
                selected: root.isCurrentLevel(modelData.id)
                sheetShown: root.shown

                onClicked: root.selectLevel(modelData.id)
            }
        }
    }

    // Footer note
    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Controls extended thinking budget and verification effort.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }
}
