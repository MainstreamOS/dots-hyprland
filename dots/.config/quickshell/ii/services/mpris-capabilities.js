.pragma library

// Bridge sources advertise controls that need a real DOM media element.
// Other MPRIS players retain the capabilities reported by Quickshell.
function supports(player, key, fallback) {
    if (!player || !player.canControl) return false;
    const metadata = player.metadata || {};
    return metadata["mainstream:capabilitiesVersion"] === 1
        ? metadata["mainstream:" + key] === true : !!fallback;
}
function hasLength(player) { return !!player && player.lengthSupported && player.length > 0; }
function volume(player) { return supports(player, "canSetVolume", player?.volumeSupported); }
function loop(player) { return supports(player, "canSetLoop", player?.loopSupported); }
function shuffle(player) { return supports(player, "canShuffle", player?.shuffleSupported); }
