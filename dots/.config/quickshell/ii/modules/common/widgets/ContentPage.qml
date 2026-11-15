import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600 * Appearance.font.roomGrowth
    property bool forceWidth: false
    property real bottomContentPadding: 100
    property alias sectionSpacing: contentColumn.spacing
    property Item searchTarget: null
    property var searchRequest: null

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

    function revealSetting(label, sections) {
        root.searchRequest = {label, sections};
        root.searchTarget = null;
        searchSettle.restart();
        root.resolveSearchTarget();
    }

    function resolveSearchTarget() {
        if (!root.visible || root.moving) return;
        const request = root.searchRequest;
        if (!request) {
            root.positionSearchTarget();
            return;
        }
        let group = contentColumn;
        for (const section of request.sections) {
            const found = root.findSearchItem(group, child => child !== group && child.title === section);
            if (!found) break;
            group = found;
        }
        const target = root.findSearchItem(group, child =>
            [child.searchLabel, child.title, child.text, child.buttonText, child.mainText, child.label].includes(request.label));
        const next = target || (group !== contentColumn ? group : null);
        if (next !== root.searchTarget && next)
            searchHighlight.restart();
        root.searchTarget = next;
        if (target)
            root.searchRequest = null;
        root.positionSearchTarget();
    }

    function findSearchItem(start, matches) {
        const stack = [start];
        while (stack.length) {
            const child = stack.pop();
            if (!child.visible) continue;
            if (matches(child)) return child;
            for (let i = child.children.length - 1; i >= 0; i--)
                stack.push(child.children[i]);
        }
        return null;
    }

    function positionSearchTarget() {
        if (!root.searchTarget) return;
        const rect = root.searchTarget.mapToItem(root.contentItem, 0, 0,
            root.searchTarget.width, root.searchTarget.height);
        searchOutline.x = rect.x - 4;
        searchOutline.y = rect.y - 3;
        searchOutline.width = rect.width + 8;
        searchOutline.height = Math.min(rect.height, 70) + 6;
        if (searchOutline.y >= root.contentY && searchOutline.y + searchOutline.height <= root.contentY + root.height)
            return;
        root.contentY = Math.max(0, Math.min(rect.y - 18, root.contentHeight - root.height));
    }

    // Repeated rows and storage scans can populate sections after the page loads.
    onContentHeightChanged: if (searchSettle.running) Qt.callLater(root.resolveSearchTarget)
    onMovementStarted: {
        searchSettle.stop();
        root.searchRequest = null;
    }
    property Timer searchSettle: Timer {
        interval: 3000
        onTriggered: {
            root.resolveSearchTarget();
            root.searchRequest = null;
        }
    }
    property Timer searchHighlight: Timer {
        interval: 3000
        onTriggered: root.searchTarget = null
    }
    property Rectangle searchOutline: Rectangle {
        parent: root.contentItem
        visible: root.searchTarget !== null
        z: 1
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colPrimary
        radius: Appearance.rounding.small
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
