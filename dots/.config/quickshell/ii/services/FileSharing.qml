pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * FileSharing: folders shared with other computers on the home network.
 *
 * scripts/sharing/sharing.sh reads the state and manages the shares, which
 * needs no root. Everything that does (installing Samba, the sharing account,
 * which networks are trusted, the computer's name) goes through the
 * mainstream-system helper under pkexec. This service is the Settings side of
 * both, and it holds every bit of state the Sharing page shows, because
 * Settings rebuilds its pages on each switch and color change.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/sharing/sharing.sh")
    readonly property string helperPath: "/usr/lib/mainstream/file-sharing"
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/mainstream"
    // The folder Files asked to share, kept on disk because setup outlives
    // this window: the Files extension shares it when setup finishes with
    // Settings closed. Holds the absolute path and nothing else.
    readonly property string pendingPath: root.stateDir + "/sharing-pending"
    // Which keyring copy of the sharing password is the current one. Not
    // secret. The first line is the id of the copy to read, empty when none
    // is saved; the lines after it are older copies still to be removed.
    readonly property string passwordIdPath: root.stateDir + "/sharing-password-id"

    // What `sharing.sh status` last said. `loaded` stays false until the
    // first answer, so the page can hold its switches still until then.
    property bool loaded: false
    property bool helper: false
    property bool installed: false
    property string config: "none"
    property string sharingState: "unset"
    property bool serviceRunning: false
    // The helper refuses to turn sharing on or trust a network while firewalld
    // is stopped, since nothing would keep port 445 to the home network.
    property bool firewall: true
    property bool account: false
    property string user: ""
    property string hostname: ""
    property var addresses: []
    property string current: ""
    property var connections: []
    property var shares: []

    readonly property var currentConnection: root.connections.find(c => c.uuid === root.current) ?? null
    // A share whose folder was deleted, moved or unplugged stays listed so it
    // can be removed, but nothing is served from it.
    readonly property var liveShares: root.shares.filter(s => s.missing !== true)
    readonly property bool foreign: root.config === "foreign"
    // Removing Samba by hand leaves the state file saying "on", and a switch
    // showing on over a service that is gone would be a lie.
    readonly property bool isOn: root.sharingState === "on" && root.installed
    // On for the computer and set up for this account, so folders can go out.
    readonly property bool ready: root.isOn && root.account

    // The sharing password lives in the keyring so the page can show it again.
    // Without a keyring it is shown once, right after it is set, and kept only
    // until the page is left.
    //
    // It is a keyring item of its own rather than a field in KeyringStorage's
    // shared entry. Every process writes that whole entry from the copy it
    // read, so the shell saving an API key would drop a password Settings
    // saved after the shell's read, and the other way round.
    //
    // Only the copy tagged with the id in passwordIdPath is read. A keyring
    // that is locked or not running keeps whatever copy it has when a new
    // password is set, so a save it refuses clears that id: the old copy,
    // now wrong, can then never come back as the password once the keyring
    // opens again.
    readonly property string secretApplication: "mainstream-file-sharing"
    property string storedPassword: ""
    property string revealedPassword: ""
    readonly property string password: root.revealedPassword.length > 0 ? root.revealedPassword : root.storedPassword
    // Whether the last read or save reached an unlocked keyring, so a
    // password can be saved there.
    property bool keyringOk: false
    property bool keyringChecked: false
    // A password is saved, but the keyring is locked, so it cannot be read.
    property bool keyringLocked: false
    // Until the read is in, a saved password looks missing, and turning
    // sharing back on would give Samba a new one.
    readonly property bool keyringPending: !root.keyringChecked || lookupProc.running
    // Set up, and the password other computers sign in with is in a locked
    // keyring. Turning sharing back on waits for it to be unlocked, rather
    // than replacing a password that was only out of reach.
    readonly property bool passwordLocked: root.account && root.keyringLocked && root.password.length === 0
    // Set up, but this computer does not know the password other computers
    // sign in with.
    readonly property bool passwordMissing: root.account && !root.keyringPending && !root.keyringLocked && root.password.length === 0

    // One change at a time. busyTarget names the share or network it is for,
    // so that row can hold still while the rest of the page stays readable.
    property string busyAction: ""
    property string busyTarget: ""
    // A setup started from a window that has since closed goes on as root,
    // and this page must neither start a second one nor look idle meanwhile.
    property bool helperBusy: false
    readonly property bool busy: root.busyAction !== "" || root.helperBusy
    readonly property bool settingUp: root.busyAction === "enable" || root.busyAction === "account" || root.helperBusy

    // The scope says which section the message belongs under: "setup",
    // "folders", "networks", "name" or "password".
    property string lastError: ""
    property string errorScope: ""

    // A folder Files asked to share. It goes out as View only once this
    // account is ready, in place of the Public folder suggestion.
    property string pendingFolder: ""
    // Whether that folder is shared already, so it keeps the access it has
    // and the page must not promise View only. Only meaningful once checked.
    property bool pendingChecked: false
    property bool pendingShared: false
    property string pendingAccess: ""

    // Emitted after every status read that was applied, and after a change
    // that was refused before anything ran, so switches that a click moved
    // can be put back where the system says they are.
    signal refreshed()
    signal passwordSuggested(string suggestion)
    signal passwordSaved()
    signal renamed()

    // The same rules the helper applies. A password is one line of printable
    // characters, as the helper reads it from stdin.
    function validHostname(name) {
        return /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(name);
    }

    function validPassword(pw) {
        return /^[\x20-\x7E]{8,128}$/.test(pw);
    }

    // ---- page visibility -------------------------------------------------

    // The page counts itself in and out. A rebuild destroys one page and
    // makes the next, so the count briefly touches zero; the leave timer
    // waits that out before treating the page as closed.
    property int watchers: 0

    function watch() {
        // A rebuild comes back while the leave timer runs, and the keyring
        // has not changed since the read a moment ago. A new visit reads it
        // again, in case it was unlocked in between.
        const rebuilt = leaveTimer.running;
        root.watchers += 1;
        leaveTimer.stop();
        if (!rebuilt)
            root.readPassword();
        root.refresh(true);
    }

    function unwatch() {
        root.watchers = Math.max(0, root.watchers - 1);
        if (root.watchers === 0)
            leaveTimer.restart();
    }

    Timer {
        id: leaveTimer
        interval: 1000
        onTriggered: {
            if (root.watchers > 0)
                return;
            root.revealedPassword = "";
            root.clearError();
        }
    }

    // Networks come and go while the page is open, and the Files menu can
    // share a folder behind its back, so it keeps reading while it is shown.
    // A setup running from another window is only seen ending this way.
    Timer {
        interval: 5000
        repeat: true
        running: root.watchers > 0 && root.busyAction === ""
        onTriggered: root.refresh(false)
    }

    // ---- status ----------------------------------------------------------

    property string lastStatus: ""
    property bool forceApply: false
    property bool refreshQueued: false
    // Bumped whenever a change finishes. A read that started before then
    // describes the machine as it was, so it is dropped for the one queued
    // behind it.
    property int generation: 0

    function refresh(force) {
        if (force)
            root.forceApply = true;
        if (root.statusBusy) {
            root.refreshQueued = true;
            return;
        }
        root.statusBusy = true;
        statusProc.startedAt = root.generation;
        statusProc.running = true;
    }

    property bool statusBusy: false

    Process {
        id: statusProc
        property int startedAt: 0
        // Through bash, so a missing or unexecutable script still ends in an
        // answer (an empty one) instead of a process that never started.
        command: ["bash", root.scriptPath, "status"]
        stdout: StdioCollector {
            id: statusOut
        }
        onExited: root.statusFinished()
    }

    function statusFinished() {
        root.statusBusy = false;
        if (statusProc.startedAt === root.generation)
            root.applyStatus(statusOut.text);
        else
            root.refreshQueued = true;
        if (root.refreshQueued) {
            root.refreshQueued = false;
            // After this handler returns, when the process has let go.
            Qt.callLater(() => root.refresh(false));
        }
    }

    function parseJson(text) {
        try {
            return JSON.parse(String(text ?? "").trim());
        } catch (e) {
            return null;
        }
    }

    function applyStatus(text) {
        const force = root.forceApply;
        root.forceApply = false;
        // An unchanged answer is not reassigned: the lists would rebuild
        // every row and close a dropdown someone has open.
        if (!force && root.loaded && text === root.lastStatus)
            return;
        root.lastStatus = text;

        let s = root.parseJson(text);
        // No answer reads as no helper, which shows the page's update notice
        // rather than switches that cannot work.
        if (!s || typeof s !== "object" || s.error !== undefined)
            s = {};

        root.helper = s.helper === true;
        root.installed = s.installed === true;
        root.config = typeof s.config === "string" ? s.config : "none";
        root.sharingState = typeof s.state === "string" ? s.state : "unset";
        root.serviceRunning = s.running === true;
        root.firewall = s.firewall !== false;
        root.helperBusy = s.busy === true;
        root.account = s.account === true;
        root.user = typeof s.user === "string" ? s.user : "";
        root.hostname = typeof s.hostname === "string" ? s.hostname : "";
        root.addresses = Array.isArray(s.addresses) ? s.addresses : [];
        root.current = typeof s.current === "string" ? s.current : "";
        root.connections = Array.isArray(s.connections) ? s.connections : [];
        root.shares = Array.isArray(s.shares) ? s.shares : [];
        root.loaded = true;

        // A setup that failed late may still have set the account up with the
        // password it was given. Kept only when the account appeared during
        // that run, so the page never shows a password Samba does not have.
        if (root.unconfirmedPassword.length > 0) {
            if (root.account)
                root.keepPassword(root.unconfirmedPassword);
            root.unconfirmedPassword = "";
        }

        root.refreshed();
        root.sharePendingFolder();
    }

    // ---- errors ----------------------------------------------------------

    function clearError() {
        root.lastError = "";
        root.errorScope = "";
    }

    function fail(scope, message) {
        root.errorScope = scope;
        root.lastError = message;
    }

    // Why a network cannot be trusted, from the reason sharing.sh gives:
    // "open" for Wi-Fi anyone can join, "weak" for WEP, "private" for a
    // profile saved for one account, "zone" for one given a firewall zone by
    // hand. Only a private Wi-Fi profile is given a way forward: forgetting
    // it on the Wi-Fi page and connecting again saves it for every account.
    // Nothing in Settings does that for a wired profile, or edits a
    // profile's zone, so those texts name no control to do it with.
    function ineligibleMessage(conn) {
        const name = conn?.name ?? "";
        let why = "";
        if (conn?.reason === "open")
            why = Translation.tr("%1 has no password, so anyone nearby can join it. Sharing is not offered on open networks.").arg(name);
        else if (conn?.reason === "weak")
            why = Translation.tr("%1 uses old Wi-Fi security that is easy to break, so sharing is not offered on it.").arg(name);
        else if (conn?.reason === "private" && conn?.type === "wifi")
            why = Translation.tr("%1 is saved for one account only, so sharing is not offered on it. To share on it, forget this network on the Wi-Fi page, then connect to it again.").arg(name);
        else if (conn?.reason === "private")
            why = Translation.tr("%1 is saved for one account only, so sharing is not offered on it.").arg(name);
        else if (conn?.reason === "zone")
            why = Translation.tr("%1 has its own firewall zone, so sharing is not offered on it. Sharing can be turned on here once that zone is cleared.").arg(name);
        // A network trusted before it stopped passing these checks keeps its
        // switch on under Networks, since that switch is the only way to take
        // the trust back, yet the helper no longer shares on it.
        if (why.length > 0 && conn?.trusted === true)
            why += " " + Translation.tr("Your folders stay closed on %1, even though it is turned on under Networks.").arg(name);
        return why;
    }

    function networkRefusal(conn) {
        return conn && (conn.reason ?? "") !== ""
            ? root.ineligibleMessage(conn)
            : Translation.tr("Connect to your home network first, then turn this on.");
    }

    function firewallMessage() {
        return Translation.tr("The firewall is turned off, so sharing stays off to keep your folders safe. Turn the firewall back on to share folders.");
    }

    // The helper's exit codes, and pkexec's own for a prompt that was
    // dismissed or refused. uuid names the network the run was for, if any.
    function helperMessage(verb, code, err, uuid) {
        if (code === 126 || code === 127)
            return verb === "enable"
                ? Translation.tr("Sharing was not turned on: authentication was canceled.")
                : Translation.tr("The change was not made: authentication was canceled.");
        if (code === 3)
            return Translation.tr("This computer already has its own Samba setup, so it was left alone.");
        if (code === 4)
            return Translation.tr("The sharing service could not be downloaded. Check your internet connection, or run Update first, then try again.");

        // The helper's last line says why, in English whatever the locale.
        const lines = String(err ?? "").split("\n").map(l => l.trim()).filter(l => l.length > 0);
        const reason = lines.length > 0 ? lines[lines.length - 1].replace(/^file-sharing:\s*/, "") : "";
        // The page checks both of these before asking, but the firewall can
        // stop and a zone can be set while the prompt is up.
        if (code === 1 && reason.startsWith("the firewall is not running"))
            return root.firewallMessage();
        if (code === 5) {
            const conn = root.connections.find(c => c.uuid === uuid);
            return root.networkRefusal(conn && reason.includes("has its own firewall zone") ? { name: conn.name, reason: "zone" } : null);
        }

        let fallback = Translation.tr("The change could not be applied.");
        if (verb === "enable")
            fallback = Translation.tr("Sharing was not turned on.");
        else if (verb === "account")
            fallback = Translation.tr("Your account could not be set up for sharing.");
        else if (verb === "password")
            fallback = Translation.tr("The sharing password was not changed.");
        // Untranslated, so it goes beside the translated sentence rather than
        // in place of it.
        return reason.length > 0 ? `${fallback} (${reason})` : fallback;
    }

    function scriptMessage(verb, code) {
        switch (code) {
        case "not-owner":
            return Translation.tr("You can only share folders that belong to you.");
        case "home":
            return Translation.tr("Your home folder holds your private settings and keys, so it cannot be shared as a whole. Share the folders inside it instead.");
        // Also a folder whose own name has no dot, inside one that does.
        case "hidden":
            return Translation.tr("Hidden folders, whose names start with a dot, and the folders inside them hold app settings and keys, so they cannot be shared. Choose a regular folder instead.");
        case "not-dir":
            return Translation.tr("That folder no longer exists.");
        case "no-access":
            return Translation.tr("Your account cannot share folders yet. Sign out and back in, then try again.");
        case "percent":
            return Translation.tr("Folders with a percent sign (%) followed by a letter in their path cannot be shared. Rename the folder, then try again.");
        }
        return verb === "add"
            ? Translation.tr("The folder could not be shared.")
            : Translation.tr("The change could not be applied.");
    }

    // ---- the keyring -----------------------------------------------------

    function readPassword() {
        if (lookupProc.running)
            return;
        lookupProc.startedAt = root.storeGeneration;
        lookupProc.running = true;
    }

    // Prints the password and exits 0 when found. Otherwise 1 for an unlocked
    // keyring without it, 3 for a locked one that may hold it, and 2 for no
    // keyring, or a locked one when nothing was ever saved. The lookup itself
    // brings up the keyring's own unlock prompt.
    Process {
        id: lookupProc
        property int startedAt: 0
        command: ["bash", "-c",
            'id=$(head -n 1 -- "$1" 2>/dev/null); '
            + 'if [ -n "$id" ]; then '
            + 'pw=$(secret-tool lookup application "$2" id "$id" 2>/dev/null); '
            + 'if [ -n "$pw" ]; then printf %s "$pw"; exit 0; fi; fi; '
            + 's=$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login '
            + 'org.freedesktop.Secret.Collection Locked 2>/dev/null); '
            + '[ "$s" = "b false" ] && exit 1; '
            + '[ "$s" = "b true" ] && [ -n "$id" ] && exit 3; '
            + 'exit 2',
            "--", root.passwordIdPath, root.secretApplication]
        stdout: StdioCollector {
            id: lookupOut
        }
        onExited: code => root.lookupFinished(code, lookupOut.text)
    }

    function lookupFinished(code, text) {
        root.keyringChecked = true;
        // A save made while this read ran is newer than what it found, and
        // says for itself whether the keyring took it.
        if (lookupProc.startedAt !== root.storeGeneration || storeProc.running)
            return;
        root.keyringOk = code === 0 || code === 1;
        root.keyringLocked = code === 3;
        root.storedPassword = code === 0 && root.validPassword(text) ? text : "";
    }

    property int storeGeneration: 0

    // reveal: show the password once if the keyring refuses it. Off for a
    // password saved ahead of a setup that may not happen.
    function storePassword(pw, reveal) {
        root.storeGeneration += 1;
        root.storedPassword = pw;
        if (storeProc.running) {
            storeProc.queued = pw;
            storeProc.queuedReveal = reveal;
            return;
        }
        root.startStore(pw, reveal);
    }

    function startStore(pw, reveal) {
        storeProc.password = pw;
        storeProc.reveal = reveal;
        storeProc.stdinEnabled = true;
        storeProc.running = true;
    }

    // Saves over the current copy, or under a new id when none is current.
    // The id is random, so a lost id file can never match an old copy again.
    // Once a save lands, the older copies listed are removed; a refused save
    // leaves no current id and lists this one's for removal.
    Process {
        id: storeProc
        property string password: ""
        property bool reveal: false
        property string queued: ""
        property bool queuedReveal: false
        command: ["bash", "-c",
            'f=$1; ids=(); if [ -r "$f" ]; then mapfile -t ids < "$f"; fi; '
            + 'id=${ids[0]}; '
            + '[ -n "$id" ] || id=$(od -An -N8 -tx1 /dev/urandom | tr -d " \\n"); '
            + '[ -n "$id" ] || exit 1; '
            + 'save() { mkdir -p -- "${f%/*}" && printf "%s\\n" "$@" > "$f.new" && mv -f -- "$f.new" "$f"; }; '
            + 'save "$id" "${ids[@]:1}" || exit 1; '
            + 'if secret-tool store --label="$3" application "$2" id "$id"; then '
            + 'for old in "${ids[@]:1}"; do [ -z "$old" ] || secret-tool clear application "$2" id "$old"; done; '
            + 'save "$id"; exit 0; fi; '
            + 'save "" "$id" "${ids[@]:1}"; exit 1',
            "--", root.passwordIdPath, root.secretApplication, Translation.tr("Mainstream Sharing Password")]
        // No newline: secret-tool keeps every byte it reads as the secret.
        onRunningChanged: {
            if (running) {
                write(password);
                stdinEnabled = false;
            }
        }
        onExited: code => {
            const pw = storeProc.password;
            storeProc.password = "";
            root.keyringOk = code === 0;
            // Saved means the keyring is open, and refused means no copy is
            // current any more; either way nothing is locked away.
            root.keyringLocked = false;
            if (code !== 0 && storeProc.queued.length === 0 && root.storedPassword === pw) {
                root.storedPassword = "";
                if (storeProc.reveal)
                    root.revealedPassword = pw;
            }
            if (storeProc.queued.length > 0) {
                const next = storeProc.queued;
                const nextReveal = storeProc.queuedReveal;
                storeProc.queued = "";
                // After this handler returns, when the process has let go.
                Qt.callLater(() => root.startStore(next, nextReveal));
            }
        }
    }

    // ---- the root helper -------------------------------------------------

    // Holds a new password between a failed setup and the status read that
    // says whether the account step had already run.
    property string unconfirmedPassword: ""

    // Saved even when the last read found no open keyring: saving asks for
    // it to be unlocked, and a save it refuses still retires the old copy,
    // then shows this password once.
    function keepPassword(pw) {
        root.revealedPassword = "";
        if (root.storedPassword !== pw) {
            root.storePassword(pw, true);
            return;
        }
        // Saved ahead of the prompt and possibly still being saved; the
        // account exists now, so a refusal has to show it.
        if (storeProc.running && storeProc.password === pw)
            storeProc.reveal = true;
        else if (storeProc.queued === pw)
            storeProc.queuedReveal = true;
    }

    function runHelper(verb, args, scope, pw) {
        // Setup can outlive this window, and a password held only here would
        // go with it, leaving Samba with one nobody knows. So a new account's
        // password is saved before the prompt; the page shows it only once
        // the account exists. An existing account's new one waits for the run
        // to succeed, since a canceled prompt leaves Samba with the old one.
        if ((verb === "enable" || verb === "account") && !root.account && root.keyringOk
                && (pw ?? "").length > 0 && pw !== root.storedPassword)
            root.storePassword(pw, false);
        root.busyAction = verb;
        helperProc.verb = verb;
        helperProc.scope = scope;
        helperProc.uuid = verb === "enable" || verb === "trust" ? (args[0] ?? "") : "";
        helperProc.password = pw ?? "";
        helperProc.input = pw ?? "";
        helperProc.hadAccount = root.account;
        helperProc.command = ["pkexec", root.helperPath, verb].concat(args);
        // stdinEnabled has to be on before running goes true, or the write
        // lands after the helper has already read.
        helperProc.stdinEnabled = helperProc.input.length > 0;
        helperProc.running = true;
    }

    Process {
        id: helperProc
        property string verb: ""
        property string scope: ""
        property string uuid: ""
        property string input: ""
        property string password: ""
        property bool hadAccount: false
        stderr: StdioCollector {
            id: helperErr
        }
        // A password handed over as an argument is readable in ps by anyone
        // on the machine while the command runs, so it goes down stdin.
        // Closing the stream is what lets the helper's read return.
        onRunningChanged: {
            if (running && input.length > 0) {
                write(input + "\n");
                input = "";
                stdinEnabled = false;
            }
        }
        onExited: code => root.helperFinished(code)
    }

    function helperFinished(code) {
        const verb = helperProc.verb;
        const pw = helperProc.password;
        helperProc.password = "";
        root.busyAction = "";
        root.busyTarget = "";

        const setsPassword = verb === "enable" || verb === "account" || verb === "password";
        if (code === 0) {
            if (setsPassword && pw.length > 0)
                root.keepPassword(pw);
            if (verb === "password")
                root.passwordSaved();
            else if (verb === "rename")
                root.renamed();
            else if (verb === "disable")
                root.dropPendingFolder();
        } else {
            root.fail(helperProc.scope, root.helperMessage(verb, code, helperErr.text, helperProc.uuid));
            // Already saved means it is shown the moment the account exists.
            if ((verb === "enable" || verb === "account") && !helperProc.hadAccount && root.storedPassword !== pw)
                root.unconfirmedPassword = pw;
        }
        root.generation += 1;
        root.refresh(true);
    }

    // ---- sharing.sh verbs ------------------------------------------------

    function runScript(verb, command, target) {
        root.busyAction = verb;
        root.busyTarget = target ?? "";
        scriptProc.verb = verb;
        scriptProc.command = command;
        scriptProc.running = true;
    }

    Process {
        id: scriptProc
        property string verb: ""
        stdout: StdioCollector {
            id: scriptOut
        }
        onExited: code => root.scriptFinished(code)
    }

    function scriptFinished(code) {
        const verb = scriptProc.verb;
        const reply = root.parseJson(scriptOut.text);
        root.busyAction = "";
        root.busyTarget = "";
        if (code !== 0 || !reply || reply.error !== undefined)
            root.fail("folders", root.scriptMessage(verb, reply?.error ?? ""));
        root.generation += 1;
        root.refresh(true);
    }

    // ---- actions ---------------------------------------------------------

    // Turns sharing on for this computer and trusts the network it is on now.
    // Turning it back on keeps the password other computers already saved,
    // as long as this computer knows it. Otherwise a new one is made, and the
    // page says so before the switch is flipped.
    function enable() {
        if (root.busy)
            return;
        if (root.keyringPending || root.passwordLocked) {
            root.refreshed();
            return;
        }
        root.clearError();
        // The page already says why, and the helper would refuse it only
        // after the password prompt.
        if (!root.firewall) {
            root.refreshed();
            return;
        }
        // The page holds the switch while it shows why the network it is on
        // is not offered; the helper would refuse it only after the prompt.
        const conn = root.currentConnection;
        if (!conn || !conn.eligible) {
            root.fail("setup", root.networkRefusal(conn));
            root.refreshed();
            return;
        }
        if (root.account && root.password.length > 0) {
            root.runHelper("enable", [conn.uuid], "setup", root.password);
            return;
        }
        if (root.reuseSavedPassword("enable", [conn.uuid]))
            return;
        root.generateFor("enable", [conn.uuid], "setup");
    }

    // A second account on a computer that already shares.
    function setUpAccount() {
        if (root.busy || root.keyringPending)
            return;
        root.clearError();
        if (root.reuseSavedPassword("account", []))
            return;
        root.generateFor("account", [], "setup");
    }

    // A password saved ahead of an earlier setup that was canceled or timed
    // out may be the one Samba got, if that run went on as root. A new one
    // would leave the keyring and Samba with different passwords, so it is
    // given again.
    function reuseSavedPassword(verb, args) {
        if (root.account || !root.validPassword(root.storedPassword))
            return false;
        root.runHelper(verb, args, "setup", root.storedPassword);
        return true;
    }

    function disable() {
        if (root.busy)
            return;
        root.clearError();
        root.runHelper("disable", [], "setup");
    }

    function trust(uuid, on) {
        if (root.busy || !uuid)
            return;
        root.clearError();
        // Refused here rather than by the helper, which would ask for a
        // password first. The forced read puts the switch back.
        if (on && !root.firewall) {
            root.fail("networks", root.firewallMessage());
            root.refresh(true);
            return;
        }
        const conn = root.connections.find(c => c.uuid === uuid);
        if (on && conn && !conn.eligible) {
            root.fail("networks", root.networkRefusal(conn));
            root.refresh(true);
            return;
        }
        root.busyTarget = uuid;
        root.runHelper("trust", [uuid, on ? "on" : "off"], "networks");
    }

    function trustCurrent() {
        if (root.busy || !root.currentConnection || !root.firewall)
            return;
        root.clearError();
        root.runHelper("trust", [root.current, "on"], "setup");
    }

    function changePassword(pw) {
        if (root.busy)
            return;
        root.clearError();
        if (!root.validPassword(pw)) {
            root.fail("password", Translation.tr("Use 8 to 128 characters. Letters with accents and emoji are not allowed."));
            return;
        }
        root.runHelper("password", [], "password", pw);
    }

    // Checked here as well as in the helper, so a name it would refuse never
    // costs a password prompt.
    function rename(name) {
        if (root.busy)
            return;
        root.clearError();
        const clean = String(name ?? "").trim().toLowerCase();
        if (!root.validHostname(clean)) {
            root.fail("name", Translation.tr("Use lowercase letters, numbers and dashes, up to 63 characters. The name cannot start or end with a dash."));
            return;
        }
        if (clean === root.hostname) {
            root.renamed();
            return;
        }
        root.runHelper("rename", [clean], "name");
    }

    function add(path, access) {
        if (root.busy || !path)
            return;
        root.clearError();
        root.runScript("add", ["bash", root.scriptPath, "add", path, access === "edit" ? "edit" : "view"], path);
    }

    function remove(name) {
        if (root.busy || !name)
            return;
        root.clearError();
        root.runScript("remove", ["bash", root.scriptPath, "remove", name], name);
    }

    function setAccess(name, access) {
        if (root.busy || !name)
            return;
        root.clearError();
        root.runScript("access", ["bash", root.scriptPath, "access", name, access === "edit" ? "edit" : "view"], name);
    }

    // The folder xdg-user-dirs calls Public, made if it is missing. A machine
    // with the entry unset points it at home itself, which can never be
    // shared, so that falls back to ~/Public as well.
    function sharePublic() {
        if (root.busy)
            return;
        root.clearError();
        root.runScript("add", ["bash", "-c",
            'd=$(xdg-user-dir PUBLICSHARE 2>/dev/null); '
            + 'if [ -z "$d" ] || [ "$d" = "$HOME" ]; then d="$HOME/Public"; fi; '
            + 'mkdir -p -- "$d" || { echo \'{"error":"failed"}\'; exit 1; }; '
            + 'exec bash "$0" add "$d" view',
            root.scriptPath], "");
    }

    // Files names a folder when it sends someone here to set sharing up. The
    // path is kept as given, spaces and all: a folder's name can end in one,
    // and trimming it would name a different folder.
    function requestFolder(path) {
        let p = String(path ?? "").replace(/^file:\/\//, "");
        if (p.length > 1)
            p = p.replace(/\/+$/, "");
        if (!p.startsWith("/"))
            return;
        root.pendingFolder = p;
        Quickshell.execDetached(["bash", "-c",
            'mkdir -p -- "${1%/*}" && printf %s "$2" > "$1.new" && mv -f -- "$1.new" "$1"',
            "--", root.pendingPath, p]);
        root.checkPendingFolder();
        root.refresh(true);
    }

    function sharePendingFolder() {
        if (root.pendingFolder.length === 0 || root.busy || !root.ready)
            return;
        const path = root.pendingFolder;
        // Taken before the run, so a refused folder is reported once instead
        // of being tried again on every read.
        root.pendingFolder = "";
        root.checkPendingFolder();
        // Only if it still names this folder: the Files extension may have
        // taken it first, and a newer request may have replaced it since.
        Quickshell.execDetached(["bash", "-c",
            '[ "$(cat -- "$1" 2>/dev/null; printf x)" = "$2x" ] && rm -f -- "$1"',
            "--", root.pendingPath, path]);
        // A missing share at this path does not count: adding the folder
        // serves that share again under its old name.
        if (root.liveShares.some(s => s.path === path))
            return;
        root.add(path, "view");
    }

    // Turning sharing off answers a folder still waiting on setup, so the
    // request does not come back the next time sharing is turned on.
    function dropPendingFolder() {
        root.pendingFolder = "";
        root.checkPendingFolder();
        Quickshell.execDetached(["rm", "-f", "--", root.pendingPath]);
    }

    // A request left by a Settings window that closed before setup finished.
    Process {
        running: true
        command: ["cat", "--", root.pendingPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text;
                // One named since this window opened is newer.
                if (root.pendingFolder.length > 0 || !p.startsWith("/"))
                    return;
                root.pendingFolder = p;
                root.checkPendingFolder();
                root.sharePendingFolder();
            }
        }
    }

    function checkPendingFolder() {
        root.pendingChecked = false;
        root.pendingShared = false;
        root.pendingAccess = "";
        if (root.pendingFolder.length === 0 || infoProc.running)
            return;
        infoProc.forPath = root.pendingFolder;
        infoProc.command = ["bash", root.scriptPath, "info", root.pendingFolder];
        infoProc.running = true;
    }

    // info resolves symlinks the way add does, so a folder Files showed
    // through one still matches its share.
    Process {
        id: infoProc
        property string forPath: ""
        stdout: StdioCollector {
            id: infoOut
        }
        onExited: root.infoFinished()
    }

    function infoFinished() {
        if (infoProc.forPath !== root.pendingFolder) {
            // Named while this ran. After this handler returns, when the
            // process has let go.
            Qt.callLater(root.checkPendingFolder);
            return;
        }
        const info = root.parseJson(infoOut.text);
        root.pendingShared = info?.shared === true;
        root.pendingAccess = info?.access === "edit" ? "edit" : "view";
        root.pendingChecked = true;
    }

    // ---- passwords and the folder picker ---------------------------------

    function generateFor(verb, args, scope) {
        root.busyAction = verb;
        genProc.verb = verb;
        genProc.args = args;
        genProc.scope = scope;
        genProc.running = true;
    }

    function suggestPassword() {
        if (genProc.running)
            return;
        genProc.verb = "suggest";
        genProc.args = [];
        genProc.scope = "password";
        genProc.running = true;
    }

    Process {
        id: genProc
        property string verb: ""
        property var args: []
        property string scope: ""
        command: ["bash", root.scriptPath, "gen-password"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pw = String(root.parseJson(this.text)?.password ?? "");
                if (genProc.verb === "suggest") {
                    if (pw.length > 0)
                        root.passwordSuggested(pw);
                    return;
                }
                if (pw.length === 0) {
                    root.busyAction = "";
                    root.fail(genProc.scope, genProc.verb === "enable"
                        ? Translation.tr("Sharing was not turned on.")
                        : Translation.tr("Your account could not be set up for sharing."));
                    root.refreshed();
                    return;
                }
                root.runHelper(genProc.verb, genProc.args, genProc.scope, pw);
            }
        }
    }

    readonly property bool picking: pickerProc.running

    function pickFolder() {
        if (pickerProc.running || root.busy)
            return;
        pickerProc.command = ["bash", "-c",
            'zenity --file-selection --directory --filename="$1/" --title="$2"',
            "--", root.home, Translation.tr("Choose a folder to share")];
        pickerProc.running = true;
    }

    // Kept here rather than on the page: a rebuild would take the open
    // dialog down with the page that started it.
    Process {
        id: pickerProc
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = this.text.trim();
                if (picked.length > 0)
                    root.add(picked, "view");
            }
        }
    }
}
