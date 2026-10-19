pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../../services/IslandText.js" as TextFormatting

Rectangle {
    id: root
    property string text: ""
    property bool markup: false
    property var images: []
    property var audioClips: []
    property bool imagesOnRight: false
    readonly property color ink: Appearance.colors.colOnLayer0
    readonly property bool hasAudio: root.audioClips && root.audioClips.length > 0
    readonly property bool hasTextOrAudio: (root.text && root.text.length > 0) || root.hasAudio
    readonly property bool hasImageSources: root.images && root.images.some(source => typeof source === "string" && source.trim().length > 0)
    readonly property bool hasImages: !!leftImageLoader.item?.hasImages || !!rightImageLoader.item?.hasImages
    readonly property bool isAudioOnly: root.hasAudio && (!root.text || root.text.length === 0) && !root.hasImages
    implicitHeight: root.isAudioOnly ? 70 : 104
    radius: 12
    color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
    RowLayout {
        anchors.fill: parent
        anchors.topMargin: root.isAudioOnly ? 8 : 10
        anchors.bottomMargin: root.isAudioOnly ? 8 : 10
        anchors.leftMargin: root.isAudioOnly ? 10 : 10
        anchors.rightMargin: root.isAudioOnly ? 10 : 10
        spacing: 12
        Loader {
            id: leftImageLoader
            active: root.hasImageSources && !root.imagesOnRight
            visible: active && !!item?.hasImages
            Layout.fillWidth: !root.hasTextOrAudio
            Layout.fillHeight: false
            Layout.preferredWidth: root.hasTextOrAudio
                ? (root.images.length > 1 ? Math.min(180, item?.implicitWidth ?? 84) : Math.min(84, root.height - 20))
                : -1
            Layout.maximumWidth: root.hasTextOrAudio ? 180 : -1
            Layout.preferredHeight: Math.min(84, root.height - 20)
            Layout.alignment: root.hasTextOrAudio ? Qt.AlignTop : Qt.AlignCenter
            sourceComponent: imageStripComponent
        }
        ScrollView {
            id: scroll
            visible: root.hasTextOrAudio || !root.hasImages
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            clip: !root.isAudioOnly
            contentWidth: availableWidth
            ScrollBar.vertical.policy: root.isAudioOnly ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: contentCol
                width: scroll.availableWidth
                y: (!root.text && root.hasAudio && height < scroll.availableHeight)
                    ? Math.round((scroll.availableHeight - height) / 2) : 0
                spacing: root.isAudioOnly ? 4 : 8
                Repeater {
                    model: root.audioClips
                    MessageAudioClip {
                        required property var modelData
                        Layout.fillWidth: true
                        attachment: modelData
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: text.length > 0 && (!root.hasAudio || root.text.length > 0)
                    text: root.text.length > 0
                        ? TextFormatting.body(root.text, root.markup)
                        : (!root.hasImages && !root.hasAudio ? Translation.tr("Media message") : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    lineHeight: 1.2
                    font.pixelSize: 13
                    color: Appearance.colors.colOnLayer0
                    verticalAlignment: Text.AlignTop
                }
            }
        }
        Loader {
            id: rightImageLoader
            active: root.hasImageSources && root.imagesOnRight
            visible: active && !!item?.hasImages
            Layout.fillWidth: !root.hasTextOrAudio
            Layout.fillHeight: false
            Layout.preferredWidth: root.hasTextOrAudio
                ? (root.images.length > 1 ? Math.min(180, item?.implicitWidth ?? 84) : Math.min(84, root.height - 20))
                : -1
            Layout.maximumWidth: root.hasTextOrAudio ? 180 : -1
            Layout.preferredHeight: Math.min(84, root.height - 20)
            Layout.alignment: root.hasTextOrAudio ? Qt.AlignTop : Qt.AlignCenter
            sourceComponent: imageStripComponent
        }
    }
    Component {
        id: imageStripComponent
        ImageStrip {
            images: root.images
            square: true
        }
    }
}
