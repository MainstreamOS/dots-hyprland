import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A searchable dropdown over keyboard layouts: the current pick in a field,
// a popup with a search box and the filtered list beneath it.
Item {
    id: picker

    // The list to offer, the identity that tells two entries apart, and
    // whether the catalog behind them has arrived — all handed in, so this
    // stays a picker over anything shaped like a layout rather than a reader
    // of one particular section's state.
    property var options: []
    property var layoutIdOf: layout => ""
    property bool ready: false
    property string searchPlaceholder: Translation.tr("Search layouts…")
    implicitHeight: 40
    enabled: picker.ready && picker.options.length > 0

    property string selectedId: ""
    readonly property var selectedLayout: options.find(layout => picker.layoutIdOf(layout) === selectedId)

    onOptionsChanged: {
        if (!options.some(layout => picker.layoutIdOf(layout) === selectedId))
            selectedId = options.length > 0 ? picker.layoutIdOf(options[0]) : ""
    }

    Rectangle {
        id: layoutPickerField
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: fieldArea.containsMouse && picker.enabled
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colSecondaryContainer

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: picker.selectedLayout
                    ? picker.selectedLayout.code + " — " + picker.selectedLayout.name
                    : picker.ready
                        ? Translation.tr("All layouts enabled")
                        : Translation.tr("Loading layouts…")
                color: Appearance.colors.colOnSecondaryContainer
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
                rotation: layoutPickerPopup.visible ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        MouseArea {
            id: fieldArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: picker.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                layoutSearchField.text = ""
                const overlay = Overlay.overlay
                const topY = layoutPickerField.mapToItem(overlay, 0, 0).y
                const overlayHeight = overlay ? overlay.height : 750
                const spaceBelow = overlayHeight - (topY + layoutPickerField.height) - 8
                const spaceAbove = topY - 8
                layoutPickerPopup.dropUp = spaceBelow < 340 && spaceAbove > spaceBelow
                layoutPickerPopup.availH = Math.min(340, layoutPickerPopup.dropUp ? spaceAbove : spaceBelow)
                layoutPickerPopup.open()
            }
        }
    }

    Popup {
        id: layoutPickerPopup
        property bool dropUp: false
        property real availH: 340
        y: dropUp ? -(height + 4) : (layoutPickerField.height + 4)
        width: layoutPickerField.width
        height: availH
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: layoutSearchField.forceActiveFocus()

        background: Item {
            StyledRectangularShadow { target: layoutPopupBackground }
            Rectangle {
                id: layoutPopupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 6

            MaterialTextField {
                id: layoutSearchField
                Layout.fillWidth: true
                placeholderText: picker.searchPlaceholder
            }

            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                animateAppearance: false
                model: {
                    const query = layoutSearchField.text.trim().toLowerCase()
                    if (query.length === 0)
                        return picker.options
                    return picker.options.filter(layout =>
                        layout.code.toLowerCase().includes(query)
                        || layout.name.toLowerCase().includes(query))
                }
                delegate: Rectangle {
                    id: layoutOption
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: 38
                    radius: Appearance.rounding.small
                    color: picker.layoutIdOf(layoutOption.modelData) === picker.selectedId
                        ? Appearance.colors.colSecondaryContainer
                        : layoutOptionArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: layoutOption.modelData.code + " — " + layoutOption.modelData.name
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        MaterialSymbol {
                            visible: picker.layoutIdOf(layoutOption.modelData) === picker.selectedId
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }
                    }

                    MouseArea {
                        id: layoutOptionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            picker.selectedId = picker.layoutIdOf(layoutOption.modelData)
                            layoutPickerPopup.close()
                        }
                    }
                }
            }
        }
    }
}
