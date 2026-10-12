pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overview
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import "layout.js" as Layout

Item {
    id: root
    required property var controller
    required property int workspaceId
    required property var monitor
    required property string screenName
    property bool current: false
    property bool nearby: false
    property real progress: 1
    readonly property var clients: controller.clients.filter(w => w.workspace.id === workspaceId
        && controller.matches(w))
    readonly property real inset: Math.max(24, Math.min(width, height) * 0.035)
    readonly property var positions: !nearby ? ({}) : Layout.arrange(clients, width - inset * 2, height - inset * 2, 40, 46)
    // Whether the wallpaper and the window captures can be drawn yet.
    function ready(): bool {
        if (!wallpaperBackdrop.ready) return false;
        for (let i = 0; i < tiles.count; i++) {
            if (tiles.itemAt(i)?.waiting) return false;
        }
        return true;
    }

    Rectangle {
        id: backdrop
        anchors.fill: parent
        radius: RoundedCorners.on ? Appearance.rounding.large * (root.current ? root.progress : 1) : 0
        color: Appearance.colors.colLayer1
        layer.enabled: root.nearby
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
        Rectangle {
            id: mask
            anchors.fill: parent
            radius: backdrop.radius
            layer.enabled: root.nearby
            visible: false
        }
        // Share the launchers' cached wallpaper blur, without a dim overlay.
        LauncherBackdrop {
            id: wallpaperBackdrop
            anchors.fill: parent
            screen: root.controller.targetScreen
        }
        Rectangle {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(Appearance.colors.colDockBackground, 0.14)
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.current ? root.controller.activateWorkspace(root.workspaceId)
            : root.controller.showWorkspace(root.workspaceId)
        onWheel: event => root.controller.scrollWorkspace(event)
    }

    Repeater {
        id: tiles
        // ObjectModel membership survives title/geometry updates, keeping each
        // capture alive instead of recreating every preview on each IPC refresh.
        model: root.nearby ? ToplevelManager.toplevels : null
        delegate: Item {
            id: tile
            required property var modelData
            readonly property var client: HyprlandData.clientForToplevel(modelData)
            readonly property string address: client?.address ?? ""
            readonly property var position: root.positions[address]
            readonly property bool selected: root.controller.selectedAddress === address && root.current
            readonly property string appId: TaskbarApps.resolveAppId(modelData)
            readonly property string icon: AppSearch.guessIcon(appId)
            readonly property real nativeScale: root.width / Math.max(1,
                root.controller.targetScreen?.width ?? root.width)
            // Keep the masked rendering surfaces fixed during the zoom. Resizing
            // them with the tile reallocates textures on every animation frame.
            readonly property real renderWidth: Math.max(1,
                (client?.size?.[0] ?? 1) * nativeScale, position?.width ?? 1)
            readonly property real renderHeight: Math.max(1,
                (client?.size?.[1] ?? 1) * nativeScale, position?.height ?? 1)
            readonly property real moveProgress: root.current ? root.progress : 1
            readonly property bool waiting: visible && preview.captureSource !== null && !preview.hasContent
            property bool hovered: hover.hovered && !root.controller.held
            visible: !!position && !!client
            x: ((client?.at?.[0] ?? 0) - (root.monitor?.x ?? 0)) * nativeScale * (1 - moveProgress)
                + (root.inset + (position?.x ?? 0)) * moveProgress
            y: ((client?.at?.[1] ?? 0) - (root.monitor?.y ?? 0)) * nativeScale * (1 - moveProgress)
                + (root.inset + (position?.y ?? 0)) * moveProgress
            width: Math.max(1, (client?.size?.[0] ?? 1) * nativeScale * (1 - moveProgress)
                + (position?.width ?? 1) * moveProgress)
            height: Math.max(1, (client?.size?.[1] ?? 1) * nativeScale * (1 - moveProgress)
                + (position?.height ?? 1) * moveProgress)
            z: tile.selected ? 3 : tile.hovered ? 2 : 1
            scale: 1 + (tile.selected ? 0.10 : tile.hovered ? 0.025 : 0) * root.progress
            Behavior on x { enabled: root.progress === 1 && root.controller.opened; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on y { enabled: root.progress === 1 && root.controller.opened; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on width { enabled: root.progress === 1 && root.controller.opened; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on height { enabled: root.progress === 1 && root.controller.opened; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on scale { enabled: root.progress === 1; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

            // These decorative shadows stay separate from the live capture.
            StyledRectangularShadow {
                id: ambientShadow
                target: windowFrame
                blur: (tile.selected ? 24 : 16) * root.controller.uiScale
                offset: Qt.vector2d(0, (tile.selected ? 7 : 4) * root.controller.uiScale)
                spread: root.controller.uiScale
                color: ColorUtils.applyAlpha(Appearance.m3colors.m3shadow, tile.selected ? 0.32 : 0.18)
                opacity: root.progress
                cached: false
            }
            StyledRectangularShadow {
                id: contactShadow
                target: windowFrame
                blur: (tile.selected ? 6 : 4) * root.controller.uiScale
                offset: Qt.vector2d(0, 2 * root.controller.uiScale)
                spread: 0.5 * root.controller.uiScale
                color: ColorUtils.applyAlpha(Appearance.m3colors.m3shadow, tile.selected ? 0.38 : 0.24)
                opacity: root.progress
                cached: false
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3 * root.controller.uiScale
                radius: RoundedCorners.on ? (Appearance.rounding.verysmall + 3) * root.controller.uiScale : 0
                color: "transparent"
                border.width: (tile.selected ? 3 : tile.hovered ? 1 : 0) * root.controller.uiScale
                border.color: tile.selected ? ColorUtils.applyAlpha(Appearance.launcherContent.colSecondaryOnTile, 0.95)
                    : ColorUtils.applyAlpha(Appearance.launcherContent.colOnLayer0, 0.35)
                opacity: root.progress
            }
            Rectangle {
                id: previewBody
                width: tile.renderWidth
                height: tile.renderHeight
                scale: tile.width / width
                transformOrigin: Item.TopLeft
                color: Appearance.colors.colLayer2
                radius: RoundedCorners.on ? Appearance.rounding.verysmall / Math.max(0.01, scale) : 0
                layer.enabled: tile.visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: previewMask
                }
                Rectangle {
                    id: previewMask
                    anchors.fill: parent
                    radius: previewBody.radius
                    layer.enabled: tile.visible
                    visible: false
                }
                HdrScreencopyView {
                    id: preview
                    anchors.fill: parent
                    captureSource: tile.visible && root.nearby && !GlobalStates.screenLocked ? tile.modelData : null
                    live: root.controller.opened && root.current
                    constraintSize: Qt.size(Math.ceil(previewBody.width), Math.ceil(previewBody.height))
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.min(64, previewBody.width * 0.3, previewBody.height * 0.3)
                    source: Quickshell.iconPath(tile.icon, "application-x-executable")
                    visible: !preview.hasContent
                }
            }
            // A dark outer edge reads on white; the light inner edge reads on black.
            Rectangle {
                id: windowFrame
                anchors.fill: parent
                anchors.margins: -root.controller.uiScale
                radius: RoundedCorners.on ? (Appearance.rounding.verysmall + 1) * root.controller.uiScale : 0
                color: "transparent"
                border.width: root.controller.uiScale
                border.color: ColorUtils.applyAlpha(Appearance.m3colors.m3shadow, tile.selected ? 0.48 : 0.28)
                opacity: root.progress
            }
            Rectangle {
                id: innerEdge
                anchors.fill: parent
                anchors.margins: root.controller.uiScale
                radius: RoundedCorners.on ? Math.max(0, Appearance.rounding.verysmall - 1) * root.controller.uiScale : 0
                color: "transparent"
                border.width: root.controller.uiScale
                border.color: Qt.rgba(1, 1, 1, tile.selected ? 0.24 : 0.14)
                opacity: root.progress
            }
            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 16
                implicitSize: 38
                source: Quickshell.iconPath(tile.icon, "application-x-executable")
            }
            HoverHandler { id: hover }
            TapHandler {
                onTapped: root.controller.activate(tile.address)
            }
            StyledToolTip {
                text: tile.client?.title || tile.modelData.title || tile.appId
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.clients.length === 0
        text: root.controller.query ? Translation.tr("No matching windows") : Translation.tr("Empty workspace")
        color: Appearance.launcherContent.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.huge
        style: Text.Outline
        styleColor: ColorUtils.applyAlpha(Appearance.m3colors.m3background, 0.4)
    }
}
