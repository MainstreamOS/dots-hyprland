#!/usr/bin/env bash

repair_venv_paths() {
    local venv_path="$1"
    [[ -d "$venv_path" ]] || return 0

    # uv console scripts may put the venv Python path on line 2. Older
    # pre-baked venvs also carried the absolute ISO build-tree path.
    find "$venv_path/bin" -type f -exec \
        sed -i -E "s|/[^\"'[:space:]]*\\.local/state/quickshell/\\.venv|$venv_path|g" {} + 2>/dev/null || true
    find "$venv_path/bin" -maxdepth 1 -type f -exec chmod 755 {} + 2>/dev/null || true
    [[ -f "$venv_path/pyvenv.cfg" ]] && \
        sed -i -E "s|/[^\"'[:space:]]*\\.local/state/quickshell/\\.venv|$venv_path|g" "$venv_path/pyvenv.cfg" 2>/dev/null || true
}
