pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Applies saved themes atomically in the main shell process so external writes
 * and the shell's own Config adapter can't race on config.json. Exposes an IPC
 * target so the settings app (separate process) can request an apply without
 * running bash itself.
 *
 * Also hosts the Day/Night themes scheduler — see _evaluateSchedule below for
 * the apply-when-boundary-crossed logic. The scheduler must live in the main
 * shell process (where this singleton is loaded) so transitions still fire
 * when the Settings window is closed.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/themes/apply-theme.sh`
    readonly property string themesDir: `${FileUtils.trimFileProtocol(Directories.home)}/.config/mainstream/themes`

    signal applied(string slug)
    signal applyFailed(string slug, string message)

    function load() {} // For forcing initialization

    // Cache of valid slugs from themes/index.json — populated by
    // themesIndexProc below. The scheduler checks this before calling
    // apply() so a stale Config (e.g. user deleted a theme after
    // selecting it as Day or Night) silently gets skipped instead of
    // running the apply script against a phantom slug.
    property var _validSlugs: ({})
    // Flips true after the first index parse completes. Without this
    // gate, the scheduler can fire on Config-ready / Hyprsunset signals
    // BEFORE the index has loaded — every slug would look "valid"
    // (empty cache → guard skipped) and a phantom apply would slip
    // through with no chance for validation.
    property bool _validSlugsLoaded: false

    function _refreshValidSlugs() {
        themesIndexProc.running = false
        themesIndexProc.running = true
    }
    Process {
        id: themesIndexProc
        property string buf: ""
        // The index is a record of what was saved, not of what is there now: a
        // theme directory removed any other way than through this page stays
        // listed. A slug only counts as real if its directory is on disk, or the
        // scheduler applies one that isn't and gives up on the window.
        command: ["bash", "-c",
            `cd "$1" 2>/dev/null || exit 0\n` +
            `jq -r '.[].slug // empty' index.json 2>/dev/null | while IFS= read -r s; do\n` +
            `  [ -n "$s" ] && [ -d "$s" ] && printf '%s\\n' "$s"\n` +
            `done`,
            "theme-index", root.themesDir]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => themesIndexProc.buf += data + "\n" }
        onExited: {
            let map = ({})
            const slugs = (themesIndexProc.buf || "").split("\n")
            for (let i = 0; i < slugs.length; ++i) {
                const s = slugs[i].trim()
                if (s.length > 0) map[s] = true
            }
            root._validSlugs = map
            root._validSlugsLoaded = true
            // Auto-clear phantom Day/Night slugs that point to themes
            // no longer on disk (most often: user deleted the theme).
            // Without this, the scheduler would silently skip apply on
            // every evaluation and the dropdown would still show the
            // phantom slug as "selected" even though there's no card.
            //
            // Only when the index parsed into something: an empty map means
            // unreadable or caught mid-rewrite, not empty, and clearing on that
            // reading wipes the picks — by writing config.json from
            // Component.onCompleted, which startup must never do.
            const sched = Config.options?.appearance?.themeSchedule
            if (sched && Object.keys(map).length > 0) {
                if (sched.daySlug && !map[sched.daySlug]) sched.daySlug = ""
                if (sched.nightSlug && !map[sched.nightSlug]) sched.nightSlug = ""
            }
            // Same invalidation for _lastScheduledSlug — it normally tracks
            // what's actually on screen, but if the user deletes the active
            // theme (e.g. nightSlug during night hours) we leave the orphan
            // colours up by design (no jarring auto-switch), and the slug
            // sticks around here pointing at a theme that's gone from disk.
            // Purely defensive: nothing in the current codebase reads this
            // outside the eval-skip check (which self-heals on the next
            // boundary), but resetting it keeps the bookkeeping honest so
            // future readers don't inherit a phantom slug.
            if (root._lastScheduledSlug && !map[root._lastScheduledSlug]) {
                root._lastScheduledSlug = ""
            }
            // Re-run the scheduler now that we know which slugs are real;
            // a previously-blocked phantom slug check might now succeed.
            Qt.callLater(root._evaluateSchedule)
        }
    }

    function apply(slug) {
        if (!slug || slug.length === 0) return
        // Cross-process race guard: settings UI's IPC apply and the main
        // shell's Config-watcher-driven _evaluateSchedule can both reach
        // here for the same slug after a single dropdown pick. Whoever
        // arrives second would otherwise restart the apply-theme.sh
        // process (running=false→true) cancelling the first run mid-flight.
        // Same-slug duplicates are now skipped; different-slug calls still
        // restart (latest pick wins).
        if (applyProc.running && applyProc.pendingSlug === slug) return
        // Block the live adapter from racing with our staged write-and-move.
        Config.blockWrites = true
        applyProc.pendingSlug = slug
        applyProc.command = ["bash", root.scriptPath, slug]
        applyProc.running = false
        applyProc.running = true
        // Bookkeeping for _evaluateSchedule: it short-circuits when the
        // computed target already matches _lastScheduledSlug, so every
        // apply (scheduler-driven OR a Day/Night dropdown pick that
        // matches the current window) must move the baseline forward
        // here. The Themes-page grid can't reach this in schedule-on
        // states because the lockout disables its Apply buttons; the
        // only callers left are the scheduler itself and the dropdown
        // fast-path that mirrors what the scheduler would compute next.
        root._lastScheduledSlug = slug
    }

    Process {
        id: applyProc
        property string pendingSlug: ""
        // apply-theme.sh explains why it rolled back. With nowhere to put that
        // output the channel is closed and the explanation is discarded, which
        // leaves a failed apply with nothing to report but a number.
        stderr: StdioCollector { id: applyStderr }
        onExited: (exitCode, exitStatus) => {
            // Cancelled to start a different theme: pendingSlug already names
            // the replacement, so anything reported here names the wrong one.
            // blockWrites is left alone too — the run now underway set it.
            if (exitCode === 143 || exitCode === 137) return
            Config.blockWrites = false
            // Force a re-read of the generated colors.json. Matugen writes via
            // rename which can leave QFileSystemWatcher tracking a stale inode,
            // so onFileChanged doesn't always fire.
            MaterialThemeLoader.reapplyTheme()
            if (exitCode === 0) {
                root._failedSlug = ""
                root._failedAttempts = 0
                root.applied(applyProc.pendingSlug)
            } else {
                const reason = (applyStderr.text ?? "").trim()
                const failedSlug = applyProc.pendingSlug
                root.applyFailed(failedSlug, reason.length > 0 ? reason : "exit " + exitCode)
                // The scheduler short-circuits while its baseline still matches
                // the computed target, so clearing the baseline is what lets the
                // next tick try again. Bounded, since ticks are once a minute
                // and each attempt costs a notification.
                let scheduleRetry = false
                if (failedSlug === root._lastScheduledSlug) {
                    root._failedAttempts = (root._failedSlug === failedSlug) ? root._failedAttempts + 1 : 1
                    root._failedSlug = failedSlug
                    if (root._failedAttempts < root._maxScheduleRetries) {
                        root._lastScheduledSlug = ""
                        scheduleRetry = root._failedAttempts > 1
                    }
                }
                // A theme that rolls back puts the previous one back and says
                // nothing, so the desktop simply doesn't change and the user is
                // left to guess. The Settings page can't be relied on to carry
                // this — applies are started over IPC and land in this process,
                // not in the one drawing that page, which may not even be open.
                console.log("[ThemeManager] apply failed for " + failedSlug + ": " + reason)
                // Said once per failure, not once per retry of the same one.
                if (!scheduleRetry) {
                    Quickshell.execDetached(["notify-send",
                        Translation.tr("Couldn't apply that theme"),
                        Translation.tr("Your previous theme is still in place."),
                        "-a", "Shell"])
                }
            }
        }
    }

    IpcHandler {
        target: "themes"

        function apply(slug: string): void {
            root.apply(slug);
        }
    }

    // ── Day/Night scheduler ────────────────────────────────────────────────
    // Tracks the most recently applied slug so _evaluateSchedule can
    // short-circuit on every clock tick when nothing has changed —
    // otherwise the scheduler would fire apply-theme.sh once a minute
    // for the same target. Updated by apply(), which is the only place
    // the live theme actually changes.
    property string _lastScheduledSlug: ""

    // Which scheduled slug last failed, and how many times running. Cleared by
    // any successful apply.
    property string _failedSlug: ""
    property int _failedAttempts: 0
    readonly property int _maxScheduleRetries: 3

    // Gate: only the main shell (shell.qml's Component.onCompleted) flips
    // this on. The settings.qml process loads ThemeManager too as part of
    // qs.services, but its IPC handler routes back to the main shell, so
    // letting BOTH processes auto-apply would race the apply script with
    // itself. Settings still re-evaluates indirectly: it writes to Config,
    // the main shell's Config FileView reloads, and the Connections below
    // fire there.
    property bool _autoApplyEnabled: false

    function _evaluateSchedule() {
        if (!Config.ready) return
        if (!root._autoApplyEnabled) return
        // Without the index loaded we can't tell phantom slugs from real
        // ones, and applying a phantom would set _lastScheduledSlug to
        // it, masking the failure on every subsequent evaluation. Wait
        // for themesIndexProc to finish — it calls _evaluateSchedule
        // again itself once it's done.
        if (!root._validSlugsLoaded) return
        const s = Config.options.appearance.themeSchedule
        if (!s || s.mode === "off") return
        let target = ""
        if (s.mode === "nightlight") {
            // Bind to the same shouldBeOn signal Hyprsunset uses for its own
            // filter, so theme changes line up with Night Light transitions.
            target = Hyprsunset.shouldBeOn ? s.nightSlug : s.daySlug
        } else if (s.mode === "manual") {
            const now = new Date()
            const t = now.getHours() * 60 + now.getMinutes()
            const dayParts = (s.dayFrom || "06:00").split(":")
            const nightParts = (s.nightFrom || "20:00").split(":")
            const dayMin = (parseInt(dayParts[0], 10) || 0) * 60 + (parseInt(dayParts[1], 10) || 0)
            const nightMin = (parseInt(nightParts[0], 10) || 0) * 60 + (parseInt(nightParts[1], 10) || 0)
            // Day window = [dayFrom, nightFrom). Wraps around midnight if
            // the user inverts the order (night-shifted setup).
            const isDayWindow = dayMin < nightMin
                ? (t >= dayMin && t < nightMin)
                : (t >= dayMin || t < nightMin)
            target = isDayWindow ? s.daySlug : s.nightSlug
        }
        if (!target || target === root._lastScheduledSlug) return
        // Reject phantom slugs (theme renamed/deleted after being
        // selected as Day or Night). Without this guard apply() would
        // run the bash script with a slug that has no directory, fail,
        // and leave the system applying nothing — but _lastScheduledSlug
        // would have moved, masking the failure on later evaluations.
        if (Object.keys(root._validSlugs).length > 0 && !root._validSlugs[target]) return
        root.apply(target)   // updates _lastScheduledSlug via apply()
    }

    // Hyprsunset already maintains a clock-minute property and
    // computes shouldBeOn from from/to. Reuse both to avoid a second
    // timer doing the same work.
    Connections {
        target: Hyprsunset
        function onClockMinuteChanged() { root._evaluateSchedule() }
        function onShouldBeOnChanged()  { root._evaluateSchedule() }
    }

    // Re-evaluate immediately when the user changes any scheduler-relevant
    // setting in the Settings page. Bound separately rather than to the
    // whole `themeSchedule` object so a wallpaper-path tweak elsewhere
    // doesn't trigger an unrelated re-evaluation.
    Connections {
        target: Config.options?.appearance?.themeSchedule ?? null
        function onModeChanged()      { root._evaluateSchedule() }
        function onDaySlugChanged()   { root._evaluateSchedule() }
        function onNightSlugChanged() { root._evaluateSchedule() }
        function onDayFromChanged()   { root._evaluateSchedule() }
        function onNightFromChanged() { root._evaluateSchedule() }
    }

    // First-run / shell-reload pass: apply the right theme as soon as Config
    // and Hyprsunset are both ready, even if no setting just changed.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) Qt.callLater(root._evaluateSchedule)
        }
    }

    // Refresh the valid-slug cache on startup, and again whenever the
    // theme library changes. The FileView watcher below catches save /
    // delete from any process (settings UI or a future CLI tool) by
    // watching index.json directly — that file is the canonical record
    // of what's installed. apply-theme.sh doesn't touch index.json, so
    // there's nothing to refresh on a successful apply.
    Component.onCompleted: root._refreshValidSlugs()
    FileView {
        path: `${root.themesDir}/index.json`
        watchChanges: true
        onFileChanged: root._refreshValidSlugs()
    }
}
