import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    Layout.fillWidth: true
    spacing: 2
    property real buttonWidth: 0
    // Every button grows or shrinks by the same amount so that one line of
    // them spans the row exactly, for a row whose ends have to meet the edges
    // of the rows around it. A squeeze that would leave a button less than
    // half its side padding (12, in SelectionGroupButton) is not made, and the
    // row wraps as usual instead.
    property bool justify: false
    // How wide the buttons are on one line at their own size, for a row that
    // is sized to its buttons rather than to the page.
    readonly property real naturalWidth: {
        let total = 0;
        let count = 0;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (child.naturalWidth === undefined || !child.visible)
                continue;
            total += child.naturalWidth;
            count++;
        }
        return total + spacing * Math.max(0, count - 1);
    }
    // A hair short of the edge, so rounding never sends the last button onto
    // a line of its own.
    readonly property real justifyExtra: {
        if (!justify || options.length === 0 || width <= 0)
            return 0;
        const extra = (width - 0.1 - naturalWidth) / options.length;
        return extra < -12 ? 0 : extra;
    }
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null

    signal selected(var newValue)

    Repeater {
        model: root.options
        delegate: SelectionGroupButton {
            id: paletteButton
            required property var modelData
            required property int index
            readonly property real naturalWidth: contentItem.implicitWidth + horizontalPadding * 2
            baseWidth: root.buttonWidth > 0 ? root.buttonWidth : naturalWidth + root.justifyExtra
            onYChanged: {
                if (index === 0) {
                    paletteButton.leftmost = true
                } else {
                    var prev = root.children[index - 1]
                    var thisIsOnNewLine = prev && prev.y !== paletteButton.y
                    paletteButton.leftmost = thisIsOnNewLine
                    prev.rightmost = thisIsOnNewLine
                }
            }
            leftmost: index === 0
            rightmost: index === root.options.length - 1
            buttonIcon: modelData.icon || ""
            buttonText: modelData.displayName
            toggled: root.currentValue == modelData.value
            // An option can be shown without being on offer. Dimmed by its own
            // flag rather than by whether it is enabled, so a row a page has
            // already dimmed as a whole is not dimmed twice.
            enabled: modelData.enabled ?? true
            opacity: (modelData.enabled ?? true) ? 1 : 0.5
            onClicked: {
                root.selected(modelData.value);
            }
        }
    }
}
