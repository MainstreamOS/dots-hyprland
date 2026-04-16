pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Manages application folders for the app drawer.
 * Folders are stored as a JSON file and persist across sessions.
 * Each folder has: id, name, appIds (list of desktop entry IDs).
 */
Singleton {
    id: root

    property string filePath: Directories.appFoldersPath
    property var folders: []  // Array of {id: string, name: string, appIds: string[]}
    property bool ready: false

    Component.onCompleted: {
        loadFolders();
    }

    // Generate a unique folder ID
    function generateId() {
        return "folder_" + Date.now() + "_" + Math.floor(Math.random() * 10000);
    }

    // Create a new folder from two apps
    function createFolder(name, appId1, appId2) {
        const folder = {
            id: root.generateId(),
            name: name,
            appIds: [appId1, appId2]
        };
        const updated = root.folders.slice();
        updated.push(folder);
        root.folders = updated;

        saveFolders();
        return folder;
    }

    // Add an app to an existing folder
    function addAppToFolder(folderId, appId) {
        const updated = root.folders.slice();
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].id === folderId) {
                if (updated[i].appIds.indexOf(appId) === -1) {
                    updated[i] = Object.assign({}, updated[i]);
                    updated[i].appIds = updated[i].appIds.slice();
                    updated[i].appIds.push(appId);
                }
                break;
            }
        }
        root.folders = updated;

        saveFolders();
    }

    // Remove an app from a folder; delete folder if it becomes empty
    function removeAppFromFolder(folderId, appId) {
        let updated = root.folders.slice();
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].id === folderId) {
                updated[i] = Object.assign({}, updated[i]);
                updated[i].appIds = updated[i].appIds.filter(id => id !== appId);
                if (updated[i].appIds.length === 0) {
                    updated.splice(i, 1);
                }
                break;
            }
        }
        root.folders = updated;

        saveFolders();
    }

    // Rename a folder
    function renameFolder(folderId, newName) {
        const updated = root.folders.slice();
        for (let i = 0; i < updated.length; i++) {
            if (updated[i].id === folderId) {
                updated[i] = Object.assign({}, updated[i]);
                updated[i].name = newName;
                break;
            }
        }
        root.folders = updated;

        saveFolders();
    }

    // Delete a folder entirely (also unpins from dock if pinned)
    function deleteFolder(folderId) {
        root.folders = root.folders.filter(f => f.id !== folderId);
        if (TaskbarApps.isFolderPinned(folderId))
            TaskbarApps.toggleFolderPin(folderId);
        saveFolders();
    }

    // Get a folder by ID
    function getFolder(folderId) {
        for (let i = 0; i < root.folders.length; i++) {
            if (root.folders[i].id === folderId) return root.folders[i];
        }
        return null;
    }

    // Check if an app is inside any folder
    function folderContainingApp(appId) {
        for (let i = 0; i < root.folders.length; i++) {
            if (root.folders[i].appIds.indexOf(appId) !== -1) return root.folders[i];
        }
        return null;
    }

    // Get all app IDs that are inside folders (to hide from main grid)
    function allFolderedAppIds() {
        const ids = {};
        for (let i = 0; i < root.folders.length; i++) {
            const folder = root.folders[i];
            for (let j = 0; j < folder.appIds.length; j++) {
                ids[folder.appIds[j]] = true;
            }
        }
        return ids;
    }

    // ── Persistence ──────────────────────────────────────────────
    Process {
        id: loadProcess
        property string output: ""
        command: ["cat", root.filePath]
        stdout: SplitParser { onRead: data => loadProcess.output += data }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && loadProcess.output.trim().length > 0) {
                try {
                    root.folders = JSON.parse(loadProcess.output.trim());
                } catch (e) {
                    console.warn("AppFolderManager: failed to parse folders JSON:", e);
                    root.folders = [];
                }
            } else {
                root.folders = [];
            }
            root.ready = true;
    
            loadProcess.output = "";
        }
    }

    function loadFolders() {
        loadProcess.output = "";
        loadProcess.running = true;
    }

    Process {
        id: saveProcess
        property string jsonData: ""
        command: ["bash", "-c", `mkdir -p "$(dirname '${root.filePath}')" && cat > '${root.filePath}'`]
        onRunningChanged: {
            if (saveProcess.running) {
                saveProcess.write(saveProcess.jsonData);
                stdinEnabled = false;
            }
        }
    }

    function saveFolders() {
        saveProcess.jsonData = JSON.stringify(root.folders, null, 2);
        saveProcess.stdinEnabled = true;
        saveProcess.running = true;
    }
}
