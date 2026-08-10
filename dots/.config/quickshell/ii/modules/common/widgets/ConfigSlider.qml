import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    id: root
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property bool usePercentTooltip: true
    property real from: slider.from
    property real to: slider.to
    property real textWidth: 120
    // The track fills whatever is left over unless a width is asked for. A row
    // whose label needs the room is better served by a shorter track than by a
    // label written over it.
    property real sliderWidth: 0

    // StyledToolTip reads `hovered` off its parent and counts a parent that has
    // no such property as hovered, so a row without this shows its tooltip for
    // as long as the page is open.
    property bool hovered: hoverHandler.hovered
    HoverHandler { id: hoverHandler }

    // Fires only for a drag or a key press, never for a change that arrived
    // through the value binding. A row saves what the user did from here; the
    // track still follows the bound value either way, so a setting changed
    // elsewhere moves the handle without being written back.
    signal moved()

    RowLayout {
        id: row
        spacing: 10

        OptionalMaterialSymbol {
            id: iconWidget
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        StyledText {
            id: labelWidget
            Layout.preferredWidth: root.textWidth
            text: root.text
            // Cut short rather than allowed to run under the track, so a label
            // that outgrows the width it was given says so instead of colliding.
            elide: Text.ElideRight
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    StyledSlider {
        id: slider
        configuration: StyledSlider.Configuration.XS
        usePercentTooltip: root.usePercentTooltip
        value: root.value
        from: root.from
        to: root.to
        onMoved: root.moved()
        Layout.fillWidth: root.sliderWidth <= 0
        Layout.preferredWidth: root.sliderWidth > 0 ? root.sliderWidth : -1
    }
}