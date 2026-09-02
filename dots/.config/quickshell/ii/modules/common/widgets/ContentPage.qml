import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: 100

    default property alias contentData: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth

    // Deep links can name a section: settings.qml reads QS_SETTINGS_SECTION
    // and hands the name to the loaded page. Sections are direct children of
    // the content column by construction (the contentData default alias), so
    // one level is the whole search space. Returns whether it was found.
    function scrollToSection(name) {
        for (let i = 0; i < contentColumn.children.length; i++) {
            const child = contentColumn.children[i];
            if (child.objectName === name) {
                root.contentY = Math.max(0, Math.min(child.y, root.contentHeight - root.height));
                return true;
            }
        }
        return false;
    }
    
    ColumnLayout {
        id: contentColumn
        width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: 20
        }
        spacing: 30
    }

}
