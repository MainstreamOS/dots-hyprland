pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * To-do list manager. Local items live in a JSON file; on systems with
 * evolution-data-server the online accounts' task lists (e.g. Google
 * Tasks) are merged in, and changes to those items are written back
 * through the eds-tasks helper so they sync to the account. New tasks go
 * to the first online task list when one exists, otherwise to the local
 * file. Each item has "content", "done", and optional "date"; synced
 * items additionally carry "eds", "uid", "listUid", and "listName".
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var localList: []
    property var edsTasks: []
    property var edsLists: []
    property var list: localList.concat(edsTasks)

    readonly property var syncList: {
        for (let i = 0; i < edsLists.length; i++)
            if (edsLists[i].remote) return edsLists[i]
        return null
    }

    readonly property string helperPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/calendar/eds-tasks.py`)

    function _persistLocal() {
        todoFileView.setText(JSON.stringify(root.localList))
    }

    function _isEds(index) {
        return index >= localList.length
    }

    function _edsAt(index) {
        return edsTasks[index - localList.length]
    }

    function _edsWrite(args) {
        Quickshell.execDetached([root.helperPath].concat(args))
        edsReconcileTimer.restart()
    }

    function addItem(item) {
        localList.push(item)
        root.localList = localList.slice(0)
        _persistLocal()
    }

    function addTask(desc, date) {
        if (root.syncList) {
            const item = {
                "content": desc,
                "done": false,
                "eds": true,
                "uid": "",
                "listUid": root.syncList.uid,
                "listName": root.syncList.name,
            }
            if (date !== undefined && date !== null) {
                item.date = date.toISOString()
                _edsWrite(["add", root.syncList.uid, desc, date.toISOString().slice(0, 10)])
            } else {
                _edsWrite(["add", root.syncList.uid, desc, "-"])
            }
            root.edsTasks = edsTasks.concat([item])
            return
        }
        const item = {
            "content": desc,
            "done": false,
        }
        if (date !== undefined && date !== null)
            item.date = date.toISOString()
        addItem(item)
    }

    function updateTask(index, desc, date) {
        if (index < 0 || index >= list.length) return
        if (_isEds(index)) {
            const item = _edsAt(index)
            item.content = desc
            if (date !== undefined && date !== null)
                item.date = date.toISOString()
            else
                delete item.date
            root.edsTasks = edsTasks.slice(0)
            if (item.uid.length > 0)
                _edsWrite(["update", item.listUid, item.uid, desc,
                          (date !== undefined && date !== null) ? date.toISOString().slice(0, 10) : "-"])
            return
        }
        localList[index].content = desc
        if (date !== undefined && date !== null)
            localList[index].date = date.toISOString()
        else
            delete localList[index].date
        root.localList = localList.slice(0)
        _persistLocal()
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

    function _setDone(index, value) {
        if (index < 0 || index >= list.length) return
        if (_isEds(index)) {
            const item = _edsAt(index)
            item.done = value
            root.edsTasks = edsTasks.slice(0)
            if (item.uid.length > 0)
                _edsWrite(["set-done", item.listUid, item.uid, value ? "1" : "0"])
            return
        }
        localList[index].done = value
        root.localList = localList.slice(0)
        _persistLocal()
    }

    function markDone(index) {
        _setDone(index, true)
    }

    function markUnfinished(index) {
        _setDone(index, false)
    }

    function deleteItem(index) {
        if (index < 0 || index >= list.length) return
        if (_isEds(index)) {
            const item = _edsAt(index)
            edsTasks.splice(index - localList.length, 1)
            root.edsTasks = edsTasks.slice(0)
            if (item.uid.length > 0)
                _edsWrite(["delete", item.listUid, item.uid])
            return
        }
        localList.splice(index, 1)
        root.localList = localList.slice(0)
        _persistLocal()
    }

    function refresh() {
        todoFileView.reload()
        if (!edsFetchProc.running) edsFetchProc.running = true
    }

    Component.onCompleted: {
        refresh()
    }

    Process {
        id: edsFetchProc
        command: [root.helperPath, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text || "{}")
                    root.edsLists = data.lists ?? []
                    root.edsTasks = data.tasks ?? []
                } catch (e) {
                    // keep the previous state on parse trouble
                }
            }
        }
    }

    // Write operations fire detached; pull the authoritative state (real
    // uids, server-side tweaks) shortly after the last one.
    Timer {
        id: edsReconcileTimer
        interval: 2000
        onTriggered: {
            if (!edsFetchProc.running) edsFetchProc.running = true
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) root.refresh()
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            root.localList = JSON.parse(fileContents)
            console.log("[To Do] File loaded")
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.localList = []
                todoFileView.setText(JSON.stringify(root.localList))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}
