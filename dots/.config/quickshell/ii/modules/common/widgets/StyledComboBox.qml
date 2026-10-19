pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import Quickshell.Widgets

ComboBox {
    id: root

    property string buttonIcon: ""
    property string buttonAppIcon: ""
    property string appIconRole: "appIcon"
    readonly property var currentEntry: currentIndex >= 0 && typeof model?.[currentIndex] === 'object' ? model[currentIndex] : null
    readonly property string currentAppIcon: buttonAppIcon || (currentEntry?.[appIconRole] ?? "")
    readonly property real appIconSize: Appearance.font.pixelSize.larger + 4
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    implicitHeight: 40
    readonly property real contentInset: 16
    leftPadding: 0
    rightPadding: indicator.width + root.contentInset
    Layout.fillWidth: true

    function iconSource(icon) {
        if (!icon) return "";
        return (icon.startsWith("/") || icon.startsWith("file://")) ? icon : Quickshell.iconPath(icon, "multimedia-audio-player");
    }

    background: Rectangle {
        radius: root.buttonRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitWidth: buttonLayout.implicitWidth
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: root.contentInset
            anchors.rightMargin: 8

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.currentAppIcon.length > 0
                visible: active
                sourceComponent: IconImage {
                    implicitSize: root.appIconSize
                    source: root.iconSource(root.currentAppIcon)
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: !root.currentAppIcon && (root.buttonIcon.length > 0 || !!root.currentEntry?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: root.currentEntry?.icon || root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                visible: text.length > 0
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: Math.max(40, implicitContentHeight + topPadding + bottomPadding)
        topPadding: 8
        bottomPadding: 8
        // The popup's own padding also contributes to the icon's screen position.
        leftPadding: Math.max(0, root.contentInset - root.popup.leftPadding)
        rightPadding: 12

        required property var model
        required property int index
        readonly property string appIcon: typeof model === 'object' ? (model?.[root.appIconRole] ?? "") : ""
        property color color: {
            if (root.currentIndex === itemDelegate.index) {
                if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                if (itemDelegate.hovered) return Appearance.colors.colSecondaryContainerHover;
                return Appearance.colors.colSecondaryContainer;
            } else {
                if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                if (itemDelegate.hovered) return Appearance.colors.colLayer3Hover;
                return ColorUtils.transparentize(Appearance.colors.colLayer3);
            }
        }
        property color colText: (root.currentIndex === itemDelegate.index) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

        background: Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: itemDelegate.color

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        contentItem: RowLayout {
            spacing: 8

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: itemDelegate.appIcon.length > 0
                visible: active
                sourceComponent: IconImage {
                    implicitSize: root.appIconSize
                    source: root.iconSource(itemDelegate.appIcon)
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                active: !itemDelegate.appIcon && typeof itemDelegate.model === 'object' && itemDelegate.model?.icon?.length > 0
                visible: active

                sourceComponent: Item {
                    implicitWidth: icon.implicitWidth
                    implicitHeight: Appearance.font.pixelSize.larger

                    MaterialSymbol {
                        id: icon
                        anchors.centerIn: parent
                        text: itemDelegate.model?.icon ?? ""
                        iconSize: Appearance.font.pixelSize.larger
                        color: itemDelegate.colText
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: itemDelegate.colText
                text: root.textRole ? (itemDelegate.model[root.textRole] ?? "") : (itemDelegate.model.modelData ?? "")
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        height: Math.min(listView.contentHeight + topPadding + bottomPadding, 300)
        padding: 8

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        exit: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: StyledListView {
            id: listView
            clip: true
            implicitHeight: contentHeight
            spacing: 2
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }
    }
}
