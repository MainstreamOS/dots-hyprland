import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80
    property bool editable: false
    signal editRequested(int originalIndex, string content, var date)

    // Shared styled context menu
    Popup {
        id: taskContextMenu
        property int taskIndex: -1
        property string taskContent: ""
        property var taskDate: null
        property bool taskDone: false

        padding: 0
        background: Item {
            StyledRectangularShadow {
                target: menuBg
            }
            Rectangle {
                id: menuBg
                anchors.fill: parent
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
            }
        }

        contentItem: ColumnLayout {
            spacing: 0

            // Edit item
            Loader {
                active: root.editable
                Layout.fillWidth: true
                sourceComponent: RippleButton {
                    id: editButton
                    implicitHeight: 36
                    implicitWidth: Math.max(editRow.implicitWidth + 20, 160)
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        root.editRequested(taskContextMenu.taskIndex, taskContextMenu.taskContent, taskContextMenu.taskDate)
                        taskContextMenu.close()
                    }
                    contentItem: RowLayout {
                        id: editRow
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 14
                        }
                        spacing: 8
                        MaterialSymbol {
                            text: "edit"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSurface
                            Layout.alignment: Qt.AlignVCenter
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Edit")
                            horizontalAlignment: Text.AlignLeft
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Separator (only when editable)
            Loader {
                active: root.editable
                Layout.fillWidth: true
                sourceComponent: Item {
                    implicitHeight: 9
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 10
                            rightMargin: 10
                        }
                        implicitHeight: 1
                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                    }
                }
            }

            // Delete item
            RippleButton {
                id: deleteButton
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(deleteRow.implicitWidth + 20, 160)
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    Todo.deleteItem(taskContextMenu.taskIndex)
                    taskContextMenu.close()
                }
                contentItem: RowLayout {
                    id: deleteRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Delete")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            property bool pendingDoneToggle: false
            property bool pendingDelete: false
            property bool enableHeightAnimation: false

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: true

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: todoContentRowLayout.implicitHeight
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: (mouse) => {
                        taskContextMenu.taskIndex = todoItem.modelData.originalIndex
                        taskContextMenu.taskContent = todoItem.modelData.content
                        taskContextMenu.taskDate = todoItem.modelData.date || null
                        taskContextMenu.taskDone = todoItem.modelData.done || false
                        let pos = mapToItem(root, mouse.x, mouse.y)
                        taskContextMenu.x = pos.x
                        taskContextMenu.y = pos.y
                        taskContextMenu.open()
                    }
                }

                ColumnLayout {
                    id: todoContentRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true // Needed for wrapping
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.topMargin: todoListItemPadding
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                    }

                    // Date label (clickable to edit)
                    RowLayout {
                        visible: todoItem.modelData.date !== undefined && todoItem.modelData.date !== ""
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        spacing: 4

                        MaterialSymbol {
                            text: "calendar_today"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3outline
                        }

                        StyledText {
                            id: deadlineText
                            text: {
                                if (!todoItem.modelData.date) return ""
                                var d = new Date(todoItem.modelData.date)
                                var dateStr = Qt.locale().toString(d, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
                                return Translation.tr("Deadline") + ": " + dateStr
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: deadlineMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline

                            MouseArea {
                                id: deadlineMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: root.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.editable) {
                                        root.editRequested(
                                            todoItem.modelData.originalIndex,
                                            todoItem.modelData.content,
                                            todoItem.modelData.date || null
                                        )
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: todoListItemPadding
                        Item {
                            Layout.fillWidth: true
                        }
                        TodoItemActionButton {
                            visible: root.editable
                            Layout.fillWidth: false
                            onClicked: {
                                root.editRequested(
                                    todoItem.modelData.originalIndex,
                                    todoItem.modelData.content,
                                    todoItem.modelData.date || null
                                )
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "edit"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                if (!todoItem.modelData.done)
                                    Todo.markDone(todoItem.modelData.originalIndex);
                                else
                                    Todo.markUnfinished(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: todoItem.modelData.done ? "remove_done" : "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            onClicked: {
                                Todo.deleteItem(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete_forever"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
