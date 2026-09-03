pragma ComponentBehavior: Bound

import QtQuick
import qs.services

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
        { id: "bind",     label: Translation.tr("Normal"),        desc: Translation.tr("Triggers on key press") },
        { id: "binde",    label: Translation.tr("Repeat"),        desc: Translation.tr("Repeats while held (volume, resize)") },
        { id: "bindl",    label: Translation.tr("Locked"),        desc: Translation.tr("Works even when screen is locked") },
        { id: "bindr",    label: Translation.tr("Release"),       desc: Translation.tr("Triggers on key release") },
        { id: "bindn",    label: Translation.tr("Non-consuming"), desc: Translation.tr("Key event passes through to windows") },
        { id: "bindm",    label: Translation.tr("Mouse"),         desc: Translation.tr("Mouse button bind (move/resize)") },
        { id: "bindd",    label: Translation.tr("Described"),     desc: Translation.tr("Bind with a description (cheatsheet)") },
        { id: "bindid",   label: Translation.tr("Ignore-mods Desc"), desc: Translation.tr("Ignore mods + has description") },
        { id: "bindit",   label: Translation.tr("Transparent"),   desc: Translation.tr("Doesn't block other binds") },
        { id: "binditn",  label: Translation.tr("Trans Non-cons"), desc: Translation.tr("Transparent + non-consuming") },
        { id: "bindle",   label: Translation.tr("Locked Repeat"), desc: Translation.tr("Locked + repeats while held") },
        { id: "bindld",   label: Translation.tr("Locked Desc"),   desc: Translation.tr("Locked + described") },
        { id: "bindp",    label: Translation.tr("Pass"),          desc: Translation.tr("Pass key through") },
        { id: "bindln",   label: Translation.tr("Locked Non-cons"), desc: Translation.tr("Locked + non-consuming") }
    ]

    readonly property var mouseButtonPresets: [
        { value: "mouse:272", label: Translation.tr("Left button")   },
        { value: "mouse:273", label: Translation.tr("Right button")  },
        { value: "mouse:274", label: Translation.tr("Middle button") },
        { value: "mouse:275", label: Translation.tr("Back")          },
        { value: "mouse:276", label: Translation.tr("Forward")       }
    ]

    // Dispatchers that make sense for `bindm` (mouse drag).
    readonly property var bindmDispatchers: ({
        "movewindow":   Translation.tr("Move window"),
        "resizewindow": Translation.tr("Resize window")
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
            label: Translation.tr("Launch Application"),
            icon: "terminal",
            dispatchers: [
                { id: "exec",  label: Translation.tr("Run command"),     argType: "command" },
                { id: "execr", label: Translation.tr("Run raw command"), argType: "command" }
            ]
        },
        {
            id: "window_mgmt",
            label: Translation.tr("Window Management"),
            icon: "select_window",
            dispatchers: [
                { id: "killactive",       label: Translation.tr("Close window"),         argType: "none" },
                { id: "forcekillactive",  label: Translation.tr("Force kill window"),    argType: "none" },
                { id: "togglefloating",   label: Translation.tr("Toggle floating"),      argType: "none" },
                { id: "fullscreen",       label: Translation.tr("Toggle fullscreen"),    argType: "fullscreen_mode" },
                { id: "fullscreenstate",  label: Translation.tr("Set fullscreen state"), argType: "text" },
                { id: "fakefullscreen",   label: Translation.tr("Toggle fake fullscreen"), argType: "none" },
                { id: "pin",              label: Translation.tr("Pin window"),           argType: "none" },
                { id: "centerwindow",     label: Translation.tr("Center window"),        argType: "none" },
                { id: "pseudo",           label: Translation.tr("Toggle pseudo-tiling"), argType: "none" },
                { id: "layoutmsg",        label: Translation.tr("Layout message"),       argType: "text" }
            ]
        },
        {
            id: "workspace_nav",
            label: Translation.tr("Workspace Navigation"),
            icon: "grid_view",
            dispatchers: [
                { id: "workspace",                label: Translation.tr("Switch workspace"),          argType: "workspace" },
                { id: "movetoworkspace",          label: Translation.tr("Move window to workspace"),  argType: "workspace" },
                { id: "movetoworkspacesilent",    label: Translation.tr("Move window silently"),      argType: "workspace" },
                { id: "togglespecialworkspace",   label: Translation.tr("Toggle scratchpad"),         argType: "optional_text" }
            ]
        },
        {
            id: "window_focus",
            label: Translation.tr("Focus and Move Windows"),
            icon: "open_with",
            dispatchers: [
                { id: "movefocus",          label: Translation.tr("Move focus"),          argType: "direction" },
                { id: "movewindow",         label: Translation.tr("Move window"),         argType: "direction" },
                { id: "swapwindow",         label: Translation.tr("Swap window"),         argType: "direction" },
                { id: "movewindoworgroup",  label: Translation.tr("Move window or group"), argType: "direction" },
                { id: "resizeactive",       label: Translation.tr("Resize window"),       argType: "text" },
                { id: "cyclenext",          label: Translation.tr("Cycle focus next"),    argType: "none" },
                { id: "swapnext",           label: Translation.tr("Swap with next"),      argType: "none" },
                { id: "focuscurrentorlast", label: Translation.tr("Focus last window"),   argType: "none" },
                { id: "focusurgentorlast",  label: Translation.tr("Focus urgent/last"),   argType: "none" }
            ]
        },
        {
            id: "mouse_button",
            label: Translation.tr("Mouse Button"),
            icon: "mouse",
            // Empty here — the dialog reads bindmDispatchers directly when in mouse mode.
            dispatchers: []
        },
        {
            id: "grouping",
            label: Translation.tr("Window Grouping"),
            icon: "select_all",
            dispatchers: [
                { id: "togglegroup",         label: Translation.tr("Toggle group"),          argType: "none" },
                { id: "changegroupactive",   label: Translation.tr("Cycle group member"),    argType: "group_dir" },
                { id: "moveoutofgroup",      label: Translation.tr("Remove from group"),     argType: "none" },
                { id: "moveintogroup",       label: Translation.tr("Move into group"),       argType: "direction" },
                { id: "movegroupwindow",     label: Translation.tr("Reorder in group"),      argType: "group_dir" },
                { id: "lockgroups",          label: Translation.tr("Lock all groups"),       argType: "text" },
                { id: "lockactivegroup",     label: Translation.tr("Lock active group"),     argType: "text" },
                { id: "denywindowfromgroup", label: Translation.tr("Deny window from group"), argType: "text" }
            ]
        },
        {
            id: "monitor",
            label: Translation.tr("Monitor Control"),
            icon: "monitor",
            dispatchers: [
                { id: "focusmonitor",                  label: Translation.tr("Focus monitor"),            argType: "text" },
                { id: "movecurrentworkspacetomonitor", label: Translation.tr("Move workspace to monitor"), argType: "text" },
                { id: "moveworkspacetomonitor",        label: Translation.tr("Move specific workspace to monitor"), argType: "text" },
                { id: "swapactiveworkspaces",          label: Translation.tr("Swap workspaces between monitors"), argType: "text" },
                { id: "focusworkspaceoncurrentmonitor", label: Translation.tr("Focus workspace on current monitor"), argType: "workspace" },
                { id: "dpms",                          label: Translation.tr("Screen on/off"),            argType: "dpms" }
            ]
        },
        {
            id: "session",
            label: Translation.tr("Session"),
            icon: "computer",
            dispatchers: [
                { id: "exit",   label: Translation.tr("Exit Hyprland"),     argType: "none" },
                { id: "pass",   label: Translation.tr("Pass key to window"), argType: "text" },
                { id: "global", label: Translation.tr("Global shortcut"),   argType: "text" },
                { id: "submap", label: Translation.tr("Enter submap"),      argType: "text" }
            ]
        },
        {
            id: "advanced",
            label: Translation.tr("Other"),
            icon: "more_horiz",
            dispatchers: []
        }
    ]

    readonly property var workspacePresets: [
        { value: "1",  label: Translation.tr("Workspace 1") },
        { value: "2",  label: Translation.tr("Workspace 2") },
        { value: "3",  label: Translation.tr("Workspace 3") },
        { value: "4",  label: Translation.tr("Workspace 4") },
        { value: "5",  label: Translation.tr("Workspace 5") },
        { value: "6",  label: Translation.tr("Workspace 6") },
        { value: "7",  label: Translation.tr("Workspace 7") },
        { value: "8",  label: Translation.tr("Workspace 8") },
        { value: "9",  label: Translation.tr("Workspace 9") },
        { value: "10", label: Translation.tr("Workspace 10") },
        { value: "+1", label: Translation.tr("Next workspace") },
        { value: "-1", label: Translation.tr("Previous workspace") },
        { value: "previous", label: Translation.tr("Last visited") },
        { value: "empty",    label: Translation.tr("First empty") },
        { value: "special",  label: Translation.tr("Special (scratchpad)") }
    ]

    readonly property var fullscreenModes: [
        { value: "0", label: Translation.tr("Fullscreen") },
        { value: "1", label: Translation.tr("Maximize") },
        { value: "2", label: Translation.tr("Fullscreen (no gaps)") }
    ]

    readonly property var directionChoices: [
        { value: "l", icon: "arrow_back",    label: Translation.tr("Left") },
        { value: "d", icon: "arrow_downward", label: Translation.tr("Down") },
        { value: "u", icon: "arrow_upward",   label: Translation.tr("Up") },
        { value: "r", icon: "arrow_forward",  label: Translation.tr("Right") }
    ]

    readonly property var groupDirChoices: [
        { value: "f", label: Translation.tr("Forward") },
        { value: "b", label: Translation.tr("Back") }
    ]

    readonly property var dpmsChoices: [
        { value: "on",     label: Translation.tr("On") },
        { value: "off",    label: Translation.tr("Off") },
        { value: "toggle", label: Translation.tr("Toggle") }
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

    // Settings-side names for binds that ship without a description. The
    // cheatsheet stays curated by keybinds.lua alone; this list can still
    // say "Play/pause media" instead of the playerctl invocation. First
    // match wins, and a bind nothing here recognizes keeps the raw action
    // text, so a user's own commands are never mislabeled.
    readonly property var execNameRules: [
        { has: "playerctl play-pause", name: Translation.tr("Play/pause media") },
        { has: "playerctl next", name: Translation.tr("Next track") },
        { has: "playerctl previous", name: Translation.tr("Previous track") },
        { has: "@DEFAULT_AUDIO_SINK@ 2%+", name: Translation.tr("Raise volume") },
        { has: "@DEFAULT_AUDIO_SINK@ 2%-", name: Translation.tr("Lower volume") },
        { has: "set-mute @DEFAULT_SINK@", name: Translation.tr("Mute/unmute audio") },
        { has: "set-mute @DEFAULT_SOURCE@", name: Translation.tr("Mute/unmute microphone") },
        { has: "brightness increment", name: Translation.tr("Increase brightness") },
        { has: "brightness decrement", name: Translation.tr("Decrease brightness") },
        { has: "save-numlock-state", name: Translation.tr("Remember the Num Lock state") },
        { has: "switchwall", name: Translation.tr("Switch wallpaper") },
        { has: "wlogout", name: Translation.tr("Open the session menu") },
        { has: "welcome-tutorial", name: Translation.tr("Open the welcome tour") },
        { has: "cliphist list", name: Translation.tr("Clipboard history") },
        { has: "fuzzel-emoji", name: Translation.tr("Emoji picker") },
        { has: "--clipboard-only --mode region", name: Translation.tr("Screenshot a region") },
        { has: "snip_to_search", name: Translation.tr("Search what is on screen") },
        { has: "tesseract", name: Translation.tr("Copy text from the screen") },
        { has: "record.sh --fullscreen", name: Translation.tr("Record the full screen") },
        { has: "record.sh", name: Translation.tr("Record a region") },
        { has: "systemctl poweroff", name: Translation.tr("Power off now") },
        { has: "Urgent notification", name: Translation.tr("Send a test notification (urgent)") },
        { has: "Test notification with body image", name: Translation.tr("Send a test notification (image)") },
        { has: "Test notification", name: Translation.tr("Send a test notification") },
        { has: "pkill fuzzel || fuzzel", name: Translation.tr("Open the app launcher") },
        { has: "kitty", name: Translation.tr("Open the terminal") },
        { has: "exec_cmd(terminal)", name: Translation.tr("Open the terminal") },
    ]
    readonly property var globalNameRules: [
        { has: "searchToggleRelease", name: Translation.tr("Toggle search") },
        { has: "workspaceNumber", name: Translation.tr("Show workspace numbers") },
        { has: "sidebarLeftToggleDetach", name: Translation.tr("Detach the left sidebar") },
        { has: "regionOcr", name: Translation.tr("Copy text from the screen") },
        { has: "regionRecord", name: Translation.tr("Record a region") },
    ]

    // Binds written as Lua functions arrive with their source text in the
    // dispatcher field and empty args, so these read the whole line. Loop
    // binds carry unexpanded variables (focusdir[i]), which is why several
    // names speak of "that direction" and let the key column say which.
    readonly property var luaNameRules: [
        { has: "mediaNextCommand", name: Translation.tr("Next track") },
        { has: "zoomfunction(-", name: Translation.tr("Zoom out") },
        { has: "zoomfunction(", name: Translation.tr("Zoom in") },
        { has: "Wrong close keybind", name: Translation.tr("Show the close shortcut reminder") },
        { has: "window.drag", name: Translation.tr("Move a window with the mouse") },
        { has: "window.move({direction", name: Translation.tr("Move the window in that direction") },
        { has: "window.move({ workspace", name: Translation.tr("Move the window to that workspace") },
        { has: "window.move({workspace", name: Translation.tr("Move the window to that workspace") },
        { has: ".focus({direction", name: Translation.tr("Focus the window in that direction") },
        { has: ".focus({ workspace", name: Translation.tr("Go to that workspace") },
        { has: ".focus({workspace", name: Translation.tr("Go to that workspace") },
        { has: "toggle_special", name: Translation.tr("Toggle the scratchpad workspace") },
        { has: "window.resize", name: Translation.tr("Resize the window") },
        { has: "splitratio +", name: Translation.tr("Grow the window split") },
        { has: "splitratio -", name: Translation.tr("Shrink the window split") },
        // Last: a multiline Lua bind survives parsing only as this fragment,
        // and a vague name still reads better than source soup.
        { has: "function(", name: Translation.tr("Run a scripted action") },
    ]

    function friendlyBindName(dispatcher, args) {
        const d = dispatcher || "";
        const a = args || "";
        const hay = d + " " + a;
        if (d === "exec" || hay.indexOf("exec_cmd(") >= 0) {
            for (const rule of execNameRules)
                if (hay.indexOf(rule.has) >= 0) return rule.name;
        }
        for (const rule of globalNameRules)
            if (hay.indexOf(rule.has) >= 0) return rule.name;
        for (const rule of luaNameRules)
            if (hay.indexOf(rule.has) >= 0) return rule.name;
        const directions = ({
            "l": Translation.tr("left"), "r": Translation.tr("right"),
            "u": Translation.tr("up"), "d": Translation.tr("down"),
        });
        switch (d) {
        case "movefocus":
            return directions[a] ? Translation.tr("Focus the window %1").arg(directions[a]) : "";
        case "movewindow":
            return directions[a] ? Translation.tr("Move the window %1").arg(directions[a]) : "";
        case "workspace":
            if (/^[0-9]+$/.test(a)) return Translation.tr("Go to workspace %1").arg(a);
            if (a === "+1" || a === "r+1" || a === "m+1" || a === "e+1") return Translation.tr("Next workspace");
            if (a === "-1" || a === "r-1" || a === "m-1" || a === "e-1") return Translation.tr("Previous workspace");
            return "";
        case "movetoworkspace":
        case "movetoworkspacesilent":
            if (/^[0-9]+$/.test(a)) return Translation.tr("Move the window to workspace %1").arg(a);
            if (a === "+1" || a === "r+1") return Translation.tr("Move the window to the next workspace");
            if (a === "-1" || a === "r-1") return Translation.tr("Move the window to the previous workspace");
            return "";
        case "togglespecialworkspace":
            return Translation.tr("Toggle the scratchpad workspace");
        case "layoutmsg":
            if (a.indexOf("splitratio +") >= 0) return Translation.tr("Grow the window split");
            if (a.indexOf("splitratio -") >= 0) return Translation.tr("Shrink the window split");
            return "";
        case "resizeactive":
            return Translation.tr("Resize the window");
        case "submap":
            return a === "reset" ? Translation.tr("Exit the keybind submap") : "";
        }
        return "";
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
