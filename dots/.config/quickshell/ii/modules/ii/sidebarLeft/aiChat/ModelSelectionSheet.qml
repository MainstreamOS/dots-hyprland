import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell

SheetBase {
    id: root

    property string searchQuery: ""

    readonly property var filteredModels: {
        const list = Ai.modelList || [];
        const query = root.searchQuery;
        return list.filter(id => {
            const m = Ai.models[id];
            if (!m) return false;
            if (!query) return true;
            const name = (m.name || id).toLowerCase();
            const desc = (m.description || "").toLowerCase();
            return name.includes(query) || desc.includes(query) || id.toLowerCase().includes(query);
        });
    }

    function open(): void {
        searchField.text = "";
        modelListView.currentIndex = Math.max(0, root.filteredModels.indexOf(Ai.currentModelId));
        root.show(searchField.input);
    }

    function selectModel(id: string): void {
        Ai.setModel(id, false, true, true);
        root.close();
    }

    maxCardHeight: 520
    icon: "neurology"
    title: Translation.tr("Select AI Model")
    inputField: searchField.input
    filterField: searchField.input
    navList: modelListView

    onRowActivated: index => root.selectModel(root.filteredModels[index])

    // Search Bar
    SheetSearchField {
        id: searchField
        Layout.fillWidth: true
        placeholder: Translation.tr("Filter models…")
        clearable: true

        onTextChanged: {
            root.searchQuery = text.trim().toLowerCase();
            modelListView.currentIndex = 0;
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 14
        color: Appearance.surfaces.row

        // Model List
        StyledListView {
            id: modelListView
            anchors.fill: parent
            anchors.margins: 6
            visible: root.filteredModels.length > 0
            clip: true
            spacing: 6

            model: ScriptModel {
                values: root.filteredModels
            }

            delegate: RippleButton {
                id: modelItemButton
                required property var modelData
                required property int index

                readonly property var modelObj: Ai.models[modelData]
                readonly property bool isCurrent: Ai.currentModelId === modelData
                readonly property bool isFocused: modelListView.currentIndex === index && root.shown
                readonly property bool isPlan: Ai.apiStrategies[modelObj?.api_format]?.isCliStrategy ?? false

                width: modelListView.width
                implicitHeight: Math.max(64, itemRow.implicitHeight + 20)
                buttonRadius: 10
                colBackground: isCurrent ? Appearance.colors.colSecondaryContainer
                    : isFocused ? Appearance.colors.colLayer2Hover : "transparent"
                colBackgroundHover: isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                Accessible.name: modelObj?.name ?? modelData
                Accessible.description: modelObj?.description ?? ""

                onClicked: root.selectModel(modelData)

                contentItem: RowLayout {
                    id: itemRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 10

                    // Icon
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 10
                        color: modelItemButton.isCurrent
                            ? ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.9)
                            : Appearance.colors.colLayer2
                        Layout.alignment: Qt.AlignVCenter

                        CustomIcon {
                            id: cIcon
                            anchors.centerIn: parent
                            visible: !!(modelItemButton.modelObj && modelItemButton.modelObj.icon)
                            width: 22
                            height: 22
                            source: (modelItemButton.modelObj && modelItemButton.modelObj.icon) ? modelItemButton.modelObj.icon : ""
                            colorize: true
                            color: modelItemButton.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !cIcon.visible
                            text: modelItemButton.isPlan ? "bolt" : "api"
                            iconSize: Appearance.font.pixelSize.larger
                            color: modelItemButton.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                        }
                    }

                    // Name & Description
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: (modelItemButton.modelObj && modelItemButton.modelObj.name) ? modelItemButton.modelObj.name : modelItemButton.modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: modelItemButton.isCurrent ? Font.Bold : Font.DemiBold
                                color: modelItemButton.isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.m3colors.m3onSurface
                            }

                            // Plan / Format pill
                            Rectangle {
                                visible: modelItemButton.isPlan
                                implicitHeight: 16
                                implicitWidth: planText.implicitWidth + 8
                                radius: 8
                                color: Appearance.colors.colPrimaryContainer

                                StyledText {
                                    id: planText
                                    anchors.centerIn: parent
                                    text: Translation.tr("Subscription")
                                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const raw = (modelItemButton.modelObj && modelItemButton.modelObj.description) ? modelItemButton.modelObj.description : "";
                                const newline = raw.indexOf("\n");
                                const firstLine = newline >= 0 ? raw.slice(0, newline) : raw;
                                return firstLine.replace(/^Online\s*\|\s*/, "");
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: modelItemButton.isCurrent
                                ? ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.18)
                                : Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    // Selected checkmark
                    MaterialSymbol {
                        visible: modelItemButton.isCurrent
                        text: "check_circle"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        SheetEmptyState {
            anchors.centerIn: parent
            visible: root.filteredModels.length === 0
            icon: "search_off"
            title: Translation.tr("No matching models")
            subtitle: Translation.tr("Try a different search query.")
        }
    }

    // Footer
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Commands: /model <name> · /mode [ask|auto|plan]")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        RippleButton {
            implicitHeight: 28
            implicitWidth: refreshRow.implicitWidth + 12
            topPadding: 0
            bottomPadding: 0
            leftPadding: 6
            rightPadding: 6
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover

            contentItem: Item {
                RowLayout {
                    id: refreshRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Ollama")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            onClicked: Ai.fetchOllamaModels()
            StyledToolTip {
                text: Translation.tr("Refresh local Ollama models")
            }
        }
    }
}
