#!/usr/bin/env bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <target_locale> [model]"
    exit 1
fi

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_CONFIG_DIR="$XDG_CONFIG_HOME/illogical-impulse"
SHELL_CONFIG_FILE="${SHELL_CONFIG_DIR}/config.json"
TRANSLATIONS_DIR="${SCRIPT_DIR}/../../translations"
TRANSLATIONS_TARGET_DIR="${SHELL_CONFIG_DIR}/translations"
SOURCE_LOCALE="en_US"
NOTIFICATION_APP_NAME="Shell"
TARGET_LOCALE="$1"
MODEL="${2:-${GEMINI_MODEL:-gemini-3.8-flash}}"

# Update the source keys for translation
"${TRANSLATIONS_DIR}/tools/manage-translations.sh" update -l "$SOURCE_LOCALE" --yes
mkdir -p "$TRANSLATIONS_TARGET_DIR"

# Construct the prompt string
instruction='You are to translate the user interface of a **desktop shell**. Given a JSON object of key-value pairs, return a JSON with the same structure, with keys unchanged and values translated to '"$TARGET_LOCALE"'. Be as **concise** as possible to save screen space, and make sure terminology is relevant (e.g. "discharging" refers to the battery status).'
content=$(cat "${TRANSLATIONS_DIR}/en_US.json")
prompt_json=$(jq -n --arg prompt_text "$instruction" --arg content "$content" '$prompt_text + "\n```\n" + $content + "\n```\n"')

# Prepare request data using jq
# Gemini 3 cannot turn thinking off; low leaves room in its output cap for the whole file.
payload=$(jq -n \
    --arg prompt "$prompt_json" \
    --arg model "$MODEL" \
    '{
        contents: [{
            parts: [
                {text: $prompt}
            ]
        }],
        generationConfig: ({ responseMimeType: "application/json" }
            + (if ($model | startswith("gemini-3")) then { thinkingConfig: { thinkingLevel: "low" } } else {} end))
    }'
)
# echo "$payload" | jq

# Get API key
API_KEY=$(secret-tool lookup 'application' 'illogical-impulse' | jq -r '.apiKeys.gemini')

# Notify start
notify-send "Translation started" "Will take 2 minutes, and you'll be notified when it's done, so feel free to do something else in the meantime." -a "$NOTIFICATION_APP_NAME"

# Make the request
response=$(curl "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent" \
-H "x-goog-api-key: $API_KEY" \
-H 'Content-Type: application/json' \
-X POST \
-d "$payload" 2> /dev/null)
# echo "$response" | jq

# Only a complete JSON object replaces the language file and switches the language.
result=$(printf '%s' "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
if ! printf '%s' "$result" | jq -se 'length == 1 and (.[0] | type == "object" and length > 0)' >/dev/null 2>&1; then
    reason=$(printf '%s' "$response" | jq -r '.error.message // (.candidates[0].finishReason | select(. != null and . != "STOP")) // empty' 2>/dev/null)
    notify-send "Translation failed" "Nothing was changed. ${reason:-The answer was not a complete translation.}" -a "$NOTIFICATION_APP_NAME"
    exit 1
fi
printf '%s\n' "$result" > "${TRANSLATIONS_TARGET_DIR}/${TARGET_LOCALE}.json"
jq --arg locale "$TARGET_LOCALE" '.language.ui = $locale' "$SHELL_CONFIG_FILE" > "${SHELL_CONFIG_FILE}.tmp" && mv "${SHELL_CONFIG_FILE}.tmp" "$SHELL_CONFIG_FILE"
notify-send "Translation complete" "Enjoy! In case you wanna refine it, the file is in ${TRANSLATIONS_TARGET_DIR}/${TARGET_LOCALE}.json" -a "$NOTIFICATION_APP_NAME"
