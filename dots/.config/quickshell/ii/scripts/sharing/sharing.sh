#!/usr/bin/env bash
# sharing.sh: the folders this account shares on the network.
#
# A shared folder is a Samba "usershare": a small file in the usershare
# directory that `net usershare` writes as the user, so sharing one needs no
# password. Everything that does need one (installing Samba, the account's
# sharing password, which networks are trusted) belongs to the root helper;
# this script only reads the state that helper leaves behind.
#
#   status                         everything the Sharing page shows
#   add <path> view|edit           share a folder; prints the name it got
#   remove <path|name>             stop sharing a folder
#   access <path|name> view|edit   change what others may do in it
#   gen-password                   a new sharing password
#   info <path>                    whether one folder is shared, for Files
#
# Every verb prints one JSON object. A failure exits 1 and prints
# {"error":"<code>"}.
#
# SHARING_NET_ARGS goes in front of every net subcommand (for example
# "-s /path/smb.conf") and SHARING_USERSHARE_DIR stands in for the usershare
# directory, so all of this can run against a scratch config.
set -uo pipefail
shopt -s extglob

# The output of nmcli and net is parsed below, so it has to be the untranslated
# English, and UTF-8 keeps network and folder names intact on the way through.
export LC_ALL=C.UTF-8

HELPER=/usr/lib/mainstream/file-sharing
SAMBA_ETC=/etc/samba
SMB_CONF=$SAMBA_ETC/smb.conf
MARKER='# Managed by Mainstream Settings > Sharing'
STATE_DIR=/var/lib/mainstream/sharing
USERSHARE_DIR=${SHARING_USERSHARE_DIR:-/var/lib/samba/usershares}
TRUSTED_ZONE=MainstreamHome
read -ra NET_ARGS <<<"${SHARING_NET_ARGS:-}"
ME=$(id -un)

fail() {
    printf '{"error":"%s"}\n' "$1"
    exit 1
}

net_() {
    net "${NET_ARGS[@]}" "$@"
}

# Without Samba there is nothing to list or add to. A config handed in through
# SHARING_NET_ARGS stands in for the system one.
samba_ready() {
    command -v net >/dev/null 2>&1 || return 1
    [ ${#NET_ARGS[@]} -gt 0 ] || [ -f "$SMB_CONF" ]
}

# The usershare directory belongs to root and the sambashare group. The helper
# also gives the account an ACL entry, so a session that started before the
# group was added can share right away; test -w honors that entry.
can_share() {
    [ -d "$USERSHARE_DIR" ] && [ -w "$USERSHARE_DIR" ] && [ -x "$USERSHARE_DIR" ]
}

read_state() {
    local s=""
    { read -r s <"$STATE_DIR/state"; } 2>/dev/null
    case $s in
        on|off) STATE=$s ;;
        *) STATE=unset ;;
    esac
}

has_account() {
    [ -e "$STATE_DIR/users/$ME" ]
}

# A setup goes on as root after the Settings window that started it closes,
# and a page opened meanwhile has to show it rather than a switch that would
# start a second one. The helper's lock would also catch the network hook,
# which holds it for a moment whenever a network comes or goes, so this looks
# for the helper itself. A pkexec still waiting on its password prompt does
# not count; once allowed, the helper runs under bash.
setup_running() {
    pgrep -u 0 -f "^[^ ]*bash $HELPER (enable|account)( |\$)" >/dev/null 2>&1
}

host_name() {
    local h=""
    { read -r h </proc/sys/kernel/hostname; } 2>/dev/null || h=${HOSTNAME:-}
    printf '%s' "$h"
}

# "Everyone" by name only resolves while smbd is running; the SID behind it
# works whether or not it is.
acl_for() {
    case $1 in
        view) ACL=S-1-1-0:R ;;
        edit) ACL=S-1-1-0:F ;;
        *) fail usage ;;
    esac
}

# The account's own shares. `net usershare info` lists the shares whose files
# this account owns and whose folders are there, one block each:
#   [name]
#   path=/abs/path
#   comment=
#   usershare_acl=S-1-1-0:R,
#   guest_ok=n
# A share whose folder was deleted, moved or is on an unplugged drive drops out
# of that list, yet its file stays and the share is served again as soon as a
# folder turns up at that path. Those are read from the files themselves and
# marked missing, so the page can show them and they can still be removed.
load_shares() {
    SH_NAME=() SH_PATH=() SH_COMMENT=() SH_ACCESS=() SH_MISSING=()
    samba_ready || return 0
    local line
    while IFS= read -r line; do
        if [[ $line == \[*\] ]]; then
            SH_NAME+=("${line:1:${#line}-2}")
            SH_PATH+=("")
            SH_COMMENT+=("")
            SH_ACCESS+=(view)
            SH_MISSING+=(false)
            continue
        fi
        [ ${#SH_NAME[@]} -gt 0 ] || continue
        case $line in
            path=*) SH_PATH[-1]=${line#path=} ;;
            comment=*) SH_COMMENT[-1]=${line#comment=} ;;
            usershare_acl=*) edit_acl "${line#usershare_acl=}" && SH_ACCESS[-1]=edit ;;
        esac
    done < <(net_ usershare info 2>/dev/null)

    local f n i first name path comment access
    for f in "$USERSHARE_DIR"/*; do
        # Samba reads only regular files, and skips the temporary ones net
        # writes a share to first, whose names start with a colon.
        [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] && [ -r "$f" ] || continue
        n=${f##*/}
        [[ $n == :* ]] && continue
        for i in "${!SH_NAME[@]}"; do
            [ "${SH_NAME[i],,}" = "$n" ] && continue 2
        done
        first="" name="" path="" comment="" access=view
        { IFS= read -r first <"$f"; } 2>/dev/null
        [[ $first == "#VERSION "* ]] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            case $line in
                sharename=*) name=${line#sharename=} ;;
                path=*) path=${line#path=} ;;
                comment=*) comment=${line#comment=} ;;
                usershare_acl=*) edit_acl "${line#usershare_acl=}" && access=edit ;;
            esac
        done <"$f"
        [[ $path == /* ]] || continue
        # The file is named after the share in lower case, which is also the
        # name net deletes it by.
        [ "${name,,}" = "$n" ] || name=$n
        SH_NAME+=("$name")
        SH_PATH+=("$path")
        SH_COMMENT+=("$comment")
        SH_ACCESS+=("$access")
        SH_MISSING+=(true)
    done
}

# Any entry that may change files makes the share "edit", so a share made
# somewhere else never looks safer than it is.
edit_acl() {
    [[ $1, == *:[Ff],* ]]
}

# Finds one of the account's shares by folder or by name and leaves its index
# in FOUND.
find_share() {
    local arg=$1 want="" gone=false i
    FOUND=-1
    if [[ $arg != */* ]]; then
        for i in "${!SH_NAME[@]}"; do
            if [ "${SH_NAME[i],,}" = "${arg,,}" ]; then
                FOUND=$i
                return 0
            fi
        done
        return 1
    fi
    IFS= read -r -d '' want < <(realpath -ez -- "$arg" 2>/dev/null)
    # A folder that is not there can only belong to a missing share, which is
    # still found by the path it was shared at so that it can be removed.
    if [ -z "$want" ]; then
        IFS= read -r -d '' want < <(realpath -mz -- "$arg" 2>/dev/null)
        [ -n "$want" ] || return 1
        gone=true
    fi
    for i in "${!SH_PATH[@]}"; do
        [ "$gone" = true ] && [ "${SH_MISSING[i]}" = false ] && continue
        if [ "${SH_PATH[i]}" = "$want" ]; then
            FOUND=$i
            return 0
        fi
    done
    # A share made somewhere else may name its folder through a symlink.
    [ ${#SH_PATH[@]} -gt 0 ] || return 1
    local real=()
    mapfile -d '' real < <(realpath -mz -- "${SH_PATH[@]}" 2>/dev/null)
    [ ${#real[@]} -eq ${#SH_PATH[@]} ] || return 1
    for i in "${!real[@]}"; do
        [ "$gone" = true ] && [ "${SH_MISSING[i]}" = false ] && continue
        if [ "${real[i]}" = "$want" ]; then
            FOUND=$i
            return 0
        fi
    done
    return 1
}

# The home folder as the account database has it and as HOME says, which are
# the same folder unless something overrode HOME.
home_dirs() {
    HOMES=()
    local h r
    for h in "$(getent passwd "$UID" | cut -d: -f6)" "${HOME:-}"; do
        [ -n "$h" ] || continue
        r=""
        IFS= read -r -d '' r < <(realpath -ez -- "$h" 2>/dev/null)
        [ -n "$r" ] || continue
        [ ${#HOMES[@]} -gt 0 ] && [ "${HOMES[0]}" = "$r" ] && continue
        HOMES+=("$r")
    done
}

# Share names end up in addresses people type, so they are kept to letters,
# digits, dots, dashes and underscores. Accents are spelled out first so that
# "Música" becomes "Musica" rather than "M-sica". Windows drops a trailing dot
# from an address it opens, so the ends are trimmed of dots as well as dashes.
pick_name() {
    local base=${1##*/} n name suffix i=2
    base=$(printf '%s' "$base" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null) || base=${1##*/}
    base=${base//[^A-Za-z0-9._-]/-}
    base=${base//+(-)/-}
    base=${base##+([-.])}
    base=${base:0:60}
    base=${base%%+([-.])}
    [ -n "$base" ] || base=Folder

    # Share names are not case sensitive. A name matching an account would
    # read like that person's home folder, and the others are names Samba
    # keeps for itself.
    local -A taken=([global]=1 [homes]=1 [printers]=1 ['print$']=1 ['ipc$']=1)
    while IFS=: read -r n _; do
        [ -n "$n" ] && taken[${n,,}]=1
    done < <(getent passwd)
    while IFS= read -r n; do
        [ -n "$n" ] && taken[${n,,}]=1
    done < <(net_ usershare list --long 2>/dev/null)
    # net leaves out a share whose folder is missing, such as one on a drive
    # that is unplugged, but its file is still there under the lowercased name.
    # Reusing that name would overwrite it, and the share would be gone for
    # good when the drive comes back.
    local f
    for f in "$USERSHARE_DIR"/*; do
        [ -f "$f" ] || continue
        n=${f##*/}
        taken[${n,,}]=1
    done

    name=$base
    while [ -n "${taken[${name,,}]:-}" ]; do
        suffix=-$i
        name=${base:0:60-${#suffix}}
        name=${name%%+([-.])}$suffix
        i=$((i + 1))
    done
    SHARE_NAME=$name
}

cmd_add() {
    [ $# -eq 2 ] || fail usage
    acl_for "$2"
    local path="" h rel name
    IFS= read -r -d '' path < <(realpath -ez -- "$1" 2>/dev/null)
    if [ -z "$path" ] || [ ! -d "$path" ]; then
        fail not-dir
    fi

    # The home folder holds keys and settings, and a folder above it would
    # share the home folder along with everything else.
    home_dirs
    [ ${#HOMES[@]} -gt 0 ] || fail failed
    [ "$path" = / ] && fail home
    for h in "${HOMES[@]}"; do
        if [ "$path" = "$h" ] || [[ $h == "$path"/* ]]; then
            fail home
        fi
    done
    rel=$path
    for h in "${HOMES[@]}"; do
        if [[ $path == "$h"/* ]]; then
            rel=${path#"$h"}
            break
        fi
    done
    [[ $rel == */.* ]] && fail hidden
    [ "$(stat -c %u -- "$path" 2>/dev/null)" = "$UID" ] || fail not-owner

    # net writes the path into the usershare file as one line, so a newline in
    # it would add lines of its own. Samba cannot serve a path that is not
    # UTF-8 either.
    [[ $path == *[[:cntrl:]]* ]] && fail failed
    printf '%s' "$path" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || fail failed
    # smbd fills in %u, %S, %$(VAR) and the like in a share's path each time
    # someone connects, so the folder served would not be this one.
    [[ $path == *%[A-Za-z\$]* ]] && fail percent

    if ! samba_ready || ! can_share; then
        fail no-access
    fi

    # A folder that is already shared stays as it is, so picking it again
    # never quietly takes away what others may do in it; that is the access
    # verb's job. One Samba stopped serving is shared again under its name.
    load_shares
    if find_share "$path"; then
        if [ "${SH_MISSING[FOUND]}" = false ]; then
            jq -nc --arg name "${SH_NAME[FOUND]}" --arg path "${SH_PATH[FOUND]}" \
                --arg access "${SH_ACCESS[FOUND]}" '{name: $name, path: $path, access: $access}'
            exit 0
        fi
        name=${SH_NAME[FOUND]}
    else
        pick_name "$path"
        name=$SHARE_NAME
    fi
    net_ usershare add -- "$name" "$path" "" "$ACL" guest_ok=n >/dev/null || fail failed
    jq -nc --arg name "$name" --arg path "$path" --arg access "$2" \
        '{name: $name, path: $path, access: $access}'
}

cmd_remove() {
    if [ $# -ne 1 ] || [ -z "$1" ]; then
        fail usage
    fi
    samba_ready || fail no-access
    load_shares
    find_share "$1" || fail not-shared
    can_share || fail no-access
    net_ usershare delete -- "${SH_NAME[FOUND]}" >/dev/null || fail failed
    printf '{"ok":true}\n'
}

cmd_access() {
    if [ $# -ne 2 ] || [ -z "$1" ]; then
        fail usage
    fi
    acl_for "$2"
    samba_ready || fail no-access
    load_shares
    find_share "$1" || fail not-shared
    local name=${SH_NAME[FOUND]} path=${SH_PATH[FOUND]}
    [ -d "$path" ] || fail not-dir
    can_share || fail no-access
    net_ usershare add -- "$name" "$path" "${SH_COMMENT[FOUND]}" "$ACL" guest_ok=n >/dev/null ||
        fail failed
    jq -nc --arg name "$name" --arg path "$path" --arg access "$2" \
        '{ok: true, name: $name, path: $path, access: $access}'
}

# Twelve characters from 31 that cannot be mistaken for one another, about 59
# bits. A byte of 248 or more is thrown away, since 248 is the largest multiple
# of 31 a byte can hold and keeping the rest would favor the first letters.
cmd_gen_password() {
    local alphabet=abcdefghjkmnpqrstuvwxyz23456789 pw="" b
    local -a bytes
    while [ ${#pw} -lt 12 ]; do
        read -ra bytes < <(od -An -v -tu1 -w32 -N32 /dev/urandom)
        [ ${#bytes[@]} -gt 0 ] || fail failed
        for b in "${bytes[@]}"; do
            [ "$b" -lt 248 ] || continue
            pw+=${alphabet:b%31:1}
            [ ${#pw} -lt 12 ] || break
        done
    done
    printf '{"password":"%s-%s-%s"}\n' "${pw:0:4}" "${pw:4:4}" "${pw:8:4}"
}

cmd_info() {
    if [ $# -ne 1 ] || [ -z "$1" ]; then
        fail usage
    fi
    local shared=false name="" access="" account=false
    load_shares
    if find_share "$1" && [ "${SH_MISSING[FOUND]}" = false ]; then
        shared=true
        name=${SH_NAME[FOUND]}
        access=${SH_ACCESS[FOUND]}
    fi
    read_state
    has_account && account=true
    jq -nc --argjson shared "$shared" --arg name "$name" --arg access "$access" \
        --arg state "$STATE" --argjson account "$account" --arg hostname "$(host_name)" \
        '{shared: $shared, name: $name, access: $access, state: $state,
          account: $account, hostname: $hostname}'
}

# The saved Wi-Fi and wired profiles worth showing, and which one carries this
# computer's traffic, in three nmcli calls however many profiles are saved.
# Leaves CURRENT, ADDRS and CONN_FIELDS (seven fields per profile).
network_info() {
    CURRENT="" ADDRS=() CONN_FIELDS=()
    command -v nmcli >/dev/null 2>&1 || return 0

    local uuid type active line i
    local -a uuids=() types=() actives=() lookup=()
    while IFS=: read -r uuid type active; do
        case $type in
            802-3-ethernet) type=ethernet ;;
            802-11-wireless) type=wifi ;;
            *) continue ;;
        esac
        uuids+=("$uuid")
        types+=("$type")
        actives+=("$active")
        lookup+=(uuid "$uuid")
    done < <(nmcli -g UUID,TYPE,ACTIVE connection show 2>/dev/null)
    [ ${#uuids[@]} -gt 0 ] || return 0

    # nmcli prints the profiles in the order they were asked for. The name
    # comes last and is the only field that can hold a newline, so it runs
    # until the next profile's uuid line.
    local -a zones=() perms=() modes=() keymgmt=() names=()
    local idx=-1 in_name=0 nl=$'\n'
    while IFS= read -r line; do
        if (( idx + 1 < ${#uuids[@]} )) && [ "$line" = "connection.uuid:${uuids[idx + 1]}" ]; then
            idx=$((idx + 1))
            in_name=0
            zones[idx]="" perms[idx]="" modes[idx]="" keymgmt[idx]="" names[idx]=""
            continue
        fi
        (( idx >= 0 )) || continue
        if (( in_name )); then
            names[idx]+=$nl$line
            continue
        fi
        case $line in
            connection.zone:*) zones[idx]=${line#*:} ;;
            connection.permissions:*) perms[idx]=${line#*:} ;;
            802-11-wireless.mode:*) modes[idx]=${line#*:} ;;
            802-11-wireless-security.key-mgmt:*) keymgmt[idx]=${line#*:} ;;
            connection.id:*)
                names[idx]=${line#*:}
                in_name=1
                ;;
        esac
    done < <(nmcli --escape no -t \
        -f connection.uuid,connection.zone,connection.permissions,802-11-wireless.mode,802-11-wireless-security.key-mgmt,connection.id \
        connection show "${lookup[@]}" 2>/dev/null)

    # A hotspot this computer runs is not a network it joins, so it is never
    # offered and never counts as the one carrying traffic.
    local -A usable=()
    for i in "${!uuids[@]}"; do
        [ -n "${names[i]+x}" ] || continue
        names[i]=${names[i]%%+("$nl")}
        case ${modes[i]} in
            ap|adhoc|mesh) continue ;;
        esac
        usable[${uuids[i]}]=1
    done

    # The profile carrying traffic is the one whose default route wins. A VPN's
    # default route is left out, which leaves the Wi-Fi or wired profile under
    # it, since that one keeps its own route at a higher metric.
    local dev_uuid="" val metric best4="" best4_uuid="" best6="" best6_uuid="" first_addr=""
    local -A addrs=()
    while IFS= read -r line; do
        case $line in
            GENERAL.DEVICE:*) dev_uuid="" ;;
            GENERAL.CON-UUID:*) dev_uuid=${line#*:} ;;
        esac
        if [ -z "$dev_uuid" ] || [ -z "${usable[$dev_uuid]:-}" ]; then
            continue
        fi
        val=${line#*:}
        case $line in
            IP4.ADDRESS*)
                addrs[$dev_uuid]+="${val%/*} "
                [ -n "$first_addr" ] || first_addr=$dev_uuid
                ;;
            IP4.ROUTE*|IP6.ROUTE*)
                [[ $val == "dst = 0.0.0.0/0,"* || $val == "dst = ::/0,"* ]] || continue
                if [[ $val =~ table=([0-9]+) ]] && [ "${BASH_REMATCH[1]}" != 254 ]; then
                    continue
                fi
                metric=0
                [[ $val =~ mt\ =\ ([0-9]+) ]] && metric=${BASH_REMATCH[1]}
                if [[ $line == IP4* ]]; then
                    if [ -z "$best4" ] || [ "$metric" -lt "$best4" ]; then
                        best4=$metric best4_uuid=$dev_uuid
                    fi
                elif [ -z "$best6" ] || [ "$metric" -lt "$best6" ]; then
                    best6=$metric best6_uuid=$dev_uuid
                fi
                ;;
        esac
    done < <(nmcli --escape no -t -f GENERAL.DEVICE,GENERAL.CON-UUID,IP4.ADDRESS,IP4.ROUTE,IP6.ROUTE \
        device show 2>/dev/null)

    # A home network without a router has no default route at all; the
    # connected profile with an address is the best guess there.
    CURRENT=${best4_uuid:-${best6_uuid:-$first_addr}}
    [ -n "$CURRENT" ] && read -ra ADDRS <<<"${addrs[$CURRENT]:-}"

    # Anyone in an active session can put a profile of their own in any zone
    # without a password, so a network counts as trusted only while the
    # helper's record of that trust is there as well. A profile in the zone
    # without one is offered as untrusted, and trusting it writes the record.
    local act trusted eligible reason rec
    for i in "${!uuids[@]}"; do
        [ -n "${usable[${uuids[i]}]:-}" ] || continue
        act=false trusted=false
        [ "${actives[i]}" = yes ] && act=true
        rec=$STATE_DIR/trusted/${uuids[i],,}
        if [ "${zones[i]}" = "$TRUSTED_ZONE" ] && [ -f "$rec" ] && [ ! -L "$rec" ]; then
            trusted=true
        fi
        [ "$act" = true ] || [ "$trusted" = true ] || continue
        eligible=true reason=""
        # NetworkManager leaves the security setting off an open profile, and
        # OWE takes no password either. key-mgmt "none" is WEP, which does
        # have a password but one that is easy to break.
        if [ "${types[i]}" = wifi ]; then
            case ${keymgmt[i]} in
                ''|owe) eligible=false reason=open ;;
                none) eligible=false reason=weak ;;
            esac
        fi
        # The helper refuses these too, but only after the password prompt.
        # A profile kept for one account can be pointed at another network by
        # that account alone, and a zone somebody picked by hand would be
        # lost when trust is taken back.
        if [ "$eligible" = true ]; then
            if [ -n "${perms[i]}" ]; then
                eligible=false reason=private
            elif [ -n "${zones[i]}" ] && [ "${zones[i]}" != "$TRUSTED_ZONE" ]; then
                eligible=false reason=zone
            fi
        fi
        CONN_FIELDS+=("${uuids[i]}" "${names[i]}" "${types[i]}" "$act" "$trusted" "$eligible" "$reason")
    done
}

cmd_status() {
    [ $# -eq 0 ] || fail usage
    local helper=false installed=false config=none first="" running=false
    local account=false canshare=false busy=false firewall=false i
    [ -x "$HELPER" ] && helper=true
    [ -e /usr/bin/smbd ] && installed=true
    # The same rule the helper goes by: a config reached through a symlink is
    # somebody's own setup, which the helper leaves alone, so the page must not
    # offer to manage it either.
    if [ -L "$SAMBA_ETC" ] || [ -L "$SMB_CONF" ]; then
        config=foreign
    elif [ -e "$SMB_CONF" ]; then
        config=foreign
        [ -f "$SMB_CONF" ] && { IFS= read -r first <"$SMB_CONF"; } 2>/dev/null
        [ "$first" = "$MARKER" ] && config=managed
    fi
    systemctl is-active --quiet smb.service 2>/dev/null && running=true
    # The helper will not turn sharing on or trust a network without it, so
    # the page says so before asking for a password.
    systemctl is-active --quiet firewalld.service 2>/dev/null && firewall=true
    read_state
    has_account && account=true
    setup_running && busy=true
    can_share && canshare=true
    network_info
    load_shares
    local -a share_fields=()
    for i in "${!SH_NAME[@]}"; do
        share_fields+=("${SH_NAME[i]}" "${SH_PATH[i]}" "${SH_ACCESS[i]}" "${SH_MISSING[i]}")
    done

    jq -nc \
        --argjson helper "$helper" --argjson installed "$installed" --arg config "$config" \
        --arg state "$STATE" --argjson busy "$busy" --argjson running "$running" \
        --argjson firewall "$firewall" --argjson account "$account" \
        --argjson canShare "$canshare" --arg user "$ME" \
        --arg hostname "$(host_name)" --arg current "$CURRENT" \
        --argjson na "${#ADDRS[@]}" --argjson nc "${#CONN_FIELDS[@]}" \
        '$ARGS.positional as $p
         | $p[$na:$na + $nc] as $c
         | $p[$na + $nc:] as $s
         | {helper: $helper, installed: $installed, config: $config, state: $state,
            busy: $busy, running: $running, firewall: $firewall, account: $account,
            canShare: $canShare, user: $user, hostname: $hostname, addresses: $p[:$na],
            current: $current,
            connections: [range(0; $c | length; 7) as $i
                | {uuid: $c[$i], name: $c[$i + 1], type: $c[$i + 2],
                   active: ($c[$i + 3] == "true"), trusted: ($c[$i + 4] == "true"),
                   eligible: ($c[$i + 5] == "true"), reason: $c[$i + 6]}],
            shares: [range(0; $s | length; 4) as $i
                | {name: $s[$i], path: $s[$i + 1], access: $s[$i + 2],
                   missing: ($s[$i + 3] == "true")}]}' \
        --args -- "${ADDRS[@]}" "${CONN_FIELDS[@]}" "${share_fields[@]}"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
    status) cmd_status "$@" ;;
    add) cmd_add "$@" ;;
    remove) cmd_remove "$@" ;;
    access) cmd_access "$@" ;;
    gen-password)
        [ $# -eq 0 ] || fail usage
        cmd_gen_password
        ;;
    info) cmd_info "$@" ;;
    *) fail usage ;;
esac
