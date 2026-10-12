#!/usr/bin/env bash
# Review the changes to the given absolute paths, grouped by repository.
# Repositories are only read: git never writes the index, runs a hook, reaches
# a remote or runs any program the repository configures (fsmonitor, pager,
# external diff, textconv, filter drivers), and a repository's submodules are
# not inspected.

# Sets the array named $1 to git's environment for -C REPO, or with no REPO for
# diffs outside a repository. Every filter driver and hook the config defines
# (includes too) is turned off by name; an unreadable config leaves it empty.
git_context() {
    local -n context_env=$1
    shift
    local keys=() env=("${base_env[@]}") n key k name rc
    local -A seen=()
    context_env=()
    mapfile -d '' keys < <(git "$@" config -z --name-only --get-regexp '^(filter|hook)\.' 2>/dev/null; printf '%s' "$?")
    rc=${keys[-1]}
    unset 'keys[-1]'
    [ "$rc" -le 1 ] || return "$rc"

    n=${GIT_CONFIG_COUNT:-0}
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    for key in "${keys[@]}"; do
        name=${key#*.}
        [[ "$name" == *.* ]] || continue
        name=${key%.*}
        [ -n "${seen["$name"]}" ] && continue
        seen["$name"]=1
        case "$name" in
            filter.*)
                for k in clean smudge process; do
                    env+=("GIT_CONFIG_KEY_$n=$name.$k" "GIT_CONFIG_VALUE_$n=")
                    n=$((n + 1))
                done
                env+=("GIT_CONFIG_KEY_$n=$name.required" "GIT_CONFIG_VALUE_$n=false")
                ;;
            *) env+=("GIT_CONFIG_KEY_$n=$name.enabled" "GIT_CONFIG_VALUE_$n=false") ;;
        esac
        n=$((n + 1))
    done
    context_env=("${env[@]}" GIT_CONFIG_COUNT="$n")
}

# No lazy fetch and no transport at all, so no credential helper, ssh command
# or remote helper can start; optional locks off keeps status from writing.
# Literal pathspecs keep a name like notes[1].md from matching notes1.md.
base_env=(GIT_NO_LAZY_FETCH=1 GIT_ALLOW_PROTOCOL= GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1)

# Runs git in the context whose environment the array named $1 holds.
# diff.autoRefreshIndex off keeps diff from writing the index too.
safe_git() {
    local -n git_env=$1
    shift
    [ ${#git_env[@]} -gt 0 ] || return 1
    env "${git_env[@]}" git -c core.fsmonitor= -c core.hooksPath=/dev/null -c core.pager=cat \
        -c diff.external= -c diff.autoRefreshIndex=false --no-pager "$@"
}

show_repo_diff() {
    local repo="$1"
    shift
    local files=("$@")
    local repo_env
    git_context repo_env -C "$repo"
    echo -e "\033[1;36m========================================\033[0m"
    printf '\033[1;36mRepository: %s\033[0m\n' "${repo//[[:cntrl:]]/?}"
    echo -e "\033[1;36m========================================\033[0m\n"

    echo -e "\033[1;33mStatus:\033[0m"
    safe_git repo_env -C "$repo" status -s --ignore-submodules=dirty -- "${files[@]}"
    echo ""

    local staged
    staged=$(safe_git repo_env -C "$repo" diff --cached --no-ext-diff --no-textconv --ignore-submodules=dirty --submodule=short --color=always -- "${files[@]}" 2>/dev/null || true)
    if [ -n "$staged" ]; then
        echo -e "\033[1;33mStaged Changes:\033[0m"
        echo "$staged"
        echo ""
    fi

    local unstaged
    unstaged=$(safe_git repo_env -C "$repo" diff --no-ext-diff --no-textconv --ignore-submodules=dirty --submodule=short --color=always -- "${files[@]}" 2>/dev/null || true)
    if [ -n "$unstaged" ]; then
        echo -e "\033[1;32mUnstaged Changes:\033[0m"
        echo "$unstaged"
        echo ""
    fi

    local untracked=() uf
    mapfile -d '' untracked < <(safe_git repo_env -C "$repo" ls-files -z --others --exclude-standard -- "${files[@]}" 2>/dev/null)
    if [ ${#untracked[@]} -gt 0 ]; then
        echo -e "\033[1;34mUntracked New Files:\033[0m"
        for uf in "${untracked[@]}"; do
            [ -z "$uf" ] && continue
            # Names are raw with -z, so control characters must not reach the terminal.
            printf '\033[0;36m+++ %s (New File)\033[0m\n' "${uf//[[:cntrl:]]/?}"
            safe_git noindex_env diff --no-index --no-ext-diff --no-textconv --color=always -- /dev/null "$repo/$uf" 2>/dev/null || true
            echo ""
        done
    fi
}

show_standalone_file() {
    local sf="$1"
    echo -e "\033[1;35m========================================\033[0m"
    printf '\033[1;35mFile: %s\033[0m\n' "${sf//[[:cntrl:]]/?}"
    echo -e "\033[1;35m========================================\033[0m\n"
    if [ -f "$sf" ]; then
        safe_git noindex_env diff --no-index --no-ext-diff --no-textconv --color=always -- /dev/null "$sf" 2>/dev/null || true
    else
        echo "File not found or removed: $sf"
    fi
    echo ""
}

repos=()
target_repos=()
targets=()
standalone_files=()

for target in "$@"; do
    [[ "$target" == /* ]] || continue
    dir="$target"
    [ -d "$target" ] || dir=$(dirname -- "$target")

    repo=""
    if [ -d "$dir" ]; then
        repo=$(safe_git base_env -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [ -n "$repo" ]; then
        known=0
        for r in "${repos[@]}"; do [ "$r" = "$repo" ] && known=1; done
        [ "$known" -eq 1 ] || repos+=("$repo")
        target_repos+=("$repo")
        targets+=("$target")
    else
        standalone_files+=("$target")
    fi
done

report() {
    local repo files i sf noindex_env
    git_context noindex_env
    for repo in "${repos[@]}"; do
        files=()
        for i in "${!targets[@]}"; do
            [ "${target_repos[$i]}" = "$repo" ] && files+=("${targets[$i]}")
        done
        show_repo_diff "$repo" "${files[@]}"
    done
    for sf in "${standalone_files[@]}"; do
        show_standalone_file "$sf"
    done
}

if [ "${#repos[@]}" -eq 0 ] && [ "${#standalone_files[@]}" -eq 0 ]; then
    echo -e "\033[1;33mNo git repository or changed files to inspect.\033[0m"
elif command -v less >/dev/null 2>&1; then
    report | less -R
else
    report
fi

echo ""
read -rp "Press Enter to exit..."
