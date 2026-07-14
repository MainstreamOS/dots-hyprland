#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# Match the recording color to the focused monitor's mode so it's correct on any
# GPU + monitor: SDR -> 8-bit H.264 BT.709 (limited range); HDR -> 10-bit HEVC
# BT.2020 + PQ. Without this the full-range capture is written untagged and
# players wash it out.
COLOR_PRESET=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .colorManagementPreset' 2>/dev/null)
if [[ "$COLOR_PRESET" == "hdr" || "$COLOR_PRESET" == "hdredid" ]]; then
    PIXEL_FORMAT="yuv420p10le"
    COLOR_ARGS=(-c libx265 -p color_range=tv -p colorspace=bt2020nc -p color_primaries=bt2020 -p color_trc=smpte2084)
else
    PIXEL_FORMAT="yuv420p"
    COLOR_ARGS=(-p color_range=tv -p colorspace=bt709 -p color_primaries=bt709 -p color_trc=bt709)
fi

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

if pgrep wf-recorder > /dev/null; then
    pkill wf-recorder
    # wait for wf-recorder to finish finalizing the file
    for _i in $(seq 1 100); do pgrep wf-recorder >/dev/null || break; sleep 0.1; done
    FILE=$(ls -t "$RECORDING_DIR"/recording_*.mp4 2>/dev/null | head -1)
    NOTIFY_ARGS=(-a 'Recorder' -A "open=Open folder")
    if [[ -n "$FILE" ]]; then
        mkdir -p /tmp/quickshell
        THUMB="/tmp/quickshell/recording-thumb-$(getdate).jpg"
        ffmpeg -y -v error -ss 1 -i "$FILE" -frames:v 1 -vf "scale=480:-2" "$THUMB" 2>/dev/null || ffmpeg -y -v error -i "$FILE" -frames:v 1 -vf "scale=480:-2" "$THUMB" 2>/dev/null
        [[ -s "$THUMB" ]] && NOTIFY_ARGS+=(-h "string:image-path:$THUMB")
    fi
    (
        action=$(notify-send "Recording saved" "${FILE##*/}" "${NOTIFY_ARGS[@]}")
        [[ "$action" == "open" ]] && xdg-open "$RECORDING_DIR"
    ) & disown
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder -o "$(getactivemonitor)" --pixel-format "$PIXEL_FORMAT" "${COLOR_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' -t --audio="$(getaudiooutput)"
        else
            wf-recorder -o "$(getactivemonitor)" --pixel-format "$PIXEL_FORMAT" "${COLOR_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' -t
        fi
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder --pixel-format "$PIXEL_FORMAT" "${COLOR_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' -t --geometry "$region" --audio="$(getaudiooutput)"
        else
            wf-recorder --pixel-format "$PIXEL_FORMAT" "${COLOR_ARGS[@]}" -f './recording_'"$(getdate)"'.mp4' -t --geometry "$region"
        fi
    fi
fi