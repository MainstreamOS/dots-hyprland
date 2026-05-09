import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    // The dropdown's persistent choice (in Settings → Display and the
    // right-sidebar Night Light dialog) is the source of truth — the
    // button mirrors it rather than deriving from runtime fields like
    // Hyprsunset.temperatureActive (which can flip with the schedule).
    readonly property string mode: Config.options.light.night.mode

    name: Translation.tr("Night Light")
    // "On" includes any of the three non-disabled modes — automatic
    // schedule, manual schedule (Set hours), and always-on enabled.
    toggled: mode !== "disabled"
    icon: (mode === "automatic" || mode === "manual") ? "night_sight_auto" : "bedtime"
    statusText: {
        if (mode === "disabled")  return Translation.tr("Inactive");
        if (mode === "automatic") return Translation.tr("Auto, Active");
        if (mode === "manual")    return Translation.tr("Scheduled, Active");
        if (mode === "enabled")   return Translation.tr("Active");
        return Translation.tr("Inactive");
    }

    // Click behaviour:
    //   - Disabled → restore the last non-disabled mode the user picked
    //     (lastActiveMode, default "automatic"). This is the "always
    //     return to the last status" behaviour requested over the old
    //     "just toggle the filter" approach.
    //   - Anything else → switch to "disabled" (off).
    mainAction: () => {
        if (mode === "disabled") {
            const last = Config.options.light.night.lastActiveMode || "automatic";
            Hyprsunset.applyNightLightMode(last);
        } else {
            Hyprsunset.applyNightLightMode("disabled");
        }
    }
    hasMenu: true

    Component.onCompleted: {
        Hyprsunset.fetchState()
    }

    tooltipText: Translation.tr("Night Light | Right-click to configure")
}
