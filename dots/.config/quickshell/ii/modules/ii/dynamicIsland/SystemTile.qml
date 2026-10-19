pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    property string symbol: ""
    property string subtitle: ""
    property bool opensPanel: false
    property bool expanded: false
    property var iconAction: null

    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)
    readonly property color colText: Appearance.colors.colOnLayer1
    readonly property color colIcon: highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3

    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 44
    padding: 5
    leftPadding: 6
    rightPadding: 8

    colBackground: elevatedSurface
    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer2Hover, Appearance.colors.colOnLayer0, 0.92)
    colRipple: Appearance.colors.colLayer2Active
    buttonRadius: highlighted ? (Appearance?.rounding?.normal ?? 17) : height / 2
    buttonRadiusPressed: Appearance?.rounding?.small ?? 12
    Accessible.name: text + ": " + subtitle

    Behavior on buttonRadius {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    contentItem: RowLayout {
        spacing: 6

        MouseArea {
            id: iconArea
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            acceptedButtons: root.iconAction ? Qt.LeftButton : Qt.NoButton
            onClicked: {
                if (root.iconAction) root.iconAction();
            }

            Rectangle {
                id: iconBg
                anchors.fill: parent
                radius: Math.max(4, root.buttonEffectiveRadius - root.padding)
                color: root.highlighted
                    ? Appearance.colors.colPrimary
                    : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                Behavior on radius {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: root.highlighted ? 1 : 0
                    text: root.symbol
                    iconSize: 18
                    color: root.colIcon
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: iconArea.containsMouse && root.iconAction
                    color: ColorUtils.transparentize(root.colIcon, iconArea.pressed ? 0.85 : 0.93)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.text
                font.pixelSize: 11
                font.weight: 600
                color: root.colText
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.subtitle
                font.pixelSize: 10
                font.weight: Font.Normal
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        MaterialSymbol {
            visible: root.opensPanel
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            text: "chevron_right"
            iconSize: 14
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            rotation: root.expanded ? 90 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
