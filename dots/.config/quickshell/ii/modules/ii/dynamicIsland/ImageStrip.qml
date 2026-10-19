pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell.Widgets
import qs.modules.common

Flickable {
    id: root
    property var images: []
    property bool square: true
    property int readyImageCount: 0
    readonly property bool hasImages: readyImageCount > 0

    function refreshImages(): void {
        let count = 0;
        for (let i = 0; i < imageRepeater.count; i++) {
            if (imageRepeater.itemAt(i)?.ready) count++;
        }
        root.readyImageCount = count;
    }

    implicitHeight: 84
    implicitWidth: previews.width
    contentWidth: Math.max(width, previews.width)
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Row {
        id: previews
        x: Math.max(0, (root.width - previews.width) / 2)
        height: root.height
        spacing: 8
        Repeater {
            id: imageRepeater
            model: (root.images || []).filter(source => typeof source === "string" && source.trim().length > 0)
            onItemAdded: Qt.callLater(root.refreshImages)
            onItemRemoved: Qt.callLater(root.refreshImages)
            ClippingRectangle {
                id: preview
                required property string modelData
                readonly property bool ready: img.status === Image.Ready
                visible: ready
                onReadyChanged: Qt.callLater(root.refreshImages)
                readonly property string imageSource: {
                    const source = preview.modelData;
                    if (source.startsWith("image://icon//")) return "file://" + source.slice("image://icon".length);
                    if (source.startsWith("/") && !source.startsWith("//")) return "file://" + source;
                    return source;
                }
                readonly property size decodeSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)),
                    Math.max(1, Math.ceil(height * Screen.devicePixelRatio)))
                readonly property real aspect: (img.implicitWidth > 0 && img.implicitHeight > 0)
                    ? (img.implicitWidth / img.implicitHeight) : 1.0
                width: root.square ? root.height : (root.images.length === 1
                    ? Math.max(56, Math.min(root.width > 0 ? root.width : 280, Math.round(root.height * aspect)))
                    : Math.max(56, Math.min(140, Math.round(root.height * aspect))))
                height: root.height
                radius: 10
                // Transparent artwork already carries its own silhouette.
                // Keep the rounded crop for photos without painting a tile
                // into the transparent corners of circular contact pictures.
                color: "transparent"

                Image {
                    id: img
                    anchors.fill: parent
                    source: preview.imageSource
                    sourceSize: preview.decodeSize
                    autoTransform: true
                    visible: !animation.item || animation.item.status !== Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    horizontalAlignment: Image.AlignHCenter
                    verticalAlignment: Image.AlignVCenter
                    smooth: true
                    // QIcon providers must be read on the GUI thread.
                    asynchronous: !preview.imageSource.startsWith("image://")
                    cache: true
                }

                Loader {
                    id: animation
                    anchors.fill: parent
                    active: img.status === Image.Ready && img.frameCount > 1
                    sourceComponent: AnimatedImage {
                        source: preview.imageSource
                        sourceSize: preview.decodeSize
                        autoTransform: true
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: true
                        playing: root.visible
                    }
                }
            }
        }
    }
}
