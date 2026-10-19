import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * A floating reaction bar that pops up when a message is held or right-clicked.
 * Provides quick emoji reactions and message copy actions.
 */
Rectangle {
    id: root
    property var targetMessage: null
    readonly property string activeEmoji: {
        if (!targetMessage || !targetMessage.reactions) return "";
        const my = targetMessage.reactions.find(r => r.outgoing);
        return my ? my.emoji : "";
    }
    property string link: ""

    signal react(string emoji)
    signal reply()
    signal copyText()
    signal copyLink()
    signal triggerPop()

    onVisibleChanged: {
        if (visible) triggerPop();
    }
    Component.onCompleted: triggerPop()

    implicitWidth: contentRow.implicitWidth + 16
    implicitHeight: 46
    radius: Appearance.rounding.full
    color: Appearance.m3colors.m3surfaceContainerHighest

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: [
                { emoji: "❤️", asset: "heart" },
                { emoji: "😂", asset: "joy" },
                { emoji: "😮", asset: "wow" },
                { emoji: "😢", asset: "cry" },
                { emoji: "👍", asset: "thumbs_up" },
                { emoji: "👎", asset: "thumbs_down" }
            ]
            delegate: Item {
                id: emojiItem
                required property var modelData
                required property int index
                readonly property string emojiChar: modelData.emoji
                readonly property string assetName: modelData.asset
                readonly property bool isActive: root.activeEmoji === emojiChar
                implicitWidth: 34
                implicitHeight: 34
                z: hoverHandler.hovered ? 5 : (isActive ? 2 : 1)

                property real popScale: 0.0
                property real popY: 8.0

                SequentialAnimation {
                    id: popAnim
                    PauseAnimation { duration: emojiItem.index * 32 }
                    ScriptAction {
                        script: {
                            if (animEmoji) {
                                animEmoji.currentFrame = 0;
                                animEmoji.playing = true;
                            }
                        }
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: emojiItem
                            property: "popScale"
                            from: 0.0
                            to: 1.0
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                        NumberAnimation {
                            target: emojiItem
                            property: "popY"
                            from: 8.0
                            to: 0.0
                            duration: 180
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                Connections {
                    target: root
                    function onTriggerPop() {
                        emojiItem.popScale = 0.0;
                        emojiItem.popY = 8.0;
                        if (animEmoji) {
                            animEmoji.playing = false;
                            animEmoji.currentFrame = 0;
                        }
                        popAnim.restart();
                    }
                }

                Rectangle {
                    id: bg
                    anchors.fill: parent
                    transform: Translate { y: emojiItem.popY }
                    radius: Appearance.rounding.full
                    color: emojiItem.isActive ? Appearance.colors.colSecondaryContainer :
                        hoverHandler.hovered ? Appearance.colors.colLayer1Hover : "transparent"

                    scale: emojiItem.popScale * (hoverHandler.hovered ? 1.25 : (mouseArea.pressed ? 0.92 : 1.0))
                    Behavior on scale {
                        enabled: !popAnim.running
                        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                    }

                    AnimatedImage {
                        id: animEmoji
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        mipmap: true
                        smooth: true
                        source: Quickshell.shellPath(`assets/emojis/${emojiItem.assetName}.webp`)
                        fillMode: Image.PreserveAspectFit
                        loops: 1
                        playing: false
                        asynchronous: true
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: animEmoji.status !== Image.Ready
                        text: emojiItem.emojiChar
                        font.pixelSize: Appearance.font.pixelSize.larger
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.react(emojiItem.emojiChar)
                    }

                    StyledToolTip {
                        extraVisibleCondition: hoverHandler.hovered
                        text: emojiItem.isActive ? Translation.tr("Remove %1").arg(emojiItem.emojiChar) : emojiItem.emojiChar
                    }
                }
            }
        }

        Item {
            implicitWidth: 4
        }

        RippleButton {
            id: replyBtn
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colSecondaryContainer
            onClicked: root.reply()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "reply"
                iconSize: Appearance.font.pixelSize.normal
                color: replyBtn.hovered ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: Translation.tr("Reply")
            }
        }

        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            onClicked: root.copyText()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "content_copy"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: Translation.tr("Copy text")
            }
        }

        RippleButton {
            visible: root.link.length > 0
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer1Hover
            onClicked: root.copyLink()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "link"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: Translation.tr("Copy link")
            }
        }
    }
}
