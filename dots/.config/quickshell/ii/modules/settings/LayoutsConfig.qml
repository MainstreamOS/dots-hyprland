import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ContentPage {
    id: root
    forceWidth: true

    property string currentLayout: "dwindle"
    property var workspaceLayouts: ["dwindle","dwindle","dwindle","dwindle","dwindle",
                                    "dwindle","dwindle","dwindle","dwindle","dwindle"]
    property var workspaceFloats: [false,false,false,false,false,false,false,false,false,false]
    property bool titleBarsEnabled: false

    readonly property bool perWorkspace: currentLayout === "per_workspace"
    readonly property string hyprlandConf: Quickshell.env("HOME") + "/.config/hypr/hyprland.conf"
    readonly property string workspacesConf: Quickshell.env("HOME") + "/.config/hypr/workspaces.conf"
    readonly property string rulesConf: Quickshell.env("HOME") + "/.config/hypr/custom/rules.conf"
    readonly property string customGeneralConf: Quickshell.env("HOME") + "/.config/hypr/custom/general.conf"

    Component.onCompleted: {
        layoutProc.running = false; layoutProc.running = true
        titleBarReader.running = true
    }

    Process {
        id: titleBarReader
        command: ["cat", root.customGeneralConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => titleBarReader.buf += data + "\n" }
        onExited: {
            // Enabled when the plugin = .../hyprbars.so line exists and is NOT commented out
            root.titleBarsEnabled = /^[ \t]*plugin[ \t]*=[ \t]*.*hyprbars\.so/m.test(titleBarReader.buf);
        }
    }

    Process {
        id: layoutProc
        command: ["hyprctl", "getoption", "general:layout"]
        stdout: SplitParser {
            onRead: data => {
                const m = data.match(/str:\s*(\S+)/)
                if (m) root.currentLayout = m[1].toLowerCase()
                // After getting the base layout, check if per-workspace mode is active
                perWsCheckProc.running = false
                perWsCheckProc.running = true
            }
        }
    }

    // Check if source=workspaces.conf is uncommented (per-workspace active)
    Process {
        id: perWsCheckProc
        command: ["grep", "-cE", "^\\s*source\\s*=\\s*workspaces\\.conf", root.hyprlandConf]
        stdout: SplitParser {
            onRead: data => {
                if (parseInt(data) > 0)
                    root.currentLayout = "per_workspace"
            }
        }
        // Always read workspaces.conf to restore saved per-workspace assignments
        onExited: {
            readWsConf.running = false
            readWsConf.running = true
        }
    }

    // Parse workspace layouts from workspaces.conf
    Process {
        id: readWsConf
        command: ["cat", root.workspacesConf]
        property var parsed: []
        stdout: SplitParser {
            onRead: data => {
                const m = data.match(/workspace\s*=\s*(\d+)\s*,\s*layout:(\S+)/)
                if (m) {
                    const idx = parseInt(m[1]) - 1
                    if (idx >= 0 && idx < 10) {
                        readWsConf.parsed[idx] = m[2]
                    }
                }
            }
        }
        onExited: {
            if (parsed.length > 0) {
                const layouts = root.workspaceLayouts.slice()
                for (let i = 0; i < 10; i++) {
                    if (parsed[i]) layouts[i] = parsed[i]
                }
                root.workspaceLayouts = layouts
            }
            parsed = []
            readFloatRulesProc.running = false
            readFloatRulesProc.running = true
        }
    }

    // Parse float rules from rules.conf
    Process {
        id: readFloatRulesProc
        command: ["cat", root.rulesConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => readFloatRulesProc.buf += data + "\n" }
        onExited: {
            const floats = [false,false,false,false,false,false,false,false,false,false]
            const re = /windowrule\s*=\s*float\s+on\s*,\s*match:workspace\s+(\d+)/g
            let m
            while ((m = re.exec(readFloatRulesProc.buf)) !== null) {
                const idx = parseInt(m[1]) - 1
                if (idx >= 0 && idx < 10) floats[idx] = true
            }
            root.workspaceFloats = floats

            // If all 10 are float, set global float indicator
            if (floats.every(f => f))
                root.currentLayout = "float"
        }
    }

    // ── Process chain: enable per-workspace ──────────────────────────────────
    // Step 1: single Python script writes workspaces.conf AND uncomments
    //         source=workspaces.conf — both files done before we reload.
    Process {
        id: enablePerWsProc
        onExited: Quickshell.execDetached(["hyprctl", "reload"])
    }

    function enablePerWorkspace() {
        let py =
            "import sys\n" +
            "ws_conf, hy_conf = sys.argv[1], sys.argv[2]\n" +
            "ws_lines = [\n"
        for (let i = 0; i < 10; i++) {
            py += "    'workspace = " + (i + 1) + ", layout:" + root.workspaceLayouts[i] + "',\n"
        }
        py +=
            "]\n" +
            "open(ws_conf, 'w').write('\\n'.join(ws_lines) + '\\n')\n" +
            "lines = open(hy_conf).read().split('\\n')\n" +
            "result = []\n" +
            "for line in lines:\n" +
            "    stripped = line.lstrip('#').strip()\n" +
            "    if stripped == 'source=workspaces.conf':\n" +
            "        result.append(stripped)\n" +
            "    else:\n" +
            "        result.append(line)\n" +
            "open(hy_conf, 'w').write('\\n'.join(result))\n"
        enablePerWsProc.command = ["python3", "-c", py, root.workspacesConf, root.hyprlandConf]
        enablePerWsProc.running = false
        enablePerWsProc.running = true
    }

    // ── Process chain: disable per-workspace ─────────────────────────────────
    // Step 3: apply the chosen layout keyword after reload completes
    Process {
        id: applyLayoutProc
        property string pendingLayout: ""
        command: ["hyprctl", "keyword", "general:layout", pendingLayout]
        onExited: pendingLayout = ""
    }

    // Step 2: reload Hyprland to flush workspace rules, then trigger step 3
    Process {
        id: reloadProc
        property string pendingLayout: ""
        command: ["hyprctl", "reload"]
        onExited: {
            if (pendingLayout !== "") {
                applyLayoutProc.pendingLayout = pendingLayout
                applyLayoutProc.running = false
                applyLayoutProc.running = true
                pendingLayout = ""
            }
        }
    }

    // Step 1: comment out source=workspaces.conf, then trigger step 2
    Process {
        id: editConfProc
        property string pendingLayout: ""
        onExited: {
            if (pendingLayout !== "") {
                reloadProc.pendingLayout = pendingLayout
                reloadProc.running = false
                reloadProc.running = true
                pendingLayout = ""
            }
        }
    }

    function applyLayout(name) {
        root.currentLayout = name
        if (name === "float") {
            // Float is an overlay — just add float rules, don't touch the tiling layout
            root.setFloatRules([true,true,true,true,true,true,true,true,true,true])
            return
        }
        // Clear float rules when switching to a non-float layout
        root.setFloatRules([false,false,false,false,false,false,false,false,false,false])
        if (name === "per_workspace") {
            enablePerWorkspace()
        } else {
            const py =
                "import sys, re\n" +
                "path, layout = sys.argv[1], sys.argv[2]\n" +
                "lines = open(path).read().split('\\n')\n" +
                "result = []\n" +
                "in_general = False\n" +
                "layout_written = False\n" +
                "for line in lines:\n" +
                "    stripped = line.lstrip('#').strip()\n" +
                "    if stripped == 'source=workspaces.conf':\n" +
                "        result.append('#' + stripped)\n" +
                "    elif re.match(r'^general\\s*\\{', stripped):\n" +
                "        in_general = True\n" +
                "        result.append(line)\n" +
                "    elif in_general and re.match(r'^\\}', stripped):\n" +
                "        in_general = False\n" +
                "        result.append(line)\n" +
                "    elif re.match(r'^general:layout\\s*=', stripped):\n" +
                "        result.append('general:layout = ' + layout)\n" +
                "        layout_written = True\n" +
                "    elif in_general and re.match(r'^layout\\s*=', stripped):\n" +
                "        indent = len(line) - len(line.lstrip())\n" +
                "        result.append(' ' * indent + 'layout = ' + layout)\n" +
                "        layout_written = True\n" +
                "    else:\n" +
                "        result.append(line)\n" +
                "if not layout_written:\n" +
                "    result.append('general:layout = ' + layout)\n" +
                "open(path, 'w').write('\\n'.join(result))\n"
            editConfProc.pendingLayout = name
            editConfProc.command = ["python3", "-c", py, root.hyprlandConf, name]
            editConfProc.running = false
            editConfProc.running = true
        }
    }

    // ── Float rule management ──────────────────────────────────────────────────
    Process { id: floatRulesProc }

    function setFloatRules(floatArr) {
        root.workspaceFloats = floatArr
        const py =
            "import re, sys, json\n" +
            "conf = sys.argv[1]\n" +
            "floats = json.loads(sys.argv[2])\n" +
            "text = open(conf).read()\n" +
            "# Remove all existing ii float rules\n" +
            "text = re.sub(r'\\nwindowrule = float on, match:workspace \\d+', '', text)\n" +
            "text = re.sub(r'^windowrule = float on, match:workspace \\d+\\n?', '', text, flags=re.M)\n" +
            "# Add new float rules at end\n" +
            "rules = []\n" +
            "for i, f in enumerate(floats):\n" +
            "    if f:\n" +
            "        rules.append('windowrule = float on, match:workspace ' + str(i + 1))\n" +
            "if rules:\n" +
            "    text = text.rstrip() + '\\n' + '\\n'.join(rules) + '\\n'\n" +
            "else:\n" +
            "    text = text.rstrip() + '\\n'\n" +
            "open(conf, 'w').write(text)\n"
        floatRulesProc.command = ["python3", "-c", py, root.rulesConf, JSON.stringify(floatArr)]
        floatRulesProc.running = false
        floatRulesProc.running = true
    }

    // ── Process chain: update a single workspace layout ───────────────────────
    // Write workspaces.conf first, reload only after write completes.
    Process {
        id: writeWsConfProc
        onExited: Quickshell.execDetached(["hyprctl", "reload"])
    }

    function applyWorkspaceLayout(wsIndex, layout) {
        if (layout === "float") {
            // Float is an overlay — toggle the float rule, keep the tiling layout
            const floats = root.workspaceFloats.slice()
            floats[wsIndex] = true
            root.setFloatRules(floats)
            return
        }

        // Switching to a tiling layout — update workspaceLayouts and remove float rule
        const updated = root.workspaceLayouts.slice()
        updated[wsIndex] = layout
        root.workspaceLayouts = updated

        const floats = root.workspaceFloats.slice()
        floats[wsIndex] = false
        root.setFloatRules(floats)

        // Write workspaces.conf
        let py =
            "import sys\n" +
            "path = sys.argv[1]\n" +
            "lines = [\n"
        for (let i = 0; i < 10; i++) {
            py += "    'workspace = " + (i + 1) + ", layout:" + root.workspaceLayouts[i] + "',\n"
        }
        py += "]\nopen(path, 'w').write('\\n'.join(lines) + '\\n')\n"
        writeWsConfProc.command = ["python3", "-c", py, root.workspacesConf]
        writeWsConfProc.running = false
        writeWsConfProc.running = true
    }

    ContentSection {
        icon: "view_quilt"
        title: Translation.tr("Layout")

        ContentSubsection {
            title: Translation.tr("Window Layout")

            // ── 2×2 grid: Dwindle, Master, Scrolling, Monocle ────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 16
                columnSpacing: 16

                // ── Dwindle ───────────────────────────────────────────────────
                MouseArea {
                    id: dwindleCard
                    Layout.fillWidth: true
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: dwindleCol.implicitHeight
                    onClicked: root.applyLayout("dwindle")
                    readonly property bool sel: root.currentLayout === "dwindle"

                    ColumnLayout {
                        id: dwindleCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            color: dwindleCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: dwindleCard.sel ? 2 : 1
                            border.color: dwindleCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("dwindle") }

                            Item {
                                anchors { fill: parent; margins: 10 }
                                Rectangle {
                                    x: 0; y: 0; width: parent.width * 0.54; height: parent.height
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 7; y: 15; spacing: 4
                                        Repeater { model: [38, 28, 40, 24]
                                            Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                    StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                                        text: "1"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Rectangle {
                                    x: parent.width * 0.54 + 3; y: 0
                                    width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                    StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                        text: "2"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Rectangle {
                                    x: parent.width * 0.54 + 3; y: parent.height * 0.5 + 2
                                    width: (parent.width * 0.46 - 3) * 0.54; height: parent.height * 0.5 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                    StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                        text: "3"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                                Rectangle {
                                    x: parent.width * 0.54 + 3 + (parent.width * 0.46 - 3) * 0.54 + 2
                                    y: parent.height * 0.5 + 2
                                    width: (parent.width * 0.46 - 3) * 0.46 - 2; height: parent.height * 0.5 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                    StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                        text: "4"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: dwindleCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: dwindleCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: dwindleCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Dwindle (default)"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Each new window splits the last in half"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                // ── Master ────────────────────────────────────────────────────
                MouseArea {
                    id: masterCard
                    Layout.fillWidth: true
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: masterCol.implicitHeight
                    onClicked: root.applyLayout("master")
                    readonly property bool sel: root.currentLayout === "master"

                    ColumnLayout {
                        id: masterCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            color: masterCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: masterCard.sel ? 2 : 1
                            border.color: masterCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("master") }

                            Item {
                                anchors { fill: parent; margins: 10 }
                                Rectangle {
                                    x: 0; y: 0; width: parent.width * 0.57; height: parent.height
                                    radius: 3
                                    color: masterCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08) : Appearance.colors.colLayer3
                                    border.width: 1
                                    border.color: masterCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.5) : Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 7; y: 15; spacing: 4
                                        Repeater { model: [38, 26, 42, 20, 36]
                                            Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                    StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                                        text: "M"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.45 }
                                }
                                Rectangle {
                                    x: parent.width * 0.57 + 3; y: 0
                                    width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                }
                                Rectangle {
                                    x: parent.width * 0.57 + 3; y: parent.height / 3 + 1
                                    width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                }
                                Rectangle {
                                    x: parent.width * 0.57 + 3; y: parent.height * 2 / 3 + 2
                                    width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: masterCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: masterCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: masterCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Master"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("One main window with a side stack"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                // ── Scrolling ─────────────────────────────────────────────────
                MouseArea {
                    id: scrollingCard
                    Layout.fillWidth: true
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: scrollingCol.implicitHeight
                    onClicked: root.applyLayout("scrolling")
                    readonly property bool sel: root.currentLayout === "scrolling"

                    ColumnLayout {
                        id: scrollingCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            clip: true
                            color: scrollingCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: scrollingCard.sel ? 2 : 1
                            border.color: scrollingCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("scrolling") }

                            Item {
                                anchors { fill: parent; margins: 10 }

                                Rectangle {
                                    x: -18; y: 4; width: 24; height: parent.height - 8
                                    radius: 3; opacity: 0.45; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                }
                                Row {
                                    x: 10; y: 0; width: parent.width - 14; height: parent.height; spacing: 4
                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            width: (parent.width - 8) / 3; height: parent.height
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                                Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 }
                                            }
                                            Column { x: 5; y: 14; spacing: 3
                                                Repeater { model: [20, 14, 22, 12]
                                                    Rectangle { width: modelData; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: parent.width - 6; y: 4; width: 20; height: parent.height - 8
                                    radius: 3; opacity: 0.5; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                }
                                MaterialSymbol {
                                    x: -2; anchors.verticalCenter: parent.verticalCenter
                                    text: "chevron_left"; iconSize: 16; z: 3
                                    color: scrollingCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.75
                                }
                                MaterialSymbol {
                                    anchors.right: parent.right; anchors.rightMargin: -2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "chevron_right"; iconSize: 16; z: 3
                                    color: scrollingCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.75
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: scrollingCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: scrollingCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: scrollingCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Scrolling"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Horizontally scrollable window columns"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                // ── Monocle ───────────────────────────────────────────────────
                MouseArea {
                    id: monocleCard
                    Layout.fillWidth: true
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: monocleCol.implicitHeight
                    onClicked: root.applyLayout("monocle")
                    readonly property bool sel: root.currentLayout === "monocle"

                    ColumnLayout {
                        id: monocleCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            color: monocleCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: monocleCard.sel ? 2 : 1
                            border.color: monocleCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("monocle") }

                            Item {
                                anchors { fill: parent; margins: 10 }
                                Rectangle {
                                    x: 10; y: 8; width: parent.width - 20; height: parent.height - 18
                                    radius: 3; opacity: 0.38; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                }
                                Rectangle {
                                    x: 5; y: 4; width: parent.width - 10; height: parent.height - 10
                                    radius: 3; opacity: 0.65; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                }
                                Rectangle {
                                    x: 0; y: 0; width: parent.width; height: parent.height
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 8; y: 15; spacing: 4
                                        Repeater { model: [55, 38, 60, 28, 50]
                                            Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                        spacing: 5
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                width: index === 0 ? 16 : 6; height: 4; radius: 2
                                                color: index === 0 ? (monocleCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colSubtext) : Appearance.colors.colSubtext
                                                opacity: index === 0 ? 0.85 : 0.3
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: monocleCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: monocleCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: monocleCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Monocle"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("One focused fullscreen window at a time"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                // ── Float ─────────────────────────────────────────────────
                MouseArea {
                    id: floatCard
                    Layout.fillWidth: true
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: floatCol.implicitHeight
                    onClicked: root.applyLayout("float")
                    readonly property bool sel: root.currentLayout === "float"

                    ColumnLayout {
                        id: floatCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            color: floatCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: floatCard.sel ? 2 : 1
                            border.color: floatCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("float") }

                            Item {
                                anchors { fill: parent; margins: 10 }

                                // Scattered floating windows at various sizes and positions
                                Rectangle {
                                    x: parent.width * 0.05; y: parent.height * 0.35
                                    width: parent.width * 0.35; height: parent.height * 0.55
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 5; y: 14; spacing: 3
                                        Repeater { model: [20, 14, 18]
                                            Rectangle { width: modelData; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: parent.width * 0.25; y: parent.height * 0.05
                                    width: parent.width * 0.42; height: parent.height * 0.52
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 7; y: 15; spacing: 4
                                        Repeater { model: [28, 20, 30, 16]
                                            Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: parent.width * 0.55; y: parent.height * 0.38
                                    width: parent.width * 0.38; height: parent.height * 0.55
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                    }
                                    Column { x: 5; y: 14; spacing: 3
                                        Repeater { model: [22, 16, 20]
                                            Rectangle { width: modelData; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: floatCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: floatCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: floatCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Float"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("All windows float freely on the desktop"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                // ── Title Bars ────────────────────────────────────────────
                Item {
                    id: titleBarCard
                    Layout.fillWidth: true
                    implicitHeight: titleBarCol.implicitHeight

                    ColumnLayout {
                        id: titleBarCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 130
                            radius: Appearance.rounding.normal
                            color: root.titleBarsEnabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: root.titleBarsEnabled ? 2 : 1
                            border.color: root.titleBarsEnabled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                            Item {
                                anchors { fill: parent; margins: 10 }

                                // Dwindle-style layout but with prominent title bars
                                Rectangle {
                                    x: 0; y: 0; width: parent.width * 0.54; height: parent.height
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle {
                                        width: parent.width; height: 14; radius: 2
                                        color: root.titleBarsEnabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                        border.width: root.titleBarsEnabled ? 1 : 0
                                        border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                            spacing: 2
                                            Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                            Rectangle { width: 20; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                        }
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                            spacing: 3
                                            Repeater { model: 3
                                                Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                            }
                                        }
                                    }
                                    Column { x: 7; y: 20; spacing: 4
                                        Repeater { model: [38, 28, 40, 24]
                                            Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: parent.width * 0.54 + 3; y: 0
                                    width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle {
                                        width: parent.width; height: 14; radius: 2
                                        color: root.titleBarsEnabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                        border.width: root.titleBarsEnabled ? 1 : 0
                                        border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                            spacing: 2
                                            Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                            Rectangle { width: 14; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                        }
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                            spacing: 3
                                            Repeater { model: 3
                                                Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    x: parent.width * 0.54 + 3; y: parent.height * 0.5 + 2
                                    width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                    radius: 3; color: Appearance.colors.colLayer3
                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    Rectangle {
                                        width: parent.width; height: 14; radius: 2
                                        color: root.titleBarsEnabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                        border.width: root.titleBarsEnabled ? 1 : 0
                                        border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                            spacing: 2
                                            Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                            Rectangle { width: 14; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                        }
                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                            spacing: 3
                                            Repeater { model: 3
                                                Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Toggle centered below the card
                        ConfigSwitch {
                            Layout.alignment: Qt.AlignHCenter
                            buttonIcon: "title"
                            text: Translation.tr("Title Bars")
                            checked: root.titleBarsEnabled
                            onCheckedChanged: {
                                if (checked === root.titleBarsEnabled) return;
                                root.titleBarsEnabled = checked;
                                // Toggle by commenting/uncommenting the plugin = .../hyprbars.so line
                                // in custom/general.conf. No hyprpm needed — Hyprland loads the .so
                                // directly when the directive is present and uncommented.
                                let py =
                                    "import re, sys\n" +
                                    "enable = sys.argv[1] == '1'\n" +
                                    "conf = sys.argv[2]\n" +
                                    "text = open(conf).read()\n" +
                                    "if enable:\n" +
                                    "    text = re.sub(r'^([ \\t]*)#[ \\t]*(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1\\2', text, flags=re.M)\n" +
                                    "else:\n" +
                                    "    text = re.sub(r'^([ \\t]*)(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1# \\2', text, flags=re.M)\n" +
                                    "open(conf, 'w').write(text)\n";
                                Quickshell.execDetached(["python3", "-c", py, checked ? "1" : "0", root.customGeneralConf]);
                                Quickshell.execDetached(["hyprctl", "reload"]);
                            }
                            StyledToolTip {
                                text: Translation.tr("Show title bars on windows")
                            }
                        }
                    }
                }

            } // GridLayout


            // ── Per Workspace — centered in its own row ───────────────────────
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 16
                implicitHeight: perWsCard.implicitHeight

                MouseArea {
                    id: perWsCard
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    cursorShape: Qt.PointingHandCursor
                    implicitHeight: perWsCol.implicitHeight
                    onClicked: root.applyLayout("per_workspace")
                    readonly property bool sel: root.currentLayout === "per_workspace"

                    ColumnLayout {
                        id: perWsCol
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: wsDiagGrid.implicitHeight + 20
                            radius: Appearance.rounding.normal
                            color: perWsCard.sel ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                            border.width: perWsCard.sel ? 2 : 1
                            border.color: perWsCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            MouseArea { anchors.fill: parent; z: 1; cursorShape: Qt.PointingHandCursor; onClicked: root.applyLayout("per_workspace") }

                            // Diagram: 2 rows × 5 columns — all 10 workspaces,
                            //          each showing its assigned layout pattern
                            Item {
                                anchors { fill: parent; margins: 10 }

                                component MiniWs: Item {
                                    id: mw
                                    property int wsNum: 1
                                    property string wsLayout: "dwindle"
                                    property bool wsFloat: false

                                    Rectangle {
                                        anchors.fill: parent; radius: 3
                                        color: Appearance.colors.colLayer3
                                        border.width: 1; border.color: Appearance.colors.colOutlineVariant

                                        Rectangle { id: mwTb; width: parent.width; height: 6; radius: 2; color: Appearance.colors.colLayer2 }

                                        // Dwindle: left half + split right
                                        Item {
                                            visible: mw.wsLayout === "dwindle" && !mw.wsFloat
                                            anchors { fill: parent; topMargin: mwTb.height + 2; margins: 2 }
                                            Rectangle { x:0; y:0; width:parent.width*0.54; height:parent.height; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.54+1; y:0; width:parent.width*0.46-1; height:parent.height*0.5-1; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.54+1; y:parent.height*0.5+1; width:parent.width*0.46-1; height:parent.height*0.5-1; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                        }

                                        // Master: big left + 2 stacked right
                                        Item {
                                            visible: mw.wsLayout === "master" && !mw.wsFloat
                                            anchors { fill: parent; topMargin: mwTb.height + 2; margins: 2 }
                                            Rectangle { x:0; y:0; width:parent.width*0.57; height:parent.height; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.57+1; y:0; width:parent.width*0.43-1; height:parent.height*0.5-1; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.57+1; y:parent.height*0.5+1; width:parent.width*0.43-1; height:parent.height*0.5-1; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                        }

                                        // Scrolling: 3 equal columns
                                        Item {
                                            visible: mw.wsLayout === "scrolling" && !mw.wsFloat
                                            anchors { fill: parent; topMargin: mwTb.height + 2; margins: 2 }
                                            Repeater {
                                                model: 3
                                                Rectangle {
                                                    x: index * ((parent.width + 1) / 3); y: 0
                                                    width: (parent.width - 2) / 3; height: parent.height
                                                    radius: 2; color: Appearance.colors.colLayer2
                                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                                }
                                            }
                                        }

                                        // Monocle: stacked cards hint
                                        Item {
                                            visible: mw.wsLayout === "monocle" && !mw.wsFloat
                                            anchors { fill: parent; topMargin: mwTb.height + 2; margins: 2 }
                                            Rectangle { x:2; y:2; width:parent.width-4; height:parent.height-4; radius:2; color:Appearance.colors.colLayer2; opacity:0.45; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:0; y:0; width:parent.width; height:parent.height; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                        }

                                        // Float: scattered small windows
                                        Item {
                                            visible: mw.wsFloat
                                            anchors { fill: parent; topMargin: mwTb.height + 2; margins: 2 }
                                            Rectangle { x:0; y:parent.height*0.3; width:parent.width*0.4; height:parent.height*0.6; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.25; y:0; width:parent.width*0.45; height:parent.height*0.55; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                            Rectangle { x:parent.width*0.55; y:parent.height*0.35; width:parent.width*0.4; height:parent.height*0.55; radius:2; color:Appearance.colors.colLayer2; border.width:1; border.color:Appearance.colors.colOutlineVariant }
                                        }
                                    }

                                    // Workspace number badge (top-right corner)
                                    Rectangle {
                                        anchors { right: parent.right; top: parent.top; margins: 2 }
                                        width: 13; height: 13; radius: 7
                                        color: perWsCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                        border.width: 1; border.color: perWsCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: String(mw.wsNum); font.pixelSize: 7
                                            color: perWsCard.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                // 2 rows × 5 columns = workspaces 1–10
                                GridLayout {
                                    id: wsDiagGrid
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    columns: 5; rows: 2; columnSpacing: 4; rowSpacing: 4

                                    // Cell width = (total width minus 4 inner column gaps) / 5 columns
                                    readonly property real cellW: Math.max(1, (width - 4 * columnSpacing) / columns)
                                    // Each tile is 16:9 landscape
                                    readonly property real cellH: Math.round(cellW * 9 / 16)

                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:1;  wsLayout: root.workspaceLayouts[0]; wsFloat: root.workspaceFloats[0] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:2;  wsLayout: root.workspaceLayouts[1]; wsFloat: root.workspaceFloats[1] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:3;  wsLayout: root.workspaceLayouts[2]; wsFloat: root.workspaceFloats[2] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:4;  wsLayout: root.workspaceLayouts[3]; wsFloat: root.workspaceFloats[3] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:5;  wsLayout: root.workspaceLayouts[4]; wsFloat: root.workspaceFloats[4] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:6;  wsLayout: root.workspaceLayouts[5]; wsFloat: root.workspaceFloats[5] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:7;  wsLayout: root.workspaceLayouts[6]; wsFloat: root.workspaceFloats[6] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:8;  wsLayout: root.workspaceLayouts[7]; wsFloat: root.workspaceFloats[7] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:9;  wsLayout: root.workspaceLayouts[8]; wsFloat: root.workspaceFloats[8] }
                                    MiniWs { Layout.fillWidth:true; Layout.preferredHeight: wsDiagGrid.cellH; wsNum:10; wsLayout: root.workspaceLayouts[9]; wsFloat: root.workspaceFloats[9] }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6; Layout.alignment: Qt.AlignLeft
                            Rectangle {
                                width: 16; height: 16; radius: 8; border.width: 2
                                border.color: perWsCard.sel ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                color: perWsCard.sel ? Appearance.colors.colPrimary : "transparent"
                                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Appearance.colors.colOnPrimary; visible: perWsCard.sel }
                            }
                            ColumnLayout {
                                spacing: 1
                                StyledText { text: Translation.tr("Per Workspace"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                StyledText { text: Translation.tr("Choose a different layout for each workspace"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
            } // Per Workspace row


            // ── Workspace Layout Picker ───────────────────────────────────────
            // Fades in and becomes interactive only when Per Workspace is active
            Item {
                Layout.fillWidth: true
                implicitHeight: wsPickerCol.implicitHeight
                opacity: root.perWorkspace ? 1.0 : 0.32
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    id: wsPickerCol
                    width: parent.width
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        spacing: 8
                        MaterialSymbol { text: "grid_view"; iconSize: 16; color: Appearance.colors.colSubtext }
                        StyledText {
                            text: Translation.tr("Workspace Layouts")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 1
                        Layout.topMargin: 6; Layout.bottomMargin: 8
                        color: Appearance.colors.colOutlineVariant; opacity: 0.4
                    }

                    // One row per workspace (1–10)
                    Repeater {
                        model: 10
                        RowLayout {
                            id: wsRow
                            required property int index
                            // Capture outer workspace index before inner Repeater shadows it
                            property int wsIdx: index

                            Layout.fillWidth: true
                            Layout.bottomMargin: 6
                            spacing: 10
                            enabled: root.perWorkspace

                            // Numbered badge
                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: Appearance.colors.colLayer2
                                border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                StyledText {
                                    anchors.centerIn: parent
                                    text: String(wsRow.wsIdx + 1)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            StyledText {
                                text: Translation.tr("Workspace %1").arg(wsRow.wsIdx + 1)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                Layout.fillWidth: true
                            }

                            // True radio pills — exactly one active per workspace row
                            Repeater {
                                model: [
                                    { key: "dwindle",   label: "Dwindle"   },
                                    { key: "master",    label: "Master"    },
                                    { key: "scrolling", label: "Scrolling" },
                                    { key: "monocle",   label: "Monocle"   },
                                    { key: "float",     label: "Float"     }
                                ]

                                MouseArea {
                                    implicitWidth: pill.implicitWidth
                                    implicitHeight: 28
                                    cursorShape: root.perWorkspace ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    // Only fire if this option isn't already the active one (radio)
                                    onClicked: {
                                        if (root.perWorkspace && root.workspaceLayouts[wsRow.wsIdx] !== modelData.key)
                                            root.applyWorkspaceLayout(wsRow.wsIdx, modelData.key)
                                    }
                                    // Active when THIS workspace's layout matches THIS pill's key
                                    readonly property bool active: modelData.key === "float"
                                        ? root.workspaceFloats[wsRow.wsIdx]
                                        : (!root.workspaceFloats[wsRow.wsIdx] && root.workspaceLayouts[wsRow.wsIdx] === modelData.key)

                                    Rectangle {
                                        id: pill
                                        anchors.fill: parent
                                        implicitWidth: pillTxt.implicitWidth + 20
                                        radius: Appearance.rounding.full
                                        color: parent.active
                                            ? Appearance.colors.colPrimary
                                            : (parent.containsMouse && root.perWorkspace
                                                ? Appearance.colors.colLayer3
                                                : Appearance.colors.colLayer2)
                                        border.width: parent.active ? 0 : 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        StyledText {
                                            id: pillTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: parent.parent.active
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } // Workspace picker

        } // ContentSubsection
    } // ContentSection
}
