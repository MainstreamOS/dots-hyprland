pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    required property var attachment
    readonly property color contentColor: Appearance.islandContent.colOnLayer1
    readonly property bool current: IslandMessageAudio.currentKey === IslandMessageAudio.key(attachment)
    readonly property bool loading: current && IslandMessageAudio.loading
    readonly property bool playing: current && IslandMessageAudio.playing
    readonly property real duration: current ? IslandMessageAudio.duration : 0
    readonly property bool playable: Boolean(attachment?.deviceId && attachment?.uid && attachment?.part !== undefined && attachment.part >= 0)

    property string saveResult: ""
    readonly property bool saveBusy: Phone.attachmentBusy(root.attachment?.uid ?? "", root.attachment?.deviceId)

    function showSaveResult(res): void {
        root.saveResult = res;
        saveIconPop.restart();
        saveResetTimer.restart();
    }

    SequentialAnimation {
        id: saveIconPop
        NumberAnimation { target: saveIcon; property: "scale"; to: 1.35; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: saveIcon; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack }
    }

    Timer {
        id: saveResetTimer
        interval: 1800
        onTriggered: root.saveResult = ""
    }

    Connections {
        target: Phone
        function onLastSaveChanged() {
            const save = Phone.lastSave;
            if (save && save.uid === root.attachment?.uid) root.showSaveResult(save.ok ? "done" : "failed");
        }
    }

    spacing: 3

    RowLayout {
        Layout.fillWidth: true
        spacing: 5

        MaterialSymbol {
            text: (root.current && IslandMessageAudio.error) ? "error" : "mic"
            iconSize: 14
            color: (root.current && IslandMessageAudio.error) ? Appearance.islandContent.colErrorMark : Appearance.islandContent.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            text: (root.current && IslandMessageAudio.error)
                ? IslandMessageAudio.error
                : (root.loading ? Translation.tr("Loading audio clip…") : Translation.tr("Audio clip"))
            font.pixelSize: 11
            font.weight: Font.Medium
            elide: Text.ElideRight
            color: (root.current && IslandMessageAudio.error) ? Appearance.islandContent.colErrorMark : Appearance.islandContent.colOnSurfaceVariant
        }

        StyledText {
            text: {
                if (root.current && IslandMessageAudio.duration > 0) {
                    return StringUtils.friendlyTimeForSeconds(IslandMessageAudio.position / 1000)
                        + " / " + StringUtils.friendlyTimeForSeconds(IslandMessageAudio.duration / 1000);
                }
                const dur = Phone.durationFor(root.attachment);
                return dur > 0 ? StringUtils.friendlyTimeForSeconds(dur / 1000) : "";
            }
            font.pixelSize: 10
            font.features: {"tnum": 1}
            color: Appearance.islandContent.colOnSurfaceVariant
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        RippleButton {
            implicitWidth: 32
            implicitHeight: 32
            topPadding: 0
            bottomPadding: 0
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.contentColor, 0.88)
            colBackgroundHover: ColorUtils.transparentize(root.contentColor, 0.8)
            enabled: root.playable && (!IslandMessageAudio.fetching || root.current)
            Accessible.name: root.loading ? Translation.tr("Cancel loading audio clip") : root.playing ? Translation.tr("Pause audio clip") : Translation.tr("Play audio clip")
            onClicked: IslandMessageAudio.toggle(root.attachment)
            contentItem: Item {
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.loading
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: root.contentColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.loading
                    implicitSize: 22
                    loading: visible
                }
            }
            StyledToolTip {
                text: !root.playable ? Translation.tr("Audio clip unavailable") : root.loading ? Translation.tr("Cancel loading audio clip") : root.playing ? Translation.tr("Pause") : Translation.tr("Play")
            }
        }

        StyledSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            configuration: StyledSlider.Configuration.Wavy
            animateWave: root.playing
            enabled: root.current && root.duration > 0
            usePercentTooltip: false
            tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.duration / 1000)
            value: root.duration > 0 ? IslandMessageAudio.position / root.duration : 0
            onMoved: IslandMessageAudio.seek(value)
        }

        RippleButton {
            id: downloadBtn
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.contentColor, 0.9)
            colBackgroundHover: ColorUtils.transparentize(root.contentColor, 0.8)
            scale: down ? 0.88 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            onClicked: {
                root.saveResult = "";
                Phone.useAttachment(root.attachment, "save", root.attachment.deviceId);
            }
            contentItem: Item {
                anchors.fill: parent
                MaterialSymbol {
                    id: saveIcon
                    anchors.centerIn: parent
                    visible: !root.saveBusy
                    text: root.saveResult === "done" ? "check" : root.saveResult === "failed" ? "error" : "download"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.saveResult === "failed" ? Appearance.islandContent.colErrorMark : root.contentColor
                }
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.saveBusy
                    implicitSize: 20
                    loading: visible
                }
            }
            StyledToolTip {
                text: Translation.tr("Save to Downloads")
            }
        }
    }
}
