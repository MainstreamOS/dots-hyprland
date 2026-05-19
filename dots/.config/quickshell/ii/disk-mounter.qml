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
    property var drives: []           // populated by lsblk parse
    property var unformatted: []      // partitions with no filesystem
    property var encrypted: []        // LUKS / BitLocker — read-only listing
    property string selectedPath: ""  // /dev/... of the picked drive
    property string selectedFstype: ""
    property string selectedUuid: ""
    property string selectedExistingLabel: ""
    property string newLabel: ""

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
        command: ["bash", "-c", "lsblk -J -b -o NAME,PATH,SIZE,TYPE,MOUNTPOINT,LABEL,FSTYPE,UUID,PARTTYPE,TRAN,HOTPLUG"]
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
                function walk(node, inheritedTran, inheritedHotplug) {
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
                            transport: tran,
                            hotplug: hotplug
                        })
                    }
                    if (node.children) node.children.forEach(c => walk(c, tran, hotplug))
                }
                if (parsed.blockdevices) parsed.blockdevices.forEach(d => walk(d, "", "0"))
                // Common base filter (USB / hotplug / system-partition / label).
                function baseFilter(d) {
                    return d.transport !== "usb" &&
                        d.hotplug !== "1" &&
                        !systemParttypes.has(d.parttype) &&
                        (d.label || "").toUpperCase().indexOf("EFI") === -1 &&
                        (d.label || "").toUpperCase().indexOf("USB") === -1
                }
                // Available drives: mountable + currently-unmounted +
                // not encrypted (encrypted lands in its own bucket).
                root.drives = flat.filter(d =>
                    d.uuid && d.fstype && !d.mountpoint &&
                    d.fstype !== "swap" &&
                    d.fstype !== "iso9660" &&
                    d.fstype !== "udf" &&
                    !root.isEncrypted(d.fstype) &&
                    baseFilter(d)
                )
                // Encrypted (read-only). These show up with a lock icon
                // + a hint pointing the user at gnome-disks / kde-partition-
                // manager because we don't ship an unlock flow ourselves.
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
                if (root.selectedPath && !root.drives.some(d => d.path === root.selectedPath)) {
                    root.selectedPath = ""
                    root.selectedFstype = ""
                    root.selectedUuid = ""
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
            "{printf \"%s\\t%s\\t%s\\t%s\\n\", $1, $2, $3, $4}' /etc/fstab"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").filter(l => l.length > 0)
                root.mountedDrives = lines.map(l => {
                    const parts = l.split("\t")
                    return {
                        source: parts[0] || "",
                        mountpoint: parts[1] || "",
                        fstype: parts[2] || "",
                        options: parts[3] || ""
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

    // ── Action: mount the picked local block device ────────────────
    function startMountLocal() {
        if (root.busy || !root.selectedPath) return
        const drive = root.drives.find(d => d.path === root.selectedPath)
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

    // ── Action: mount the network share defined by the form ────────
    function startMountNetwork() {
        if (root.busy) return
        if (!root.netHost || !root.netShare) {
            root.resultKind = "error"
            root.status = Translation.tr("Host and share/path are required.")
            return
        }
        const mp = root.netMountpoint && root.netMountpoint.length > 0
            ? root.netMountpoint
            : networkMountpointDefault()
        const labelRaw = (root.netLabel || root.netShare || "share").trim()

        if (root.netProtocol === "smb") {
            const userArg = root.netGuest ? "guest" : (root.netUsername || "guest")
            mountProc.command = [
                "pkexec", "/usr/local/bin/disk-mounter",
                "mount-smb",
                root.netHost, root.netShare, mp, labelRaw, userArg, "fstab"
            ]
            mountProc.pendingPassword = root.netGuest ? "" : root.netPassword
        } else {  // nfs
            mountProc.command = [
                "pkexec", "/usr/local/bin/disk-mounter",
                "mount-nfs",
                root.netHost, root.netShare, mp, labelRaw, "fstab"
            ]
            mountProc.pendingPassword = ""
        }
        mountProc.outputBuf = ""
        root.busy = true
        root.resultKind = ""
        root.status = Translation.tr("Connecting to ") + root.netHost + "…"
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

                // Available drives list
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
                            MaterialSymbol { text: "storage"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Available drives")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: root.drives.length === 0
                                    ? Translation.tr("None found")
                                    : root.drives.length + " " + Translation.tr("found")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        ListView {
                            id: driveList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: root.drives

                            delegate: RippleButton {
                                id: dvRow
                                required property var modelData
                                readonly property bool isSelected: root.selectedPath === modelData.path
                                readonly property color titleColor:
                                    isSelected ? Appearance.m3colors.m3onPrimary
                                               : Appearance.colors.colOnLayer1
                                readonly property color subtitleColor:
                                    isSelected ? Appearance.m3colors.m3onPrimary
                                               : Appearance.colors.colSubtext
                                readonly property real subtitleOpacity:
                                    isSelected ? 0.8 : 1.0
                                width: driveList.width
                                implicitHeight: 54
                                buttonRadius: Appearance.rounding.small
                                toggled: isSelected
                                onClicked: {
                                    root.selectedPath = modelData.path
                                    root.selectedFstype = modelData.fstype
                                    root.selectedUuid = modelData.uuid
                                    root.selectedExistingLabel = modelData.label
                                    root.newLabel = root.suggestedLabel(modelData)
                                }
                                contentItem: Item {
                                    anchors.fill: parent
                                    Item {
                                        id: iconSlot
                                        width: 24
                                        height: 24
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: root.isEncrypted(modelData.fstype)
                                                ? "lock"
                                                : (modelData.transport === "usb"
                                                    ? "usb"
                                                    : (modelData.path.indexOf("nvme") >= 0 ? "memory" : "hard_drive_2"))
                                            iconSize: 22
                                            color: dvRow.titleColor
                                        }
                                    }
                                    StyledText {
                                        anchors.left: iconSlot.right
                                        anchors.leftMargin: 12
                                        anchors.bottom: parent.verticalCenter
                                        anchors.bottomMargin: 1
                                        text: root.friendlyTitle(modelData)
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: dvRow.titleColor
                                        font.weight: Font.Medium
                                    }
                                    StyledText {
                                        anchors.left: iconSlot.right
                                        anchors.leftMargin: 12
                                        anchors.top: parent.verticalCenter
                                        anchors.topMargin: 1
                                        text: root.friendlySubtitle(modelData)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: dvRow.subtitleColor
                                        opacity: dvRow.subtitleOpacity
                                    }
                                }
                            }
                        }
                    }
                }

                // Encrypted drives (read-only listing).
                //
                // The app intentionally doesn't ship its own LUKS unlock
                // flow — that path involves a keyfile or a TPM-bound
                // setup, both of which have security implications worth
                // a deliberate decision from the user. So we surface the
                // drive's existence (lock icon + "Encrypted" label) and
                // point at gnome-disks / kde-partition-manager instead.
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
                            Layout.preferredHeight: Math.min(count, 4) * 32
                            Layout.maximumHeight: 4 * 32
                            clip: true
                            spacing: 2
                            interactive: count > 4
                            model: root.encrypted
                            delegate: Item {
                                required property var modelData
                                width: encryptedList.width
                                implicitHeight: 30
                                MaterialSymbol {
                                    id: eIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "lock"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    anchors.left: eIcon.right
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.path + " · " + root.friendlyFstype(modelData.fstype) + " · " + root.humanSize(modelData.size)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.85
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Encrypted drives need to be unlocked first. Open the Disks app (gnome-disks) and choose Unlock from the partition menu.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }
                    }
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
                            Layout.preferredHeight: Math.min(count, 4) * 32
                            Layout.maximumHeight: 4 * 32
                            clip: true
                            spacing: 2
                            interactive: count > 4
                            model: root.unformatted
                            delegate: Item {
                                required property var modelData
                                width: unformattedList.width
                                implicitHeight: 30
                                MaterialSymbol {
                                    id: uIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "horizontal_rule"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    anchors.left: uIcon.right
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.path + " · " + root.humanSize(modelData.size)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.85
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("These partitions need to be formatted before they can be mounted.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Drive settings (rename) + Mount button
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.selectedPath.length > 0
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: settingsCol.implicitHeight + 24

                    ColumnLayout {
                        id: settingsCol
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

                // Local-tab Mount button (footer area)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        buttonRadius: Appearance.rounding.normal
                        implicitWidth: 130
                        implicitHeight: 36
                        enabled: !root.busy && root.selectedPath.length > 0
                        toggled: enabled
                        onClicked: root.startMountLocal()
                        contentItem: Item {
                            StyledText {
                                anchors.centerIn: parent
                                text: root.busy ? Translation.tr("Working…") : Translation.tr("Mount")
                                color: Appearance.m3colors.m3onPrimary
                                font.weight: Font.Medium
                            }
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
                                    color: Appearance.colors.colOnLayer1
                                }
                                ColumnLayout {
                                    anchors.left: mIcon.right
                                    anchors.leftMargin: 12
                                    anchors.right: unmountBtn.left
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.mountpoint
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                        font.weight: Font.Medium
                                        elide: Text.ElideMiddle
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
                onClicked: root.close()
                contentItem: Item {
                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Close")
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }
}
