#!/usr/bin/env bash

# Downloads an Ollama model and reports progress the sidebar can render.
#
# The `ollama pull` CLI draws a terminal progress bar: it writes to stderr,
# redraws with cursor-movement escapes, and wraps every line in ANSI control
# sequences even when its output is a pipe. Parsing that back into a
# percentage is guesswork that breaks whenever the bar changes. The HTTP API
# behind it streams newline-delimited JSON with exact byte counts, so that is
# what this reads.
#
# Output is one line of JSON per update, always on stdout:
#   {"state":"pulling","pct":42,"status":"pulling 797b70c4edf8"}
#   {"state":"success"}
#   {"state":"error","message":"..."}

set -uo pipefail

MODEL="${1:-}"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
[[ "$API" == http://* || "$API" == https://* ]] || API="http://$API"

emit_error() {
    # jq -R turns an arbitrary message into a valid JSON string, so a curl
    # error containing quotes cannot break the line the sidebar parses.
    jq -cn --arg m "$1" '{state:"error",message:$m}'
    exit 1
}

if [[ -z "$MODEL" ]]; then
    emit_error "No model name given."
fi

# The name arrives from a text field in the sidebar and is about to be placed
# in a JSON body, so accept only what a real Ollama reference can contain.
# Covers "llama3.2:3b", "library/qwen2.5:0.5b" and "hf.co/user/repo:Q4_K_M".
if [[ ! "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*(:[A-Za-z0-9._-]+)?$ ]]; then
    emit_error "That does not look like a model name: $MODEL"
fi

body=$(jq -cn --arg m "$MODEL" '{model:$m,stream:true}')

curl -sN --max-time 7200 "$API/api/pull" -d "$body" 2>/dev/null | jq -c --unbuffered '
    if .error then
        {state:"error", message:.error}
    elif .status == "success" then
        {state:"success"}
    elif (.total // 0) > 0 then
        {state:"pulling", pct:(((.completed // 0) * 100 / .total) | floor), status:(.status // "")}
    else
        {state:"pulling", pct:-1, status:(.status // "")}
    end
' 2>/dev/null

# PIPESTATUS[0] is curl: a server that goes away mid-download otherwise looks
# identical to a completed pull, because jq still exits 0 on a truncated stream.
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    emit_error "Lost contact with the Ollama server during the download."
fi
