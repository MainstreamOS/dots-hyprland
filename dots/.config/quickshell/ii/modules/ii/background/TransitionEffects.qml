pragma Singleton

import QtQuick
import Quickshell
import qs.services

// The catalog of wallpaper transitions. The first five are drawn by the
// background layer itself; the rest are fragment shaders that blend the
// old and new picture, from pctrade's end4-pC. Resolving the shader path
// here keeps one copy of it for the desktop and the settings preview.
Singleton {
    id: root

    readonly property list<string> drawn: ["none", "fade", "slide", "zoom", "wipe"]
    readonly property list<string> shaders: [
        "circle", "ripple", "peel", "glitch", "crt", "shatter"
    ]
    readonly property int drawnDuration: 700
    readonly property int shaderDuration: 1200

    // In the order the picker shows them.
    readonly property var options: [
        { value: "none",     icon: "block",           displayName: Translation.tr("None") },
        { value: "fade",     icon: "transition_fade", displayName: Translation.tr("Crossfade") },
        { value: "slide",    icon: "transition_push", displayName: Translation.tr("Slide") },
        { value: "zoom",     icon: "zoom_out_map",    displayName: Translation.tr("Zoom") },
        { value: "wipe",     icon: "transition_chop", displayName: Translation.tr("Wipe") },
        { value: "circle",   icon: "circle",          displayName: Translation.tr("Circle") },
        { value: "ripple",   icon: "water",           displayName: Translation.tr("Ripple") },
        { value: "peel",     icon: "layers",          displayName: Translation.tr("Peel") },
        { value: "glitch",   icon: "bug_report",      displayName: Translation.tr("Glitch") },
        { value: "crt",      icon: "tv",              displayName: Translation.tr("CRT") },
        { value: "shatter",  icon: "broken_image",    displayName: Translation.tr("Shatter") },
        { value: "random",   icon: "shuffle",         displayName: Translation.tr("Random") }
    ]

    function label(id) {
        const entry = root.options.find(o => o.value === id);
        return entry ? entry.displayName : id;
    }

    function isShader(id) {
        return root.shaders.includes(id);
    }

    function isKnown(id) {
        return id === "random" || root.drawn.includes(id) || root.shaders.includes(id);
    }

    // What one change actually plays: random draws from everything that
    // moves, and a name from an older config falls back to the crossfade.
    function resolve(id) {
        if (id === "random") {
            const pool = root.drawn.slice(1).concat(root.shaders);
            return pool[Math.floor(Math.random() * pool.length)];
        }
        return root.isKnown(id) ? id : "fade";
    }

    function durationFor(id) {
        return root.isShader(id) ? root.shaderDuration : root.drawnDuration;
    }

    function shaderUrl(id) {
        return root.isShader(id) ? Qt.resolvedUrl(`shaders/${id}.frag.qsb`) : "";
    }
}
