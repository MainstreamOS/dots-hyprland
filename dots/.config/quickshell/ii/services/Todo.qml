pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 * Each item is an object with "content", "done", and optional "date" properties.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []

    function addItem(item) {
        list.push(item)
        // Reassign to trigger onListChanged
        root.list = list.slice(0)
        todoFileView.setText(JSON.stringify(root.list))
    }

    function addTask(desc, date) {
        const item = {
            "content": desc,
            "done": false,
        }
        if (date !== undefined && date !== null)
            item.date = date.toISOString()
        addItem(item)
    }

    function updateTask(index, desc, date) {
        if (index >= 0 && index < list.length) {
            list[index].content = desc
            if (date !== undefined && date !== null)
                list[index].date = date.toISOString()
            else
                delete list[index].date
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function getTasksForDate(year, month, day) {
        var result = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].done) continue
            if (list[i].date) {
                var d = new Date(list[i].date)
                if (d.getFullYear() === year && d.getMonth() === month && d.getDate() === day)
                    result.push(list[i])
            }
        }
        return result
    }

    function hasTasksForDate(year, month, day) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].done) continue
            if (list[i].date) {
                var d = new Date(list[i].date)
                if (d.getFullYear() === year && d.getMonth() === month && d.getDate() === day)
                    return true
            }
        }
        return false
    }

    function markDone(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = true
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function markUnfinished(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = false
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function deleteItem(index) {
        if (index >= 0 && index < list.length) {
            list.splice(index, 1)
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            root.list = JSON.parse(fileContents)
            console.log("[To Do] File loaded")
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}

