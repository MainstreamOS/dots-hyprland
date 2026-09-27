import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    property bool colorize: false
    property color color
    property string source: ""
    property string iconFolder: Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))  // The folder to check first
    width: 30
    height: 30
    
    Image {
        id: iconImage
        // Tinted, the overlay draws the icon. Left showing, this uncolored
        // copy underneath darkens the overlay's antialiased edges.
        visible: !root.colorize
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: {
            const fullPathWhenSourceIsIconName = iconFolder + "/" + root.source;
            if (iconFolder && fullPathWhenSourceIsIconName) {
                return fullPathWhenSourceIsIconName
            }
            return root.source
        }
        // Asked for in logical pixels, the icon is drawn that small and then
        // stretched by the display's scale, which blurs it.
        sourceSize: {
            const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
            return Qt.size(Math.ceil(root.width * dpr), Math.ceil(root.height * dpr));
        }
    }

    Loader {
        active: root.colorize
        anchors.fill: iconImage
        sourceComponent: ColorOverlay {
            source: iconImage
            color: root.color
        }
    }
}
