#!/usr/bin/env bash

# Runs one AI sidebar request, or one command a model asked for, as the leader
# of its own process group, so that a Stop ends everything the request started.
#
# run-request.sh [--workdir DIR] [--filter FORMAT] [--diff] [--report-exit]
#                [--stdin | --body] [--tail-bytes N] [--timeout SECONDS]
#                [--secret-header NAME PREFIX ENVVAR]... [--upload-gemini PATH]
#                [--inline-file PATH] [--file-token TOKEN] -- PROGRAM [ARGS...]
#
# Secrets arrive in the environment and prompts on stdin, never in argv,
# which every local user can read in /proc. An attached file's type, contents
# and uploaded URI fill in TOKEN_MIME__, TOKEN_B64__ and TOKEN_URI__ in the body.

export PATH="$HOME/.local/bin:$PATH"
unset CLAUDECODE
# Bash gives background jobs /dev/null as stdin, so the service's pipe is kept.
exec 3<&0

# Sets state to the fields after the command name, without the fork a
# command substitution costs on every watchdog tick.
proc_state() {
    read -r state < "/proc/$1/stat" 2>/dev/null || return 1
    state=${state##*) }
}

proc_state "$$"
read -r -a fields <<< "$state"
if [ "${fields[2]}" != "$$" ]; then
    echo "run-request.sh: must lead its own process group (start it with setsid)" >&2
    exit 1
fi

on_stop() {
    trap '' TERM INT HUP
    kill -TERM -- "-$$" 2>/dev/null
    exit 143
}
trap on_stop TERM INT HUP

tmpdir=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/ms-ai.XXXXXX") || exit 1
watchdog=""
timer=""
trap 'kill -KILL $watchdog $timer 2>/dev/null; rm -rf -- "$tmpdir"' EXIT

# A FIFO nobody writes to gives `read -t` a timeout without a sleep process
# that could outlive the request.
mkfifo -m 600 "$tmpdir/tick" || exit 1

alive() {
    proc_state "$1" && [ "${state:0:1}" != "Z" ]
}

# Ends the group when Quickshell dies or this script is SIGKILLed, the paths
# on which no trap runs. It ignores TERM so a Stop cannot remove it first.
(
    trap '' TERM INT HUP
    exec 4<> "$tmpdir/tick"
    while alive "$PPID" && alive "$$"; do
        read -r -t 1 -u 4
    done
    rm -rf -- "$tmpdir"
    kill -KILL -- "-$$" 2>/dev/null
) < /dev/null > /dev/null 2>&1 3<&- &
watchdog=$!

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

workdir=""
filter=""
diff=0
report_exit=0
input=""
tail_bytes=""
timeout_s=""
upload_path=""
inline_path=""
file_token=""
secret_names=()
secret_prefixes=()
secret_vars=()

usage_error() {
    echo "run-request.sh: $1" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workdir) [ $# -ge 2 ] || usage_error "missing value for $1"; workdir=$2; shift 2 ;;
        --filter) [ $# -ge 2 ] || usage_error "missing value for $1"; filter=$2; shift 2 ;;
        --diff) diff=1; shift ;;
        --report-exit) report_exit=1; shift ;;
        --stdin) input=stdin; shift ;;
        --body) input=body; shift ;;
        --tail-bytes) [ $# -ge 2 ] || usage_error "missing value for $1"; tail_bytes=$2; shift 2 ;;
        --timeout) [ $# -ge 2 ] || usage_error "missing value for $1"; timeout_s=$2; shift 2 ;;
        --secret-header)
            [ $# -ge 4 ] || usage_error "--secret-header needs NAME PREFIX ENVVAR"
            [[ $2 =~ ^[A-Za-z0-9-]+$ ]] || usage_error "invalid header name"
            [[ $4 =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || usage_error "invalid variable name"
            secret_names+=("$2"); secret_prefixes+=("$3"); secret_vars+=("$4")
            shift 4 ;;
        --upload-gemini) [ $# -ge 2 ] || usage_error "missing value for $1"; upload_path=$2; shift 2 ;;
        --inline-file) [ $# -ge 2 ] || usage_error "missing value for $1"; inline_path=$2; shift 2 ;;
        --file-token) [ $# -ge 2 ] || usage_error "missing value for $1"; file_token=$2; shift 2 ;;
        --) shift; break ;;
        *) usage_error "unknown option $1" ;;
    esac
done
[ $# -gt 0 ] || usage_error "no program given"
[ -z "$tail_bytes" ] || [[ $tail_bytes =~ ^[1-9][0-9]*$ ]] || usage_error "invalid --tail-bytes"
[ -z "$timeout_s" ] || [[ $timeout_s =~ ^[1-9][0-9]*$ ]] || usage_error "invalid --timeout"
[ -z "$file_token" ] || [[ $file_token =~ ^[A-Za-z0-9_]+$ ]] || usage_error "invalid --file-token"
if [ "$input" = body ] && [ -n "$upload_path$inline_path" ] && [ -z "$file_token" ]; then
    usage_error "an attached file needs --file-token"
fi

if [ -n "$workdir" ]; then
    mkdir -p -- "$workdir" && cd -- "$workdir" || exit 1
fi

: > "$tmpdir/stderr"

json_exit_line() {
    if command -v jq > /dev/null 2>&1; then
        jq -cRs --argjson code "$1" '{event: "cli_exit", code: $code, stderr: .}'
    else
        python3 -c 'import json, sys; print(json.dumps({"event": "cli_exit", "code": int(sys.argv[1]), "stderr": sys.stdin.buffer.read().decode("utf-8", "replace")}, separators=(",", ":")))' "$1"
    fi
}

finish() {
    local code=$1
    if [ "$report_exit" = 1 ] && [ "$code" -ne 0 ]; then
        tail -c 8192 -- "$tmpdir/stderr" | json_exit_line "$code"
    fi
    exit "$code"
}

fail_early() {
    printf '%s\n' "$1" >> "$tmpdir/stderr"
    finish 1
}

json_field() {
    if command -v jq > /dev/null 2>&1; then
        jq -r "$1 // empty" 2>/dev/null
    else
        python3 -c 'import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1].lstrip(".").split("."):
    v = v.get(k) if isinstance(v, dict) else None
print(v if isinstance(v, str) else "")' "$1" 2>/dev/null
    fi
}

safe_value() {
    [[ $1 =~ ^[A-Za-z0-9:/._+-]+$ ]]
}

if [ "$input" = body ]; then
    cat <&3 > "$tmpdir/body" || fail_early "Could not read the request body."
fi

print_secret_headers() {
    local i value
    for i in "${!secret_names[@]}"; do
        value=${!secret_vars[i]}
        value=${value//[$'\r\n']/}
        printf '%s: %s%s\n' "${secret_names[i]}" "${secret_prefixes[i]}" "$value"
    done
}

# Sets mime for an attached file, or fails the request.
attached_mime() {
    [ -f "$1" ] || fail_early "The attached file was not found."
    mime=$(file -b --mime-type -- "$1")
    safe_value "$mime" || fail_early "The attached file has an unknown type."
}

if [ -n "$upload_path" ]; then
    attached_mime "$upload_path"
    size=$(stat -c %s -- "$upload_path") || fail_early "The attached file could not be read."
    curl --silent --show-error "https://generativelanguage.googleapis.com/upload/v1beta/files" \
        -H @<(print_secret_headers) \
        -D "$tmpdir/upload-headers" \
        -H "X-Goog-Upload-Protocol: resumable" \
        -H "X-Goog-Upload-Command: start" \
        -H "X-Goog-Upload-Header-Content-Length: $size" \
        -H "X-Goog-Upload-Header-Content-Type: $mime" \
        -H "Content-Type: application/json" \
        -d '{"file": {"display_name": "Image"}}' \
        -o /dev/null 2>> "$tmpdir/stderr" || fail_early "The attached file could not be uploaded."
    upload_url=$(grep -i '^x-goog-upload-url: ' "$tmpdir/upload-headers" | head -n 1 | cut -d ' ' -f 2 | tr -d '\r')
    [ -n "$upload_url" ] || fail_early "The attached file could not be uploaded."
    curl --silent --show-error "$upload_url" \
        -H @<(print_secret_headers) \
        -H "Content-Length: $size" \
        -H "X-Goog-Upload-Offset: 0" \
        -H "X-Goog-Upload-Command: upload, finalize" \
        --data-binary "@$upload_path" \
        -o "$tmpdir/upload-info" 2>> "$tmpdir/stderr" || fail_early "The attached file could not be uploaded."
    uri=$(json_field .file.uri < "$tmpdir/upload-info")
    safe_value "$uri" || fail_early "The attached file could not be uploaded."
    printf '{"uploadedFile":{"uri":"%s","mimeType":"%s"}}\n,\n' "$uri" "$mime"
    if [ "$input" = body ]; then
        sed -i -e "s|${file_token}_URI__|$uri|g" -e "s|${file_token}_MIME__|$mime|g" -- "$tmpdir/body"
    fi
fi

if [ -n "$inline_path" ] && [ "$input" = body ]; then
    attached_mime "$inline_path"
    sed -i -e "s|${file_token}_MIME__|$mime|g" -- "$tmpdir/body"
    placeholder=${file_token}_B64__
    offset=$(LC_ALL=C grep -bo -F -- "$placeholder" "$tmpdir/body" | head -n 1 | cut -d : -f 1)
    if [ -n "$offset" ]; then
        {
            head -c "$offset" -- "$tmpdir/body"
            base64 -w 0 -- "$inline_path"
            tail -c "+$((offset + ${#placeholder} + 1))" -- "$tmpdir/body"
        } > "$tmpdir/body.new" && mv -f -- "$tmpdir/body.new" "$tmpdir/body"
    fi
fi

filter_cmd=()
if [ -n "$filter" ] && command -v python3 > /dev/null 2>&1 && [ -f "$script_dir/stream-diff-filter.py" ]; then
    filter_cmd=(python3 -u "$script_dir/stream-diff-filter.py" --format "$filter")
    [ "$diff" = 1 ] && filter_cmd+=(--diff --since "${EPOCHREALTIME/,/.}")
fi

if [ -n "$tail_bytes" ]; then
    err_mode=merge
elif [ "$report_exit" = 1 ]; then
    err_mode=file
else
    err_mode=none
fi

# Runs PROGRAM and records its own status. The handler (not an ignore) lets
# PROGRAM keep the default TERM action while this stage outlives it to write
# the status.
first_stage() {
    trap ':' TERM INT HUP
    case "$err_mode" in
        merge) exec 4>&1 ;;
        file) exec 4>> "$tmpdir/stderr" ;;
        *) exec 4> /dev/null ;;
    esac
    case "$input" in
        stdin) exec 0<&3 ;;
        body) exec 0< "$tmpdir/body" ;;
        *) exec 0< /dev/null ;;
    esac
    # Keeps the shell's own job notices out of PROGRAM's output.
    exec 3<&- 2> /dev/null
    if [ ${#secret_names[@]} -gt 0 ]; then
        "$@" -H @<(print_secret_headers) 2>&4 4>&-
    else
        "$@" 2>&4 4>&-
    fi
    echo "$?" > "$tmpdir/status"
}

timedout=0
on_timeout() {
    timedout=1
    trap '' TERM INT HUP
    kill -TERM -- "-$$" 2>/dev/null
    trap on_stop TERM INT HUP
}

if [ -n "$timeout_s" ]; then
    trap on_timeout USR1
    (
        exec 4<> "$tmpdir/tick"
        read -r -t "$timeout_s" -u 4
        kill -USR1 "$$"
    ) < /dev/null > /dev/null 2>&1 3<&- &
    timer=$!
fi

# Run in the background and waited on, so the traps fire as soon as a signal
# arrives instead of after PROGRAM exits.
(
    trap ':' TERM INT HUP
    if [ -n "$tail_bytes" ]; then
        # The tail ignores TERM so a timed-out command still leaves its output.
        first_stage "$@" | ( trap '' TERM INT HUP; exec tail -c "$tail_bytes" ) > "$tmpdir/out"
    elif [ ${#filter_cmd[@]} -gt 0 ]; then
        first_stage "$@" | "${filter_cmd[@]}"
    else
        first_stage "$@"
    fi
) &
pipeline=$!

while kill -0 "$pipeline" 2>/dev/null; do
    wait "$pipeline"
done

status=1
if [ -s "$tmpdir/status" ]; then
    read -r status < "$tmpdir/status"
    [[ $status =~ ^[0-9]+$ ]] || status=1
fi

if [ -n "$tail_bytes" ]; then
    # A cut tail may start inside a UTF-8 character, so its first line goes.
    size=$(stat -c %s -- "$tmpdir/out" 2>/dev/null || echo 0)
    if [ "$size" -ge "$tail_bytes" ]; then
        tail -n +2 -- "$tmpdir/out" > "$tmpdir/shown"
    else
        mv -f -- "$tmpdir/out" "$tmpdir/shown"
    fi
    cat -- "$tmpdir/shown"
    if [ -s "$tmpdir/shown" ] && [ -n "$(tail -c 1 -- "$tmpdir/shown")" ]; then
        echo
    fi
    printf 'ms-exit %d %d\n' "$status" "$timedout"
fi

finish "$status"
