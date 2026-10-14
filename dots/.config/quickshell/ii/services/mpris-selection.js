.pragma library

// Selection is restricted to the same filtered sources shown by the cards.
function choose(players, tracked, preferred) {
    if (preferred && players.indexOf(preferred) !== -1 && preferred.isPlaying) return preferred;
    if (tracked && players.indexOf(tracked) !== -1 && tracked.isPlaying) return tracked;
    const playing = players.find(player => player.isPlaying);
    if (playing) return playing;
    if (tracked && players.indexOf(tracked) !== -1) return tracked;
    return players[0] ?? null;
}
