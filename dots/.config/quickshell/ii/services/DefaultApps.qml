pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * DefaultApps — which app does each job.
 *
 * A role is the job as a person names it: the web browser, the file manager,
 * the terminal. Picking an app for a role writes every file type that role
 * covers at once, so a photo and a screenshot open in the same viewer, and it
 * writes the app the matching keybind launches, so SUPER + B opens the browser
 * that double clicking a link opens.
 *
 * scripts/apps/default-apps.sh holds the mapping and does the writing; this
 * service is the shell's side of it. Nothing is cached across a write: the
 * script is asked again afterwards, so the page shows the state the system is
 * actually in rather than the one it was told to reach.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/apps/default-apps.sh")

    // The label and the icon live here beside the role rather than in the page,
    // so a second caller shows a role the same way the first one does. "keyed"
    // marks the roles a keybind launches, which are the ones whose pick is
    // written for the Hyprland config as well as for the file types.
    readonly property var roles: [
        { key: "browser",     keyed: true,  icon: "public",         label: Translation.tr("Web Browser"),   hint: Translation.tr("Opens links and web pages") },
        { key: "email",       keyed: false, icon: "mail",           label: Translation.tr("Email"),         hint: Translation.tr("Opens email addresses") },
        { key: "fileManager", keyed: true,  icon: "folder",         label: Translation.tr("File Manager"),  hint: Translation.tr("Opens folders") },
        { key: "terminal",    keyed: true,  icon: "terminal",       label: Translation.tr("Terminal"),      hint: Translation.tr("Opens a command line") },
        { key: "textEditor",  keyed: true,  icon: "edit_note",      label: Translation.tr("Text Editor"),   hint: Translation.tr("Opens plain text and notes") },
        { key: "codeEditor",  keyed: true,  icon: "code",           label: Translation.tr("Code Editor"),   hint: Translation.tr("Opens code projects") },
        { key: "music",       keyed: false, icon: "music_note",     label: Translation.tr("Music"),         hint: Translation.tr("Plays songs and audio") },
        { key: "video",       keyed: false, icon: "movie",          label: Translation.tr("Videos"),        hint: Translation.tr("Plays films and clips") },
        { key: "photos",      keyed: false, icon: "image",          label: Translation.tr("Photos"),        hint: Translation.tr("Opens pictures and screenshots") },
        { key: "pdf",         keyed: false, icon: "picture_as_pdf", label: Translation.tr("PDF Documents"), hint: Translation.tr("Opens PDFs") }
    ]

    // Role key to the desktop id of the app holding it. Read-only to callers:
    // go through setDefault() to change one.
    property var current: ({})
    // True once the first read has landed, so the page can hold its rows still
    // until it has something true to put in them.
    property bool loaded: false
    // The role a write is in flight for, so its row can say so and refuse a
    // second pick until the first one has landed.
    property string busyRole: ""

    function load() {} // For forcing singleton initialization

    function refresh() {
        currentReader.running = false;
        currentReader.running = true;
    }

    function idFor(roleKey) {
        return root.current[roleKey] ?? "";
    }

    function roleFor(roleKey) {
        return root.roles.find(role => role.key === roleKey) ?? null;
    }

    function setDefault(roleKey, entryId) {
        if (!roleKey || !entryId || entryId === root.idFor(roleKey)) return;
        root.busyRole = roleKey;
        writer.command = [root.scriptPath, "set", roleKey, entryId];
        writer.running = false;
        writer.running = true;
    }

    Process {
        id: currentReader
        command: [root.scriptPath, "get"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => currentReader.buf += data + "\n" }
        onExited: {
            const next = ({});
            for (const line of currentReader.buf.split("\n")) {
                if (line.length === 0) continue;
                const parts = line.split("\t");
                if (parts.length < 2) continue;
                next[parts[0]] = parts[1].trim();
            }
            root.current = next;
            root.loaded = true;
        }
    }

    Process {
        id: writer
        onExited: {
            root.busyRole = "";
            // The system is the authority on what took, so the answer comes
            // from reading it back rather than from what was asked for.
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
