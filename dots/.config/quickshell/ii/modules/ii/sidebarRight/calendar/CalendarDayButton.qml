import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property bool hasTasks: false
    property var tasksForDay: []
    readonly property int todoMargin: 5

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38;
    implicitHeight: 38;

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small

    Popup {
        id: dayPopUp

        x: (button.width - width) / 2
        y: -height - 4
        width: 240
        height: Math.min(popUpColumnLayout.implicitHeight + 2 * todoMargin, 450)
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Appearance.m3colors.m3background
            radius: Appearance.rounding.small
        }

        contentItem: StyledFlickable {
            anchors.fill: parent
            anchors.margins: todoMargin
            contentWidth: width
            contentHeight: popUpColumnLayout.implicitHeight
            clip: true

            ColumnLayout {
                id: popUpColumnLayout

                width: parent.width
                spacing: 8

                Repeater {
                    model: ScriptModel {
                        values: button.tasksForDay
                    }

                    delegate: Rectangle {
                        width: parent.width
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.small
                        implicitHeight: contentColumn.implicitHeight

                        ColumnLayout {
                            id: contentColumn

                            width: parent.width
                            spacing: 4
                            Layout.margins: 10

                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                Layout.topMargin: 8
                                text: modelData.content
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                Layout.topMargin: 8
                                text: {
                                    if (!modelData.date) return ""
                                    var d = new Date(modelData.date)
                                    var dateStr = Qt.locale().toString(d, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
                                    return Translation.tr("Deadline") + ": " + dateStr
                                }
                                color: Appearance.m3colors.m3outline
                                wrapMode: Text.Wrap
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                Item {
                                    Layout.fillWidth: true
                                }

                                MaterialSymbol {
                                    text: modelData.done ? "check" : "remove_done"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    contentItem: Item {
        anchors.fill: parent

        StyledText {
            anchors.centerIn: parent
            text: day
            horizontalAlignment: Text.AlignHCenter
            font.weight: bold ? Font.DemiBold : Font.Normal
            color: (isToday == 1) ? Appearance.m3colors.m3onPrimary :
                (isToday == 0) ? Appearance.colors.colOnLayer1 :
                Appearance.colors.colOutlineVariant

            MouseArea {
                anchors.fill: parent
                hoverEnabled: false
                onClicked: {
                    if (button.tasksForDay.length > 0) {
                        if (dayPopUp.opened)
                            dayPopUp.close();
                        else
                            dayPopUp.open();
                    }
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Task indicator dot
        Rectangle {
            visible: button.hasTasks
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 4
            anchors.topMargin: 4
            width: 5
            height: 5
            radius: 2.5
            color: (isToday == 1) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colPrimary
        }
    }
}
