# Mainstream installer presentation layer.
#
# Two modes:
#
#   - Plain mode (MS_VISUAL unset): centered banner + structured ms_*
#     helpers (ms_section, ms_step, etc.). v()/x()/pause()/showfun() are
#     overridden so their wrapper text is also centered. Subprocess
#     output (pacman, yay, ...) prints directly to the terminal at
#     column 0.
#
#   - Visual mode (MS_VISUAL=1, the default for ./setup install on a
#     TTY): all stdout/stderr is redirected to MS_LOG_FILE. A
#     background painter renders the last N log lines as a centered,
#     dim "→ <line>" tail under the banner, repainted in-place via
#     cursor save/restore. ms_section / ms_step lines are printed
#     *above* the tail anchor so they accumulate as visible progress
#     while the tail keeps showing live subprocess output. Interactive
#     prompts (pause, v's confirm) are suppressed — visual mode forces
#     ask=false. Pass --verbose (or set MS_VISUAL=0) to fall back to
#     the legacy interactive prompts and uncentered subprocess output.
#
# Sourced — not directly executable. Sourced *after* sdata/lib/functions.sh
# so the v/x/pause/showfun overrides win.

# --- palette (256-color indices that approximate the brand hex values) ---
MS_COL_STREAM_A='\e[38;5;80m'   # #3fb6c7
MS_COL_STREAM_B='\e[38;5;32m'   # #2f77c8
MS_COL_BODY='\e[38;5;252m'      # graphite #c9ccd4
MS_COL_MUTED='\e[38;5;245m'     # graphite-soft #9397a0
MS_COL_DIM='\e[2;38;5;240m'     # tail line color (dim)
MS_COL_OK='\e[38;5;79m'         # mint
MS_COL_ERR='\e[38;5;203m'       # error red
MS_COL_WARN='\e[38;5;214m'      # warn amber
MS_COL_ACCENT='\e[38;5;80m'     # heading = stream-a
MS_RST='\e[0m'
MS_BOLD='\e[1m'

MS_LOG_FILE="${MS_LOG_FILE:-${HOME}/.cache/mainstream-install.log}"
MS_TAIL_LINES="${MS_TAIL_LINES:-12}"

_ms_supports_truecolor() {
  case "${COLORTERM:-}" in
    truecolor|24bit) return 0 ;;
  esac
  return 1
}

_ms_logo_path() { echo "$(dirname "${BASH_SOURCE[0]}")/logo.txt"; }

_ms_term_width() {
  local cols=""
  if [[ -e /dev/tty ]]; then
    cols=$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2)
  fi
  [[ -n "$cols" ]] || cols=${COLUMNS:-80}
  echo "$cols"
}

_ms_logo_width() {
  local p; p=$(_ms_logo_path)
  if [[ -f "$p" ]]; then
    awk '{ if (length > max) max = length } END { print max+0 }' "$p"
  else
    echo 84
  fi
}

_ms_pad() {
  local n=$1
  (( n > 0 )) && printf '%*s' "$n" ''
}

_ms_col_width() {
  # Centered content column tracks the logo width so the logo, text,
  # and tail share the same horizontal bounds. Falls back to terminal
  # width on terminals narrower than the logo (logo will overflow on
  # those, but step/tail lines are clipped to stay within bounds).
  local lw; lw=$(_ms_logo_width)
  local tw; tw=$(_ms_term_width)
  if (( tw < lw )); then echo "$tw"; else echo "$lw"; fi
}

_ms_left_pad() {
  local cw; cw=$(_ms_col_width)
  local tw; tw=$(_ms_term_width)
  echo $(( (tw - cw) / 2 ))
}

_ms_clip() {
  local s="$1" n="$2"
  if (( ${#s} > n )); then printf '%s' "${s:0:n-1}…"; else printf '%s' "$s"; fi
}

# Strip every byte that could move the cursor or repaint the screen
# from $1 — ANSI/CSI/OSC escapes, charset switches, bare control chars
# (CR, BS, BEL, VT, ...). Anything left is printable UTF-8 plus space
# and tab. Used by the painter so log content can never reach the
# terminal in a form that disturbs the centered column.
_ms_strip_ansi() {
  # Order matters: sed first while ESC (0x1B) is still present so the
  # CSI/OSC patterns can match it. Cursor-position resets and line
  # erases are converted to CR so the final `s/.*\r//` keeps only the
  # last "frame" of any in-place redraw (pacman/makepkg progress).
  # Otherwise stripping the escapes alone would concatenate every frame
  # ("skipping" + "...skipping" → "skippingng…skipping").
  printf '%s' "$1" \
    | sed -E '
        s/\x1b\][^\x07]*\x07//g
        s/\x1b\[[0-9]*[GH]/\r/g
        s/\x1b\[2K/\r/g
        s/\x1b\[[?!<>=]?[0-9;]*[A-Za-z@-~]//g
        s/\x1b[()][AB012]//g
        s/\x1b[=>78cMHND\\]//g
        s/\x1b//g
        s/.*\r//
      ' \
    | tr -d '\000-\010\013-\037\177'
}

# Print to the terminal even when stdout has been redirected to a log
# (visual mode). Falls back to stdout in plain mode.
_ms_println() {
  if [[ -n "${MS_TERM_OUT:-}" ]] && { : >&"$MS_TERM_OUT"; } 2>/dev/null; then
    printf '%b\n' "$1" >&"$MS_TERM_OUT"
  else
    printf '%b\n' "$1"
  fi
}

_ms_print() {
  if [[ -n "${MS_TERM_OUT:-}" ]] && { : >&"$MS_TERM_OUT"; } 2>/dev/null; then
    printf '%b' "$1" >&"$MS_TERM_OUT"
  else
    printf '%b' "$1"
  fi
}

# --- banner / structured helpers -------------------------------------

ms_logo() {
  local logo_path; logo_path=$(_ms_logo_path)
  [[ -f "$logo_path" ]] || return 0

  local pad_s; pad_s=$(_ms_pad "$(_ms_left_pad)")

  _ms_println ""
  if _ms_supports_truecolor; then
    local lines=()
    mapfile -t lines < "$logo_path"
    local n=${#lines[@]} i
    for ((i = 0; i < n; i++)); do
      local t=$(( n > 1 ? (i * 100) / (n - 1) : 0 ))
      local r=$(( 63 + (47  - 63 ) * t / 100 ))
      local g=$(( 182 + (119 - 182) * t / 100 ))
      local b=$(( 199 + (200 - 199) * t / 100 ))
      _ms_println "${pad_s}\e[38;2;${r};${g};${b}m${lines[i]}\e[0m"
    done
  else
    while IFS= read -r line; do
      _ms_println "${pad_s}${MS_COL_STREAM_A}${line}${MS_RST}"
    done < "$logo_path"
  fi
  _ms_println ""
}

# Internal: print one centered line. In visual mode also re-anchors the
# tail painter to the new cursor position so the tail repaints below.
_ms_emit_above_tail() {
  local rendered="$1"
  if [[ -n "${MS_TERM_OUT:-}" ]] && [[ -n "${MS_TAIL_PID:-}" ]]; then
    # Visual mode: pause painter, jump cursor to anchor, clear the tail
    # region with absolute positioning (don't trust \n to reset column,
    # see _ms_anchor_to), print the new line, save the new anchor,
    # resume painter.
    _ms_pause_painter
    local n=${MS_TAIL_LINES:-12} i=0
    while (( i < n )); do
      _ms_anchor_to "$i" "$MS_TERM_OUT"
      printf '\e[2K' >&"$MS_TERM_OUT"
      i=$((i+1))
    done
    _ms_anchor_to 0 "$MS_TERM_OUT"
    printf '%b\r\n' "$rendered" >&"$MS_TERM_OUT"
    printf '\e[s' >&"$MS_TERM_OUT"
    _ms_resume_painter
  else
    printf '%b\n' "$rendered"
  fi
}

ms_section() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" "$cw")
  _ms_emit_above_tail "${pad}${MS_COL_ACCENT}${text}${MS_RST}"
}

ms_step() {
  local verb="$1" target="$2" note="${3:-}"
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local rendered
  if [[ -n "$note" ]]; then
    rendered=$(printf '%s  %b+%b %b%s %b%s%b %b(%s)%b' \
      "$pad" \
      "$MS_COL_OK" "$MS_RST" \
      "$MS_COL_BODY" "$verb" \
      "$MS_BOLD" "$target" "$MS_RST" \
      "$MS_COL_MUTED" "$note" "$MS_RST")
  else
    rendered=$(printf '%s  %b+%b %b%s %b%s%b%b...%b' \
      "$pad" \
      "$MS_COL_OK" "$MS_RST" \
      "$MS_COL_BODY" "$verb" \
      "$MS_BOLD" "$target" "$MS_RST" \
      "$MS_COL_BODY" "$MS_RST")
  fi
  _ms_emit_above_tail "$rendered"
}

ms_step_raw() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" $((cw - 4)))
  local rendered
  rendered=$(printf '%s  %b+%b %b%s%b' \
    "$pad" "$MS_COL_OK" "$MS_RST" "$MS_COL_BODY" "$text" "$MS_RST")
  _ms_emit_above_tail "$rendered"
}

ms_optdep_header() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  _ms_emit_above_tail "${pad}${MS_COL_BODY}Optional dependencies for ${MS_BOLD}$1${MS_RST}"
}

ms_optdep() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local pkg="$1" desc="$2"
  local rendered
  rendered=$(printf '%s      %b%-19s %b%s%b' \
    "$pad" "$MS_COL_BODY" "${pkg}:" "$MS_COL_MUTED" "$desc" "$MS_RST")
  _ms_emit_above_tail "$rendered"
}

ms_ready() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local msg="${1:-reboot to enter Mainstream.}"
  _ms_emit_above_tail "${pad}${MS_COL_ACCENT}Ready.${MS_RST} ${MS_COL_MUTED}${msg}${MS_RST}"
}

ms_hint() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" "$cw")
  _ms_emit_above_tail "${pad}${MS_COL_MUTED}${text}${MS_RST}"
}

ms_note() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" "$cw")
  _ms_emit_above_tail "${pad}${MS_COL_BODY}${text}${MS_RST}"
}

ms_warn() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" "$cw")
  _ms_emit_above_tail "${pad}${MS_COL_WARN}${text}${MS_RST}"
}

ms_line() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local text; text=$(_ms_clip "$1" "$cw")
  _ms_emit_above_tail "${pad}${text}"
}

# Centered read prompt (plain mode only — visual mode forces ask=false).
ms_ask() {
  local prompt="$1" var="$2"
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  printf '%s%s' "$pad" "$prompt"
  read -r "$var"
}

# --- visual mode -----------------------------------------------------

# Paint loop pause/resume via SIGSTOP/SIGCONT. The painter holds the
# terminal during repaint; pausing it briefly while a step prints
# prevents interleaving.
_ms_pause_painter() {
  [[ -n "${MS_TAIL_PID:-}" ]] && kill -STOP "$MS_TAIL_PID" 2>/dev/null || true
}
_ms_resume_painter() {
  [[ -n "${MS_TAIL_PID:-}" ]] && kill -CONT "$MS_TAIL_PID" 2>/dev/null || true
}

# Position cursor at saved anchor, offset by `row` lines down, column 0.
# Uses absolute positioning so it cannot be fooled by a TTY mode change
# (e.g. sudo/pacman briefly disabling ONLCR) — without this the cursor
# can fail to return to col 0 on \n and subsequent prints stack up at
# whatever column the previous line ended on, producing the "scattered
# tail" layout we saw in the wild.
_ms_anchor_to() {
  local row=$1 fd=$2
  if (( row == 0 )); then
    printf '\e[u\r' >&"$fd"
  else
    printf '\e[u\e[%dB\r' "$row" >&"$fd"
  fi
}

# Background loop: every tick, jump to anchor, render last N log lines
# centered + dim, blank-pad the rest of the region.
_ms_tail_painter() {
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  local cw; cw=$(_ms_col_width)
  local n=${MS_TAIL_LINES:-12}
  local fd="$MS_TERM_OUT"
  # body_w leaves room for: 2-space gutter + "→ " (2) + safety margin
  # (4) so wide UTF-8 codepoints can't push past the centered column.
  local body_w=$((cw - 10))
  (( body_w < 10 )) && body_w=10

  trap 'exit 0' TERM INT

  while true; do
    local i=0
    if [[ -f "$MS_LOG_FILE" ]]; then
      while IFS= read -r raw; do
        local clean; clean=$(_ms_strip_ansi "$raw")
        if (( ${#clean} > body_w )); then
          clean="${clean:0:body_w-1}…"
        fi
        _ms_anchor_to "$i" "$fd"
        printf '\e[2K%s  \e[2;38;5;240m→ %s\e[0m' "$pad" "$clean" >&"$fd"
        i=$((i+1))
      done < <(tail -n "$n" "$MS_LOG_FILE" 2>/dev/null)
    fi
    while (( i < n )); do
      _ms_anchor_to "$i" "$fd"
      printf '\e[2K' >&"$fd"
      i=$((i+1))
    done
    sleep 0.15
  done
}

# Begin visual mode. Must be called *after* the banner + initial
# section header have been printed, since this saves the current cursor
# as the tail anchor.
ms_visual_begin() {
  [[ "${MS_VISUAL:-0}" == "1" ]] || return 0
  mkdir -p "$(dirname "$MS_LOG_FILE")"
  : > "$MS_LOG_FILE"
  echo "=== Mainstream install · $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$MS_LOG_FILE"

  # Save the original stdout/stderr so painter + ms_* helpers can write
  # to the terminal even after we redirect script output to the log.
  exec {MS_TERM_OUT}>&1
  export MS_TERM_OUT
  # Hide cursor and save current cursor position as the tail anchor.
  printf '\e[?25l\e[s' >&"$MS_TERM_OUT"
  # Redirect everything else into the log.
  exec >>"$MS_LOG_FILE" 2>&1
  # Force non-interactive mode — visual mode swallows prompts.
  ask=false

  _ms_tail_painter &
  MS_TAIL_PID=$!
  disown "$MS_TAIL_PID" 2>/dev/null || true
}

ms_visual_end() {
  [[ -n "${MS_TAIL_PID:-}" ]] || return 0
  kill -TERM "$MS_TAIL_PID" 2>/dev/null || true
  wait "$MS_TAIL_PID" 2>/dev/null || true
  unset MS_TAIL_PID
  if [[ -n "${MS_TERM_OUT:-}" ]]; then
    # Clear the tail region and restore stdout/stderr to the terminal.
    # Absolute positioning (see _ms_anchor_to) so torn-down rows don't
    # leave residue when a child changed the TTY mode.
    local n=${MS_TAIL_LINES:-12} i=0
    while (( i < n )); do
      _ms_anchor_to "$i" "$MS_TERM_OUT" 2>/dev/null
      printf '\e[2K' >&"$MS_TERM_OUT" 2>/dev/null
      i=$((i+1))
    done
    printf '\e[u\e[?25h' >&"$MS_TERM_OUT" 2>/dev/null
    exec 1>&"$MS_TERM_OUT"
    exec 2>&"$MS_TERM_OUT"
    exec {MS_TERM_OUT}>&-
    unset MS_TERM_OUT
  fi
}

# Always restore terminal on exit, even on Ctrl-C / errors.
ms_visual_trap() {
  ms_visual_end
}

# Quick reachability check for the two services every install needs.
# Bails out before pacman installs anything if either is unreachable, so
# the user doesn't end up with base-devel installed but no AUR helper
# (the failure mode that produced /boot empty + no quickshell).
ms_preflight_network() {
  local _bad=()
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 6 -o /dev/null https://aur.archlinux.org/ 2>/dev/null \
      || _bad+=("aur.archlinux.org")
    curl -fsS --max-time 6 -o /dev/null https://archlinux.org/ 2>/dev/null \
      || _bad+=("archlinux.org")
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=6 --tries=1 -O /dev/null https://aur.archlinux.org/ \
      || _bad+=("aur.archlinux.org")
    wget -q --timeout=6 --tries=1 -O /dev/null https://archlinux.org/ \
      || _bad+=("archlinux.org")
  else
    return 0
  fi
  if (( ${#_bad[@]} > 0 )); then
    local _pad; _pad=$(_ms_pad "$(_ms_left_pad)")
    printf '\n'
    printf '%s%bcannot reach: %s%b\n'  "$_pad" "${MS_COL_ERR}"   "${_bad[*]}" "${MS_RST}"
    printf '%s%bAUR or the Arch mirrors look down. The installer needs both.%b\n' \
      "$_pad" "${MS_COL_MUTED}" "${MS_RST}"
    printf '%s%bre-run ./setup install once connectivity is back.%b\n' \
      "$_pad" "${MS_COL_MUTED}" "${MS_RST}"
    printf '\n'
    exit 1
  fi
}

# ----------------------------------------------------------------------
# Overrides for the chatty installer helpers from functions.sh.
#
# Plain mode: prints the same content as the original, padded into the
# centered column.
#
# Visual mode: suppresses the chatty wrapper output entirely (it would
# spam the log with menu text). The wrapped command's output still
# lands in the log via the global redirect.
# ----------------------------------------------------------------------

pause() {
  [[ "${MS_VISUAL:-0}" == "1" ]] && return 0
  if [ ! "$ask" == "false" ]; then
    local pad; pad=$(_ms_pad "$(_ms_left_pad)")
    printf '%s\e[2;3m(Ctrl-C to abort, Enter to proceed)\e[0m' "$pad"
    local p; read -r p
  fi
}

showfun() {
  if [[ "${MS_VISUAL:-0}" == "1" ]]; then
    # Quietly log the function definition — useful in logs, invisible
    # to the user.
    printf '\n--- function "%s" ---\n' "$1"
    type -a "$1" 2>/dev/null
    printf -- '---\n'
    return 0
  fi
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  printf '%s\e[34m[%s]: The definition of function "%s" is as follows:\e[0m\n' "$pad" "$0" "$1"
  type -a "$1" 2>/dev/null | while IFS= read -r line; do
    printf '%s\e[32m%s\e[0m\n' "$pad" "$line"
  done || return 1
}

_ms_sudo_prompt_if_needed() {
  [[ "$1" == "sudo" ]] || return 0
  sudo -n true 2>/dev/null && return 0
  _ms_pause_painter
  if [[ -n "${MS_TERM_OUT:-}" ]]; then
    local _pad; _pad=$(_ms_pad "$(_ms_left_pad)")
    printf '\e[?25h' >&"$MS_TERM_OUT" 2>/dev/null
    printf '\n%s%b[sudo password required]%b\n' "$_pad" "${MS_COL_MUTED}" "${MS_RST}" >&"$MS_TERM_OUT"
    printf '%s' "$_pad" >&"$MS_TERM_OUT"
    sudo -v </dev/tty >&"$MS_TERM_OUT" 2>&"$MS_TERM_OUT" || true
    printf '\e[?25l' >&"$MS_TERM_OUT" 2>/dev/null
  else
    sudo -v || true
  fi
  _ms_resume_painter
}

# Centered failure block + log tail. Tears down the painter, restores
# the cursor, then exits with the given rc. Writes through a saved
# terminal FD captured *before* ms_visual_end swaps stdout back —
# bash buffers stdout when it points at a file, and we don't want the
# failure block lost to an unflushed log buffer.
_ms_fail_exit() {
  local rc=$1; shift
  # Snapshot the terminal FD before tearing down the painter. After
  # ms_visual_end the prior stdout is closed and any buffered bytes
  # there are gone — write to the snapshot instead.
  local _term_fd=""
  if [[ -n "${MS_TERM_OUT:-}" ]]; then
    exec {_term_fd}>&"$MS_TERM_OUT"
  fi
  ms_visual_end
  local _out=1
  [[ -n "$_term_fd" ]] && _out=$_term_fd

  local _pad; _pad=$(_ms_pad "$(_ms_left_pad)")
  local _cw;  _cw=$(_ms_col_width)
  local _body_w=$((_cw - 4)); (( _body_w < 20 )) && _body_w=20

  printf '\n' >&"$_out"
  printf '%s%bMainstream install failed%b\n' "$_pad" "${MS_COL_ERR}" "${MS_RST}" >&"$_out"
  printf '%s%bcommand:%b %s\n'              "$_pad" "${MS_COL_MUTED}" "${MS_RST}" "$*"  >&"$_out"
  printf '%s%bexit:%b    %d\n'              "$_pad" "${MS_COL_MUTED}" "${MS_RST}" "$rc" >&"$_out"
  printf '%s%blog:%b     %s\n'              "$_pad" "${MS_COL_MUTED}" "${MS_RST}" "$MS_LOG_FILE" >&"$_out"
  printf '\n' >&"$_out"
  printf '%s%blast lines from the log:%b\n' "$_pad" "${MS_COL_MUTED}" "${MS_RST}" >&"$_out"
  if [[ -f "$MS_LOG_FILE" ]]; then
    tail -n 20 "$MS_LOG_FILE" | while IFS= read -r _line; do
      local _clean; _clean=$(_ms_strip_ansi "$_line")
      if (( ${#_clean} > _body_w )); then
        _clean="${_clean:0:_body_w-1}…"
      fi
      printf '%s  %b→ %s%b\n' "$_pad" "${MS_COL_DIM}" "$_clean" "${MS_RST}" >&"$_out"
    done
  fi
  printf '\n' >&"$_out"
  printf '%s%bre-run ./setup install once AUR / mirrors recover (idempotent).%b\n' "$_pad" "${MS_COL_MUTED}" "${MS_RST}" >&"$_out"
  printf '%s%btail -f %s%b\n' "$_pad" "${MS_COL_MUTED}" "$MS_LOG_FILE" "${MS_RST}" >&"$_out"
  printf '\n' >&"$_out"

  [[ "$_out" != "1" ]] && exec {_out}>&-
  exit "$rc"
}

v() {
  if [[ "${MS_VISUAL:-0}" == "1" ]]; then
    _ms_sudo_prompt_if_needed "$1"
    printf '\n>>> %s\n' "$*"
    "$@"; local rc=$?
    if (( rc == 0 )); then
      printf '<<< ok: %s\n' "$*"
    else
      printf '<<< FAILED (rc=%d): %s\n' "$rc" "$*"
      _ms_fail_exit "$rc" "$@"
    fi
    return 0
  fi
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  printf '%s####################################################\n' "$pad"
  printf '%s\e[34m[%s]: Next command:\e[0m\n' "$pad" "$0"
  printf '%s\e[32m%s\e[0m\n' "$pad" "$*"
  local execute=true
  if $ask; then
    while true; do
      printf '%s\e[34mExecute?\e[0m\n' "$pad"
      printf '%s  y = Yes\n' "$pad"
      printf '%s  e = Exit now\n' "$pad"
      printf '%s  s = Skip this command (NOT recommended - your setup might not work correctly)\n' "$pad"
      printf '%s  yesforall = Yes and do not ask again; NOT recommended unless you are really sure\n' "$pad"
      printf '%s====> ' "$pad"
      local p; read -r p
      case $p in
        [yY]) printf '%s\e[34mOK, executing...\e[0m\n' "$pad"; break;;
        [eE]) printf '%s\e[34mExiting...\e[0m\n' "$pad"; exit;;
        [sS]) printf '%s\e[34mAlright, skipping this one...\e[0m\n' "$pad"; execute=false; break;;
        "yesforall") printf '%s\e[34mAlright, will not ask again. Executing...\e[0m\n' "$pad"; ask=false; break;;
        *) printf '%s\e[31mPlease enter [y/e/s/yesforall].\e[0m\n' "$pad";;
      esac
    done
  fi
  if $execute; then
    x "$@"
  else
    printf '%s\e[33m[%s]: Skipped "%s"\e[0m\n' "$pad" "$0" "$*"
  fi
}

x() {
  if [[ "${MS_VISUAL:-0}" == "1" ]]; then
    _ms_sudo_prompt_if_needed "$1"
    "$@"; local _rc=$?
    if (( _rc == 0 )); then return 0; fi
    # Up to two retries with backoff for transient AUR/mirror/network
    # blips. Each retry message is rendered above the tail so the user
    # sees the install is recovering (instead of staring at a stale
    # "fatal: ..." line and Ctrl-C'ing).
    local _label
    _label=$(_ms_clip "$*" 60)
    local _attempt
    for _attempt in 1 2; do
      ms_hint "transient failure (rc=${_rc}) — retrying in $((_attempt * 3))s [${_attempt}/2]"
      ms_step_raw "retry: ${_label}"
      printf '\n[retry %d/2 after rc=%d] %s\n' "$_attempt" "$_rc" "$*"
      sleep $((_attempt * 3))
      "$@"; _rc=$?
      if (( _rc == 0 )); then
        ms_hint "recovered after retry ${_attempt}"
        return 0
      fi
    done
    _ms_fail_exit "$_rc" "$@"
  fi
  local pad; pad=$(_ms_pad "$(_ms_left_pad)")
  if "$@"; then local cmdstatus=0; else local cmdstatus=1; fi
  while [ $cmdstatus == 1 ]; do
    printf '%s\e[31m[%s]: Command "\e[32m%s\e[31m" has failed.\e[0m\n' "$pad" "$0" "$*"
    printf '%s\e[31mYou may need to resolve the problem manually BEFORE repeating this command.\e[0m\n' "$pad"
    printf '%s\e[31m[Tip] If a certain package is failing to install, try installing it separately in another terminal.\e[0m\n' "$pad"
    printf '%s  r = Repeat this command (DEFAULT)\n' "$pad"
    printf '%s  e = Exit now\n' "$pad"
    printf '%s  i = Ignore this error and continue (your setup might not work correctly)\n' "$pad"
    printf '%s [R/e/i]: ' "$pad"
    local p; read -r p
    case $p in
      [iI]) printf '%s\e[34mAlright, ignore and continue...\e[0m\n' "$pad"; cmdstatus=2;;
      [eE]) printf '%s\e[34mAlright, will exit.\e[0m\n' "$pad"; break;;
      *) printf '%s\e[34mOK, repeating...\e[0m\n' "$pad"
         if "$@"; then cmdstatus=0; else cmdstatus=1; fi;;
    esac
  done
  case $cmdstatus in
    0) printf '%s\e[34m[%s]: Command "\e[32m%s\e[34m" finished.\e[0m\n' "$pad" "$0" "$*";;
    1) printf '%s\e[31m[%s]: Command "\e[32m%s\e[31m" has failed. Exiting...\e[0m\n' "$pad" "$0" "$*"; exit 1;;
    2) printf '%s\e[31m[%s]: Command "\e[32m%s\e[31m" has failed but ignored by user.\e[0m\n' "$pad" "$0" "$*";;
  esac
}
