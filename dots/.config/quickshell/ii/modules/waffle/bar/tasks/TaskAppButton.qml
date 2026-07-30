import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar
import Quickshell

AppButton {
    id: root

    required property var appEntry
    readonly property bool isSeparator: appEntry.appId === "SEPARATOR"
    // Bumped by the retry timer to re-run the lookup below. The timer used to
    // assign straight to desktopEntry, which replaced the binding with whatever
    // that one attempt returned — see the same fix in the dock's DockAppButton.
    // Task buttons are no longer rebuilt every time a window opens, so a lookup
    // that came back null while the database was still filling in stayed null
    // until a reload.
    property int lookupAttempt: 0

    readonly property var desktopEntry: {
        // heuristicLookup() is a plain function call and registers no
        // dependency, so read the entry list to make the database itself one.
        DesktopEntries.applications.values.length;
        root.lookupAttempt;
        return DesktopEntries.heuristicLookup(root.appEntry.appId);
    }

    Timer {
        // Safety net only — nudges lookupAttempt rather than assigning to
        // desktopEntry, which is what broke the binding in the first place.
        property int retryCount: 5
        interval: 1000
        running: !root.isSeparator && root.desktopEntry === null && retryCount > 0
        repeat: true
        onTriggered: {
            retryCount--;
            root.lookupAttempt++;
        }
    }

    property bool active: root.appEntry.toplevels.some(t => t.activated)
    property bool hasWindows: appEntry.toplevels.length > 0

    signal hoverPreviewRequested()
    signal hoverPreviewDismissed()

    multiple: appEntry.toplevels.length > 1
    checked: active
    iconName: root.desktopEntry?.icon ?? AppSearch.guessIcon(appEntry.appId)
    tryCustomIcon: false
    
    onHoverTimedOut: {
        root.hoverPreviewRequested()
    }

    onClicked: {
        root.hoverTimer.stop() // Prevents preview showing up when clicking to focus
        if (root.multiple) {
            root.hoverPreviewRequested()
        } else if (root.appEntry.toplevels.length === 1) {
            root.appEntry.toplevels[0].activate()
        } else {
            root.desktopEntry.execute()
        }
    }

    middleClickAction: () => {
        if (root.desktopEntry) {
            desktopEntry.execute()
        }
    }

    altAction: () => {
        root.hoverPreviewDismissed()
        root.hoverTimer.stop()
        contextMenu.active = true;
    }

    // Active indicator
    Rectangle {
        id: activeIndicator
        opacity: root.hasWindows ? 1 : 0
        anchors {
            horizontalCenter: root.background.horizontalCenter
            bottom: root.background.bottom
            bottomMargin: 1
        }

        implicitWidth: root.active ? 16 : 6
        implicitHeight: 3
        radius: height / 2

        color: root.active ? Looks.colors.accent : Looks.colors.accentUnfocused

        Behavior on implicitWidth {
            animation: Looks.transition.enter.createObject(this)
        }
        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }
        Behavior on opacity {
            animation: Looks.transition.opacity.createObject(this)
        }
    }

    BarToolTip {
        extraVisibleCondition: root.shouldShowTooltip && !root.hasWindows
        text: desktopEntry ? desktopEntry.name : appEntry.appId
    }

    BarMenu {
        id: contextMenu
        noSmoothClosing: false // On the real thing this is always smooth

        model: [
            ...((root.desktopEntry?.actions.length > 0) ? root.desktopEntry.actions.map(action =>({
                iconName: action.icon,
                text: action.name,
                action: () => {
                    action.execute()
                }
            })).concat({ type: "separator" }) : []),
            {
                iconName: root.iconName,
                text: root.desktopEntry ? root.desktopEntry.name : StringUtils.toTitleCase(appEntry.appId),
                monochromeIcon: false,
                action: () => {
                    if (root.desktopEntry) {
                        root.desktopEntry.execute()
                    }
                }
            },
            {
                iconName: root.appEntry.pinned ? "pin-off" : "pin",
                text: root.appEntry.pinned ? Translation.tr("Unpin from taskbar") : Translation.tr("Pin to taskbar"),
                action: () => {
                    TaskbarApps.togglePin(root.appEntry.appId);
                }
            },
            ...(root.appEntry.toplevels.length > 0 ? [{
                iconName: "dismiss",
                text: root.multiple ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                action: () => {
                    for (let toplevel of root.appEntry.toplevels) {
                        toplevel.close();
                    }
                }
            }] : []),
        ]
    }
}
