//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// app-remover.qml — Mainstream OS "Uninstall Apps" utility.
//
// Lists explicitly-installed applications that ship a visible desktop
// launcher and lets the user remove them. All the pacman work funnels
// through /usr/local/bin/app-remover:
//
//   list             read-only, unprivileged  → JSON of removable apps
//   preview <pkg>    read-only, unprivileged  → the exact removal cascade,
//                    or a non-zero exit whose stderr explains why the app
//                    is required by something else and can't be removed
//   remove  <pkg>    privileged (pkexec)      → pacman -Rns
//
// Only `remove` touches the system, so browsing and previewing never
// prompt; the single polkit prompt appears when the user confirms a
// removal. A matching polkit policy declares allow_active=auth_admin_keep
// so removing several apps in a row caches the first authentication.
// The helper hard-protects the base / base-devel / mainstream groups plus
// a denylist of desktop-critical leaf packages, so those never appear here
// and are refused even if requested directly.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root
    visible: true
    width: 620
    height: 700
    minimumWidth: 620
    minimumHeight: 700
    maximumWidth: 620
    maximumHeight: 700
    color: Appearance.m3colors.m3background
    title: Translation.tr("Uninstall Apps")

    // ── State ──────────────────────────────────────────────────────
    property var apps: []          // [{pkg,name,icon,comment,size}]
    property bool loading: true
    property bool busy: false      // a preview or removal is in flight
    property string status: ""
    property string resultKind: "" // "", "success", "error"

    // Confirm-dialog state, filled by previewProc before the dialog opens.
    property bool   confirmShown: false
    property string confirmPkg: ""
    property string confirmName: ""
    property string confirmDid: ""
    property string confirmKind: "native"
    property string confirmInst: ""
    property bool   confirmBlocked: false
    property string confirmReason: ""

    readonly property var filteredApps: {
        const f = filterInput.text.trim().toLowerCase()
        if (f.length === 0) return root.apps
        return root.apps.filter(a =>
            (a.name || "").toLowerCase().indexOf(f) >= 0 ||
            (a.pkg  || "").toLowerCase().indexOf(f) >= 0)
    }

    function cleanText(s) {
        return (s || "")
            .split("\n")
            .map(l => l.replace(/^\[app-remover\]\s*/, "").replace(/^error:\s*/i, "").trim())
            .filter(l => l.length > 0)
            .join("\n")
    }

    function refresh() {
        root.loading = true
        listProc.running = true
    }

    // ── Actions ────────────────────────────────────────────────────
    function askRemove(app) {
        if (root.busy) return
        if (app.kind === "flatpak") {
            // Flatpaks are never blocked by other apps — no dry run needed.
            root.confirmPkg = app.pkg
            root.confirmName = app.name
            root.confirmDid = app.desktopId || ""
            root.confirmKind = "flatpak"
            root.confirmInst = app.installation || "system"
            root.confirmBlocked = false
            root.confirmReason = ""
            root.confirmShown = true
            return
        }
        previewProc.pkg = app.pkg
        previewProc.appName = app.name
        previewProc.did = app.desktopId || ""
        previewProc.outBuf = ""
        previewProc.errBuf = ""
        previewProc.command = ["/usr/local/bin/app-remover", "preview", app.pkg]
        root.busy = true
        root.resultKind = ""
        root.status = ""
        previewProc.running = true
    }

    function confirmRemove() {
        if (root.confirmBlocked || root.confirmPkg.length === 0) return
        removeProc.appName = root.confirmName
        removeProc.outBuf = ""
        removeProc.errBuf = ""
        if (root.confirmKind === "flatpak") {
            removeProc.command = root.confirmInst === "user"
                ? ["/usr/local/bin/app-remover", "remove-flatpak", root.confirmPkg, "user"]
                : ["pkexec", "/usr/local/bin/app-remover", "remove-flatpak", root.confirmPkg, "system"]
        } else {
            removeProc.command = ["pkexec", "/usr/local/bin/app-remover", "remove", root.confirmPkg]
        }
        root.confirmShown = false
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Removing ") + root.confirmName + "…"
        removeProc.running = true
    }

    // ── Processes ──────────────────────────────────────────────────
    Process {
        id: listProc
        command: ["/usr/local/bin/app-remover", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.apps = JSON.parse(this.text) || []
                } catch (e) {
                    root.apps = []
                    root.resultKind = "error"
                    root.status = Translation.tr("Couldn't read the app list: ") + e
                }
                root.loading = false
            }
        }
    }

    Process {
        id: previewProc
        property string pkg: ""
        property string appName: ""
        property string did: ""
        property string outBuf: ""
        property string errBuf: ""
        stdout: StdioCollector { onStreamFinished: previewProc.outBuf = this.text }
        stderr: StdioCollector { onStreamFinished: previewProc.errBuf = this.text }
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            root.confirmPkg = previewProc.pkg
            root.confirmName = previewProc.appName
            root.confirmDid = previewProc.did
            root.confirmKind = "native"
            root.confirmInst = ""
            if (exitCode === 0) {
                root.confirmBlocked = false
                root.confirmReason = ""
            } else {
                root.confirmBlocked = true
                // Turn pacman's "removing X breaks dependency ... required by Y"
                // lines into a plain-English reason.
                const needed = []
                const re = /required by ([A-Za-z0-9@._+-]+)/g
                let m
                while ((m = re.exec(previewProc.errBuf)) !== null)
                    if (needed.indexOf(m[1]) < 0) needed.push(m[1])
                root.confirmReason = needed.length > 0
                    ? Translation.tr("Other software on your system still needs it: ") + needed.join(", ")
                    : (root.cleanText(previewProc.errBuf)
                        || Translation.tr("This app can't be removed on its own."))
            }
            root.confirmShown = true
        }
    }

    Process {
        id: removeProc
        property string appName: ""
        property string outBuf: ""
        property string errBuf: ""
        stdout: StdioCollector { onStreamFinished: removeProc.outBuf = this.text }
        stderr: StdioCollector { onStreamFinished: removeProc.errBuf = this.text }
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            if (exitCode === 0) {
                root.resultKind = "success"
                root.status = removeProc.appName + Translation.tr(" was removed.")
                // Drop the app's launcher override (custom icon/name) too,
                // then refresh once the entry is gone.
                if (root.confirmDid.length > 0) {
                    cleanupProc.command = ["/usr/local/bin/app-remover", "cleanup", root.confirmDid]
                    cleanupProc.running = true
                } else {
                    root.refresh()
                }
            } else if (exitCode === 126 || exitCode === 127) {
                root.resultKind = ""
                root.status = Translation.tr("Removal cancelled.")
            } else {
                root.resultKind = "error"
                root.status = root.cleanText(removeProc.errBuf)
                    || (Translation.tr("Couldn't remove ") + removeProc.appName + ".")
            }
        }
    }

    Process {
        id: cleanupProc
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    Component.onCompleted: listProc.running = true

    // ── Layout ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol {
                text: "delete_sweep"
                iconSize: 32
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    text: Translation.tr("Uninstall Apps")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Remove apps you installed. System and Mainstream components are protected.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Search box
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: filterInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                MaterialSymbol {
                    text: "search"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                TextInput {
                    id: filterInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Appearance.colors.colOnLayer1
                    selectionColor: Appearance.colors.colPrimary
                    font.pixelSize: Appearance.font.pixelSize.normal
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: filterInput.text.length === 0
                        text: Translation.tr("Search apps…")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }
                MaterialSymbol {
                    visible: filterInput.text.length > 0
                    text: "close"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: filterInput.text = ""
                    }
                }
            }
        }

        // App list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            // Empty / loading placeholder
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8
                visible: root.filteredApps.length === 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.loading ? "hourglass_top" : "inbox"
                    iconSize: 40
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    text: root.loading ? Translation.tr("Loading installed apps…")
                        : filterInput.text.length > 0 ? Translation.tr("No apps match your search.")
                        : Translation.tr("No removable apps found.")
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            StyledListView {
                id: appList
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 4
                visible: root.filteredApps.length > 0
                model: root.filteredApps

                delegate: Rectangle {
                    required property var modelData
                    width: appList.width
                    implicitHeight: 60
                    radius: Appearance.rounding.small
                    color: rowHover.hovered ? Appearance.colors.colLayer2 : "transparent"

                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        IconImage {
                            implicitSize: 40
                            // Resolve the icon the way the launcher does: the
                            // DesktopEntries entry's icon (user-level overrides
                            // included), falling back to AppSearch's guessing.
                            source: {
                                const entry = DesktopEntries.byId(modelData.desktopId)
                                    ?? DesktopEntries.heuristicLookup(modelData.desktopId)
                                const icon = (entry?.icon && entry.icon.length > 0)
                                    ? entry.icon
                                    : AppSearch.guessIcon(modelData.icon || modelData.desktopId)
                                return Quickshell.iconPath(icon, "application-x-executable")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.pkg + (modelData.size ? "  ·  " + modelData.size : "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            buttonRadius: Appearance.rounding.small
                            implicitWidth: 96
                            implicitHeight: 34
                            enabled: !root.busy
                            colBackground: Qt.rgba(Appearance.m3colors.m3error.r, Appearance.m3colors.m3error.g, Appearance.m3colors.m3error.b, 0.12)
                            colBackgroundHover: Qt.rgba(Appearance.m3colors.m3error.r, Appearance.m3colors.m3error.g, Appearance.m3colors.m3error.b, 0.22)
                            onClicked: root.askRemove(modelData)
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol {
                                    text: "delete"
                                    iconSize: 18
                                    color: Appearance.m3colors.m3error
                                }
                                StyledText {
                                    text: Translation.tr("Remove")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.m3colors.m3error
                                }
                            }
                        }
                    }
                }
            }
        }

        // Status / result banner
        Rectangle {
            Layout.fillWidth: true
            visible: root.status.length > 0
            radius: Appearance.rounding.normal
            color: root.resultKind === "success"
                ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.14)
                : root.resultKind === "error"
                    ? Qt.rgba(Appearance.m3colors.m3error.r, Appearance.m3colors.m3error.g, Appearance.m3colors.m3error.b, 0.14)
                    : Appearance.colors.colLayer1
            border.width: 1
            border.color: root.resultKind === "success"
                ? Appearance.colors.colPrimary
                : root.resultKind === "error"
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOutlineVariant
            implicitHeight: statusRow.implicitHeight + 20

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                MaterialSymbol {
                    visible: !root.busy
                    Layout.alignment: Qt.AlignVCenter
                    text: root.resultKind === "success" ? "check_circle"
                        : root.resultKind === "error"   ? "error"
                                                        : "info"
                    iconSize: 22
                    color: root.resultKind === "success" ? Appearance.colors.colPrimary
                        : root.resultKind === "error"   ? Appearance.m3colors.m3error
                                                        : Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: root.status
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WordWrap
                    }
                    StyledIndeterminateProgressBar {
                        visible: root.busy
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            RippleButton {
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 110
                implicitHeight: 36
                enabled: !root.busy && !root.loading
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.refresh()
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol { text: "refresh"; iconSize: 18; color: Appearance.colors.colOnSecondaryContainer }
                    StyledText {
                        text: Translation.tr("Refresh")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 100
                implicitHeight: 36
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.close()
                contentItem: Item {
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Close")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }

    // ── Confirm / blocked modal ────────────────────────────────────
    Rectangle {
        id: confirmScrim
        anchors.fill: parent
        z: 100
        visible: root.confirmShown
        color: Appearance.colors.colScrim

        MouseArea {  // click outside the card dismisses
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.confirmShown = false
        }

        Rectangle {
            id: confirmCard
            anchors.centerIn: parent
            width: 420
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            implicitHeight: dialogCol.implicitHeight + 40

            MouseArea {  // swallow clicks inside so they don't dismiss
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            ColumnLayout {
                id: dialogCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.confirmBlocked ? "block" : "delete_forever"
                    iconSize: 44
                    color: root.confirmBlocked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.confirmBlocked
                        ? Translation.tr("Can't remove ") + root.confirmName
                        : Translation.tr("Remove ") + root.confirmName + "?"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                }

                StyledText {  // blocked: explain why
                    Layout.fillWidth: true
                    visible: root.confirmBlocked
                    text: root.confirmReason
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {  // removable: plain-English, no package list
                    Layout.fillWidth: true
                    visible: !root.confirmBlocked
                    text: Translation.tr("The app and anything only it uses will be removed.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    spacing: 8
                    RippleButton {
                        implicitWidth: 110
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.confirmShown = false
                        contentItem: Item {
                            StyledText {
                                anchors.centerIn: parent
                                text: root.confirmBlocked ? Translation.tr("Close") : Translation.tr("Cancel")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                    RippleButton {
                        visible: !root.confirmBlocked
                        implicitWidth: 120
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.m3colors.m3error
                        colBackgroundHover: Qt.darker(Appearance.m3colors.m3error, 1.15)
                        onClicked: root.confirmRemove()
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol { text: "delete"; iconSize: 18; color: Appearance.m3colors.m3onError }
                            StyledText {
                                text: Translation.tr("Remove")
                                color: Appearance.m3colors.m3onError
                            }
                        }
                    }
                }
            }
        }
    }
}
