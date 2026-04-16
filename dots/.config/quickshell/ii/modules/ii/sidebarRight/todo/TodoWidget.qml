import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var tabButtonList: [{"icon": "checklist", "name": Translation.tr("Unfinished")}, {"name": Translation.tr("Done"), "icon": "check_circle"}]
    property bool showAddDialog: false
    property bool showEditDialog: false
    property int editingIndex: -1
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.decrementCurrentIndex();
            }
            event.accepted = true;
        }
        // Open add dialog on "N" (any modifiers)
        else if (event.key === Qt.Key_N) {
            addDateEnabled.checked = false
            addDatePicker.selectedDate = new Date()
            root.showAddDialog = true
            event.accepted = true;
        }
        // Close dialog on Esc if open
        else if (event.key === Qt.Key_Escape && (root.showAddDialog || root.showEditDialog)) {
            root.showAddDialog = false
            root.showEditDialog = false
            event.accepted = true;
        }
    }

    function openEditDialog(originalIndex, content, date) {
        editingIndex = originalIndex
        editInput.text = content
        if (date) {
            editDateEnabled.checked = true
            editDatePicker.selectedDate = new Date(date)
        } else {
            editDateEnabled.checked = false
            editDatePicker.selectedDate = new Date()
        }
        showEditDialog = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: tabBar.currentIndex

            // To Do tab
            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                editable: true
                onEditRequested: (originalIndex, content, date) => root.openEditDialog(originalIndex, content, date)
                taskList: Todo.list
                    .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
                    .filter(function(item) { return !item.done; })
            }
            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                editable: true
                onEditRequested: (originalIndex, content, date) => root.openEditDialog(originalIndex, content, date)
                taskList: Todo.list
                    .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
                    .filter(function(item) { return item.done; })
            }

        }
    }

    // + FAB
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        onClicked: {
            addDateEnabled.checked = false
            addDatePicker.selectedDate = new Date()
            root.showAddDialog = true
        }
        iconText: "add"
    }

    // ===== Add Task Dialog =====
    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                todoInput.text = ""
                fabButton.focus = true
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }
        }

        Rectangle { // The dialog
            id: addDialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: addDialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal
            clip: true

            function addTask() {
                if (todoInput.text.length > 0) {
                    var date = addDateEnabled.checked ? addDatePicker.selectedDate : null
                    Todo.addTask(todoInput.text, date)
                    todoInput.text = ""
                    root.showAddDialog = false
                    tabBar.setCurrentIndex(0) // Show unfinished tasks
                }
            }

            ColumnLayout {
                id: addDialogColumnLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 16

                StyledText {
                    Layout.topMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add task")
                }

                TextField {
                    id: todoInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: addDialog.addTask()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: todoInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: todoInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                // Due date checkbox row
                RowLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8

                    CheckBox {
                        id: addDateEnabled
                        checked: false

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 4
                            border.color: addDateEnabled.checked ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            border.width: 2
                            color: addDateEnabled.checked ? Appearance.colors.colPrimary : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                color: Appearance.m3colors.m3onPrimary
                                visible: addDateEnabled.checked
                            }
                        }
                    }

                    StyledText {
                        text: Translation.tr("Due date")
                        color: addDateEnabled.checked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3outline
                    }
                }

                // Date picker row
                RowLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8
                    opacity: addDateEnabled.checked ? 1.0 : 0.5

                    MaterialSymbol {
                        text: "calendar_today"
                        iconSize: Appearance.font.pixelSize.larger
                        color: addDateEnabled.checked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3outline
                    }

                    DatePickerRow {
                        id: addDatePicker
                        enabled: addDateEnabled.checked
                    }
                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: todoInput.text.length > 0
                        onClicked: addDialog.addTask()
                    }
                }
            }
        }
    }

    // ===== Edit Task Dialog =====
    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showEditDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                editInput.text = ""
                fabButton.focus = true
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }
        }

        Rectangle { // The dialog
            id: editDialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: editDialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            function saveTask() {
                if (editInput.text.length > 0 && root.editingIndex >= 0) {
                    var date = editDateEnabled.checked ? editDatePicker.selectedDate : null
                    Todo.updateTask(root.editingIndex, editInput.text, date)
                    editInput.text = ""
                    root.showEditDialog = false
                    root.editingIndex = -1
                }
            }

            ColumnLayout {
                id: editDialogColumnLayout
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 16

                StyledText {
                    Layout.topMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Edit task")
                }

                TextField {
                    id: editInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showEditDialog
                    onAccepted: editDialog.saveTask()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: editInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: editInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                // Due date checkbox row
                RowLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8

                    CheckBox {
                        id: editDateEnabled
                        checked: false

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 4
                            border.color: editDateEnabled.checked ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            border.width: 2
                            color: editDateEnabled.checked ? Appearance.colors.colPrimary : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                color: Appearance.m3colors.m3onPrimary
                                visible: editDateEnabled.checked
                            }
                        }
                    }

                    StyledText {
                        text: Translation.tr("Due date")
                        color: editDateEnabled.checked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3outline
                    }
                }

                // Date picker row
                RowLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8
                    opacity: editDateEnabled.checked ? 1.0 : 0.5

                    MaterialSymbol {
                        text: "calendar_today"
                        iconSize: Appearance.font.pixelSize.larger
                        color: editDateEnabled.checked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3outline
                    }

                    DatePickerRow {
                        id: editDatePicker
                        enabled: editDateEnabled.checked
                    }
                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showEditDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Save")
                        enabled: editInput.text.length > 0
                        onClicked: editDialog.saveTask()
                    }
                }
            }
        }
    }
}
