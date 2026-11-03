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

    readonly property var contentColors: Appearance.islandSystemContent
    readonly property color colText: contentColors.onFill(Appearance.colors.colOnLayer1,
        root.buttonColor, Appearance.surfaces.raised)
    readonly property color colSubtext: contentColors.onFill(Appearance.colors.colSubtext,
        root.buttonColor, Appearance.surfaces.raised)
    readonly property color iconBackground: highlighted
        ? contentColors.markOnFill(Appearance.colors.colPrimary, root.buttonColor, Appearance.surfaces.raised)
        : contentColors.standOff(Appearance.surfaces.row, contentColors.tone(Appearance.surfaces.row),
            contentColors.m3onSurface, contentColors.laid(root.buttonColor, Appearance.barBackdrop),
            contentColors.laid(contentColors.onStock(Appearance.surfaces.raised), Appearance.barStockBackdrop))
    readonly property color colIcon: contentColors.onFill(
        highlighted ? Appearance.colors.colOnPrimary : Appearance.m3colors.m3onSurface,
        [root.buttonColor, root.iconBackground],
        [Appearance.surfaces.raised, highlighted ? Appearance.colors.colPrimary : Appearance.surfaces.row])

    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 44
    padding: 5
    leftPadding: 6
    rightPadding: 8

    colBackground: contentColors.fill(Appearance.surfaces.raised, contentColors.m3onSurface, Appearance.m3colors.m3onSurface)
    colBackgroundHover: contentColors.apartFrom(
        contentColors.fill(Appearance.surfaces.raisedHover, contentColors.m3onSurface, Appearance.m3colors.m3onSurface),
        colBackground, Appearance.colors.colOnLayer1, Appearance.surfaces.raisedHover, Appearance.surfaces.raised)
    colRipple: contentColors.flash(Appearance.colors.colLayer2Active, contentColors.m3onSurface, Appearance.m3colors.m3onSurface)
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
                color: root.iconBackground

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
                color: root.colSubtext
                elide: Text.ElideRight
            }
        }

        MaterialSymbol {
            visible: root.opensPanel
            Layout.preferredWidth: 14
            Layout.preferredHeight: 14
            text: "chevron_right"
            iconSize: 14
            color: root.colSubtext
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            rotation: root.expanded ? 90 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
