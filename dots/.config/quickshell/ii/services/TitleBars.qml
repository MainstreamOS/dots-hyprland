pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * TitleBars — single source of truth for the hyprbars (Hyprland window
 * title bars) plugin toggle. Manages both halves of "is this plugin on":
 *
 *   1. The persistent `plugin = ...hyprbars.so` directive in
 *      custom/general.conf (state across restarts).
 *   2. The live plugin state via `hyprctl plugin load|unload`
 *      (state right now, in-memory in the running Hyprland).
 *
 * Both Settings → Layouts and Settings → Interface call into this
 * service, so neither page can drift out of sync with the other.
 *
 * Before this lived as one service, the two pages had independent
 * implementations: Layouts used sed + hyprctl plugin verbs, Interface
 * used python + hyprctl reload. `hyprctl reload` re-reads the conf but
 * does NOT load or unload .so files at runtime — Hyprland only honours
 * `plugin =` directives at startup. That meant the Interface toggle
 * changed the file but not the live state, leaving title bars stuck on
 * (or off) until the user restarted Hyprland. The bug went unnoticed for
 * months because the Layouts toggle worked correctly and nobody compared
 * the two. One service prevents the recurrence.
 */
Singleton {
    id: root

    readonly property string confPath: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/general.conf`
    readonly property string pluginPath: `${FileUtils.trimFileProtocol(Directories.home)}/.local/share/hyprland/plugins/hyprbars.so`

    // Reflects whether the plugin directive in custom/general.conf is
    // currently uncommented. Refreshed at startup and after the file
    // changes. Read-only to consumers — call setEnabled() to change it.
    property bool enabled: false

    function load() {} // For forcing singleton initialization

    function refresh() {
        readerProc.running = false
        readerProc.running = true
    }

    // Flip the title-bars plugin on or off. Idempotent against the live
    // state: calling setEnabled(true) when already enabled is a no-op
    // (the early-out below + idempotent regex + harmless "already loaded"
    // exit from hyprctl). Same for setEnabled(false).
    function setEnabled(value) {
        if (value === root.enabled) return
        root.enabled = value
        // Single python process so the conf edit and the plugin verb run
        // in a guaranteed order. Two separate execDetached calls would
        // race — usually harmless, but a third party reading the conf
        // between them (e.g. a `hyprctl reload` from a theme apply)
        // could see a state where the file disagrees with the runtime.
        //
        // Self-heal: if the `plugin = ...hyprbars.so` directive is
        // missing entirely (configs predating the install hook that
        // adds it), enable prepends a fresh directive at the top of the
        // file so the toggle still works on first flip.
        const py =
            "import re, sys, os, subprocess\n" +
            "enable = sys.argv[1] == '1'\n" +
            "conf = sys.argv[2]\n" +
            "plugin_path = sys.argv[3]\n" +
            "text = open(conf).read()\n" +
            "if re.search(r'^[ \\t]*#?[ \\t]*plugin[ \\t]*=[ \\t]*.*hyprbars\\.so', text, flags=re.M):\n" +
            "    if enable:\n" +
            "        text = re.sub(r'^([ \\t]*)#[ \\t]*(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1\\2', text, flags=re.M)\n" +
            "    else:\n" +
            "        text = re.sub(r'^([ \\t]*)(?!#)(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1# \\2', text, flags=re.M)\n" +
            "elif enable:\n" +
            "    text = '# hyprbars plugin load directive\\nplugin = ' + plugin_path + '\\n\\n' + text\n" +
            "open(conf, 'w').write(text)\n" +
            // capture_output swallows hyprctl's stderr on harmless
            // states like "already loaded" / "not loaded" — those exits
            // are non-zero but the file state already reflects the
            // user's intent, so there's nothing for QML to surface.
            "verb = 'load' if enable else 'unload'\n" +
            "subprocess.run(['hyprctl', 'plugin', verb, plugin_path], capture_output=True)\n"
        Quickshell.execDetached(["python3", "-c", py, value ? "1" : "0", root.confPath, root.pluginPath])
    }

    Process {
        id: readerProc
        command: ["cat", root.confPath]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => readerProc.buf += data + "\n" }
        onExited: {
            root.enabled = /^[ \t]*plugin[ \t]*=[ \t]*.*hyprbars\.so/m.test(readerProc.buf)
        }
    }

    // Apply-theme can rewrite the plugin directive (decorations.json
    // captures titleBars true/false per theme). Re-read after each
    // theme apply so the Settings switches reflect the new state.
    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            root.refresh()
        }
    }

    Component.onCompleted: refresh()
}
