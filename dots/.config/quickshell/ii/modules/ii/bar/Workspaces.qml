import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    readonly property int effectiveActiveWorkspaceId: monitor?.activeWorkspace?.id ?? 1
    
    readonly property int workspacesShown: Config.options.bar.workspaces.shown
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / root.workspacesShown)
    property list<bool> workspaceOccupied: []
    property int widgetPadding: 4
    property int workspaceButtonWidth: 26
    property real activeWorkspaceMargin: 2
    property real workspaceIconSize: workspaceButtonWidth * 0.69
    property real workspaceIconSizeShrinked: workspaceButtonWidth * 0.55
    property real workspaceIconOpacityShrinked: 1
    property real workspaceIconMarginShrinked: -4
    property int workspaceIndexInGroup: (effectiveActiveWorkspaceId - 1) % root.workspacesShown

    // Exposed for the parent BarGroup pill to glow while a drag-to-scroll
    // is in progress. Mirrors dragScrollArea.dragActive.
    readonly property bool dragOver: dragScrollArea.dragActive

    property bool showNumbers: false
    Timer {
        id: showNumbersTimer
        interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
        repeat: false
        onTriggered: {
            root.showNumbers = true
        }
    }
    Connections {
        target: GlobalStates
        function onSuperDownChanged() {
            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable) return;
            if (GlobalStates.superDown) showNumbersTimer.restart();
            else {
                showNumbersTimer.stop();
                root.showNumbers = false;
            }
        }
        function onSuperReleaseMightTriggerChanged() { 
            showNumbersTimer.stop()
        }
    }

    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        workspaceOccupied = Array.from({ length: root.workspacesShown }, (_, i) => {
            return Hyprland.workspaces.values.some(ws => ws.id === workspaceGroup * root.workspacesShown + i + 1);
        })
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            updateWorkspaceOccupied();
        }
    }
    onWorkspaceGroupChanged: {
        updateWorkspaceOccupied();
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : (root.workspaceButtonWidth * root.workspacesShown)
    implicitHeight: root.vertical ? (root.workspaceButtonWidth * root.workspacesShown) : Appearance.sizes.barHeight

    // Scroll to switch workspaces
    WheelHandler {
        onWheel: (event) => {
            if (event.angleDelta.y < 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
            else if (event.angleDelta.y > 0)
                Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: (event) => {
            if (event.button === Qt.BackButton) {
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special("special")`);
            }
        }
    }

    // Drag-to-scroll: hover a dragged file over the widget to cycle workspaces.
    // Position within the widget determines direction and speed; center is a dead zone.
    DropArea {
        id: dragScrollArea
        anchors.fill: parent
        anchors.leftMargin: root.vertical ? 0 : -dragExtension
        anchors.rightMargin: root.vertical ? 0 : -dragExtension
        anchors.topMargin: root.vertical ? -dragExtension : 0
        anchors.bottomMargin: root.vertical ? -dragExtension : 0
        z: 10

        property int dragExtension: 50    // extra px of catch area on each side
        property real deadZone: 0.18
        property real minSpeed: 1.5       // workspaces per second just outside dead zone
        property real maxSpeed: 2.0       // workspaces per second at the edge
        property real normalizedOffset: 0 // -1 (far start) to +1 (far end), 0 = center
        property bool dragActive: false

        function updateFromDrag(drag) {
            const size = root.vertical ? height : width;
            const pos = root.vertical ? drag.y : drag.x;
            if (size <= 0) {
                normalizedOffset = 0;
                return;
            }
            // Map [0, size] to [-1, +1]
            normalizedOffset = Math.max(-1, Math.min(1, (pos / size) * 2 - 1));
        }

        onEntered: (drag) => {
            dragActive = true;
            updateFromDrag(drag);
        }
        onPositionChanged: (drag) => {
            updateFromDrag(drag);
        }
        onExited: {
            dragActive = false;
            normalizedOffset = 0;
        }
        onDropped: {
            dragActive = false;
            normalizedOffset = 0;
        }

        Timer {
            id: dragScrollTimer
            interval: 16
            repeat: true
            running: dragScrollArea.dragActive
                     && Math.abs(dragScrollArea.normalizedOffset) > dragScrollArea.deadZone

            property real accumulator: 0

            onRunningChanged: if (!running) accumulator = 0

            onTriggered: {
                const offset = dragScrollArea.normalizedOffset;
                const absOffset = Math.abs(offset);
                if (absOffset <= dragScrollArea.deadZone) {
                    accumulator = 0;
                    return;
                }
                const t = (absOffset - dragScrollArea.deadZone) / (1 - dragScrollArea.deadZone);
                const speed = dragScrollArea.minSpeed
                              + (dragScrollArea.maxSpeed - dragScrollArea.minSpeed) * t * t;
                accumulator += speed * (interval / 1000);
                if (accumulator >= 1) {
                    accumulator -= 1;
                    if (offset > 0) Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
                    else Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
                }
            }
        }
    }

    // Workspaces - background
    Grid {
        z: 1
        anchors.centerIn: parent

        rowSpacing: 0
        columnSpacing: 0
        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1

        Repeater {
            model: root.workspacesShown

            Rectangle {
                z: 1
                implicitWidth: workspaceButtonWidth
                implicitHeight: workspaceButtonWidth
                radius: (width / 2)
                property var previousOccupied: (workspaceOccupied[index-1] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index))
                property var rightOccupied: (workspaceOccupied[index+1] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index+2))
                property var radiusPrev: previousOccupied ? 0 : (width / 2)
                property var radiusNext: rightOccupied ? 0 : (width / 2)

                topLeftRadius: radiusPrev
                bottomLeftRadius: root.vertical ? radiusNext : radiusPrev
                topRightRadius: root.vertical ? radiusPrev : radiusNext
                bottomRightRadius: radiusNext
                
                color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
                opacity: (workspaceOccupied[index] && !(!activeWindow?.activated && root.effectiveActiveWorkspaceId === index+1)) ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on radiusPrev {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Behavior on radiusNext {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

            }

        }

    }

    // Active workspace
    Rectangle {
        z: 2
        // Make active ws indicator, which has a brighter color, smaller to look like it is of the same size as ws occupied highlight
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary

        anchors {
            verticalCenter: vertical ? undefined : parent.verticalCenter
            horizontalCenter: vertical ? parent.horizontalCenter : undefined
        }

        AnimatedTabIndexPair {
            id: idxPair
            index: root.workspaceIndexInGroup
        }
        property real indicatorPosition: Math.min(idxPair.idx1, idxPair.idx2) * workspaceButtonWidth + root.activeWorkspaceMargin
        property real indicatorLength: Math.abs(idxPair.idx1 - idxPair.idx2) * workspaceButtonWidth + workspaceButtonWidth - root.activeWorkspaceMargin * 2
        property real indicatorThickness: workspaceButtonWidth - root.activeWorkspaceMargin * 2

        x: root.vertical ? null : indicatorPosition
        implicitWidth: root.vertical ? indicatorThickness : indicatorLength
        y: root.vertical ? indicatorPosition : null
        implicitHeight: root.vertical ? indicatorLength : indicatorThickness
    }

    // Workspaces - numbers
    Grid {
        z: 3

        columns: root.vertical ? 1 : root.workspacesShown
        rows: root.vertical ? root.workspacesShown : 1
        columnSpacing: 0
        rowSpacing: 0

        anchors.fill: parent

        Repeater {
            model: root.workspacesShown

            Button {
                id: button
                property int workspaceValue: workspaceGroup * root.workspacesShown + index + 1
                implicitHeight: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
                implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.verticalBarWidth
                onPressed: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceValue}})`)
                width: vertical ? undefined : root.workspaceButtonWidth
                height: vertical ? root.workspaceButtonWidth : undefined

                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(button.workspaceValue)
                    property var mainAppIconSource: Quickshell.iconPath(AppSearch.guessIcon(biggestWindow?.class), "image-missing")

                    StyledText { // Workspace number text
                        opacity: root.showNumbers
                            || ((Config.options?.bar.workspaces.alwaysShowNumbers && (!Config.options?.bar.workspaces.showAppIcons || !workspaceButtonBackground.biggestWindow || root.showNumbers))
                            || (root.showNumbers && !Config.options?.bar.workspaces.showAppIcons)
                            )  ? 1 : 0
                        z: 3

                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: Appearance.font.pixelSize.small - ((text.length - 1) * (text !== "10") * 2)
                            family: Config.options?.bar.workspaces.useNerdFont ? Appearance.font.family.iconNerd : defaultFont
                        }
                        text: Config.options?.bar.workspaces.numberMap[button.workspaceValue - 1] || button.workspaceValue
                        elide: Text.ElideRight
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue) ? 
                            Appearance.m3colors.m3onPrimary : 
                            (workspaceOccupied[index] ? Appearance.m3colors.m3onSecondaryContainer : 
                                Appearance.colors.colOnLayer1Inactive)

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Rectangle { // Dot instead of ws number
                        id: wsDot
                        opacity: (Config.options?.bar.workspaces.alwaysShowNumbers
                            || root.showNumbers
                            || (Config.options?.bar.workspaces.showAppIcons && workspaceButtonBackground.biggestWindow)
                            || (root.dragOver && !dirArrow.isMiddle)
                            ) ? 0 : 1
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.18
                        height: width
                        radius: width / 2
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue) ?
                            Appearance.m3colors.m3onPrimary :
                            (workspaceOccupied[index] ? Appearance.m3colors.m3onSecondaryContainer :
                                Appearance.colors.colOnLayer1Inactive)

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    // Directional chevron — replaces the dot during a
                    // drag-to-scroll. Slots left of centre point left,
                    // right point right; the middle one (or two, if
                    // workspacesShown is even) stay as dots.
                    MaterialSymbol {
                        id: dirArrow
                        readonly property real centerIdx: (root.workspacesShown - 1) / 2
                        readonly property real distFromCenter: index - centerIdx
                        readonly property bool isLeft: distFromCenter < -0.5
                        readonly property bool isRight: distFromCenter > 0.5
                        readonly property bool isMiddle: !isLeft && !isRight

                        anchors.centerIn: parent
                        text: isLeft ? "chevron_left" : "chevron_right"
                        iconSize: workspaceButtonWidth * 0.7
                        color: (root.effectiveActiveWorkspaceId == button.workspaceValue) ?
                            Appearance.m3colors.m3onPrimary :
                            (workspaceOccupied[index] ? Appearance.m3colors.m3onSecondaryContainer :
                                Appearance.colors.colOnLayer1Inactive)

                        visible: opacity > 0.01
                        opacity: root.dragOver && !isMiddle ? 1 : 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                    Item { // Main app icon
                        anchors.centerIn: parent
                        width: workspaceButtonWidth
                        height: workspaceButtonWidth
                        opacity: !Config.options?.bar.workspaces.showAppIcons ? 0 :
                            (workspaceButtonBackground.biggestWindow && !root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                            1 : workspaceButtonBackground.biggestWindow ? workspaceIconOpacityShrinked : 0
                            visible: opacity > 0
                        IconImage {
                            id: mainAppIcon
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked
                            anchors.rightMargin: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? 
                                (workspaceButtonWidth - workspaceIconSize) / 2 : workspaceIconMarginShrinked

                            source: workspaceButtonBackground.mainAppIconSource
                            implicitSize: (!root.showNumbers && Config.options?.bar.workspaces.showAppIcons) ? workspaceIconSize : workspaceIconSizeShrinked

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.bottomMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.rightMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on implicitSize {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        Loader {
                            active: Config.options.bar.workspaces.monochromeIcons
                            anchors.fill: mainAppIcon
                            sourceComponent: Item {
                                Desaturate {
                                    id: desaturatedIcon
                                    visible: false // There's already color overlay
                                    anchors.fill: parent
                                    source: mainAppIcon
                                    desaturation: 0.8
                                }
                                ColorOverlay {
                                    anchors.fill: desaturatedIcon
                                    source: desaturatedIcon
                                    color: ColorUtils.transparentize(wsDot.color, 0.9)
                                }
                            }
                        }
                    }
                }
                

            }

        }

    }

}
