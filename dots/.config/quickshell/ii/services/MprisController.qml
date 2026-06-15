pragma Singleton
pragma ComponentBehavior: Bound

// From https://git.outfoxxed.me/outfoxxed/nixnew
// It does not have a license, but the author is okay with redistribution.

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common

/**
 * A service that provides easy access to the active Mpris player.
 */
Singleton {
	id: root;
	property list<MprisPlayer> players: Mpris.players.values.filter(player => isRealPlayer(player));
	property MprisPlayer trackedPlayer: null;
	property MprisPlayer activePlayer: trackedPlayer ?? Mpris.players.values[0] ?? null;
	signal trackChanged(reverse: bool);

	property bool __reverse: false;

	property var activeTrack;

	readonly property bool hasActivePlasmaIntegration: Mpris.players.values.some(
		p => p.dbusName?.startsWith('org.mpris.MediaPlayer2.plasma-browser-integration')
	)
	// mpris-hyprland exposes one player per browser window, named
	// org.mpris.MediaPlayer2.firefox.instance<pid>_t<windowId>. The _t<digits>
	// segment distinguishes it from the browser's own built-in player
	// (…firefox.instance_<n>_<m>, no _t).
	function isFirefoxMprisBridge(name) {
		return /\.firefox\.instance\d+_t\d+/.test(name ?? '');
	}
	readonly property bool hasFirefoxMprisBridge: Mpris.players.values.some(
		p => isFirefoxMprisBridge(p.dbusName)
	)
	// mpris-hyprland also bridges Chromium: a Chromium session publishes
	// org.mpris.MediaPlayer2.chromium.instance<pid>_t<window>. The _t<digits>
	// segment distinguishes the per-window bridge from Chromium's own native
	// single player (…chromium.instance<n>, no _t).
	function isChromiumMprisBridge(name) {
		return /\.chromium\.instance\d+_t\d+/.test(name ?? '');
	}
	readonly property bool hasChromiumMprisBridge: Mpris.players.values.some(
		p => isChromiumMprisBridge(p.dbusName)
	)
	// A browser's own sparse single MPRIS player (Firefox built-in, Chromium
	// native), as opposed to the rich per-window bridge players. Split per
	// browser so a rich source for one browser never hides the other's player.
	function isBuiltinFirefoxPlayer(name) {
		name = name ?? '';
		return name.startsWith('org.mpris.MediaPlayer2.firefox') && !isFirefoxMprisBridge(name);
	}
	function isBuiltinChromiumPlayer(name) {
		name = name ?? '';
		return (name.startsWith('org.mpris.MediaPlayer2.chromium')
			|| name.startsWith('org.mpris.MediaPlayer2.chrome'))
			&& !isChromiumMprisBridge(name);
	}
	function isBuiltinBrowserPlayer(name) {
		return isBuiltinFirefoxPlayer(name) || isBuiltinChromiumPlayer(name);
	}
	function isRealPlayer(player) {
        if (!Config.options.media.filterDuplicatePlayers) {
            return true;
        }
        const name = player.dbusName ?? '';
        // Hide a browser's built-in single player only when a richer source for
        // THAT browser is present, so it isn't duplicated. Scoped per browser:
        // the Firefox bridge (or plasma-browser-integration) hides the Firefox
        // built-in; plasma also hides the Chromium built-in. Critically a
        // Firefox bridge must NOT hide Chromium's native player — different
        // browsers — which previously left Chromium showing a bar title with no
        // player in the popup.
        const richFirefoxSource = hasActivePlasmaIntegration || hasFirefoxMprisBridge;
        const richChromiumSource = hasActivePlasmaIntegration || hasChromiumMprisBridge;
        return (
            !(richFirefoxSource && isBuiltinFirefoxPlayer(name)) &&
            !(richChromiumSource && isBuiltinChromiumPlayer(name)) &&
            // playerctld just copies other buses and we don't need duplicates
            !name.startsWith('org.mpris.MediaPlayer2.playerctld') &&
            // Non-instance mpd bus
            !(name.endsWith('.mpd') && !name.endsWith('MediaPlayer2.mpd')));
    }

	// Original stuff from fox below
	Instantiator {
		model: Mpris.players;

		Connections {
			required property MprisPlayer modelData;
			target: modelData;

			Component.onCompleted: {
				if (root.trackedPlayer == null || modelData.isPlaying) {
					root.trackedPlayer = modelData;
				}
			}

			Component.onDestruction: {
				if (root.trackedPlayer == null || !root.trackedPlayer.isPlaying) {
					for (const player of Mpris.players.values) {
						if (player.playbackState.isPlaying) {
							root.trackedPlayer = player;
							break;
						}
					}

					if (trackedPlayer == null && Mpris.players.values.length != 0) {
						trackedPlayer = Mpris.players.values[0];
					}
				}
			}

			function onPlaybackStateChanged() {
				if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData;
			}
		}
	}

	Connections {
		target: activePlayer

		function onPostTrackChanged() {
			root.updateTrack();
		}

		function onTrackArtUrlChanged() {
			// console.log("arturl:", activePlayer.trackArtUrl)
			// root.updateTrack();
			if (root.activePlayer.uniqueId == root.activeTrack.uniqueId && root.activePlayer.trackArtUrl != root.activeTrack.artUrl) {
				// cantata likes to send cover updates *BEFORE* updating the track info.
				// as such, art url changes shouldn't be able to break the reverse animation
				const r = root.__reverse;
				root.updateTrack();
				root.__reverse = r;

			}
		}
	}

	onActivePlayerChanged: this.updateTrack();

	function updateTrack() {
		//console.log(`update: ${this.activePlayer?.trackTitle ?? ""} : ${this.activePlayer?.trackArtists}`)
		this.activeTrack = {
			uniqueId: this.activePlayer?.uniqueId ?? 0,
			artUrl: this.activePlayer?.trackArtUrl ?? "",
			title: this.activePlayer?.trackTitle || Translation.tr("Unknown Title"),
			artist: this.activePlayer?.trackArtist || Translation.tr("Unknown Artist"),
			album: this.activePlayer?.trackAlbum || Translation.tr("Unknown Album"),
		};

		this.trackChanged(__reverse);
		this.__reverse = false;
	}

	property bool isPlaying: this.activePlayer && this.activePlayer.isPlaying;
	property bool canTogglePlaying: this.activePlayer?.canTogglePlaying ?? false;
	function togglePlaying() {
		if (this.canTogglePlaying) this.activePlayer.togglePlaying();
	}

	property bool canGoPrevious: this.activePlayer?.canGoPrevious ?? false;
	function previous() {
		if (this.canGoPrevious) {
			this.__reverse = true;
			this.activePlayer.previous();
		}
	}

	property bool canGoNext: this.activePlayer?.canGoNext ?? false;
	function next() {
		if (this.canGoNext) {
			this.__reverse = false;
			this.activePlayer.next();
		}
	}

	property bool canChangeVolume: this.activePlayer && this.activePlayer.volumeSupported && this.activePlayer.canControl;

	property bool loopSupported: this.activePlayer && this.activePlayer.loopSupported && this.activePlayer.canControl;
	property var loopState: this.activePlayer?.loopState ?? MprisLoopState.None;
	function setLoopState(loopState: var) {
		if (this.loopSupported) {
			this.activePlayer.loopState = loopState;
		}
	}

	property bool shuffleSupported: this.activePlayer && this.activePlayer.shuffleSupported && this.activePlayer.canControl;
	property bool hasShuffle: this.activePlayer?.shuffle ?? false;
	function setShuffle(shuffle: bool) {
		if (this.shuffleSupported) {
			this.activePlayer.shuffle = shuffle;
		}
	}

	function setActivePlayer(player: MprisPlayer) {
		const targetPlayer = player ?? Mpris.players[0];
		console.log(`[Mpris] Active player ${targetPlayer} << ${activePlayer}`)

		if (targetPlayer && this.activePlayer) {
			this.__reverse = Mpris.players.indexOf(targetPlayer) < Mpris.players.indexOf(this.activePlayer);
		} else {
			// always animate forward if going to null
			this.__reverse = false;
		}

		this.trackedPlayer = targetPlayer;
	}

	IpcHandler {
		target: "mpris"

		function pauseAll(): void {
			for (const player of Mpris.players.values) {
				if (player.canPause) player.pause();
			}
		}

		function playPause(): void { root.togglePlaying(); }
		function previous(): void { root.previous(); }
		function next(): void { root.next(); }
	}
}
