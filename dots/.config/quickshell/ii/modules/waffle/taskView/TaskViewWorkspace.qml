import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

WMouseAreaButton {
    id: root

    required property int workspace
    property bool newWorkspace: false
    property bool droppable: false

    readonly property bool isActiveWorkspace: HyprlandData.activeWorkspace?.id === root.workspace
    readonly property real screenWidth: QsWindow.window?.width ?? 0
    readonly property real screenHeight: QsWindow.window?.height ?? 0
    // Hyprland places a window in whole layout coordinates, so a monitor that does
    // not sit at the layout origin hosts windows whose corner is measured from
    // somewhere off this card. Verified: on this layout the second monitor begins
    // at -1080, 120, and its surfaces are reported there.
    readonly property real screenOriginX: QsWindow.window?.screen?.x ?? 0
    readonly property real screenOriginY: QsWindow.window?.screen?.y ?? 0
    readonly property real screenAspectRatio: (screenWidth > 0 && screenHeight > 0) ? (screenWidth / screenHeight) : (16 / 9)
    // The previews are laid out in screen coordinates, so the whole screen has to
    // fit the picture area on both axes. Fitting to height alone squeezes a
    // portrait screen's full width into a strip of a landscape card and lets a
    // preview run off the edge.
    readonly property real windowScale: (screenWidth > 0 && screenHeight > 0 && wsBg.width > 0 && wsBg.height > 0) ? Math.min(wsBg.width / screenWidth, wsBg.height / screenHeight) : 0
    readonly property real windowOffsetX: (wsBg.width - screenWidth * windowScale) / 2
    readonly property real windowOffsetY: (wsBg.height - screenHeight * windowScale) / 2

    property real wallpaperHeight: 124

    height: ListView.view?.height ?? 100
    // The card is the screen drawn small, so its width follows the screen's shape.
    // Measured against the constant picture height rather than the laid out one, so
    // the card never takes its size from a child that is sized by the card. Clamped
    // so a very tall or very wide screen still leaves the label somewhere to sit.
    implicitWidth: Math.round(Math.max(120, Math.min(320, root.wallpaperHeight * root.screenAspectRatio))) + 24

    colBackground: ColorUtils.transparentize(Looks.colors.bg2, (isActiveWorkspace || droppable) ? 0 : 1)
    Behavior on color {
        animation: Looks.transition.color.createObject(this)
    }

    scale: root.containsPress ? 0.95 : 1
    Behavior on scale {
        NumberAnimation {
            id: scaleAnim
            duration: 300
            easing.type: Easing.OutExpo
        }
    }

    // Content
    ColumnLayout {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 12
            topMargin: 9
            bottomMargin: 8
        }
        spacing: 8

        WText {
            Layout.fillWidth: true
            Layout.fillHeight: false
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            text: root.newWorkspace ? Translation.tr("New desktop") : Translation.tr("Desktop %1").arg(root.workspace)
        }

        Rectangle {
            id: wsBg
            height: root.wallpaperHeight
            Layout.fillHeight: true
            Layout.fillWidth: true
            color: Looks.colors.bg1

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: wsBg.width
                    height: wsBg.height
                    radius: Looks.radius.medium
                }
            }

            // Workspace content
            Loader {
                anchors.fill: parent
                active: !root.newWorkspace
                sourceComponent: StyledImage {
                    cache: true
                    source: Config.options.background.wallpaperPath
                    fillMode: Image.PreserveAspectCrop

                    Repeater {
                        model: ScriptModel {
                            values: HyprlandData.toplevelsForWorkspace(root.workspace)
                        }
                        delegate: ScreencopyView {
                            required property var modelData
                            readonly property var hyprlandWindowData: HyprlandData.windowByAddress[`0x${modelData.HyprlandToplevel?.address}`]
                            captureSource: modelData
                            live: true
                            width: hyprlandWindowData?.size[0] * root.windowScale
                            height: hyprlandWindowData?.size[1] * root.windowScale
                            x: (hyprlandWindowData?.at[0] - root.screenOriginX) * root.windowScale + root.windowOffsetX
                            y: (hyprlandWindowData?.at[1] - root.screenOriginY) * root.windowScale + root.windowOffsetY
                        }
                    }
                }
            }

            // New plus icon
            Loader {
                anchors.centerIn: parent
                active: root.newWorkspace
                sourceComponent: FluentIcon {
                    icon: "add"
                }
            }

            Rectangle {
                z: 2
                visible: root.droppable && !root.newWorkspace
                anchors.fill: parent
                color: Looks.colors.accent
                opacity: 0.2
            }
        }
    }

    // Active indicator
    WFadeLoader {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
        }
        shown: root.isActiveWorkspace

        sourceComponent: Rectangle {
            id: activeIndicator
            implicitWidth: 32
            implicitHeight: 3
            color: Looks.colors.accent
            radius: height / 2
        }
    }
}
