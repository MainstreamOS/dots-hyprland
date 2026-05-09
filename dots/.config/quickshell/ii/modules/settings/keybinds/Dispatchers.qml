pragma ComponentBehavior: Bound

import QtQuick

/**
 * Dispatcher category metadata for the keybinds editor.
 *
 * QML port of hyprmod's `dispatchers.py`. Pure data — categorize binds by
 * dispatcher name, look up display labels, build dialog argument widgets.
 *
 * Material Symbol icon names are used in place of hyprmod's freedesktop
 * icon names so this matches the rest of the dots-hyprland settings UI.
 */
QtObject {
    id: root

    readonly property var bindTypes: [
        { id: "bind",     label: "Normal",        desc: "Triggers on key press" },
        { id: "binde",    label: "Repeat",        desc: "Repeats while held (volume, resize)" },
        { id: "bindl",    label: "Locked",        desc: "Works even when screen is locked" },
        { id: "bindr",    label: "Release",       desc: "Triggers on key release" },
        { id: "bindn",    label: "Non-consuming", desc: "Key event passes through to windows" },
        { id: "bindm",    label: "Mouse",         desc: "Mouse button bind (move/resize)" },
        { id: "bindd",    label: "Described",     desc: "Bind with a description (cheatsheet)" },
        { id: "bindid",   label: "Ignore-mods Desc", desc: "Ignore mods + has description" },
        { id: "bindit",   label: "Transparent",   desc: "Doesn't block other binds" },
        { id: "binditn",  label: "Trans Non-cons", desc: "Transparent + non-consuming" },
        { id: "bindle",   label: "Locked Repeat", desc: "Locked + repeats while held" },
        { id: "bindld",   label: "Locked Desc",   desc: "Locked + described" },
        { id: "bindp",    label: "Pass",          desc: "Pass key through" },
        { id: "bindln",   label: "Locked Non-cons", desc: "Locked + non-consuming" }
    ]

    readonly property var mouseButtonPresets: [
        { value: "mouse:272", label: "Left button"   },
        { value: "mouse:273", label: "Right button"  },
        { value: "mouse:274", label: "Middle button" },
        { value: "mouse:275", label: "Back"          },
        { value: "mouse:276", label: "Forward"       }
    ]

    // Dispatchers that make sense for `bindm` (mouse drag).
    readonly property var bindmDispatchers: ({
        "movewindow":   "Move window",
        "resizewindow": "Resize window"
    })

    // Argument widget types — drives _buildArgWidget in the dialog.
    //   none           → no widget
    //   command        → text field (for exec, execr)
    //   text           → text field (free-form)
    //   optional_text  → text field with placeholder, may be empty
    //   workspace      → preset combo + custom value
    //   direction      → l/d/u/r toggle pills
    //   fullscreen_mode → combo: 0/1/2
    //   group_dir      → combo: forward/back
    //   dpms           → combo: on/off/toggle

    readonly property var categories: [
        {
            id: "apps",
            label: "Launch Application",
            icon: "terminal",
            dispatchers: [
                { id: "exec",  label: "Run command",     argType: "command" },
                { id: "execr", label: "Run raw command", argType: "command" }
            ]
        },
        {
            id: "window_mgmt",
            label: "Window Management",
            icon: "select_window",
            dispatchers: [
                { id: "killactive",       label: "Close window",         argType: "none" },
                { id: "forcekillactive",  label: "Force kill window",    argType: "none" },
                { id: "togglefloating",   label: "Toggle floating",      argType: "none" },
                { id: "fullscreen",       label: "Toggle fullscreen",    argType: "fullscreen_mode" },
                { id: "fullscreenstate",  label: "Set fullscreen state", argType: "text" },
                { id: "fakefullscreen",   label: "Toggle fake fullscreen", argType: "none" },
                { id: "pin",              label: "Pin window",           argType: "none" },
                { id: "centerwindow",     label: "Center window",        argType: "none" },
                { id: "pseudo",           label: "Toggle pseudo-tiling", argType: "none" },
                { id: "layoutmsg",        label: "Layout message",       argType: "text" }
            ]
        },
        {
            id: "workspace_nav",
            label: "Workspace Navigation",
            icon: "grid_view",
            dispatchers: [
                { id: "workspace",                label: "Switch workspace",          argType: "workspace" },
                { id: "movetoworkspace",          label: "Move window to workspace",  argType: "workspace" },
                { id: "movetoworkspacesilent",    label: "Move window silently",      argType: "workspace" },
                { id: "togglespecialworkspace",   label: "Toggle scratchpad",         argType: "optional_text" }
            ]
        },
        {
            id: "window_focus",
            label: "Focus and Move Windows",
            icon: "open_with",
            dispatchers: [
                { id: "movefocus",          label: "Move focus",          argType: "direction" },
                { id: "movewindow",         label: "Move window",         argType: "direction" },
                { id: "swapwindow",         label: "Swap window",         argType: "direction" },
                { id: "movewindoworgroup",  label: "Move window or group", argType: "direction" },
                { id: "resizeactive",       label: "Resize window",       argType: "text" },
                { id: "cyclenext",          label: "Cycle focus next",    argType: "none" },
                { id: "swapnext",           label: "Swap with next",      argType: "none" },
                { id: "focuscurrentorlast", label: "Focus last window",   argType: "none" },
                { id: "focusurgentorlast",  label: "Focus urgent/last",   argType: "none" }
            ]
        },
        {
            id: "mouse_button",
            label: "Mouse Button",
            icon: "mouse",
            // Empty here — the dialog reads bindmDispatchers directly when in mouse mode.
            dispatchers: []
        },
        {
            id: "grouping",
            label: "Window Grouping",
            icon: "select_all",
            dispatchers: [
                { id: "togglegroup",         label: "Toggle group",          argType: "none" },
                { id: "changegroupactive",   label: "Cycle group member",    argType: "group_dir" },
                { id: "moveoutofgroup",      label: "Remove from group",     argType: "none" },
                { id: "moveintogroup",       label: "Move into group",       argType: "direction" },
                { id: "movegroupwindow",     label: "Reorder in group",      argType: "group_dir" },
                { id: "lockgroups",          label: "Lock all groups",       argType: "text" },
                { id: "lockactivegroup",     label: "Lock active group",     argType: "text" },
                { id: "denywindowfromgroup", label: "Deny window from group", argType: "text" }
            ]
        },
        {
            id: "monitor",
            label: "Monitor Control",
            icon: "monitor",
            dispatchers: [
                { id: "focusmonitor",                  label: "Focus monitor",            argType: "text" },
                { id: "movecurrentworkspacetomonitor", label: "Move workspace to monitor", argType: "text" },
                { id: "moveworkspacetomonitor",        label: "Move specific workspace to monitor", argType: "text" },
                { id: "swapactiveworkspaces",          label: "Swap workspaces between monitors", argType: "text" },
                { id: "focusworkspaceoncurrentmonitor", label: "Focus workspace on current monitor", argType: "workspace" },
                { id: "dpms",                          label: "Screen on/off",            argType: "dpms" }
            ]
        },
        {
            id: "session",
            label: "Session",
            icon: "computer",
            dispatchers: [
                { id: "exit",   label: "Exit Hyprland",     argType: "none" },
                { id: "pass",   label: "Pass key to window", argType: "text" },
                { id: "global", label: "Global shortcut",   argType: "text" },
                { id: "submap", label: "Enter submap",      argType: "text" }
            ]
        },
        {
            id: "advanced",
            label: "Other",
            icon: "more_horiz",
            dispatchers: []
        }
    ]

    readonly property var workspacePresets: [
        { value: "1",  label: "Workspace 1" },
        { value: "2",  label: "Workspace 2" },
        { value: "3",  label: "Workspace 3" },
        { value: "4",  label: "Workspace 4" },
        { value: "5",  label: "Workspace 5" },
        { value: "6",  label: "Workspace 6" },
        { value: "7",  label: "Workspace 7" },
        { value: "8",  label: "Workspace 8" },
        { value: "9",  label: "Workspace 9" },
        { value: "10", label: "Workspace 10" },
        { value: "+1", label: "Next workspace" },
        { value: "-1", label: "Previous workspace" },
        { value: "previous", label: "Last visited" },
        { value: "empty",    label: "First empty" },
        { value: "special",  label: "Special (scratchpad)" }
    ]

    readonly property var fullscreenModes: [
        { value: "0", label: "Fullscreen" },
        { value: "1", label: "Maximize" },
        { value: "2", label: "Fullscreen (no gaps)" }
    ]

    readonly property var directionChoices: [
        { value: "l", icon: "arrow_back",    label: "Left" },
        { value: "d", icon: "arrow_downward", label: "Down" },
        { value: "u", icon: "arrow_upward",   label: "Up" },
        { value: "r", icon: "arrow_forward",  label: "Right" }
    ]

    readonly property var groupDirChoices: [
        { value: "f", label: "Forward" },
        { value: "b", label: "Back" }
    ]

    readonly property var dpmsChoices: [
        { value: "on",     label: "On" },
        { value: "off",    label: "Off" },
        { value: "toggle", label: "Toggle" }
    ]

    // Flat lookup tables built lazily.
    property var _categoryById: ({})
    property var _dispatcherInfo: ({})

    Component.onCompleted: {
        const cm = {};
        const di = {};
        for (let i = 0; i < categories.length; i++) {
            const cat = categories[i];
            cm[cat.id] = cat;
            for (let j = 0; j < cat.dispatchers.length; j++) {
                const d = cat.dispatchers[j];
                di[d.id] = Object.assign({}, d, { categoryId: cat.id });
            }
        }
        _categoryById = cm;
        _dispatcherInfo = di;
    }

    function categoryById(id) {
        return _categoryById[id] || _categoryById["advanced"];
    }

    function dispatcherInfo(name) {
        return _dispatcherInfo[name] || null;
    }

    function categorizeBind(bindType, dispatcher) {
        if (bindType === "bindm")
            return "mouse_button";
        const info = _dispatcherInfo[dispatcher];
        return info ? info.categoryId : "advanced";
    }

    function dispatcherLabel(dispatcher) {
        const info = _dispatcherInfo[dispatcher];
        return info ? info.label : dispatcher;
    }

    function bindDispatcherLabel(bindType, dispatcher) {
        if (bindType === "bindm" && bindmDispatchers[dispatcher])
            return bindmDispatchers[dispatcher];
        return dispatcherLabel(dispatcher);
    }

    function formatBindAction(bindType, dispatcher, args) {
        const label = bindDispatcherLabel(bindType, dispatcher);
        if (args && args.length > 0)
            return label + ": " + args;
        return label;
    }

    function formatShortcut(mods, key) {
        const filtered = mods.filter(m => m && m.length > 0);
        if (filtered.length === 0)
            return key || "";
        return filtered.join(" + ") + (key ? " + " + key : "");
    }

    function combo(mods, key) {
        // Normalized combo string for conflict detection.
        const sorted = mods.slice().map(m => m.toLowerCase()).sort();
        return sorted.join("+") + "|" + (key || "").toLowerCase();
    }
}
