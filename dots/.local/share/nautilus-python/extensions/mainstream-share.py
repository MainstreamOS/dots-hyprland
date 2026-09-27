# mainstream-share.py: "Share on Network" in the Files right-click menu, and
# the shared emblem on folders other computers can open. Settings > Sharing
# owns the setup; this only asks the shell's sharing.sh what a folder's state
# is and calls it to share or stop sharing, so the rules live in one place.
#
# Nautilus calls into here on its UI thread, for every file it shows, so
# nothing below waits on a process. sharing.sh runs asynchronously and its
# answers are cached; the menu and the emblems read the cache and are
# corrected when a newer answer arrives.

import json
import os
import pwd
import re
import stat
import time

from gi.repository import GLib, GObject, Gio, Nautilus

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
SHELL_DIR = os.path.join(CONFIG_HOME, "quickshell", "ii")
SHELL_CONFIG_DIR = os.path.join(CONFIG_HOME, "illogical-impulse")
SHARING_SCRIPT = os.path.join(SHELL_DIR, "scripts", "sharing", "sharing.sh")
SETTINGS_QML = os.path.join(SHELL_DIR, "settings.qml")

# Written by the root helper and readable by everyone. While the state is not
# "on" no folder gets an emblem, and a folder is asked about only when this
# account turned sharing off with folders still shared, so the common case of
# a machine that never shares costs one small file read and no process.
STATE_DIR = "/var/lib/mainstream/sharing"
STATE_FILE = os.path.join(STATE_DIR, "state")
USERS_DIR = os.path.join(STATE_DIR, "users")
USERSHARE_DIR = "/var/lib/samba/usershares"
# Anything that changes what is shared touches one of these, including the
# Settings page, so the emblems follow without waiting for the cache to age.
WATCHED_DIRS = (STATE_DIR, USERS_DIR, USERSHARE_DIR)
# A folder "Share on Network..." handed to Settings, which that window shares
# once setup is done. Setup goes on after the window closes, so the folder is
# kept here and shared from Files if it is still waiting then. It holds the
# absolute path and nothing else.
STATE_HOME = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
PENDING_FILE = os.path.join(STATE_HOME, "mainstream", "sharing-pending")

CACHE_SECONDS = 5
# A status run asks NetworkManager and systemd, which can stall; a run that
# never returns would otherwise leave the cache waiting on it for good.
RUN_TIMEOUT_SECONDS = 30
# An open Settings answers at once; one that has stopped answering would
# otherwise swallow the click instead of a new window opening.
IPC_TIMEOUT_SECONDS = 5
# Folders Files reached through a symlink, remembered so their emblems can
# be refreshed; past this many, only those of shared folders are kept.
ALIAS_LIMIT = 4096
# Translators mark a value kept in English with this; Translation.tr drops it.
KEEP_SUFFIX = "/*keep*/"
EMBLEM = "emblem-shared"
ICON = "folder-publicshare"

HOME_TEXT = "Your home folder holds your private settings and keys, so it cannot be shared as a whole. Share the folders inside it instead."
TRY_AGAIN_TEXT = "Try again from the Sharing page in Settings."
# What a new share's notification says: the first while this computer is on
# a network it shares on, the second anywhere else.
REACHABLE_TEXT = "Other computers can open it at %1 from Windows, or %2 from a Mac or Linux."
CLOSED_HERE_TEXT = "Other computers on your home network can open it. Your folders stay closed on the network you are on now."
# The Sharing page's own words while the firewall is off, when the helper
# keeps Samba stopped.
FIREWALL_TEXT = "The firewall is turned off, so sharing stays off to keep your folders safe. Turn the firewall back on to share folders."
# A stop that failed while sharing is off. The Sharing page lists shared
# folders only while sharing is on, so it is no place to try again then.
NO_ACCESS_TEXT = "Your account cannot share folders yet. Sign out and back in, then try again."
NOT_APPLIED_TEXT = "The change could not be applied."
ERROR_TEXT = {
    "not-owner": "You can only share folders that belong to you.",
    "home": HOME_TEXT,
    "hidden": "Hidden folders, whose names start with a dot, and the folders inside them hold app settings and keys, so they cannot be shared. Choose a regular folder instead.",
    "percent": "Folders with a percent sign (%) followed by a letter in their path cannot be shared. Rename the folder, then try again.",
}
# smbd fills in %u, %S, %$(VAR) and the like in a share's path each time
# someone connects, so the folder it served would not be this one.
PERCENT_PATTERN = re.compile(r"%[A-Za-z$]")

# The notification waits for one of its buttons and then copies that address,
# all in its own session: Files may be closed long before anyone clicks, and a
# notification server that goes away would leave notify-send waiting forever.
NOTIFY_WITH_COPY = (
    'action=$(timeout 3600 notify-send -a "$1" -i "$2" -A "windows=$5" -A "maclinux=$6"'
    ' -- "$3" "$4") && case $action in'
    ' windows) exec wl-copy -- "$7" ;;'
    ' maclinux) exec wl-copy -- "$8" ;;'
    ' esac'
)


_translations = None


def _system_language():
    # What Qt.locale().name gives the shell for "auto": the first of these
    # that is set, without its encoding or modifier.
    for name in ("LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(name)
        if value:
            return value.split(".", 1)[0].split("@", 1)[0]
    return ""


def _load_translations():
    try:
        with open(os.path.join(SHELL_CONFIG_DIR, "config.json"), encoding="utf-8") as f:
            language = json.load(f)["language"]["ui"]
    except (OSError, ValueError, LookupError, TypeError):
        language = "auto"
    if not isinstance(language, str) or language in ("", "auto"):
        language = _system_language()
    table = {}
    # Generated files first so the shipped ones override them, the same
    # precedence Translation.tr gives them.
    for directory in (os.path.join(SHELL_CONFIG_DIR, "translations"),
                      os.path.join(SHELL_DIR, "translations")):
        try:
            with open(os.path.join(directory, os.path.basename(language) + ".json"),
                      encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            table.update((key, value) for key, value in data.items()
                         if isinstance(value, str) and value)
    return table


def tr(text):
    global _translations
    if _translations is None:
        _translations = _load_translations()
    value = _translations.get(text, text)
    if value.endswith(KEEP_SUFFIX):
        value = value[:-len(KEEP_SUFFIX)].strip()
    return value


def folder_allowed(path, home=None, uid=None):
    """The checks sharing.sh add makes, so the menu never offers a folder it
    would refuse: a directory this user owns, not the home folder or above it,
    with no hidden part and no percent sign smbd would fill in, whether in the
    path as shown or as resolved."""
    home = home or os.path.expanduser("~")
    uid = os.getuid() if uid is None else uid
    for candidate, base in ((os.path.normpath(path), os.path.normpath(home)),
                            (os.path.realpath(path), os.path.realpath(home))):
        if any(part.startswith(".") for part in candidate.split("/")):
            return False
        if PERCENT_PATTERN.search(candidate):
            return False
        if candidate == base or base.startswith(candidate.rstrip("/") + "/"):
            return False
    try:
        st = os.stat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == uid


def menu_kind(info):
    """Which items a folder gets, from an info-shaped answer."""
    if info.get("state") != "on" or not info.get("account"):
        # Sharing turned off keeps the shares for next time, and one of them
        # can still be stopped without turning sharing back on.
        if info.get("state") == "off" and info.get("account") and info.get("shared"):
            return "setup-shared"
        return "setup"
    return "shared" if info.get("shared") else "share"


def fill(text, *values):
    """Puts the values in for %1, %2 and so on in one pass, so an address
    that happens to hold "%2" is not filled in a second time."""
    def value(match):
        index = int(match.group(1)) - 1
        return values[index] if 0 <= index < len(values) else match.group(0)
    return re.sub(r"%(\d)", value, text)


def network_address(host, name):
    return "\\\\" + host + "\\" + name


def mac_linux_address(host, name):
    # Finder and Linux file managers only take an smb:// address, reached
    # through the .local name the way the Sharing page gives it.
    return "smb://" + host + ".local/" + GLib.Uri.escape_string(name, None, False)


def reachable_now(status):
    """Whether other computers can open shares right now. Port 445 opens only
    on a network marked as home, and smbd stops when none of those is up. A
    trusted network that has since stopped passing the checks trust made no
    longer counts as one."""
    return any(isinstance(c, dict) and c.get("active") and c.get("trusted") and c.get("eligible")
               for c in status.get("connections") or [])


def _parse(output):
    try:
        result = json.loads(output or "")
    except ValueError:
        return {"error": "failed"}
    return result if isinstance(result, dict) else {"error": "failed"}


def _read_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return f.read().strip()
    except (OSError, ValueError):
        return ""


_user_marker = None


def _account_set_up():
    # The helper's marker for this account, the one sharing.sh reads too.
    # Only an account that was set up can still have folders shared while
    # sharing is off, so no other one runs a process to ask.
    global _user_marker
    if _user_marker is None:
        try:
            _user_marker = os.path.join(USERS_DIR, pwd.getpwuid(os.getuid()).pw_name)
        except KeyError:
            _user_marker = ""
    return bool(_user_marker) and os.path.exists(_user_marker)


def _take_pending():
    """The folder waiting in PENDING_FILE, or None. The file is moved aside
    before it is read, so a request is taken once, a newer one written
    meanwhile is left for next time, and a folder that cannot be shared is
    not tried again on every status."""
    taken = "%s.%d" % (PENDING_FILE, os.getpid())
    try:
        os.rename(PENDING_FILE, taken)
    except OSError:
        return None
    try:
        with open(taken, "rb") as f:
            path = os.fsdecode(f.read())
    except OSError:
        path = ""
    try:
        os.unlink(taken)
    except OSError:
        pass
    return path if path.startswith("/") else None


def _communicate(argv, seconds, done):
    """Runs argv without waiting on it and hands done() whether it exited
    cleanly and what it printed. One that cannot start, or is killed after
    the given seconds, hands done() a failure like any other."""
    try:
        proc = Gio.Subprocess.new(
            argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
    except GLib.Error:
        done(False, None)
        return
    timer = 0

    def expired():
        nonlocal timer
        timer = 0
        proc.force_exit()
        return GLib.SOURCE_REMOVE

    def finished(source, result):
        if timer:
            GLib.source_remove(timer)
        try:
            _ok, output, _err = source.communicate_utf8_finish(result)
        except GLib.Error:
            done(False, None)
            return
        done(source.get_successful(), output)

    timer = GLib.timeout_add_seconds(seconds, expired)
    proc.communicate_utf8_async(None, None, finished)


def _run(args, done):
    """Runs sharing.sh without waiting on it and hands done() the JSON object
    it printed. Errors print one too, so every outcome arrives the same way."""
    _communicate(["bash", SHARING_SCRIPT, *args], RUN_TIMEOUT_SECONDS,
                 lambda _ok, output: done(_parse(output)))


def _call_settings(args, done):
    """Calls a function on a Settings window that is already open, without
    waiting on it, and tells done() whether one took the call. qs ipc fails
    when no Settings is running, but a Settings too old to have the function
    makes it print "Function not found." and exit 0, so a call to a function
    that returns nothing only counts when it printed nothing."""
    _communicate(["quickshell", "ipc", "-p", SETTINGS_QML, "call", "settings", *args],
                 IPC_TIMEOUT_SECONDS,
                 lambda ok, output: done(ok and output is not None and not output.strip()))


def _spawn(argv, env=None):
    # Its own session, so the window or notification outlives Files and is
    # not caught by a signal meant for it.
    launcher = Gio.SubprocessLauncher.new(
        Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
    for key, value in (env or {}).items():
        launcher.setenv(key, value, True)
    try:
        launcher.spawnv(["setsid", "-f", *argv])
    except GLib.Error:
        pass


def _invalidate(path):
    # Only files Files already holds are looked up; it asks for their emblems
    # again and the cache answers.
    info = Nautilus.FileInfo.lookup(Gio.File.new_for_path(path))
    if info is not None:
        info.invalidate_extension_info()


def _served_shares(status):
    # A missing share stays listed so Settings can remove it, but nobody can
    # open it, so its folder gets neither the emblem nor Stop Sharing.
    return [s for s in status.get("shares") or []
            if isinstance(s, dict) and not s.get("missing")]


def _menu_facts(status):
    # Only what the menu and emblems depend on; addresses and networks change
    # often and would rebuild the menu for nothing.
    if not status:
        return None
    shares = sorted((str(s.get("path")), str(s.get("name"))) for s in _served_shares(status))
    return (status.get("state"), bool(status.get("account")), status.get("hostname"), shares)


class MainstreamShare(GObject.GObject, Nautilus.MenuProvider, Nautilus.InfoProvider):
    def __init__(self):
        super().__init__()
        # None until the state file has been read once, so the first read
        # is not taken for a change
        self._state = None
        self._state_read = 0.0
        self._status = None
        self._status_asked = 0.0
        self._status_loaded = 0.0
        self._status_running = False
        self._status_again = False
        # handed the next status answer, or None when it fails
        self._status_waiters = []
        # Folders are keyed by their resolved path, the way sharing.sh stores
        # a share, so one reached through a symlink still matches it.
        # resolved path -> share entry, kept empty while sharing is not on
        self._shared = {}
        # resolved path -> the other paths Files has shown it under
        self._aliases = {}
        # resolved path -> (time, info answer)
        self._info = {}
        self._info_running = set()
        # (resolved path, kind) the menu last offered, to tell whether a late
        # answer changes it
        self._shown = None
        # folders with a share or stop still running
        self._acting = set()
        # a folder is being handed to Settings; a second click meanwhile
        # would open two windows
        self._opening = False
        self._monitors = {}
        self._debounce = 0
        # A folder may have been left waiting while Files was closed.
        GLib.idle_add(self._check_pending)

    # ---- state -----------------------------------------------------------

    def _sharing_on(self):
        now = time.monotonic()
        if now - self._state_read >= CACHE_SECONDS:
            self._state_read = now
            previous = self._state
            self._state = _read_state()
            self._watch()
            if self._state != "on" and self._shared:
                self._set_shared({})
            if previous is not None and self._state != previous:
                # An answer from before would offer the other state's items.
                self._info.clear()
                self.emit_items_updated_signal()
        return self._state == "on"

    def _check_pending(self):
        if os.path.exists(PENDING_FILE) and self._sharing_on():
            self._refresh_status()
        return GLib.SOURCE_REMOVE

    def _watch(self):
        for directory in WATCHED_DIRS:
            if directory in self._monitors or not os.access(directory, os.R_OK | os.X_OK):
                continue
            try:
                monitor = Gio.File.new_for_path(directory).monitor_directory(
                    Gio.FileMonitorFlags.NONE, None)
            except GLib.Error:
                continue
            monitor.connect("changed", self._on_disk_change)
            self._monitors[directory] = monitor

    def _on_disk_change(self, *_args):
        if not self._debounce:
            self._debounce = GLib.timeout_add(300, self._after_disk_change)

    def _after_disk_change(self):
        self._debounce = 0
        self._state_read = 0.0
        self._info.clear()
        if self._sharing_on():
            self._refresh_status(force=True)
        return GLib.SOURCE_REMOVE

    def _refresh_status(self, force=False):
        if self._status_running:
            # A change seen mid-run may not be in its answer.
            self._status_again = self._status_again or force
            return
        self._status_running = True
        self._status_again = False
        self._status_asked = time.monotonic()
        _run(["status"], self._on_status)

    def _on_status(self, status):
        self._status_running = False
        if "error" not in status:
            now = time.monotonic()
            previous = self._status
            self._status = status
            self._status_loaded = now
            self._state = status.get("state") or ""
            self._state_read = now
            shares = {}
            if self._state == "on":
                for share in _served_shares(status):
                    if isinstance(share.get("path"), str):
                        # A share made somewhere else may name its folder
                        # through a symlink, as sharing.sh allows for too.
                        shares[os.path.realpath(share["path"])] = share
            self._set_shared(shares)
            if _menu_facts(previous) != _menu_facts(status):
                self._info.clear()
                self.emit_items_updated_signal()
            if self._state == "on" and status.get("account"):
                self._share_pending()
        waiters, self._status_waiters = self._status_waiters, []
        for waiter in waiters:
            waiter(None if "error" in status else status)
        if self._status_again:
            self._refresh_status()

    def _with_status(self, done):
        """Hands done() a status no older than the cache allows, asking for a
        new one when it is, or None when that fails. The cache alone can be
        far older: it is refreshed only while Files is showing folders."""
        if self._status is not None and time.monotonic() - self._status_loaded < CACHE_SECONDS:
            done(self._status)
            return
        self._status_waiters.append(done)
        self._refresh_status()

    def _set_shared(self, shares):
        old = self._shared
        self._shared = shares
        for real in old.keys() ^ shares.keys():
            _invalidate(real)
            # Files holds a folder it reached through a symlink under that
            # path, which looking up the resolved one does not find.
            for shown in tuple(self._aliases.get(real, ())):
                _invalidate(shown)

    def _remember_alias(self, real, shown):
        aliases = self._aliases.get(real)
        if aliases is None:
            if len(self._aliases) >= ALIAS_LIMIT:
                # The rest are remembered again as Files shows them.
                self._aliases = {k: v for k, v in self._aliases.items() if k in self._shared}
            aliases = self._aliases[real] = set()
        aliases.add(shown)

    # ---- emblems ---------------------------------------------------------

    def update_file_info(self, file):
        if not self._sharing_on():
            return
        if time.monotonic() - self._status_asked >= CACHE_SECONDS:
            self._refresh_status()
        if not file.is_directory() or file.get_uri_scheme() != "file":
            return
        path = file.get_location().get_path()
        if not path:
            return
        # Resolved even while nothing is shared, so a folder Files shows
        # through a symlink is still refreshed when Settings shares it.
        shown = os.path.normpath(path)
        real = os.path.realpath(shown)
        if real != shown:
            self._remember_alias(real, shown)
        if real in self._shared:
            file.add_emblem(EMBLEM)

    # ---- menu ------------------------------------------------------------

    def get_file_items(self, files):
        self._shown = None
        if len(files) != 1:
            return []
        file = files[0]
        if file.get_uri_scheme() != "file" or not file.is_directory():
            return []
        path = file.get_location().get_path()
        if not path or not folder_allowed(path):
            return []
        # The path Files shows is what the user reads and what sharing.sh is
        # handed, since it resolves paths itself; the caches use the resolved one.
        path = os.path.normpath(path)
        real = os.path.realpath(path)
        if real != path:
            self._remember_alias(real, path)
        info = self._menu_info(path, real)
        kind = menu_kind(info) if info is not None else None
        self._shown = (real, kind)
        if kind in ("setup", "setup-shared"):
            item = Nautilus.MenuItem(name="MainstreamShare::Setup",
                                     label=tr("Share on Network..."))
            item.connect("activate", self._on_setup, path)
            # Nothing is served while sharing is off, so there is no address
            # to copy yet.
            if kind == "setup-shared":
                return [item, self._stop_item(path, real)]
            return [item]
        if kind == "share":
            item = Nautilus.MenuItem(name="MainstreamShare::Share",
                                     label=tr("Share on Network"))
            item.connect("activate", self._on_share, path, real)
            return [item]
        if kind == "shared":
            stop = self._stop_item(path, real)
            copy = Nautilus.MenuItem(name="MainstreamShare::Copy",
                                     label=tr("Copy Network Address"))
            # Windows takes only the \\name\share form and a Mac or Linux only
            # smb://, so both are offered, as on the Sharing page.
            forms = Nautilus.Menu()
            copy.set_submenu(forms)
            host, name = self._host(info), info.get("name") or ""
            for key, label, address in (
                    ("Windows", tr("For Windows"), network_address(host, name)),
                    ("MacLinux", tr("For Mac and Linux"), mac_linux_address(host, name))):
                item = Nautilus.MenuItem(name="MainstreamShare::Copy" + key, label=label)
                item.connect("activate", self._on_copy, address)
                forms.append_item(item)
            return [stop, copy]
        return []

    def _stop_item(self, path, real):
        stop = Nautilus.MenuItem(name="MainstreamShare::Stop",
                                 label=tr("Stop Sharing on Network"))
        stop.connect("activate", self._on_stop, path, real)
        return stop

    def _menu_info(self, path, real):
        """The best answer on hand for a folder, without waiting. A fresh info
        answer wins, then a fresh status; anything older is shown while info
        is asked again, and the menu is rebuilt if the answer differs."""
        # Read first: a change of state it notices empties the info cache.
        on = self._sharing_on()
        now = time.monotonic()
        cached = self._info.get(real)
        if not on:
            # Turned off, the folders shared before are kept, and only info
            # knows whether this is one of them.
            if self._state != "off" or not _account_set_up():
                return {"state": self._state}
            if cached and now - cached[0] < CACHE_SECONDS:
                return cached[1]
            self._fetch_info(path, real)
            return cached[1] if cached else {"state": self._state}
        if cached and now - cached[0] < CACHE_SECONDS:
            return cached[1]
        fresh_status = self._status is not None and now - self._status_loaded < CACHE_SECONDS
        if fresh_status:
            return self._from_status(real)
        self._fetch_info(path, real)
        if cached:
            return cached[1]
        return self._from_status(real) if self._status is not None else None

    def _from_status(self, real):
        share = self._shared.get(real)
        return {
            "shared": share is not None,
            "name": share.get("name", "") if share else "",
            "state": self._state,
            "account": bool(self._status.get("account")),
            "hostname": self._status.get("hostname", ""),
        }

    def _fetch_info(self, path, real):
        if real in self._info_running:
            return
        self._info_running.add(real)

        def answered(info):
            self._info_running.discard(real)
            if "error" in info:
                return
            now = time.monotonic()
            self._info = {p: v for p, v in self._info.items() if now - v[0] < CACHE_SECONDS}
            self._info[real] = (now, info)
            if self._shown and self._shown[0] == real and self._shown[1] != menu_kind(info):
                self.emit_items_updated_signal()

        _run(["info", path], answered)

    def _host(self, info):
        return (info.get("hostname") or (self._status or {}).get("hostname")
                or GLib.get_host_name())

    # ---- actions ---------------------------------------------------------

    def _on_setup(self, _item, path):
        self._open_settings(path)

    def _open_settings(self, path):
        # A Settings window already open takes the folder and comes forward.
        # A second window would sit beside the first with the folder queued
        # in only one of them, so one is started only when none takes it.
        if self._opening:
            return
        self._opening = True

        def answered(taken):
            self._opening = False
            if not taken:
                _spawn(["quickshell", "-p", SETTINGS_QML],
                       {"QS_SETTINGS_PAGE": "SharingConfig.qml", "QS_SHARING_FOLDER": path})

        _call_settings(["shareFolder", path], answered)

    def _on_share(self, _item, path, real):
        # A second click while the first is still running would add the folder
        # twice under two names, as would one on another path to it.
        if real in self._acting:
            return
        self._acting.add(real)

        # The menu may have been built from an older answer, and adding a
        # folder that is already shared would also give it a second name.
        def checked(info):
            kind = menu_kind(info) if "error" not in info else None
            if kind in ("setup", "setup-shared"):
                self._acting.discard(real)
                self._open_settings(path)
            elif kind == "shared":
                self._acting.discard(real)
                self._notify_shared(path, info.get("name") or "", self._host(info))
            else:
                _run(["add", path, "view"], lambda result: added(result, info))

        def added(result, info):
            self._acting.discard(real)
            code = result.get("error")
            if code is None:
                self._record(path, real, result)
                self._notify_shared(path, result.get("name") or "", self._host(info))
            elif code == "no-access":
                # This session cannot write shares yet; setting up the
                # account on the Sharing page is what fixes that.
                self._open_settings(path)
            else:
                self._notify(fill(tr("%1 was not shared"), os.path.basename(path)),
                             tr(ERROR_TEXT.get(code, TRY_AGAIN_TEXT)))

        _run(["info", path], checked)

    def _on_stop(self, _item, path, real):
        if real in self._acting:
            return
        self._acting.add(real)

        def removed(result):
            self._acting.discard(real)
            code = result.get("error")
            # Stopped from somewhere else in the meantime is what was asked for.
            if code is None or code == "not-shared":
                self._record(path, real, None)
                return
            if self._state == "on":
                body = TRY_AGAIN_TEXT
            else:
                body = NO_ACCESS_TEXT if code == "no-access" else NOT_APPLIED_TEXT
            self._notify(fill(tr("%1 is still shared"), os.path.basename(path)), tr(body))
            self._refresh_status(force=True)

        _run(["remove", path], removed)

    def _on_copy(self, _item, address):
        _spawn(["wl-copy", "--", address])

    def _share_pending(self):
        """Shares the folder "Share on Network..." handed to Settings, once
        this account is set up. The window it went to may have closed before
        setup finished; if it is still open it shares the folder too, which
        sharing.sh answers with the same share."""
        path = _take_pending()
        if path is None or not folder_allowed(path):
            return
        path = os.path.normpath(path)
        real = os.path.realpath(path)
        if real in self._acting:
            return
        self._acting.add(real)

        def added(result):
            self._acting.discard(real)
            code = result.get("error")
            if code is None:
                self._record(path, real, result)
                self._notify_shared(path, result.get("name") or "", self._host({}))
            else:
                self._notify(fill(tr("%1 was not shared"), os.path.basename(path)),
                             tr(ERROR_TEXT.get(code, TRY_AGAIN_TEXT)))

        _run(["add", path, "view"], added)

    def _record(self, path, real, share):
        """Shows what an action just did at once, then confirms it with a
        full status."""
        shares = dict(self._shared)
        if share is None:
            shares.pop(real, None)
        else:
            stored = share.get("path")
            shares[os.path.realpath(stored) if isinstance(stored, str) else real] = share
        self._set_shared(shares)
        # Files holds the folder under the path it was opened by, which the
        # resolved key alone would not find.
        _invalidate(path)
        self._info.pop(real, None)
        self._refresh_status(force=True)

    def _notify_shared(self, path, name, host):
        windows = network_address(host, name)
        mac_linux = mac_linux_address(host, name)

        def send(status):
            # A status that could not be read is not taken to mean the folder
            # is closed; at home that would tell someone nobody can open it.
            # Samba already running when the firewall stopped still serves.
            if (status is not None and status.get("firewall") is False
                    and status.get("running") is not True):
                body = tr(FIREWALL_TEXT)
            elif status is None or reachable_now(status):
                body = fill(tr(REACHABLE_TEXT), windows, mac_linux)
            else:
                body = tr(CLOSED_HERE_TEXT)
            _spawn(["sh", "-c", NOTIFY_WITH_COPY, "sh",
                    tr("Sharing"), ICON,
                    fill(tr("%1 is shared"), os.path.basename(path)),
                    body,
                    tr("Copy for Windows"), tr("Copy for Mac and Linux"),
                    windows, mac_linux])

        self._with_status(send)

    def _notify(self, title, body):
        _spawn(["notify-send", "-a", tr("Sharing"), "-i", ICON, "--", title, body])

