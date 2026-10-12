pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services

// The AI execution modes in one table. Kept free of Ai so the Settings
// process can load it.
Singleton {
    id: root

    readonly property list<string> ids: ["ask", "auto", "plan"]
    readonly property string current: root.normalize(Config.options?.ai?.mode)

    function _alias(mode): string {
        const m = String(mode ?? "").trim().toLowerCase();
        return m === "yolo" ? "auto" : (m === "safe" ? "ask" : m);
    }

    function normalize(mode): string {
        const m = root._alias(mode);
        return root.ids.includes(m) ? m : "ask";
    }

    function icon(id: string): string {
        switch (root.normalize(id)) {
        case "auto":
            return "bolt";
        case "plan":
            return "edit_note";
        default:
            return "shield";
        }
    }

    function name(id: string): string {
        switch (root.normalize(id)) {
        case "auto":
            return Translation.tr("Auto");
        case "plan":
            return Translation.tr("Plan");
        default:
            return Translation.tr("Ask");
        }
    }

    function description(id: string): string {
        switch (root.normalize(id)) {
        case "auto":
            return Translation.tr("Automatically approve commands and file modifications without prompts");
        case "plan":
            return Translation.tr("Planning mode only; no code changes or terminal commands executed");
        default:
            return Translation.tr("Manual approval required for bash commands and file changes");
        }
    }

    function set(id): bool {
        const m = root._alias(id);
        if (!root.ids.includes(m))
            return false;
        Config.setNestedValue("ai.mode", m);
        return true;
    }
}
