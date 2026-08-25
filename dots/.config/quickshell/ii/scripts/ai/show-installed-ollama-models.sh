#!/usr/bin/env bash

# Three different things used to look identical here. A missing binary, a server
# that is not running, and a server with nothing pulled all ended as "[]" and an
# exit of 0, so the sidebar showed no models and had nothing to say about why.
# The state is reported alongside the list, and the caller decides what to tell
# the user.
#
# Output is always one line of JSON:
#   {"state":"ok","models":["llama3.2:3b"]}
#   {"state":"missing","models":[]}    ollama is not installed
#   {"state":"stopped","models":[]}    installed, but nothing answering on the port
#   {"state":"empty","models":[]}      running, no models pulled yet

emit() { printf '{"state":"%s","models":[%s]}\n' "$1" "${2:-}"; }

if ! command -v ollama >/dev/null 2>&1; then
    emit missing
    exit 0
fi

# `ollama list` blocks for a while against a dead server, and the sidebar is
# waiting on this, so give it a deadline.
if ! raw=$(timeout 5 ollama list 2>/dev/null); then
    emit stopped
    exit 0
fi

# Skip the header row, take the name column.
mapfile -t names < <(printf '%s\n' "$raw" | tail -n +2 | awk 'NF {print $1}')

if [[ ${#names[@]} -eq 0 ]]; then
    emit empty
    exit 0
fi

json=""
for name in "${names[@]}"; do
    # Names come from the server, so quote-escape rather than trusting them.
    esc=${name//\\/\\\\}
    esc=${esc//\"/\\\"}
    json+="\"$esc\","
done
emit ok "${json%,}"
