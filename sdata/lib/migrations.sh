# One-time repairs to a machine's own files, shared by the install and the
# update paths.
#
# Both have to run these. A migration that lives in only one of them reaches
# only the people who take that path, and the ones who update are exactly the
# ones carrying the old state it exists to repair.
#
# Each is safe to run against a machine that does not need it, and none deletes
# anything the user could have written.

# Plugin machinery moved out of custom/general.lua and into the shipped
# hyprland/plugins.lua. custom/ is written once at install and never again, so
# anything left in the old copy goes on loading the plugins and registering its
# own config.reloaded handler beside the shipped one: the plugins are configured
# twice per reload, by two versions of the same code, and the bar ends up with
# two of every button.
#
# Only a file that still carries that machinery is touched, and it is moved
# aside rather than deleted, because it is the user's file and anything they
# added to it is theirs.
migrate_custom_general_plugin_block() {
    local repo_root="${1:-$REPO_ROOT}"
    local target="$HOME/.config/hypr/custom/general.lua"
    local shipped="${repo_root}/dots/.config/hypr/custom/general.lua"

    [[ -f "$target" ]] || return 0
    grep -q 'applyPluginConfig' "$target" 2>/dev/null || return 0
    [[ -f "$shipped" ]] || return 0

    if mv "$target" "$target.pre-plugins-move"; then
        install -Dm644 "$shipped" "$target"
        echo "Plugin settings now ship in hyprland/plugins.lua; your old custom/general.lua was kept as general.lua.pre-plugins-move"
    else
        echo "Could not move $target aside; plugins may be configured twice until it is" >&2
    fi
}
