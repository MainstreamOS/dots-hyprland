pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import QtQuick.Layouts

// Thought text between activity rows, with its original indentation.
Item {
    id: root
    required property string text
    property bool renderMarkdown: true
    property bool enableMouseSelection: false

    // Text wrapped before the layout gives it a width stands one word per line,
    // so the text is set only once the width is known.
    readonly property bool sized: root.width > 0

    Layout.fillWidth: true
    implicitHeight: root.sized ? paragraphText.implicitHeight : 0

    TextEdit {
        id: paragraphText
        anchors.left: parent.left
        anchors.right: parent.right
        readOnly: true
        selectByMouse: root.enableMouseSelection
        renderType: Text.NativeRendering
        font.family: Appearance.font.family.reading
        font.pixelSize: Appearance.font.pixelSize.small
        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
        selectionColor: Appearance.colors.colSecondaryContainer
        wrapMode: TextEdit.Wrap
        color: Appearance.colors.colSubtext
        textFormat: root.renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
        text: root.sized ? root.text : ""
        onLinkActivated: (link) => linkArea.activate(link)

        MessageLinkArea {
            id: linkArea
            textItem: paragraphText
            selectable: root.enableMouseSelection
        }
    }
}
