pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    // ---- DaVinci Resolve ----
    // Resolve is built into a *local* pacman package, so checkupdates above can
    // never see it and `pacman -Syu` will never update it. Version logic is not
    // duplicated here: install-davinci-resolve --check --json is the one source
    // of truth, shared with the notifier timer and the terminal.
    property string resolvePackage: ""      // "" when no Resolve package is installed
    property string resolveInstalled: ""
    property string resolveLatest: ""
    property bool resolveUpdateAvailable: false
    property bool resolveChecked: false     // a check has completed, successfully or not

    property double resolveLastCheck: 0
    readonly property int resolveRecheckMs: 10 * 60 * 1000

    // On demand only — deliberately not wired to the periodic timer below. One
    // HTTPS request to Blackmagic every checkInterval from every Mainstream
    // install is the stampede the weekly systemd timer's RandomizedDelaySec
    // exists to avoid. Callers are UI that the user just opened.
    function refreshResolve(force) {
        if (resolveCheckProc.running) return;
        const now = Date.now();
        if (!force && root.resolveChecked && (now - root.resolveLastCheck) < root.resolveRecheckMs) return;
        root.resolveLastCheck = now;
        resolveCheckProc.running = true;
    }

    // The [mainstream] repo is put in place during the first boot, and for the
    // moment the switch takes there is no database to answer from. A check run
    // then counts nothing and an update started from it would fail on packages
    // the machine cannot see yet, so nothing is counted or announced until the
    // repo answers. It comes up in seconds; this waits rather than reporting
    // anything, because there is nothing wrong to report.
    property bool repoReady: false

    Process {
        id: repoReadyProc
        running: Config.ready && Config.options.updates.enableCheck
        // Judged by what comes back rather than the exit status: pacman -Sl on a
        // repo that is configured but has no database yet exits 0 and only warns
        // on stderr, which is the very moment being waited out. A machine with no
        // [mainstream] at all has nothing to wait for and counts as ready, or it
        // would never be told about an update again.
        command: ["bash", "-c",
            "pacman-conf --repo=mainstream >/dev/null 2>&1 || exit 0; " +
            "[ -n \"$(pacman -Slq mainstream </dev/null 2>/dev/null)\" ]"]
        onExited: (exitCode, exitStatus) => {
            const ready = (exitCode === 0);
            if (ready === root.repoReady) {
                if (!ready) repoReadyRetry.restart();
                return;
            }
            root.repoReady = ready;
            if (ready) root.refresh();
            else repoReadyRetry.restart();
        }
    }

    Timer {
        id: repoReadyRetry
        interval: 5000
        repeat: false
        onTriggered: if (!repoReadyProc.running) repoReadyProc.running = true
    }

    function load() {}
    function refresh() {
        if (!available) return;
        if (!root.repoReady) {
            if (!repoReadyProc.running && !repoReadyRetry.running) repoReadyProc.running = true;
            return;
        }
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", "checkupdates | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.count = parseInt(text.trim());
            }
        }
    }

    Process {
        id: resolveCheckProc
        // Process has no timeout of its own, and this makes a network request:
        // wrap it so a hung DNS lookup can't leave the caller's UI waiting.
        // Exit 10 means "update available", 0 "nothing to do", anything else a
        // failed check — which leaves every property untouched, so the UI keeps
        // whatever it showed before rather than claiming Resolve is missing.
        command: ["timeout", "8", "install-davinci-resolve", "--check", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return;
                try {
                    const state = JSON.parse(text);
                    root.resolvePackage = state.package || "";
                    root.resolveInstalled = state.installed || "";
                    root.resolveLatest = state.latest || "";
                    root.resolveUpdateAvailable = (state.update_available === true);
                } catch (e) {
                    print("[Updates] Resolve check returned unparseable output")
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.resolveChecked = true;
        }
    }
}
