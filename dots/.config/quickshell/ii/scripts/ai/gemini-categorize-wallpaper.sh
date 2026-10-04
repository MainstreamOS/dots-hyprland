#!/usr/bin/env bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <image_path> [model] [prompt]"
    echo "Tip: set GEMINI_WALLPAPER_MODEL and/or GEMINI_WALLPAPER_PROMPT to provide defaults."
    exit 1
fi

# Variables
SOURCE_IMG_PATH="$1"
MODEL="${2:-${GEMINI_WALLPAPER_MODEL:-gemini-3.5-flash-lite}}"
WALLPAPER_NAME="$(basename "$SOURCE_IMG_PATH")"
PROMPT="${3:-${GEMINI_WALLPAPER_PROMPT:-Categorize the wallpaper. Its file name is $WALLPAPER_NAME}}"
RESIZED_IMG_PATH="/tmp/quickshell/ai/wallpaper.jpg"

# Without a key nothing is sent; nothing is cached either, so it asks again once one is set.
API_KEY=$(secret-tool lookup 'application' 'illogical-impulse' | jq -r '.apiKeys.gemini // empty')
[[ -n "$API_KEY" ]] || exit 0

# Resize image for speed
mkdir -p "$(dirname "$RESIZED_IMG_PATH")"
# A video wallpaper is judged by its first frame, read by ffmpeg alone:
# magick would decode every frame into memory first.
case "${SOURCE_IMG_PATH,,}" in
    *.mp4|*.webm|*.mkv|*.avi|*.mov|*.m4v|*.ogv)
        ffmpeg -nostdin -v error -y -i "$SOURCE_IMG_PATH" -frames:v 1 -vf scale=200:-2 -q:v 10 "$RESIZED_IMG_PATH"
        ;;
    *)
        magick "$SOURCE_IMG_PATH" -resize 200x -quality 50 "$RESIZED_IMG_PATH"
        ;;
esac

# Encode image to base64
if [[ "$(base64 --version 2>&1)" = *"FreeBSD"* ]]; then
    B64FLAGS="--input"
else
    B64FLAGS="-w0"
fi
B64DATA="$(base64 $B64FLAGS $RESIZED_IMG_PATH)"
# echo $B64DATA

# Prepare request data
payload='{
    "contents": [{
        "parts":[
            {
                "inline_data": {
                "mime_type":"image/jpeg",
                "data": "'"$B64DATA"'"
                }
            },
            {"text": "'"$PROMPT"'"}
        ]
    }],
    "generationConfig": {
        "responseMimeType": "application/json",
        "responseSchema": {
            "type": "string",
            "enum": [ "abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space" ]
        }
    }
}'
# echo "$payload" | jq

# Make the request
response=$(curl "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
-H "x-goog-api-key: $API_KEY" \
-H 'Content-Type: application/json' \
-X POST \
-d "$payload" 2> /dev/null)
# echo "$response" | jq

# Prints nothing on an error, so switchwall.sh does not cache a bad category.
echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty | (fromjson? // .)
    | select(IN("abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"))'
