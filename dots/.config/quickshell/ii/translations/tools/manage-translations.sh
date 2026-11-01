#!/usr/bin/env bash
# Read-only reports by default. Only sync --apply can add catalog keys.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="status"
COMMAND_SEEN=false
ARGS=()

show_help() {
    cat <<'HELP'
Usage: manage-translations.sh [command] [options]

Commands:
  status       Read-only source/catalog coverage (default)
  check        Structural catalog validation
  extract      Print extracted QML/JS, Files extension and shell keys as JSON
  update       Preview missing-key additions; same as sync
  sync         Preview additions from en_US; --apply explicitly writes them
  clean        Read-only coverage report; never deletes keys

Options:
  -l, --lang CODE       Select an existing locale
  -t, --trans-dir DIR   Override the catalog directory
  -s, --source-dir DIR  Override the QML/JS source directory
  --scripts-dir DIR    Override script roots; repeat for multiple directories
  --extensions-dir DIR Override the Files extension directory
  --json               Machine-readable output
  --apply              Only valid with sync/update; adds keys, never removes them
  -h, --help           Show this help

Examples:
  manage-translations.sh
  manage-translations.sh check --json
  manage-translations.sh status -l ko_KR
  manage-translations.sh sync --apply
HELP
}

while (($#)); do
    case "$1" in
        status|check|extract|update|sync|clean)
            if $COMMAND_SEEN; then
                echo 'Error: specify only one command' >&2
                exit 2
            fi
            COMMAND="$1"; COMMAND_SEEN=true; shift ;;
        -l|--lang|--language|-t|--trans-dir|--translations-dir|-s|--source-dir|--scripts-dir|--extensions-dir)
            if (($# < 2)) || [[ "$2" == -* || -z "$2" ]]; then
                echo "Error: $1 requires a value" >&2
                exit 2
            fi
            case "$1" in
                -l|--lang|--language) ARGS+=(--language "$2") ;;
                -t|--trans-dir|--translations-dir) ARGS+=(--translations-dir "$2") ;;
                *) ARGS+=("$1" "$2") ;;
            esac
            shift 2 ;;
        --json|--apply) ARGS+=("$1"); shift ;;
        -h|--help) show_help; exit 0 ;;
        -y|--yes) echo 'Error: --yes is retired; use sync --apply for explicit additions only' >&2; exit 2 ;;
        *) echo "Error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$COMMAND" in
    status|clean) exec python3 "$SCRIPT_DIR/translation-manager.py" "${ARGS[@]}" ;;
    extract) exec python3 "$SCRIPT_DIR/translation-manager.py" --extract-only "${ARGS[@]}" ;;
    update|sync) exec python3 "$SCRIPT_DIR/translation-manager.py" --sync "${ARGS[@]}" ;;
    check) exec python3 "$SCRIPT_DIR/catalog-qa.py" "${ARGS[@]}" ;;
esac
