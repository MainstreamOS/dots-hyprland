pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell

Singleton {
    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property string music: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0]

    // Other dirs used by the shell, without "file://"
    property string assetsPath: Quickshell.shellPath("assets")
    property string scriptPath: Quickshell.shellPath("scripts")
    property string favicons: FileUtils.trimFileProtocol(`${Directories.cache}/media/favicons`)
    property string coverArt: FileUtils.trimFileProtocol(`${Directories.cache}/media/coverart`)
    property string tempImages: "/tmp/quickshell/media/images"
    property string booruPreviews: FileUtils.trimFileProtocol(`${Directories.cache}/media/boorus`)
    property string booruDownloads: FileUtils.trimFileProtocol(Directories.pictures  + "/homework")
    property string booruDownloadsNsfw: FileUtils.trimFileProtocol(Directories.pictures + "/homework/🌶️")
    property string latexOutput: FileUtils.trimFileProtocol(`${Directories.cache}/media/latex`)
    property string shellConfig: FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse`)
    property string shellConfigName: "config.json"
    property string shellConfigPath: `${Directories.shellConfig}/${Directories.shellConfigName}`
	property string todoPath: FileUtils.trimFileProtocol(`${Directories.state}/user/todo.json`)
	property string emojiFrequencyPath: FileUtils.trimFileProtocol(`${Directories.state}/user/emoji-frequency.json`)
	property string notesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/notes.txt`)
	property string desktopNotesPath: FileUtils.trimFileProtocol(`${Directories.state}/user/desktop-notes.json`)
	property string conflictCachePath: FileUtils.trimFileProtocol(`${Directories.cache}/conflict-killer`)
    property string notificationsPath: FileUtils.trimFileProtocol(`${Directories.cache}/notifications/notifications.json`)
    // updatems keeps its clone here and owns the applied-tag file, so this
    // follows its rule rather than the Qt cache location — see sdata/update/updatems.
    property string dotfilesClone: FileUtils.trimFileProtocol(
        Quickshell.env("MAINSTREAM_DOTFILES_DIR") || `${Directories.genericCache}/dots-hyprland`)
    property string appliedTagPath: `${Directories.dotfilesClone}/.updatems-applied-tag`
    // Not in the clone beside the tag: updatems stashes untracked files and
    // resets that tree on every run, and re-clones it outright when it has to,
    // so a record of what has already been announced would not survive an
    // update — which is exactly when it matters.
    property string releaseManifestPath: FileUtils.trimFileProtocol(`${Directories.cache}/updates/release-manifest.json`)
    property string releaseNotifyStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/release-notify-state.json`)
    property string settingsAppPath: FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/settings.qml`)
    // Where the detached update writes its log, exit code and pid; read by the Update page and by Settings on close.
    property string updateStateDir: Quickshell.env("HOME") + "/.local/state/mainstream"
    property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/colors.json`)
    property string generatedWallpaperCategoryPath: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/wallpaper/category.txt`)
    property string cliphistDecode: FileUtils.trimFileProtocol(`/tmp/quickshell/media/cliphist`)
    property string screenshotTemp: "/tmp/quickshell/media/screenshot"
    property string wallpaperSwitchScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/switchwall.sh`)
    property string defaultAiPrompts: Quickshell.shellPath("defaults/ai/prompts")
    property string userAiPrompts: FileUtils.trimFileProtocol(`${Directories.shellConfig}/ai/prompts`)
    property string userActions: FileUtils.trimFileProtocol(`${Directories.shellConfig}/actions`)
    property string appFoldersPath: FileUtils.trimFileProtocol(`${Directories.state}/user/app-folders.json`)
    property string aiChats: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats`)
    property string aiTranslationScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/gemini-translate.sh`)
    property string recordScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/videos/record.sh`)
    property string userAvatarPathAccountsService: FileUtils.trimFileProtocol(`/var/lib/AccountsService/icons/${SystemInfo.username}`)
    property string userAvatarPathRicersAndWeirdSystems: FileUtils.trimFileProtocol(`${Directories.home}/.face`)
    property string userAvatarPathRicersAndWeirdSystems2: FileUtils.trimFileProtocol(`${Directories.home}/.face.icon`)
    // Every process makes sure these exist; only the main shell clears any
    // of them, below.
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${favicons}`])
        Quickshell.execDetached(["mkdir", "-p", `${coverArt}`])
        Quickshell.execDetached(["mkdir", "-p", `${booruPreviews}`])
        Quickshell.execDetached(["mkdir", "-p", `${latexOutput}`])
        Quickshell.execDetached(["mkdir", "-p", `${cliphistDecode}`])
        Quickshell.execDetached(["mkdir", "-p", `${aiChats}`])
        Quickshell.execDetached(["mkdir", "-p", `${userActions}`])
    }

    // Whatever writes into the folders below reads their paths from here
    // first, so nothing this shell writes there can be older than this.
    readonly property real startTime: Date.now()

    // Only the main shell sets this. Settings, the Welcome app and Uninstall
    // Apps load this too, as processes of their own, and clearing from those
    // would empty the folders under the shell that is showing what is in them.
    property bool _clearCachesEnabled: false
    on_ClearCachesEnabledChanged: {
        if (!_clearCachesEnabled) return
        // Media already playing at startup gets its art fetched straight
        // away, alongside this rather than after it, so only what an earlier
        // run left behind is taken and a fresh download never is. Each folder
        // goes on its own: the ones under /tmp can belong to whoever logged
        // in first, and one that cannot be made must not keep the rest full.
        // Once per login: a reload of the shell keeps what these hold, so art
        // fetched before shows at once rather than being fetched again. The
        // runtime folder empties at logout, which starts the next login clean.
        Quickshell.execDetached(["bash", "-c",
            'm="${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/quickshell-ii-caches-cleared}"; [ -n "$m" ] && [ -e "$m" ] && exit 0; before="$1"; shift; for d in "$@"; do mkdir -p -- "$d" && find "$d" -mindepth 1 -maxdepth 1 ! -newermt "@$before" -exec rm -rf -- {} +; done; [ -n "$m" ] && : > "$m"',
            "clear-caches", String(Math.floor(startTime / 1000)),
            coverArt, booruPreviews, latexOutput, cliphistDecode, tempImages])
    }
}
