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

# Brings an existing venv to exactly the packages a requirements file pins,
# which is what the installer's `uv pip install -r` gives a new one. A sync
# rather than an install, so a package the list dropped goes too.
#
# When a release swaps a package for a variant that ships the same files
# (opencv-contrib-python for its -headless build, which both own cv2/),
# removing the old one can take files the new one just wrote. Pins that are
# new since the old list, when one is given, are installed again afterwards.
#
# Like the first-login install, a list whose cffi pin will not install is
# tried again with that pin loosened. It is loosened rather than dropped,
# since a sync removes whatever the list leaves out.
sync_venv_requirements() {
    local venv_path="$1" requirements="$2" old_requirements="${3:-}" uv_bin relaxed rc=0 loosened=0
    local -a added=()
    [[ -x "$venv_path/bin/python" && -f "$requirements" ]] || return 1
    uv_bin=$(command -v uv 2>/dev/null) || uv_bin="$HOME/.local/bin/uv"
    [[ -x "$uv_bin" ]] || return 1
    if ! "$uv_bin" pip sync --python "$venv_path/bin/python" "$requirements"; then
        grep -qE '^cffi==' "$requirements" || return 1
        relaxed=$(mktemp) || return 1
        sed -E 's/^cffi==(.*)$/cffi>=\1/' "$requirements" >"$relaxed"
        "$uv_bin" pip sync --python "$venv_path/bin/python" "$relaxed" || rc=1
        rm -f "$relaxed"
        (( rc == 0 )) || return 1
        loosened=1
    fi
    if [[ -f "$old_requirements" ]] && grep -qE '^[A-Za-z0-9._-]+==' "$old_requirements"; then
        mapfile -t added < <(grep -E '^[A-Za-z0-9._-]+==' "$requirements" \
            | grep -vxF -f <(grep -E '^[A-Za-z0-9._-]+==' "$old_requirements") \
            | { if (( loosened )); then grep -v '^cffi=='; else cat; fi; })
        if (( ${#added[@]} )); then
            "$uv_bin" pip install --python "$venv_path/bin/python" --reinstall --no-deps "${added[@]}" || return 1
        fi
    fi
    repair_venv_paths "$venv_path"
}
