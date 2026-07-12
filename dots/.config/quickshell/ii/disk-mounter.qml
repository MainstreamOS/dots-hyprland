//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// disk-mounter.qml — Mainstream OS utility for mounting drives.
//
// Three tabs, each owns one of the app's three responsibilities:
//
//   Local    — pick an unmounted internal partition, optionally rename
//              and relabel it, mount + add to /etc/fstab.
//   Network  — discover SMB hosts on the LAN via avahi-browse; mount
//              SMB/CIFS or NFS shares with optional saved credentials.
//   Mounted  — list all /mnt/* fstab entries this app's domain manages,
//              with a one-click unmount + fstab-strip action per row.
//
// Privileged work funnels through /usr/local/bin/disk-mounter — a
// subcommand dispatcher installed system-wide (by dots-hyprland's
// `setup_disk_mounter` step, or shipped on the Mainstream OS ISO).
// A matching polkit policy declares allow_active=auth_admin_keep so
// the first prompt caches for ~5 minutes and subsequent operations
// (mount three drives in a row) go through silently. SMB passwords
// are piped to the helper via stdin so they never appear in
// /proc/<pid>/cmdline.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ApplicationWindow {
    id: root
    visible: true
    width: 760
    height: 700
    minimumWidth: 760
    minimumHeight: 700
    maximumWidth: 760
    maximumHeight: 700
    color: Appearance.m3colors.m3background
    title: Translation.tr("Auto Drive Mount")

    // ── Top-level tab state ────────────────────────────────────────
    // Three logical tabs; integer index drives the StackLayout below.
    //   0 = Local, 1 = Network, 2 = Mounted
    property int currentTab: 0

    // ── Local-tab state ────────────────────────────────────────────
    property var drives: []           // storage drives (not on an OS disk)
    property var osDrives: []         // partitions on a disk that has an ESP
    property var unformatted: []      // partitions with no filesystem
    readonly property bool selectedUnformatted: root.unformatted.some(d => d.path === root.selectedPath)
    property bool   mountedPopupShown: false
    property string mountedPopupText: ""
    property var encrypted: []        // LUKS / BitLocker — locked containers
    readonly property bool selectedEncrypted: root.encrypted.some(d => d.path === root.selectedPath)
    property string selectedPath: ""  // /dev/... of the picked drive
    property string selectedExistingLabel: ""
    property string newLabel: ""
    property string unlockPassword: ""
    onSelectedPathChanged: unlockPassword = ""

    // ── Network-tab state ──────────────────────────────────────────
    // discoveredHosts: list of {name, address} entries from avahi-browse.
    // SMB only — there's no equivalent auto-advertise for NFS on most
    // networks, so NFS is manual-entry only.
    property var discoveredHosts: []
    property string netProtocol: "smb"    // "smb" or "nfs"
    property string netHost: ""
    property string netShare: ""          // SMB share name, or NFS export path
    property string netUsername: ""
    property string netPassword: ""
    property bool   netGuest: true        // SMB-only; NFS ignores
    property string netLabel: ""
    property string netMountpoint: ""

    // ── Mounted-tab state ──────────────────────────────────────────
    // mountedDrives: list of {source, mountpoint, fstype, options}
    // entries parsed out of /etc/fstab where mountpoint starts with /mnt/.
    // We exclude /, /boot*, /home, /var*, swap, pseudo-fs etc. via the
    // /mnt/ prefix filter — that's where this app and `mount /mnt/...`
    // by convention put user-data drives.
    property var mountedDrives: []

    // ── Shared status banner ───────────────────────────────────────
    // status / resultKind drive the bottom-of-page banner across all
    // tabs. The 3-second statusClearTimer wipes it after a successful
    // operation so the dialog stays usable for the next action.
    property string status: ""
    property bool   busy: false
    property string resultKind: ""        // "" | "success" | "error"

    // ── Friendly-name helpers (Local tab) ──────────────────────────
    // Mainstream OS aims at Windows / Mac users, so the UI shows
    // "Windows (NTFS)" rather than "ntfs" and suggests human labels.
    function friendlyFstype(fstype) {
        const m = {
            "ext2": "Linux", "ext3": "Linux", "ext4": "Linux",
            "btrfs": "Linux", "xfs": "Linux", "f2fs": "Linux",
            "vfat": "FAT", "fat": "FAT",
            "fat16": "FAT", "fat32": "FAT", "msdos": "FAT",
            "exfat": "exFAT",
            "ntfs": "Windows (NTFS)", "ntfs-3g": "Windows (NTFS)",
            "apfs": "Mac (APFS)",
            "hfs": "Mac (HFS+)", "hfsplus": "Mac (HFS+)",
            "iso9660": "CD/DVD",
            "udf": "DVD/Blu-ray",
            "cifs": "Windows share", "smbfs": "Windows share",
            "nfs": "Linux share", "nfs4": "Linux share",
            // crypto_LUKS surfaces from lsblk on a partition that's been
            // luksFormat'd but isn't currently unlocked. The user-facing
            // label hides the implementation detail.
            "crypto_luks": "Encrypted",
            "bitlocker": "Encrypted (BitLocker)"
        }
        return m[(fstype || "").toLowerCase()]
            || ((fstype || "").charAt(0).toUpperCase() + (fstype || "").slice(1))
    }
    function isEncrypted(fstype) {
        const f = (fstype || "").toLowerCase()
        return f === "crypto_luks" || f === "bitlocker"
    }
    function fstypeFamily(fstype) {
        const linux = ["ext2","ext3","ext4","btrfs","xfs","f2fs"]
        const windows = ["vfat","fat","fat16","fat32","msdos","exfat","ntfs","ntfs-3g"]
        const mac = ["apfs","hfs","hfsplus"]
        const f = (fstype || "").toLowerCase()
        if (linux.indexOf(f) >= 0)   return "linux"
        if (windows.indexOf(f) >= 0) return "windows"
        if (mac.indexOf(f) >= 0)     return "mac"
        return "other"
    }
    function suggestedLabel(drive) {
        if (drive.label && drive.label.length > 0) return drive.label
        if (isEncrypted(drive.fstype)) return "Encrypted Drive"
        if (drive.transport === "usb") return "USB Drive"
        const fam = fstypeFamily(drive.fstype)
        if (fam === "windows") return "Windows Drive"
        if (fam === "mac")     return "Mac Drive"
        if (fam === "linux")   return "Linux Drive"
        return humanSize(drive.size) + " Drive"
    }
    function friendlyTitle(drive) {
        if (drive.label && drive.label.length > 0) return drive.label
        return friendlyFstype(drive.fstype) + " · " + humanSize(drive.size)
    }
    function friendlySubtitle(drive) {
        return drive.path + (drive.label ? " · " + friendlyFstype(drive.fstype) + " · " + humanSize(drive.size) : "")
    }

    function sanitizeMountSegment(s) {
        return (s || "").replace(/[^A-Za-z0-9_.-]/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "")
    }

    function humanSize(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB", "PB"]
        let size = Number(bytes) || 0
        let i = 0
        while (size >= 1024 && i < units.length - 1) { size /= 1024; i++ }
        return (i === 0 ? size.toFixed(0) : size.toFixed(1)) + " " + units[i]
    }

    // Path under /mnt for a network share. Falls back to host_share if no
    // explicit label was given.
    function networkMountpointDefault() {
        const labelSrc = root.netLabel || root.netShare || root.netHost || "share"
        const safe = sanitizeMountSegment(labelSrc) || "share"
        return "/mnt/" + safe
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        scanProc.running = true
        fstabScanProc.running = true
    }

    // ── Local: block-device scan ───────────────────────────────────
    // `lsblk -J -b ...` returns a tree of block devices with size in
    // bytes. We flatten partitions + unpartitioned disks and filter
    // to entries that have a real filesystem and aren't mounted.
    Process {
        id: scanProc
        command: ["bash", "-c", "lsblk -J -b -o NAME,PATH,SIZE,TYPE,MOUNTPOINT,LABEL,FSTYPE,UUID,PARTTYPE,PARTTYPENAME,TRAN,HOTPLUG"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed
                try {
                    parsed = JSON.parse(this.text)
                } catch (e) {
                    root.status = Translation.tr("Failed to read drive list: ") + e
                    return
                }
                const systemParttypes = new Set([
                    "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", // EFI System Partition
                    "0xef",                                 // EFI System Partition (MBR/hybrid)
                    "21686148-6449-6e6f-744e-656564454649", // BIOS boot
                    "e3c9e316-0b5c-4db8-817d-f92df00215ae", // Microsoft Reserved
                    "de94bba4-06d1-4d40-a16a-bfd50179d6ac", // Windows Recovery
                    "9d275380-40ad-11db-bf97-000c2911d1b8"  // VMware
                ])

                const flat = []
                function normHot(v) {
                    if (v === true || v === 1 || v === "1" || v === "true") return "1"
                    if (v === false || v === 0 || v === "0" || v === "false") return "0"
                    return ""
                }
                function isEfiNode(n) {
                    const pt = (n.parttype || "").toLowerCase()
                    return pt === "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" || pt === "0xef" ||
                        (n.parttypename || "").toUpperCase().indexOf("EFI") >= 0
                }
                function subtreeHasEfi(n) {
                    return isEfiNode(n) || (n.children || []).some(subtreeHasEfi)
                }
                function walk(node, inheritedTran, inheritedHotplug, bootDisk) {
                    const isLeaf = !node.children || node.children.length === 0
                    const tran = (node.tran || inheritedTran || "").toLowerCase()
                    const ownHot = normHot(node.hotplug)
                    const hotplug = ownHot || inheritedHotplug || "0"
                    if ((node.type === "part" || node.type === "disk") && isLeaf) {
                        flat.push({
                            name: node.name || "",
                            path: node.path || ("/dev/" + node.name),
                            size: node.size || 0,
                            type: node.type || "",
                            fstype: node.fstype || "",
                            label: node.label || "",
                            uuid: node.uuid || "",
                            mountpoint: node.mountpoint || "",
                            parttype: (node.parttype || "").toLowerCase(),
                            parttypename: (node.parttypename || "").toUpperCase(),
                            transport: tran,
                            hotplug: hotplug,
                            bootDisk: bootDisk
                        })
                    }
                    if (node.children) node.children.forEach(c => walk(c, tran, hotplug, bootDisk))
                }
                if (parsed.blockdevices) parsed.blockdevices.forEach(d => walk(d, "", "0", subtreeHasEfi(d)))
                // Common base filter (USB / hotplug / system-partition / label).
                function baseFilter(d) {
                    return d.transport !== "usb" &&
                        d.hotplug !== "1" &&
                        !systemParttypes.has(d.parttype) &&
                        (d.parttypename || "").indexOf("EFI") === -1 &&
                        (d.label || "").toUpperCase().indexOf("EFI") === -1 &&
                        (d.label || "").toUpperCase().indexOf("USB") === -1
                }
                // Mountable leaf: unmounted, has a filesystem, not swap/optical,
                // not encrypted, passes the base filter. Split into plain storage
                // vs partitions on a disk that carries an ESP (an OS disk).
                function mountableLeaf(d) {
                    return d.uuid && d.fstype && !d.mountpoint &&
                        d.fstype !== "swap" && d.fstype !== "iso9660" && d.fstype !== "udf" &&
                        !root.isEncrypted(d.fstype) && baseFilter(d)
                }
                root.drives   = flat.filter(d => mountableLeaf(d) && !d.bootDisk)
                root.osDrives = flat.filter(d => mountableLeaf(d) &&  d.bootDisk)
                // Encrypted containers, unlockable in place: selecting one
                // reveals a passphrase + rename block wired to the helper's
                // unlock-mount subcommand.
                root.encrypted = flat.filter(d =>
                    d.uuid && d.fstype && !d.mountpoint &&
                    root.isEncrypted(d.fstype) &&
                    baseFilter(d)
                )
                root.unformatted = flat.filter(d =>
                    (d.type === "part" || d.type === "disk") &&
                    (!d.fstype || d.fstype === "iso9660" || d.fstype === "udf") &&
                    !d.mountpoint &&
                    d.size > 0 &&
                    baseFilter(d)
                )
                const stillListed = root.drives.some(d => d.path === root.selectedPath)
                    || root.osDrives.some(d => d.path === root.selectedPath)
                    || root.unformatted.some(d => d.path === root.selectedPath)
                    || root.encrypted.some(d => d.path === root.selectedPath)
                if (root.selectedPath && !stillListed) {
                    root.selectedPath = ""
                    root.selectedExistingLabel = ""
                    root.newLabel = ""
                }
            }
        }
    }

    // ── Mounted: /etc/fstab scan ───────────────────────────────────
    // Read /etc/fstab and surface entries whose mountpoint begins with
    // /mnt/. That's the convention this app uses, and it's where users
    // typically put permanent external drives — never the OS's own
    // mounts (those go to /, /boot, /home, /var, etc.), so the unmount
    // action is always safe to expose for these rows.
    //
    // awk handles comment lines, blank lines, and tab-vs-space columns
    // more cleanly than a shell-only parser. The output is one
    // "source\tmountpoint\tfstype\toptions" record per line.
    Process {
        id: fstabScanProc
        command: ["bash", "-c",
            "awk '$0 !~ /^[[:space:]]*#/ && NF>=4 && $2 ~ /^\\/mnt\\// " +
            "{printf \"%s\\t%s\\t%s\\t%s\\n\", $1, $2, $3, $4}' /etc/fstab | " +
            "while IFS=$'\\t' read -r src mp fstype opts; do conn=1; case \"$src\" in " +
            "UUID=*) [ -e \"/dev/disk/by-uuid/${src#UUID=}\" ] || conn=0 ;; " +
            "LABEL=*) [ -e \"/dev/disk/by-label/${src#LABEL=}\" ] || conn=0 ;; " +
            "PARTUUID=*) [ -e \"/dev/disk/by-partuuid/${src#PARTUUID=}\" ] || conn=0 ;; " +
            "/dev/*) [ -b \"$src\" ] || conn=0 ;; esac; " +
            "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$src\" \"$mp\" \"$fstype\" \"$opts\" \"$conn\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").filter(l => l.length > 0)
                root.mountedDrives = lines.map(l => {
                    const parts = l.split("\t")
                    return {
                        source: parts[0] || "",
                        mountpoint: parts[1] || "",
                        fstype: parts[2] || "",
                        options: parts[3] || "",
                        connected: (parts[4] || "1") !== "0"
                    }
                })
            }
        }
    }

    // ── Network: avahi-browse for SMB hosts ───────────────────────
    // -tarp: terminate after exhausting cache (-t), all services (-a),
    // resolve hostnames+ports (-r), parsable output (-p). _smb._tcp is
    // what Samba and Windows file shares advertise via mDNS/zeroconf.
    //
    // Output format (semicolon-separated): operation;iface;proto;name;type;domain;hostname;address;port;txt
    // operation is "+" (new) or "=" (resolved); we want "=" rows since
    // they carry the resolved address.
    Process {
        id: discoveryProc
        command: ["bash", "-c",
            "command -v avahi-browse >/dev/null 2>&1 || exit 0; " +
            "avahi-browse -tarp _smb._tcp 2>/dev/null | awk -F';' '$1==\"=\" && $3==\"IPv4\" " +
            "{printf \"%s\\t%s\\n\", $4, $8}' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").filter(l => l.length > 0)
                const seen = new Set()
                const hosts = []
                lines.forEach(l => {
                    const parts = l.split("\t")
                    const name = (parts[0] || "").replace(/\\(\d{3})/g, (m, c) =>
                        String.fromCharCode(parseInt(c, 10)))
                    const addr = parts[1] || ""
                    const key = (name + "|" + addr).toLowerCase()
                    if (!seen.has(key)) {
                        seen.add(key)
                        hosts.push({ name: name, address: addr })
                    }
                })
                root.discoveredHosts = hosts
            }
        }
    }

    // ── Mount / unmount processes ──────────────────────────────────
    // Both share the same outputBuf + onExited shape. The script's
    // last line of stdout is the operation summary; we surface that as
    // the success/error message in the status banner.
    Process {
        id: mountProc
        property string outputBuf: ""
        property string pendingPassword: ""  // piped to stdin after start
        stdout: StdioCollector { onStreamFinished: mountProc.outputBuf += this.text }
        stderr: StdioCollector { onStreamFinished: mountProc.outputBuf += this.text }
        onRunningChanged: {
            // When the process flips from idle → running, push the
            // password (if any) into stdin and close the stream so the
            // script's `read -r password` returns rather than blocking.
            // stdinEnabled must have been flipped on BEFORE running was
            // set true — see startMountNetwork().
            if (running && pendingPassword.length > 0) {
                write(pendingPassword + "\n")
                pendingPassword = ""
                stdinEnabled = false
            }
        }
        onExited: (code, _status) => {
            root.busy = false
            const trimmed = (mountProc.outputBuf || "").trim()
            const lastLine = trimmed.split("\n").pop() || ""
            if (code === 0) {
                root.resultKind = "success"
                root.status = lastLine || Translation.tr("Mounted successfully")
                root.mountedPopupText = lastLine
                root.mountedPopupShown = true
                // Refresh every list — the freshly mounted drive should
                // disappear from Available (Local) AND appear in Mounted.
                scanProc.running = true
                fstabScanProc.running = true
                statusClearTimer.restart()
            } else {
                root.resultKind = "error"
                root.status = lastLine || (Translation.tr("Failed (exit ") + code + ")")
            }
        }
    }

    Process {
        id: unmountProc
        property string outputBuf: ""
        property string lastMountpoint: ""
        stdout: StdioCollector { onStreamFinished: unmountProc.outputBuf += this.text }
        stderr: StdioCollector { onStreamFinished: unmountProc.outputBuf += this.text }
        onExited: (code, _status) => {
            root.busy = false
            const trimmed = (unmountProc.outputBuf || "").trim()
            const lastLine = trimmed.split("\n").pop() || ""
            if (code === 0) {
                root.resultKind = "success"
                root.status = lastLine || (Translation.tr("Removed ") + unmountProc.lastMountpoint)
                // Refresh: the unmounted drive should leave Mounted AND
                // come back into Available (for block devices).
                scanProc.running = true
                fstabScanProc.running = true
                statusClearTimer.restart()
            } else {
                root.resultKind = "error"
                root.status = lastLine || (Translation.tr("Unmount failed (exit ") + code + ")")
            }
        }
    }

    Timer {
        id: statusClearTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.status = ""
            root.resultKind = ""
        }
    }

    // ── Action: clear the current selection (closes the Rename section) ─
    function deselectDrive() {
        root.selectedPath = ""
        root.selectedExistingLabel = ""
        root.newLabel = ""
    }

    // ── Auto-scroll the Local list so a picked drive's action block shows ─
    function revealBlock(loader) {
        if (!loader) return
        Qt.callLater(function() {
            const p = loader.mapToItem(localFlick.contentItem, 0, 0)
            const bottom = p.y + loader.height
            const maxY = Math.max(0, localFlick.contentHeight - localFlick.height)
            localFlick.contentY = Math.max(0, Math.min(bottom - localFlick.height, maxY))
        })
    }

    // ── Action: mount the picked local block device ────────────────
    function startMountLocal() {
        if (root.busy || !root.selectedPath) return
        const drive = root.drives.find(d => d.path === root.selectedPath)
            || root.osDrives.find(d => d.path === root.selectedPath)
        if (!drive) return
        const labelRaw = (root.newLabel || drive.label || drive.name).trim()
        const labelSafe = sanitizeMountSegment(labelRaw) || "drive"
        const mountPoint = "/mnt/" + labelSafe
        mountProc.command = [
            "pkexec", "/usr/local/bin/disk-mounter",
            "mount-block",
            drive.path, drive.fstype, drive.uuid,
            mountPoint, labelRaw, "fstab"
        ]
        mountProc.outputBuf = ""
        mountProc.pendingPassword = ""
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Working on it… you may see a password prompt.")
        mountProc.stdinEnabled = false
        mountProc.running = true
    }

    // ── Action: format a blank device as ext4, then mount it ───────
    function startFormatLocal(path) {
        if (root.busy || !path) return
        const drive = root.unformatted.find(d => d.path === path)
        if (!drive) return
        const labelRaw = (root.newLabel || drive.name || "drive").trim()
        const labelSafe = sanitizeMountSegment(labelRaw) || "drive"
        const mountPoint = "/mnt/" + labelSafe
        mountProc.command = [
            "pkexec", "/usr/local/bin/disk-mounter",
            "format-mount",
            drive.path, mountPoint, labelRaw, "fstab"
        ]
        mountProc.outputBuf = ""
        mountProc.pendingPassword = ""
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Formatting and mounting… you may see a password prompt.")
        mountProc.stdinEnabled = false
        mountProc.running = true
    }

    // ── Action: unlock the picked encrypted drive, then mount it ───
    function startUnlockLocal() {
        if (root.busy || !root.selectedPath || root.unlockPassword.length === 0) return
        const drive = root.encrypted.find(d => d.path === root.selectedPath)
        if (!drive) return
        const labelRaw = (root.newLabel || drive.label || drive.name).trim()
        const labelSafe = sanitizeMountSegment(labelRaw) || "drive"
        const mountPoint = "/mnt/" + labelSafe
        mountProc.command = [
            "pkexec", "/usr/local/bin/disk-mounter",
            "unlock-mount",
            drive.path, mountPoint, labelRaw, "fstab"
        ]
        mountProc.outputBuf = ""
        mountProc.pendingPassword = root.unlockPassword
        root.unlockPassword = ""
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Unlocking… you may see a password prompt.")
        // stdinEnabled must be flipped on BEFORE running goes true so the
        // child process has a connected stdin handle to read from.
        mountProc.stdinEnabled = true
        mountProc.running = true
    }

    // ── Action: mount the network share defined by the form ────────
    function startMountNetwork() {
        if (root.busy) return
        const host = (root.netHost || "").trim()
        const share = (root.netShare || "").trim()
        if (!host || !share) {
            root.resultKind = "error"
            root.status = Translation.tr("Host and share/path are required.")
            return
        }
        const mp = root.netMountpoint && root.netMountpoint.length > 0
            ? root.netMountpoint
            : networkMountpointDefault()
        const labelRaw = (root.netLabel || share || "share").trim()

        if (root.netProtocol === "smb") {
            const userArg = root.netGuest ? "guest" : (root.netUsername || "guest")
            mountProc.command = [
                "pkexec", "/usr/local/bin/disk-mounter",
                "mount-smb",
                host, share, mp, labelRaw, userArg, "fstab"
            ]
            mountProc.pendingPassword = root.netGuest ? "" : root.netPassword
        } else {  // nfs
            mountProc.command = [
                "pkexec", "/usr/local/bin/disk-mounter",
                "mount-nfs",
                host, share, mp, labelRaw, "fstab"
            ]
            mountProc.pendingPassword = ""
        }
        mountProc.outputBuf = ""
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Connecting to ") + host + "…"
        // stdinEnabled must be flipped on BEFORE running goes true so the
        // child process has a connected stdin handle to read from.
        mountProc.stdinEnabled = mountProc.pendingPassword.length > 0
        mountProc.running = true
    }

    // ── Action: unmount one of the Mounted-tab rows ────────────────
    function startUnmount(mountpoint) {
        if (root.busy || !mountpoint) return
        unmountProc.command = ["pkexec", "/usr/local/bin/disk-mounter", "unmount", mountpoint, "remove-fstab"]
        unmountProc.outputBuf = ""
        unmountProc.lastMountpoint = mountpoint
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Removing ") + mountpoint + "…"
        unmountProc.running = true
    }

    // Rename + Mount block, dropped in below whichever category holds the
    // currently-selected drive (via a Loader per mountable category).
    Component {
        id: renameMountBlock
        ColumnLayout {
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: rmCol.implicitHeight + 24
                ColumnLayout {
                    id: rmCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        StyledText {
                            Layout.preferredWidth: 110
                            text: Translation.tr("Rename to")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            text: root.newLabel
                            onTextEdited: root.newLabel = text
                            placeholderText: Translation.tr("e.g. Photos, Backups")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "auto_awesome"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("This drive will be ready every time you log in, as \"") +
                                (root.newLabel || root.selectedExistingLabel || "Drive") +
                                Translation.tr("\".")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: 90
                    implicitHeight: 36
                    enabled: !root.busy
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.deselectDrive()
                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Close")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.weight: Font.Medium
                        }
                    }
                }
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: root.selectedUnformatted ? 160 : 130
                    implicitHeight: 36
                    enabled: !root.busy && root.selectedPath.length > 0
                    toggled: enabled
                    onClicked: root.selectedUnformatted
                        ? root.startFormatLocal(root.selectedPath)
                        : root.startMountLocal()
                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: root.busy
                                ? Translation.tr("Working…")
                                : (root.selectedUnformatted ? Translation.tr("Format & Mount") : Translation.tr("Mount"))
                            color: Appearance.m3colors.m3onPrimary
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    // Passphrase + Rename + Unlock block, dropped in below the Encrypted
    // category when the selected drive is a locked container.
    Component {
        id: unlockMountBlock
        ColumnLayout {
            spacing: 12
            Rectangle {
                Layout.fillWidth: true
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                implicitHeight: umCol.implicitHeight + 24
                ColumnLayout {
                    id: umCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        StyledText {
                            Layout.preferredWidth: 110
                            text: Translation.tr("Passphrase")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            text: root.unlockPassword
                            echoMode: TextInput.Password
                            onTextEdited: root.unlockPassword = text
                            onAccepted: root.startUnlockLocal()
                            placeholderText: Translation.tr("The drive's encryption passphrase")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        StyledText {
                            Layout.preferredWidth: 110
                            text: Translation.tr("Rename to")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            text: root.newLabel
                            onTextEdited: root.newLabel = text
                            placeholderText: Translation.tr("e.g. Photos, Backups")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "lock_open"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Unlocks just for this session — the drive locks again when removed or on reboot, and mounts as \"") +
                                (root.newLabel || root.selectedExistingLabel || "Drive") +
                                Translation.tr("\" whenever you unlock it.")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: 90
                    implicitHeight: 36
                    enabled: !root.busy
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: root.deselectDrive()
                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("Close")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.weight: Font.Medium
                        }
                    }
                }
                RippleButton {
                    buttonRadius: Appearance.rounding.normal
                    implicitWidth: 160
                    implicitHeight: 36
                    enabled: !root.busy && root.selectedPath.length > 0 && root.unlockPassword.length > 0
                    toggled: enabled
                    onClicked: root.startUnlockLocal()
                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: root.busy ? Translation.tr("Working…") : Translation.tr("Unlock & Mount")
                            color: Appearance.m3colors.m3onPrimary
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    // Shared selectable drive row — used by the Storage / OS / Unformatted
    // lists. Renders a blank drive (no fstype) or a formatted one.
    Component {
        id: driveRow
        RippleButton {
            id: rowBtn
            required property var modelData
            readonly property bool blank: (modelData.fstype || "") === ""
            readonly property bool isSelected: root.selectedPath === modelData.path
            readonly property color titleColor: isSelected ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
            readonly property color subtitleColor: isSelected ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
            width: ListView.view ? ListView.view.width : implicitWidth
            implicitHeight: 54
            buttonRadius: Appearance.rounding.small
            toggled: isSelected
            onClicked: {
                if (isSelected) {
                    root.deselectDrive()
                } else {
                    root.selectedPath = modelData.path
                    root.selectedExistingLabel = modelData.label
                    root.newLabel = root.suggestedLabel(modelData)
                }
            }
            contentItem: Item {
                anchors.fill: parent
                Item {
                    id: rowIconSlot
                    width: 24
                    height: 24
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isEncrypted(rowBtn.modelData.fstype)
                            ? "lock"
                            : (rowBtn.modelData.transport === "usb"
                                ? "usb"
                                : (rowBtn.modelData.path.indexOf("nvme") >= 0 ? "memory" : "hard_drive_2"))
                        iconSize: 22
                        color: rowBtn.titleColor
                    }
                }
                StyledText {
                    anchors.left: rowIconSlot.right
                    anchors.leftMargin: 12
                    anchors.bottom: parent.verticalCenter
                    anchors.bottomMargin: 1
                    text: rowBtn.blank
                        ? root.humanSize(rowBtn.modelData.size) + " " + Translation.tr("Drive")
                        : root.friendlyTitle(rowBtn.modelData)
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: rowBtn.titleColor
                    font.weight: Font.Medium
                }
                StyledText {
                    anchors.left: rowIconSlot.right
                    anchors.leftMargin: 12
                    anchors.top: parent.verticalCenter
                    anchors.topMargin: 1
                    text: rowBtn.blank
                        ? rowBtn.modelData.path + " · " + Translation.tr("Unformatted")
                        : root.friendlySubtitle(rowBtn.modelData)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: rowBtn.subtitleColor
                    opacity: rowBtn.isSelected ? 0.8 : 1.0
                }
            }
        }
    }

    // ── Layout ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // Titlebar — title left, refresh right
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, refreshBtn.implicitHeight)

            StyledText {
                id: titleText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 4
                text: Translation.tr("Auto Drive Mount")
                color: Appearance.colors.colOnLayer0
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RippleButton {
                id: refreshBtn
                buttonRadius: Appearance.rounding.full
                implicitWidth: 35
                implicitHeight: 35
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                enabled: !root.busy
                onClicked: {
                    // Refresh whichever lists are relevant for the
                    // current tab. Cheap to refresh all three; keeps
                    // the button's behaviour consistent.
                    scanProc.running = true
                    fstabScanProc.running = true
                    if (root.currentTab === 1) discoveryProc.running = true
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: Translation.tr("Refresh") }
            }
        }

        // ── Tab switcher: Local / Network / Mounted ────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { label: Translation.tr("Local"),   icon: "storage" },
                    { label: Translation.tr("Network"), icon: "lan" },
                    { label: Translation.tr("Mounted"), icon: "folder_special" }
                ]

                delegate: RippleButton {
                    required property int index
                    required property var modelData
                    readonly property bool isCurrent: root.currentTab === index
                    Layout.fillWidth: true
                    implicitHeight: 38
                    buttonRadius: Appearance.rounding.normal
                    toggled: isCurrent
                    enabled: !root.busy
                    onClicked: {
                        root.currentTab = index
                        if (index === 1 && root.discoveredHosts.length === 0)
                            discoveryProc.running = true
                    }
                    contentItem: Item {
                        anchors.fill: parent
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                iconSize: 18
                                color: isCurrent ? Appearance.m3colors.m3onPrimary
                                                 : Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.weight: Font.Medium
                                color: isCurrent ? Appearance.m3colors.m3onPrimary
                                                 : Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }
        }

        // ── Tab content (StackLayout) ──────────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTab

            // ===== TAB 0: LOCAL ===========================================
            ColumnLayout {
                spacing: 12

                StyledFlickable {
                    id: localFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: localScrollCol.implicitHeight
                    onContentHeightChanged: {
                        const maxY = Math.max(0, contentHeight - height)
                        if (contentY > maxY) contentY = maxY
                    }
                    ColumnLayout {
                        id: localScrollCol
                        width: localFlick.width
                        spacing: 12

                // Storage drives list
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.drives.length > 0
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: storageCol.implicitHeight + 24

                    ColumnLayout {
                        id: storageCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "storage"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Storage Drives")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.drives.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        ListView {
                            id: driveList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(count, 6) * 58
                            Layout.maximumHeight: 6 * 58
                            clip: true
                            spacing: 4
                            model: root.drives

                            delegate: driveRow
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.drives.some(d => d.path === root.selectedPath)
                    visible: active
                    sourceComponent: renameMountBlock
                    onActiveChanged: if (active) root.revealBlock(this)
                }

                // Operating System Drives (partitions on a disk that has an ESP).
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.osDrives.length > 0
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: osCol.implicitHeight + 24

                    ColumnLayout {
                        id: osCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "install_desktop"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Operating System Drives")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.osDrives.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ListView {
                            id: osDriveList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(count, 4) * 58
                            Layout.maximumHeight: 4 * 58
                            clip: true
                            spacing: 4
                            interactive: count > 4
                            model: root.osDrives
                            delegate: driveRow
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.osDrives.some(d => d.path === root.selectedPath)
                    visible: active
                    sourceComponent: renameMountBlock
                    onActiveChanged: if (active) root.revealBlock(this)
                }

                // Encrypted drives. Selecting one reveals the passphrase +
                // rename block; the helper opens a session-only mapper (no
                // keyfile on disk, no crypttab entry — the tradeoffs that
                // kept auto-unlock out of the app), mounts the filesystem
                // inside, and re-locks the container on removal.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.encrypted.length > 0
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: encryptedCol.implicitHeight + 24

                    ColumnLayout {
                        id: encryptedCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "lock"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Encrypted")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.encrypted.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ListView {
                            id: encryptedList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(count, 4) * 58
                            Layout.maximumHeight: 4 * 58
                            clip: true
                            spacing: 4
                            interactive: count > 4
                            model: root.encrypted
                            delegate: driveRow
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Select an encrypted drive to unlock it with its passphrase and mount it.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.selectedEncrypted
                    visible: active
                    sourceComponent: unlockMountBlock
                    onActiveChanged: if (active) root.revealBlock(this)
                }

                // Unformatted partitions (read-only listing)
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.unformatted.length > 0
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: unformattedCol.implicitHeight + 24

                    ColumnLayout {
                        id: unformattedCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "deployed_code"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Unformatted")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.unformatted.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ListView {
                            id: unformattedList
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(count, 4) * 58
                            Layout.maximumHeight: 4 * 58
                            clip: true
                            spacing: 4
                            interactive: count > 4
                            model: root.unformatted
                            delegate: driveRow
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Select a blank drive to name and format it as Ext4, then mount.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.unformatted.some(d => d.path === root.selectedPath)
                    visible: active
                    sourceComponent: renameMountBlock
                    onActiveChanged: if (active) root.revealBlock(this)
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: root.drives.length === 0 && root.osDrives.length === 0
                        && root.encrypted.length === 0 && root.unformatted.length === 0
                    text: Translation.tr("No drives found. Plug in a drive to mount it.")
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
                    }
                }
            }

            // ===== TAB 1: NETWORK ========================================
            ColumnLayout {
                spacing: 12

                // Discovered hosts via avahi-browse
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "lan"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Found on your network")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.discoveredHosts.length === 0
                                    ? Translation.tr("None yet")
                                    : root.discoveredHosts.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        ListView {
                            id: discoveredList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: root.discoveredHosts

                            delegate: RippleButton {
                                required property var modelData
                                width: discoveredList.width
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.small
                                onClicked: {
                                    // Fill the form's host field with this
                                    // entry. Prefer the resolved IP because
                                    // it works without working DNS / mDNS
                                    // resolution at boot time when the
                                    // fstab entry is processed.
                                    root.netHost = modelData.address || modelData.name
                                    root.netProtocol = "smb"
                                }
                                contentItem: Item {
                                    anchors.fill: parent
                                    MaterialSymbol {
                                        id: dhIcon
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "computer"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        anchors.left: dhIcon.right
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name + (modelData.address ? "  ·  " + modelData.address : "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.discoveredHosts.length === 0
                            text: Translation.tr("SMB hosts that advertise themselves on the local network will appear here. Click one to fill in the form below.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Manual entry form
                //
                // The form rectangle's outer ColumnLayout has three children:
                // a fixed header row, a Flickable that scrolls the field
                // rows (because all of them together exceed the available
                // height once Username/Password show in non-guest mode),
                // and a fixed Mount button row at the bottom. clip:true on
                // the rectangle prevents the scrolling region from
                // visually bleeding over the Close button below.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // ── Fixed header ─────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            MaterialSymbol { text: "add_link"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Add a network share")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        // ── Scrollable field area ───────────────────
                        Flickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: width
                            contentHeight: formFields.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            ColumnLayout {
                                id: formFields
                                width: parent.width
                                spacing: 10

                                // Protocol picker: SMB / NFS as toggle pair
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { value: "smb", label: "SMB / Windows" },
                                            { value: "nfs", label: "NFS / Linux"   }
                                        ]
                                        delegate: RippleButton {
                                            required property var modelData
                                            readonly property bool isOn: root.netProtocol === modelData.value
                                            Layout.fillWidth: true
                                            implicitHeight: 32
                                            buttonRadius: Appearance.rounding.small
                                            toggled: isOn
                                            onClicked: root.netProtocol = modelData.value
                                            contentItem: Item {
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: modelData.label
                                                    color: isOn ? Appearance.m3colors.m3onPrimary
                                                                : Appearance.colors.colOnLayer1
                                                }
                                            }
                                        }
                                    }
                                }

                                // Host
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Server")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netHost
                                        onTextEdited: root.netHost = text
                                        placeholderText: root.netProtocol === "smb"
                                            ? "192.168.1.100 or nas.local"
                                            : "192.168.1.50"
                                    }
                                }

                                // Share / Export path
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: root.netProtocol === "smb"
                                            ? Translation.tr("Share")
                                            : Translation.tr("Export")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netShare
                                        onTextEdited: root.netShare = text
                                        placeholderText: root.netProtocol === "smb"
                                            ? "Photos"
                                            : "/srv/nfs/photos"
                                    }
                                }

                                // Mountpoint (optional, auto-derived)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Mount at")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netMountpoint
                                        onTextEdited: root.netMountpoint = text
                                        placeholderText: root.networkMountpointDefault()
                                    }
                                }

                                // Sidebar label
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Show as")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netLabel
                                        onTextEdited: root.netLabel = text
                                        placeholderText: root.netShare || Translation.tr("(uses share name)")
                                    }
                                }

                                // Credentials (SMB only)
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.netProtocol === "smb"
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Sign in")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    RippleButton {
                                        implicitHeight: 28
                                        implicitWidth: 110
                                        buttonRadius: Appearance.rounding.small
                                        toggled: root.netGuest
                                        onClicked: root.netGuest = !root.netGuest
                                        contentItem: Item {
                                            StyledText {
                                                anchors.centerIn: parent
                                                text: root.netGuest
                                                    ? Translation.tr("✓ Guest")
                                                    : Translation.tr("Guest")
                                                color: root.netGuest ? Appearance.m3colors.m3onPrimary
                                                                     : Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.small
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.netProtocol === "smb" && !root.netGuest
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Username")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netUsername
                                        onTextEdited: root.netUsername = text
                                        placeholderText: "anonymous"
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: root.netProtocol === "smb" && !root.netGuest
                                    spacing: 10
                                    StyledText {
                                        Layout.preferredWidth: 90
                                        text: Translation.tr("Password")
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialTextField {
                                        Layout.fillWidth: true
                                        text: root.netPassword
                                        onTextEdited: root.netPassword = text
                                        echoMode: TextInput.Password
                                        placeholderText: Translation.tr("Stored in /etc/disk-mounter-credentials/")
                                    }
                                }
                            }
                        }

                        // ── Fixed Mount button ──────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Item { Layout.fillWidth: true }
                            RippleButton {
                                buttonRadius: Appearance.rounding.normal
                                implicitWidth: 160
                                implicitHeight: 36
                                enabled: !root.busy
                                    && root.netHost.length > 0
                                    && root.netShare.length > 0
                                toggled: enabled
                                onClicked: root.startMountNetwork()
                                contentItem: Item {
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: root.busy
                                            ? Translation.tr("Working…")
                                            : Translation.tr("Mount share")
                                        color: Appearance.m3colors.m3onPrimary
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ===== TAB 2: MOUNTED ========================================
            ColumnLayout {
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "folder_special"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Auto-mounted drives")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.mountedDrives.length === 0
                                    ? Translation.tr("None")
                                    : root.mountedDrives.length + " " + Translation.tr("active")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.mountedDrives.length === 0
                            text: Translation.tr("Drives that this app added to /etc/fstab show up here. Mount a drive from the Local or Network tab and it'll appear in this list, ready to remove with one click.")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }

                        ListView {
                            id: mountedList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: root.mountedDrives

                            delegate: Rectangle {
                                required property var modelData
                                width: mountedList.width
                                implicitHeight: 56
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colOutlineVariant

                                MaterialSymbol {
                                    id: mIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        const ft = (modelData.fstype || "").toLowerCase()
                                        if (ft === "cifs" || ft === "smbfs") return "lan"
                                        if (ft === "nfs"  || ft === "nfs4")  return "lan"
                                        return "hard_drive_2"
                                    }
                                    iconSize: 22
                                    color: modelData.connected === false
                                        ? Appearance.colors.colSubtext
                                        : Appearance.colors.colOnLayer1
                                }
                                ColumnLayout {
                                    anchors.left: mIcon.right
                                    anchors.leftMargin: 12
                                    anchors.right: unmountBtn.left
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            Layout.fillWidth: modelData.connected !== false
                                            text: modelData.mountpoint
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: modelData.connected === false
                                                ? Appearance.colors.colSubtext
                                                : Appearance.colors.colOnLayer1
                                            font.weight: Font.Medium
                                            elide: Text.ElideMiddle
                                        }
                                        StyledText {
                                            visible: modelData.connected === false
                                            text: Translation.tr("(Disconnected)")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colError
                                            font.weight: Font.Medium
                                        }
                                        Item {
                                            visible: modelData.connected === false
                                            Layout.fillWidth: true
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.friendlyFstype(modelData.fstype) + " · " + modelData.source
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                                RippleButton {
                                    id: unmountBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 110
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.small
                                    enabled: !root.busy
                                    onClicked: root.startUnmount(modelData.mountpoint)
                                    contentItem: Item {
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "link_off"
                                                iconSize: 16
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Translation.tr("Remove")
                                                color: Appearance.colors.colOnLayer1
                                                font.pixelSize: Appearance.font.pixelSize.small
                                            }
                                        }
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Unmount and remove from /etc/fstab")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Status / result banner ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.status.length > 0
            radius: Appearance.rounding.normal
            color: root.resultKind === "success"
                ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.14)
                : root.resultKind === "error"
                    ? Qt.rgba(Appearance.m3colors.m3error.r, Appearance.m3colors.m3error.g, Appearance.m3colors.m3error.b, 0.14)
                    : Appearance.colors.colLayer1
            border.width: 1
            border.color: root.resultKind === "success"
                ? Appearance.colors.colPrimary
                : root.resultKind === "error"
                    ? Appearance.m3colors.m3error
                    : Appearance.colors.colOutlineVariant
            implicitHeight: statusRow.implicitHeight + 20

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.resultKind === "success" ? "check_circle"
                        : root.resultKind === "error"   ? "error"
                                                        : "hourglass_top"
                    iconSize: 22
                    color: root.resultKind === "success" ? Appearance.colors.colPrimary
                        : root.resultKind === "error"   ? Appearance.m3colors.m3error
                                                        : Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: root.resultKind === "success" ? Translation.tr("Done")
                            : root.resultKind === "error"   ? Translation.tr("Something went wrong")
                                                            : Translation.tr("Working…")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.status
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.8
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ── Close button (always visible, in all tabs) ──────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            RippleButton {
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 100
                implicitHeight: 36
                enabled: !root.busy
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.close()
                contentItem: Item {
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Close")
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }

    // ── "Disk mounted" confirmation popup ──────────────────────────
    // Loader-wrapped: WindowDialog only collapses via onShowChanged, so
    // placing it directly would render + block on load. Instantiate on demand.
    Loader {
        anchors.fill: parent
        z: 100
        active: root.mountedPopupShown
        sourceComponent: Component {
            WindowDialog {
                id: mountedDialog
                // WindowDialog snapshots backgroundHeight once when `show`
                // flips true. Compute it from our own items (the message
                // gets an explicit width so its wrapped height resolves
                // synchronously) and only flip show after every binding is
                // initialized — otherwise a two-line message overflows the
                // frozen too-small background.
                show: false
                Component.onCompleted: show = true
                onDismiss: root.mountedPopupShown = false
                backgroundHeight: popupIcon.implicitHeight + popupTitle.implicitHeight
                    + (popupMsg.visible ? popupMsg.implicitHeight + 16 : 0)
                    + popupBtn.implicitHeight + 16 * 2 + Appearance.rounding.large * 2

                MaterialSymbol {
                    id: popupIcon
                    Layout.alignment: Qt.AlignHCenter
                    text: "check_circle"
                    iconSize: 48
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    id: popupTitle
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Disk mounted")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    id: popupMsg
                    Layout.alignment: Qt.AlignHCenter
                    width: mountedDialog.backgroundWidth - Appearance.rounding.large * 2
                    visible: root.mountedPopupText.length > 0
                    text: root.mountedPopupText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    id: popupBtn
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 100
                    implicitHeight: 34
                    toggled: true
                    buttonRadius: Appearance.rounding.small
                    onClicked: root.mountedPopupShown = false
                    contentItem: Item {
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("OK")
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
