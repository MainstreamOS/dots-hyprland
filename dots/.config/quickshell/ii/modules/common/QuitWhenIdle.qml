import QtQuick
import Quickshell
import Quickshell.Io

// Ends the process of a window that runs on its own (qs -p) once the work it
// started is done. Quitting takes the process's children down with it, and
// one of those can be pacman partway through a removal, or a wallpaper whose
// colors are still being generated; a settings change can also still be
// counting down to its write. So once asked, this looks a few times a second
// and quits only when no child process is left and Config has nothing unsaved.
// The first look comes a quarter second after the ask, which also lets a
// slider's short write delay run out and send its change first.
Scope {
    id: root

    // Something that never finishes must not keep the process around for good.
    // Half an hour is far past the slowest thing these windows start, a package
    // removal, so real work is never cut short by it.
    property int giveUpAfter: 30 * 60 * 1000

    property bool _requested: false
    property int _idleLooks: 0

    function request() {
        if (root._requested) return;
        root._requested = true;
        lookTimer.start();
        giveUpTimer.start();
    }

    // The timer rather than the look's exit drives the next look, because a
    // look that fails to start never reports an exit; it is simply tried again.
    Timer {
        id: lookTimer
        interval: 250
        repeat: true
        onTriggered: if (!look.running) look.running = true
    }

    // Idle twice in a row before quitting: a child that has just ended may be
    // about to hand on to the next step, and a write Config has just started
    // is given a moment to land.
    Process {
        id: look
        // The shell doing the looking is a child too, so one child left means idle.
        command: ["sh", "-c", '[ "$(pgrep -c -P "$PPID")" -le 1 ]']
        onExited: (exitCode, exitStatus) => {
            root._idleLooks = (exitCode === 0 && !Config.writePending) ? root._idleLooks + 1 : 0;
            if (root._idleLooks >= 2) {
                lookTimer.stop();
                Qt.quit();
            }
        }
    }

    Timer {
        id: giveUpTimer
        interval: root.giveUpAfter
        onTriggered: Qt.quit()
    }
}
