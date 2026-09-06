# Translations for the scripts the shell drives, the update helper first of
# all. They print into the same panes the shell translates, so their words
# have to come from the same place: the language the shell is set to and the
# same JSON files, keyed by the English text, with the English text as the
# fallback. A script that says t "Some message" reaches translators once the
# message is in translations/en_US.json, which is what tr-keys.py checks.
#
# Sourced, never executed. tr_init [user] picks the language the way
# Translation.qml does: the shell's language.ui setting when it names one,
# the environment's locale otherwise. Called before a script forces its own
# locale for tool output, since that is not the user's language.
#
#   t  "English text"            prints the translation, or the text
#   tf "Installed %s files" 12   the same through printf
#
# The files are read for the user the script runs for: under sudo that is
# the caller, whose home holds the shell's copy and the generated ones.

MAINSTREAM_TR_LANG="en_US"
MAINSTREAM_TR_FILES=()

tr_init() {
    local user="${1:-${SUDO_USER:-$USER}}" home lang f
    home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
    [ -n "$home" ] || home="$HOME"

    lang="$(jq -r '.language.ui // "auto"' "$home/.config/illogical-impulse/config.json" 2>/dev/null || true)"
    if [ -z "$lang" ] || [ "$lang" = auto ] || [ "$lang" = null ]; then
        lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-en_US}}}"
        lang="${lang%%.*}"
        lang="${lang%%@*}"
    fi
    case "$lang" in C|POSIX|"") lang=en_US ;; esac
    MAINSTREAM_TR_LANG="$lang"

    MAINSTREAM_TR_FILES=()
    for f in "$home/.config/quickshell/ii/translations/$lang.json" \
             "$home/.config/illogical-impulse/translations/$lang.json"; do
        [ -r "$f" ] && MAINSTREAM_TR_FILES+=("$f")
    done
    return 0
}

t() {
    local key="$1" f v
    for f in "${MAINSTREAM_TR_FILES[@]}"; do
        v="$(jq -r --arg k "$key" 'if has($k) then .[$k] else empty end' "$f" 2>/dev/null)" || v=""
        if [ -n "$v" ]; then
            # A translation ending in /*keep*/ is one the translator marked as final.
            v="${v%/\*keep\*/}"
            printf '%s' "${v%"${v##*[![:space:]]}"}"
            return 0
        fi
    done
    printf '%s' "$key"
}

tf() {
    local fmt
    fmt="$(t "$1")"
    shift
    # shellcheck disable=SC2059
    printf -- "$fmt" "$@"
}
