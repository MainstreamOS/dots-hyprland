import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root
    signal modelRequested()
    signal modeRequested()
    signal reasoningRequested()

    implicitHeight: controls.implicitHeight + 16
    radius: 14
    color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94)

    Flickable {
        id: viewport
        anchors.fill: parent
        anchors.margins: 8
        contentWidth: Math.max(width, controls.implicitWidth)
        contentHeight: controls.implicitHeight
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // Reserve the other selectors' full widths, then elide only the model
        // label to fit. Extra sidebar width restores the complete model name.
        RowLayout {
            id: controls
            x: Math.max(0, (viewport.contentWidth - width) / 2)
            width: implicitWidth
            readonly property real fixedWidth: modeIndicator.implicitWidth + reasoningIndicator.implicitWidth + spacing * 2
            spacing: 4

            AiInputBoxIndicator {
                id: modelIndicator
                icon: "api"
                maxTextWidth: Math.max(0, Math.floor(viewport.width - controls.fixedWidth - labelPadding))
                customIcon: Ai.currentModel?.icon ?? ""
                text: (Ai.currentModel?.name || Ai.ollamaSetupEntryName || "").replace(/^Custom:\s*/i, "")
                tooltipText: Translation.tr("Current model: %1\nClick to choose model").arg(text)
                onClicked: root.modelRequested()
            }

            AiInputBoxIndicator {
                id: modeIndicator
                icon: AiModes.icon(AiModes.current)
                text: Translation.tr("Execution Mode")
                tooltipText: Translation.tr("Execution Mode: %1\nClick to choose execution mode").arg(AiModes.name(AiModes.current))
                onClicked: root.modeRequested()
            }

            AiInputBoxIndicator {
                id: reasoningIndicator
                icon: "psychology"
                text: Translation.tr("Reasoning")
                maxTextWidth: 120
                tooltipText: Translation.tr("Reasoning Level: %1\nClick to choose reasoning depth")
                    .arg(Ai.thinkingLevelName(Ai.thinkingLevel))
                onClicked: root.reasoningRequested()
            }
        }
    }
}
