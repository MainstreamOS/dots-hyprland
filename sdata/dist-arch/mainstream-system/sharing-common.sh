# Sourced by the Settings > Sharing helper (/usr/lib/mainstream/file-sharing)
# and by its NetworkManager hook (50-mainstream-sharing), so both agree on
# which networks are trusted and on the interfaces wsdd answers on. It sets no
# shell options; each caller keeps its own.

SAMBA_ETC=/etc/samba
SMB_CONF=$SAMBA_ETC/smb.conf
MARKER='# Managed by Mainstream Settings > Sharing'
MAINSTREAM_LIB=/var/lib/mainstream
STATE_DIR=$MAINSTREAM_LIB/sharing
TRUSTED_DIR=$STATE_DIR/trusted
STATE_FILE=$STATE_DIR/state
ZONE=MainstreamHome
SERVICES=(smb.service wsdd.service)
WSDD_ENV=/run/mainstream/sharing/wsdd.env
IPSEC_GUARD=/usr/lib/mainstream/sharing-ipsec.nft
IPSEC_TABLE=mainstream_sharing
LOCK=/run/lock/mainstream-file-sharing.lock

valid_uuid() { [[ $1 =~ ^[0-9a-fA-F-]{36}$ ]]; }

# Only a network that keeps strangers out can be a home network: wired, or
# Wi-Fi that takes a password to join. Open and OWE Wi-Fi let anyone nearby
# on (OWE encrypts, but asks nobody for anything), `none` is WEP or nothing,
# and a hotspot or ad-hoc profile has this computer serving the network
# rather than joining one. The profile also has to belong to the whole
# system: NetworkManager lets an account change a profile kept for it alone
# without a password, which would let it point a trusted profile at any
# network, and only an administrator can change a system one.
eligible() {  # $1 = uuid
    local type mode key perms
    perms=$(nmcli -g connection.permissions connection show uuid "$1" 2>/dev/null) || return 1
    [[ -z $perms ]] || return 1
    type=$(nmcli -g connection.type connection show uuid "$1" 2>/dev/null) || return 1
    case $type in
        802-3-ethernet) return 0 ;;
        802-11-wireless) ;;
        *) return 1 ;;
    esac
    mode=$(nmcli -g 802-11-wireless.mode connection show uuid "$1" 2>/dev/null) || return 1
    case $mode in ''|infrastructure) ;; *) return 1 ;; esac
    key=$(nmcli -g 802-11-wireless-security.key-mgmt connection show uuid "$1" 2>/dev/null) || key=""
    case $key in ''|none|owe) return 1 ;; esac
    return 0
}

zone_of() {  # $1 = uuid
    nmcli -g connection.zone connection show uuid "$1" 2>/dev/null
}

# NetworkManager lets anyone in an active session put a profile of their own
# in any zone, with no password, so the zone alone does not make a network a
# home network. It counts only while the helper's record of the trust is
# there, which takes an administrator's password to write, the profile is
# still in MainstreamHome, and it still passes the checks trust made.
is_home() {  # $1 = uuid
    local rec
    valid_uuid "$1" || return 1
    rec=$TRUSTED_DIR/${1,,}
    [[ -f $rec && ! -L $rec ]] || return 1
    [[ $(zone_of "$1") == "$ZONE" ]] || return 1
    eligible "$1"
}

# The interfaces a connection is up on, one per line; nothing when it is saved
# but not connected.
connection_devices() {  # $1 = uuid
    nmcli -g GENERAL.DEVICES connection show uuid "$1" 2>/dev/null | tr ',' '\n' | sed '/^$/d'
}

# managed, foreign or none. A file the helper did not write, or one reached
# through a symlink, is somebody's own Samba setup and is never touched.
config_kind() {
    local first=""
    if [[ -L $SAMBA_ETC || -L $SMB_CONF ]]; then echo foreign; return; fi
    if [[ ! -e $SMB_CONF ]]; then echo none; return; fi
    if [[ ! -f $SMB_CONF ]]; then echo foreign; return; fi
    IFS= read -r first <"$SMB_CONF"
    if [[ $first == "$MARKER" ]]; then echo managed; else echo foreign; fi
}

# The interfaces of the trusted networks that are up, one per line.
home_devices() {  # $1 = a connection to leave out, or nothing
    local u d uuids=() devs=()
    mapfile -t uuids < <(nmcli -g UUID connection show --active 2>/dev/null)
    for u in "${uuids[@]}"; do
        [[ -n $u && $u != "${1:-}" ]] && is_home "$u" || continue
        mapfile -t devs < <(connection_devices "$u")
        for d in "${devs[@]}"; do
            [[ $d =~ ^[A-Za-z0-9_.-]{1,15}$ ]] && printf '%s\n' "$d"
        done
    done | sort -u
}

# The drop-in only works while systemd has loaded it and the unit passes
# WSDD_PARAMS to wsdd. Without both, wsdd would answer everywhere, so it
# stays stopped.
wsdd_confined() {
    local cmd files re='\$\{?WSDD_PARAMS([^A-Za-z0-9_]|$)'
    cmd=$(systemctl show -P ExecStart wsdd.service 2>/dev/null) || return 1
    files=$(systemctl show -P EnvironmentFiles wsdd.service 2>/dev/null) || return 1
    [[ $cmd =~ $re && $files == *"$WSDD_ENV"* ]]
}
