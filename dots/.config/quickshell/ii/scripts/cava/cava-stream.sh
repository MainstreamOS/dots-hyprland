#!/usr/bin/env bash
# cava-stream.sh <app-name>
#
# Per-app visualizer source. Finds the named application's PipeWire output
# stream (by application.name / node.name / media.name) and runs cava on just
# that stream's object.serial, so each app's media tile animates to its own
# audio. If the app can't be matched (e.g. Electron apps like Spotify whose
# stream is anonymous "audio-src"), it falls back to the default sink (the
# mixed system output) so the tile still shows something.
#
# The mapping is done here, not in QML, because Quickshell's PwNode.properties
# doesn't expose object.serial without tracking — pactl always has it.

app="${1,,}"
serial=""

if [ -n "$app" ]; then
    serial=$(pactl list sink-inputs 2>/dev/null | awk -v app="$app" '
        /^Sink Input #/ { c=0; s=""; m=0 }
        /Corked: no/    { c=1 }
        /object\.serial = / { v=$NF; gsub(/"/,"",v); s=v }
        {
            lv=tolower($0)
            if (lv ~ /(application\.name|node\.name|media\.name) =/ && index(lv, app)) m=1
            if (c && m && s != "") { print s; exit }
        }
    ')
fi

conf="$(mktemp --suffix=.mpris-cava.conf)"
trap 'rm -f "$conf"' EXIT
{
    echo "[general]"
    echo "mode = waves"
    echo "framerate = 60"
    echo "autosens = 1"
    echo "bars = 50"
    echo "[input]"
    echo "method = pipewire"
    if [ -n "$serial" ]; then echo "source = $serial"; else echo "source = auto"; fi
    echo "[output]"
    echo "method = raw"
    echo "raw_target = /dev/stdout"
    echo "data_format = ascii"
    echo "channels = mono"
    echo "mono_option = average"
    echo "[smoothing]"
    echo "noise_reduction = 20"
} > "$conf"

exec cava -p "$conf"
