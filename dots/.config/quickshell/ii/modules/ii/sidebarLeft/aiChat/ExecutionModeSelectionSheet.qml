import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

SheetBase {
    id: root

    signal modeSelected(string mode)

    readonly property var modes: AiModes.ids.map(id => ({
        id: id,
        name: AiModes.name(id),
        desc: AiModes.description(id),
        icon: AiModes.icon(id)
    }))

    function open(): void {
        modeListView.currentIndex = Math.max(0, AiModes.ids.indexOf(AiModes.current));
        root.show(null);
    }

    function selectMode(id: string): void {
        root.modeSelected(id);
        root.close();
    }

    maxCardHeight: 370
    icon: AiModes.icon(AiModes.current)
    title: Translation.tr("Execution Mode")
    subtitle: Translation.tr("Tool and command execution behavior")

    navList: modeListView

    onRowActivated: index => root.selectMode(root.modes[index].id)

    // Mode List
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 14
        color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.55)
        StyledListView {
            id: modeListView
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            spacing: 6

            model: root.modes

            delegate: SheetOptionRow {
                required property var modelData

                iconName: modelData.icon
                name: modelData.name
                description: modelData.desc
                selected: AiModes.current === modelData.id
                sheetShown: root.shown

                onClicked: root.selectMode(modelData.id)
            }
        }
    }

    // Footer note
    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Click to select tool approval and execution mode.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }
}
