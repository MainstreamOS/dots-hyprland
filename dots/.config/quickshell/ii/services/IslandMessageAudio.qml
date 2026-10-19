pragma Singleton
import QtQuick
import QtMultimedia
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root
    property string currentKey: ""
    property string error: ""
    property var sources: ({})
    // The clip being fetched through Phone, by attachment uid.
    property string fetchingUid: ""
    property string fetchingDevice: ""
    readonly property bool fetching: fetchingUid.length > 0
    readonly property bool loading: fetching || player.mediaStatus === MediaPlayer.LoadingMedia
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property real position: player.position
    readonly property real duration: player.duration
    function key(attachment) { return (attachment?.deviceId || "") + ":" + (attachment?.uid || ""); }
    function toggle(attachment) {
        const id = key(attachment);
        if (fetching) {
            if (id === currentKey) stop();
            return;
        }
        if (id === currentKey && player.source.toString() && !error) {
            if (playing) player.pause();
            else player.play();
            return;
        }
        player.stop();
        player.source = "";
        currentKey = id;
        error = "";
        if (sources[id]) {
            player.source = sources[id];
            player.play();
            return;
        }
        if (!attachment?.deviceId || !attachment.uid || !(attachment.part >= 0)) {
            error = Translation.tr("This audio clip is unavailable from the phone.");
            return;
        }
        fetchingUid = attachment.uid;
        fetchingDevice = attachment.deviceId;
        Phone.useAttachment(attachment, "play", attachment.deviceId);
    }
    function seek(fraction) { if (duration > 0) player.position = Math.max(0, Math.min(1, fraction)) * duration; }
    function stop() {
        currentKey = "";
        error = "";
        fetchingUid = "";
        player.stop();
        player.source = "";
    }
    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) Phone.playingMedia = "island"
        onErrorOccurred: (code, description) => {
            root.error = Translation.tr("Unable to play this audio clip.");
            const saved = Object.assign({}, root.sources);
            delete saved[root.currentKey];
            root.sources = saved;
            const split = root.currentKey.indexOf(":");
            Phone.forgetAttachment(root.currentKey.slice(split + 1), root.currentKey.slice(0, split));
        }
    }
    Connections {
        target: Phone
        function onPlayingMediaChanged() { if (Phone.playingMedia !== "island") player.pause(); }
        function onAudioReady(uid, path, device) {
            if (uid !== root.fetchingUid || device !== root.fetchingDevice) return;
            root.fetchingUid = "";
            const source = FileUtils.fileUrl(path);
            root.sources = Object.assign({}, root.sources, {[root.currentKey]: source});
            player.source = source;
            player.play();
        }
        function onAttachmentUnavailable(uid, device) {
            if (uid !== root.fetchingUid || device !== root.fetchingDevice) return;
            root.fetchingUid = "";
            root.error = Translation.tr("Unable to load this audio clip. Check your phone connection and try again.");
        }
    }
    Connections {
        target: Config.options.bar.island
        function onShowMessageChanged() { if (!Config.options.bar.island.showMessage) root.stop(); }
    }
    Connections {
        target: Appearance.sizes
        function onBarIsIslandChanged() { if (!Appearance.sizes.barIsIsland) root.stop(); }
    }
}
