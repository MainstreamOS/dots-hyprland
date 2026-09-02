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

    // Deep links can name a section, not just a page: the settings window
    // stores QS_SETTINGS_SECTION as pendingSettingsSection, and whichever
    // page first contains a child with that objectName scrolls to it and
    // consumes the request, so later page visits stay at the top.
    function _findSection(item, name, depth) {
        if (depth > 4) return null;
        for (let i = 0; i < item.children.length; i++) {
            const child = item.children[i];
            if (child.objectName === name) return child;
            const found = _findSection(child, name, depth + 1);
            if (found) return found;
        }
        return null;
    }
    function _jumpToPendingSection() {
        const win = root.Window.window;
        if (!win || !("pendingSettingsSection" in win) || !win.pendingSettingsSection) return;
        const target = _findSection(contentColumn, win.pendingSettingsSection, 0);
        if (!target) return;
        win.pendingSettingsSection = "";
        const y = target.mapToItem(contentColumn, 0, 0).y;
        root.contentY = Math.max(0, Math.min(y, root.contentHeight - root.height));
    }
    Component.onCompleted: Qt.callLater(_jumpToPendingSection)
    Timer {
        // Sections below asynchronously sized content settle a beat after
        // load, so one late re-apply catches the final layout.
        interval: 250
        running: true
        repeat: false
        onTriggered: root._jumpToPendingSection()
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
