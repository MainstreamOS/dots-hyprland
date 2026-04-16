import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: displayConfigPage
    forceWidth: true

    property var monitors: []
    property var pendingChanges: ({})

    // Palette of colours for distinguishing monitors on the canvas
    readonly property var monitorColors: [
        Appearance.colors.colPrimary,
        Appearance.m3colors.m3tertiary,
        Appearance.m3colors.m3secondary,
        Appearance.m3colors.m3error,
    ]

    property string monitorsConfPath: `${Quickshell.env("HOME")}/.config/hypr/monitors.conf`
    property string hyprlandConfPath: `${Quickshell.env("HOME")}/.config/hypr/hyprland.conf`
    property string defaultMonitor: ""
    property var confBitdepth: ({})
    property var confVrr: ({})
    property var confPositionMode: ({})
    property var confColorMode: ({})
    property var confIccProfile: ({})
    property var confMaxLuminance:    ({})
    property var confMaxAvgLuminance: ({})
    property var confMinLuminance:    ({})
    property var confSdrMaxLuminance: ({})
    property var confSdrMinLuminance: ({})
    property var confSdrBrightness:   ({})
    property var confSdrSaturation:   ({})
    property var confHdrMode:          ({})
    // Set to true for a monitor name once the calibration wizard has been completed
    // (either this session via the wizard, or previously — detected from confMaxLuminance)
    property var hdrCalibratedMonitors: ({})

    property string iccProfileDir: `${Quickshell.env("HOME")}/.icc-profiles`
    // List of { name, path } objects — one per file in iccProfileDir
    property var iccProfiles: []

    // Workspace-to-monitor bindings
    // "default" = Hyprland decides, "custom" = user assigns workspaces to monitors
    property string wsBindingMode: "default"
    // Map of workspace number (1–10) → monitor name. Empty string = unassigned.
    property var workspaceAssignments: ({})
    // Per-monitor count of 10-workspace rows shown (default 1 = workspaces 1–10)
    property var wsRowCounts: ({})

    // Centralized HDR default values — used by initPending, buildMonitorBlock,
    // hdrCalLoader, and fine-tune sliders so they stay in sync.
    readonly property var hdrDefaults: ({
        maxLuminance: 600, maxAvgLuminance: 400, minLuminance: 0,
        sdrMaxLuminance: 250, sdrMinLuminance: 0.005,
        sdrBrightness: 1.0, sdrSaturation: 1.0,
    })

    // Helper: update a single key in pendingChanges for a monitor and trigger bindings.
    function updatePending(monName, key, value) {
        let p = Object.assign({}, pendingChanges[monName] ?? {});
        p[key] = value;
        pendingChanges[monName] = p;
        pendingChanges = Object.assign({}, pendingChanges);
    }

    // Helper: merge multiple keys into pendingChanges for a monitor.
    function updatePendingBatch(monName, obj) {
        let p = Object.assign({}, pendingChanges[monName] ?? {}, obj);
        pendingChanges[monName] = p;
        pendingChanges = Object.assign({}, pendingChanges);
    }

    function assignWorkspace(wsNum, monName) {
        let a = Object.assign({}, workspaceAssignments);
        // If already assigned to this monitor, unassign
        if (a[wsNum] === monName) {
            delete a[wsNum];
        } else {
            a[wsNum] = monName;
        }
        workspaceAssignments = a;
    }

    function setDefaultMonitor(monitorName) {
        displayConfigPage.defaultMonitor = monitorName;
        // Force the new default to position 0x0
        let p = Object.assign({}, pendingChanges[monitorName] ?? {});
        p.x = 0;
        p.y = 0;
        delete p.positionMode;
        pendingChanges[monitorName] = p;
        pendingChanges = Object.assign({}, pendingChanges);

        // Re-sort monitors so default is first
        let sorted = displayConfigPage.monitors.slice().sort((a, b) => {
            if (a.name === monitorName) return -1;
            if (b.name === monitorName) return 1;
            return 0;
        });
        displayConfigPage.monitors = sorted;

        // Write cursor block to hyprland.conf
        let escaped = monitorName.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
        let confPath = displayConfigPage.hyprlandConfPath.replace(/'/g, "\\'");
        let py =
            "import re\n" +
            "path = '" + confPath + "'\n" +
            "name = '" + escaped + "'\n" +
            "try:\n" +
            "    content = open(path, 'r').read()\n" +
            "except FileNotFoundError:\n" +
            "    content = ''\n" +
            "content = re.sub(r'\\ncursor\\s*\\{[^}]*\\}', '', content)\n" +
            "content = content.rstrip('\\n') + '\\ncursor {\\n    default_monitor = ' + name + '\\n}\\n'\n" +
            "open(path, 'w').write(content)\n";
        writeHyprlandProc.command = ["python3", "-c", py];
        writeHyprlandProc.running = false;
        writeHyprlandProc.running = true;
    }


    function clearAllAssignments() {
        workspaceAssignments = ({});
    }

    function workspacesForMonitor(monName) {
        let result = [];
        for (let ws = 1; ws <= 10; ws++) {
            if (workspaceAssignments[ws] === monName) result.push(ws);
        }
        return result;
    }
    // Keyed by monitor name (e.g. "DP-1").
    // Each entry: { vrr: bool, tenBit: bool }
    // Only populated after capabilitiesProc finishes; defaults to false while pending.
    property var monitorCapabilities: ({})

    function parseMonitorsConf() {
        readConfProc.running = false;
        readConfProc.running = true;
    }

    // Capability detection for VRR and 10-bit per connector.
    //
    // - amdgpu, i915, xe: safe, features allowed
    // - nvidia >= 581: modern nvidia-open, safe
    // - nvidia < 581: legacy (580xx/470xx/390xx), features blocked
    // - nouveau, radeon, unknown: features blocked
    // Per-connector sysfs files (vrr_capable, pixel_formats) are used where
    // available; missing files fall back to the driver-level flag.
    Process {
        id: capabilitiesProc
        command: ["python3", "-c", `
import os, json, glob

def card_driver(card):
    try:
        return os.path.basename(os.readlink(os.path.join(card, 'device', 'driver')))
    except Exception:
        return ''

def nvidia_is_legacy():
    # nvidia-580xx-dkms is frozen at 580.x and will never exceed it.
    # nvidia-open will only increase from here. >= 581 means modern safe driver.
    try:
        v = open('/sys/module/nvidia/version').read().strip()
        return int(v.split('.')[0]) < 581
    except Exception:
        return True   # cannot confirm — treat as legacy to be safe

result = {}
for card in sorted(glob.glob('/sys/class/drm/card[0-9]')):
    driver  = card_driver(card)
    card_id = os.path.basename(card)

    if driver == 'amdgpu':
        drv_vrr   = True
        drv_10bit = True
    elif driver in ('i915', 'xe'):
        drv_vrr   = True
        drv_10bit = True
    elif driver == 'nvidia':
        legacy    = nvidia_is_legacy()
        drv_vrr   = not legacy
        drv_10bit = not legacy
    else:
        # nouveau, radeon, unknown — conservatively disabled
        drv_vrr   = False
        drv_10bit = False

    for conn_dir in sorted(glob.glob(f'/sys/class/drm/{card_id}-*/')):
        conn_full = os.path.basename(conn_dir.rstrip('/'))
        name = '-'.join(conn_full.split('-')[1:])
        if 'Writeback' in name:
            continue

        # VRR: read vrr_capable from EDID sysfs, fall back to driver flag
        vrr = False
        if drv_vrr:
            try:
                vrr = open(os.path.join(conn_dir, 'vrr_capable')).read().strip() == '1'
            except FileNotFoundError:
                vrr = drv_vrr
            except Exception:
                vrr = False

        # 10-bit: read pixel_formats from sysfs, fall back to driver flag
        ten_bit = False
        if drv_10bit:
            try:
                fmts    = open(os.path.join(conn_dir, 'pixel_formats')).read().split()
                ten_bit = any(f in {'XR30','XB30','AR30','AB30'} or f.endswith('30')
                              for f in fmts)
            except FileNotFoundError:
                ten_bit = drv_10bit
            except Exception:
                ten_bit = False

        # HDR: check EDID for CTA-861 HDR Static Metadata Data Block (tag 7, ext-tag 6)
        hdr = False
        try:
            edid = open(os.path.join(conn_dir, 'edid'), 'rb').read()
            for blk in range(1, len(edid) // 128):
                b = edid[blk*128:(blk+1)*128]
                if len(b) < 128 or b[0] != 0x02:
                    continue
                dtd_off = b[2]
                pos = 4
                while pos < dtd_off and pos < 128:
                    t = (b[pos] >> 5) & 0x07
                    ln = b[pos] & 0x1F
                    if pos + 1 + ln > 128:
                        break
                    if t == 7 and ln >= 2 and b[pos+1] == 6:
                        hdr = True
                    pos += 1 + ln
        except Exception:
            pass

        result[name] = {'vrr': vrr, 'tenBit': ten_bit, 'hdr': hdr}

print(json.dumps(result))
`]
        property string output: ""
        stdout: SplitParser {
            onRead: data => capabilitiesProc.output += data
        }
        onExited: {
            try {
                let parsed = JSON.parse(capabilitiesProc.output.trim());
                displayConfigPage.monitorCapabilities = parsed;
            } catch(e) {
                console.warn("Failed to parse monitor capabilities:", e);
            }
            capabilitiesProc.output = "";
        }
    }

    Process {
        id: readConfProc
        command: ["cat", displayConfigPage.monitorsConfPath]
        property string output: ""
        stdout: SplitParser {
            onRead: data => readConfProc.output += data + "\n"
        }
        onExited: {
            let bitdepthResult = {};
            let vrrResult = {};
            let positionModeResult = {};
            let colorModeResult = {};
            let iccProfileResult = {};
            let maxLuminanceResult    = {};
            let maxAvgLuminanceResult = {};
            let minLuminanceResult    = {};
            let sdrMaxLuminanceResult = {};
            let sdrMinLuminanceResult = {};
            let sdrBrightnessResult   = {};
            let sdrSaturationResult   = {};
            let hdrModeResult = {};
            let wsAssignments = {};
            let hasAnyWsBinding = false;

            // Parse monitorv2 { ... } blocks as well as legacy monitor= lines
            let currentBlock = null;
            readConfProc.output.split("\n").forEach(line => {
                let trimmed = line.trim();

                // ── monitorv2 block start ──────────────────────────────────
                if (/^monitorv2\s*\{/.test(trimmed)) {
                    currentBlock = {};
                    return;
                }
                if (currentBlock !== null) {
                    if (trimmed === "}") {
                        // End of block — commit parsed values
                        let name = currentBlock["output"];
                        if (name) {
                            if (currentBlock["bitdepth"])  bitdepthResult[name]    = parseInt(currentBlock["bitdepth"]);
                            if (currentBlock["vrr"])       vrrResult[name]         = parseInt(currentBlock["vrr"]);
                            if (currentBlock["cm"])        colorModeResult[name]   = currentBlock["cm"];
                            if (currentBlock["icc"])       iccProfileResult[name]  = currentBlock["icc"];
                            if (currentBlock["max_luminance"])     maxLuminanceResult[name]    = parseFloat(currentBlock["max_luminance"]);
                            if (currentBlock["max_avg_luminance"]) maxAvgLuminanceResult[name] = parseFloat(currentBlock["max_avg_luminance"]);
                            if (currentBlock["min_luminance"])     minLuminanceResult[name]    = parseFloat(currentBlock["min_luminance"]);
                            if (currentBlock["sdr_max_luminance"]) sdrMaxLuminanceResult[name] = parseFloat(currentBlock["sdr_max_luminance"]);
                            if (currentBlock["sdr_min_luminance"]) sdrMinLuminanceResult[name] = parseFloat(currentBlock["sdr_min_luminance"]);
                            if (currentBlock["sdrbrightness"])     sdrBrightnessResult[name]   = parseFloat(currentBlock["sdrbrightness"]);
                            if (currentBlock["sdrsaturation"])     sdrSaturationResult[name]   = parseFloat(currentBlock["sdrsaturation"]);
                            let pos = currentBlock["position"] ?? "";
                            if (pos.startsWith("auto-center-")) positionModeResult[name] = pos;
                        }
                        currentBlock = null;
                    } else {
                        let kv = trimmed.match(/^(\w+)\s*=\s*(.+)$/);
                        if (kv) currentBlock[kv[1]] = kv[2].trim();
                    }
                    return;
                }

                // ── Legacy monitor= lines (fallback) ──────────────────────
                let mb = line.match(/^monitor=([^,]+),.+,bitdepth,(\d+)/);
                if (mb) bitdepthResult[mb[1]] = parseInt(mb[2]);
                let mv = line.match(/^monitor=([^,]+),.+,vrr,(\d+)/);
                if (mv) vrrResult[mv[1]] = parseInt(mv[2]);
                let mp = line.match(/^monitor=([^,]+),[^,]+,(auto-center-[^,]+),/);
                if (mp) positionModeResult[mp[1]] = mp[2];
                let mc = line.match(/^monitor=([^,]+),.+,cm,(\w+)/);
                if (mc) colorModeResult[mc[1]] = mc[2];
                let mi = line.match(/^monitor=([^,]+),.+,icc,([^,\n]+)/);
                if (mi) iccProfileResult[mi[1]] = mi[2].trim();

                // ── HDR mode metadata (persisted as comment) ─────────────
                let mh = trimmed.match(/^#\s*ii_hdr_mode:(\S+)\s*=\s*(\d+)/);
                if (mh) hdrModeResult[mh[1]] = parseInt(mh[2]);

                // ── Workspace bindings (same in both syntaxes) ─────────────
                let mw = line.match(/^workspace\s*=\s*(\d+)\s*,\s*monitor:(\S+)/);
                if (mw) {
                    wsAssignments[parseInt(mw[1])] = mw[2];
                    hasAnyWsBinding = true;
                }
            });

            displayConfigPage.confBitdepth      = bitdepthResult;
            displayConfigPage.confVrr            = vrrResult;
            displayConfigPage.confPositionMode   = positionModeResult;
            displayConfigPage.confColorMode      = colorModeResult;
            displayConfigPage.confIccProfile     = iccProfileResult;
            displayConfigPage.confMaxLuminance    = maxLuminanceResult;
            displayConfigPage.confMaxAvgLuminance = maxAvgLuminanceResult;
            displayConfigPage.confMinLuminance    = minLuminanceResult;
            displayConfigPage.confSdrMaxLuminance = sdrMaxLuminanceResult;
            displayConfigPage.confSdrMinLuminance = sdrMinLuminanceResult;
            displayConfigPage.confSdrBrightness   = sdrBrightnessResult;
            displayConfigPage.confSdrSaturation   = sdrSaturationResult;
            displayConfigPage.confHdrMode          = hdrModeResult;
            // Any monitor that already has max_luminance in conf has been calibrated before
            let calibrated = Object.assign({}, displayConfigPage.hdrCalibratedMonitors);
            Object.keys(maxLuminanceResult).forEach(n => { calibrated[n] = true; });
            displayConfigPage.hdrCalibratedMonitors = calibrated;
            displayConfigPage.workspaceAssignments = wsAssignments;
            displayConfigPage.wsBindingMode = hasAnyWsBinding ? "custom" : "default";
            readConfProc.output = "";
            // Only refresh monitors after conf is parsed so initPending gets correct values
            displayConfigPage.refreshMonitors();
        }
    }

    function refreshMonitors() {
        monitorProc.running = false;
        monitorProc.running = true;
    }

    // Snap scale to exact rational values to avoid floating point drift
    function snapScale(scale) {
        const knownScales = [1.0, 1.25, 1.5, 5/3, 1.875, 2.0];
        return knownScales.reduce((prev, curr) =>
            Math.abs(curr - scale) < Math.abs(prev - scale) ? curr : prev);
    }

    function buildMonitorBlock(name, m, mon) {
        let snapped = snapScale(m.scale);
        const scaleMap = {
            [1.0]:   "1.0",
            [1.25]:  "1.25",
            [1.5]:   "1.5",
            [5/3]:   "1.666667",
            [1.875]: "1.875",
            [2.0]:   "2.0"
        };
        let scale = scaleMap[snapped] ?? snapped.toFixed(4);
        let isDefault = name === displayConfigPage.defaultMonitor;
        let pos = isDefault ? "0x0" : (m.positionMode ?? `${m.x}x${m.y}`);
        let mode = `${m.width}x${m.height}@${m.refreshRate.toFixed(6)}`;
        let colorMode = m.colorMode ?? "srgb";
        let isHdr = colorMode === "hdr" || colorMode === "hdredid";
        let hdrMode = m.hdrMode ?? 0;  // 0=none, 1=Always On, 2=Fullscreen Only
        // HDR forces 10-bit; otherwise use the stored bitdepth
        let bitdepth = (isHdr || hdrMode > 0) ? 10 : (m.bitdepth ?? 8);

        let lines = [];
        // Persist HDR mode as a comment so it survives reloads
        if (isHdr && hdrMode > 0)
            lines.push(`# ii_hdr_mode:${name} = ${hdrMode}`);
        lines.push(`monitorv2 {`);
        lines.push(`    output = ${name}`);
        if (!m.enabled) {
            lines.push(`    disabled = true`);
        } else {
            lines.push(`    mode = ${mode}`);
            lines.push(`    position = ${pos}`);
            lines.push(`    scale = ${scale}`);
            lines.push(`    transform = ${m.transform}`);
            if (bitdepth !== 8)          lines.push(`    bitdepth = ${bitdepth}`);
            if ((m.vrr ?? 0) !== 0)      lines.push(`    vrr = ${m.vrr}`);
            // "Fullscreen Only" (2): don't write cm=hdr — Hyprland's
            // render:cm_auto_hdr (default 1) handles fullscreen HDR switching.
            // "Always On" (1): write cm=hdr/hdredid as usual.
            if (isHdr && hdrMode === 2) {
                // Skip cm = hdr so Hyprland only activates HDR for fullscreen apps
            } else if (colorMode !== "auto") {
                lines.push(`    cm = ${colorMode}`);
            }
            if (isHdr) {
                let d = displayConfigPage.hdrDefaults;
                lines.push(`    sdrbrightness = ${(m.sdrBrightness   ?? d.sdrBrightness).toFixed(3)}`);
                lines.push(`    sdrsaturation = ${(m.sdrSaturation   ?? d.sdrSaturation).toFixed(3)}`);
                lines.push(`    sdr_min_luminance = ${(m.sdrMinLuminance ?? d.sdrMinLuminance).toFixed(4)}`);
                lines.push(`    sdr_max_luminance = ${Math.round(m.sdrMaxLuminance ?? d.sdrMaxLuminance)}`);
                // Only write luminance limits if the user explicitly calibrated them;
                // otherwise let Hyprland infer them from the monitor's EDID.
                let calibrated = displayConfigPage.hdrCalibratedMonitors[name] ?? false;
                if (calibrated) {
                    lines.push(`    min_luminance = ${(m.minLuminance    ?? d.minLuminance).toFixed(4)}`);
                    lines.push(`    max_luminance = ${Math.round(m.maxLuminance    ?? d.maxLuminance)}`);
                    lines.push(`    max_avg_luminance = ${Math.round(m.maxAvgLuminance ?? d.maxAvgLuminance)}`);
                }
                lines.push(`    sdr_eotf = srgb`);
            }
            let icc = m.iccProfile ?? "";
            if (icc && !isHdr)           lines.push(`    icc = ${icc}`);
        }
        lines.push(`}`);
        return lines.join("\n");
    }

    function applyMonitorChanges(monitorName) {
        let m = pendingChanges[monitorName];
        if (!m) return;
        // Build full monitors.conf content from all pending changes
        let blocks = [];
        monitors.forEach(mon => {
            let p = pendingChanges[mon.name] ?? {};
            blocks.push(buildMonitorBlock(mon.name, p, mon));
        });
        // Append workspace-monitor bindings if in custom mode
        if (wsBindingMode === "custom") {
            let wsLines = [];
            for (let ws = 1; ws <= 10; ws++) {
                let assigned = workspaceAssignments[ws];
                if (assigned) wsLines.push(`workspace = ${ws}, monitor:${assigned}`);
            }
            if (wsLines.length > 0) blocks.push(wsLines.join("\n"));
        }
        let fileContent = blocks.join("\n\n") + "\n";
        // Embed content directly in the Python script to avoid argv newline issues
        let escaped = fileContent
            .replace(/\\/g, "\\\\")
            .replace(/'/g, "\\'")
            .replace(/\n/g, "\\n");
        let py =
            "path = '" + displayConfigPage.monitorsConfPath + "'\n" +
            "content = '" + escaped + "'\n" +
            "open(path, 'w').write(content)\n";
        writeProc.command = ["python3", "-c", py];
        writeProc.running = false;
        writeProc.running = true;
    }

    function parseMode(modeStr) {
        let match = modeStr.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
        if (!match) return null;
        return {
            width: parseInt(match[1]),
            height: parseInt(match[2]),
            refreshRate: parseFloat(match[3]),
            label: `${match[1]}x${match[2]} @ ${parseFloat(match[3]).toFixed(2)} Hz`
        };
    }

    function initPending(monitor) {
        let name = monitor.name;
        if (!pendingChanges[name]) {
            let isDefault = name === displayConfigPage.defaultMonitor;
            pendingChanges[name] = {
                width: monitor.width,
                height: monitor.height,
                refreshRate: monitor.refreshRate,
                x: monitor.x,
                y: monitor.y,
                scale: monitor.scale,
                transform: monitor.transform,
                enabled: !monitor.disabled,
                bitdepth: confBitdepth[name] ?? 8,
                vrr: confVrr[name] ?? 0,
                positionMode: isDefault ? undefined : (confPositionMode[name] ?? "auto-center-right"),
                // If hdrMode is "Fullscreen Only" (2), cm=hdr isn't in the config file,
                // but the UI still needs to show HDR as the active color mode.
                colorMode: (confHdrMode[name] === 2 && !confColorMode[name])
                    ? "hdr" : (confColorMode[name] ?? "auto"),
                hdrMode: confHdrMode[name] ?? 0,
                iccProfile: confIccProfile[name] ?? "",
                maxLuminance:    confMaxLuminance[name]    ?? hdrDefaults.maxLuminance,
                maxAvgLuminance: confMaxAvgLuminance[name] ?? hdrDefaults.maxAvgLuminance,
                minLuminance:    confMinLuminance[name]    ?? hdrDefaults.minLuminance,
                sdrMaxLuminance: confSdrMaxLuminance[name] ?? hdrDefaults.sdrMaxLuminance,
                sdrMinLuminance: confSdrMinLuminance[name] ?? hdrDefaults.sdrMinLuminance,
                sdrBrightness:   confSdrBrightness[name]   ?? hdrDefaults.sdrBrightness,
                sdrSaturation:   confSdrSaturation[name]   ?? hdrDefaults.sdrSaturation,
            };
        }
    }

    function currentModeIndex(monitor) {
        let seen = new Set();
        let sorted = [];
        let modes = monitor.availableModes || [];
        modes.forEach(modeStr => {
            let m = parseMode(modeStr);
            if (!m) return;
            let key = `${m.width}x${m.height}@${Math.round(m.refreshRate)}`;
            if (seen.has(key)) return;
            seen.add(key);
            sorted.push(m);
        });
        sorted.sort((a, b) => {
            let pixelDiff = (b.width * b.height) - (a.width * a.height);
            if (pixelDiff !== 0) return pixelDiff;
            return b.refreshRate - a.refreshRate;
        });
        for (let i = 0; i < sorted.length; i++) {
            let m = sorted[i];
            if (m.width === monitor.width &&
                m.height === monitor.height &&
                Math.abs(m.refreshRate - monitor.refreshRate) < 0.1) {
                return i;
            }
        }
        return 0;
    }

    // Resolve the visual canvas position of a monitor, honouring positionMode
    // when it is set to an auto-center-* value.  The default monitor is always
    // at 0×0; every other monitor is placed relative to it.
    function resolveEffectivePos(monName, p, mon) {
        let mode = p.positionMode;
        if (!mode || monName === displayConfigPage.defaultMonitor) {
            return { x: p.x ?? mon.x, y: p.y ?? mon.y };
        }
        // Find the default monitor's pending dimensions
        let defName = displayConfigPage.defaultMonitor;
        let defMon  = displayConfigPage.monitors.find(m => m.name === defName);
        if (!defMon) return { x: p.x ?? mon.x, y: p.y ?? mon.y };
        let dp   = displayConfigPage.pendingChanges[defName] ?? {};
        let defW = dp.width  ?? defMon.width;
        let defH = dp.height ?? defMon.height;
        let thisW = p.width  ?? mon.width;
        let thisH = p.height ?? mon.height;
        switch (mode) {
            case "auto-center-right": return { x: defW,           y: Math.round((defH - thisH) / 2) };
            case "auto-center-left":  return { x: -thisW,         y: Math.round((defH - thisH) / 2) };
            case "auto-center-up":    return { x: Math.round((defW - thisW) / 2), y: -thisH  };
            case "auto-center-down":  return { x: Math.round((defW - thisW) / 2), y: defH    };
            default:                  return { x: p.x ?? mon.x,   y: p.y ?? mon.y };
        }
    }

    // Compute canvas scale factor and offset so all monitors fit
    function canvasLayout(canvasWidth, canvasHeight, padding) {
        if (monitors.length === 0) return { scale: 1, offsetX: 0, offsetY: 0 };

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        monitors.forEach(mon => {
            let p   = pendingChanges[mon.name] ?? {};
            let pos = resolveEffectivePos(mon.name, p, mon);
            let w   = p.width  ?? mon.width;
            let h   = p.height ?? mon.height;
            minX = Math.min(minX, pos.x);
            minY = Math.min(minY, pos.y);
            maxX = Math.max(maxX, pos.x + w);
            maxY = Math.max(maxY, pos.y + h);
        });

        let totalW = maxX - minX;
        let totalH = maxY - minY;
        if (totalW <= 0 || totalH <= 0) return { scale: 1, offsetX: 0, offsetY: 0 };

        let scaleX = (canvasWidth  - padding * 2) / totalW;
        let scaleY = (canvasHeight - padding * 2) / totalH;
        let s = Math.min(scaleX, scaleY);

        let scaledW = totalW * s;
        let scaledH = totalH * s;

        return {
            scale: s,
            offsetX: padding + (canvasWidth  - padding * 2 - scaledW) / 2 - minX * s,
            offsetY: padding + (canvasHeight - padding * 2 - scaledH) / 2 - minY * s
        };
    }

    Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "all", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: data => monitorProc.output += data
        }
        onExited: {
            try {
                let parsed = JSON.parse(monitorProc.output.trim());
                // Ensure a default monitor is always set.
                // If hyprland.conf hasn't been read yet (race), or no cursor block exists,
                // fall back to whichever monitor is at 0x0, or the first monitor.
                if (!displayConfigPage.defaultMonitor ||
                    !parsed.find(m => m.name === displayConfigPage.defaultMonitor)) {
                    let atOrigin = parsed.find(m => m.x === 0 && m.y === 0);
                    displayConfigPage.defaultMonitor = atOrigin
                        ? atOrigin.name
                        : (parsed.length > 0 ? parsed[0].name : "");
                }
                // Sort so default monitor appears first
                parsed.sort((a, b) => {
                    if (a.name === displayConfigPage.defaultMonitor) return -1;
                    if (b.name === displayConfigPage.defaultMonitor) return 1;
                    return 0;
                });
                displayConfigPage.monitors = parsed;
                displayConfigPage.pendingChanges = ({});
                parsed.forEach(m => displayConfigPage.initPending(m));
                // Force reassignment so onPendingChangesChanged fires with fully populated data
                displayConfigPage.pendingChanges = Object.assign({}, displayConfigPage.pendingChanges);
            } catch (e) {
                console.warn("Failed to parse monitor data:", e);
            }
            monitorProc.output = "";
        }
    }

    // Write monitors.conf then reload Hyprland
    Process {
        id: writeProc
        command: []
        onExited: {
            reloadProc.running = false;
            reloadProc.running = true;
        }
    }

    // Write hyprland.conf cursor block (default_monitor)
    Process {
        id: writeHyprlandProc
        command: []
        onExited: {
            reloadProc.running = false;
            reloadProc.running = true;
        }
    }

    // Read hyprland.conf to get current default_monitor
    Process {
        id: readHyprlandConfProc
        command: ["cat", displayConfigPage.hyprlandConfPath]
        property string output: ""
        stdout: SplitParser {
            onRead: data => readHyprlandConfProc.output += data + "\n"
        }
        onExited: {
            let defaultMon = "";
            let inCursorBlock = false;
            readHyprlandConfProc.output.split("\n").forEach(line => {
                if (/^\s*cursor\s*\{/.test(line)) inCursorBlock = true;
                if (inCursorBlock) {
                    let m = line.match(/^\s*default_monitor\s*=\s*(.+?)\s*$/);
                    if (m) defaultMon = m[1];
                }
                if (/^\s*\}/.test(line)) inCursorBlock = false;
            });
            if (defaultMon) {
                displayConfigPage.defaultMonitor = defaultMon;
                // Re-sort monitor list if it was already populated before this proc finished
                if (displayConfigPage.monitors.length > 0) {
                    let sorted = displayConfigPage.monitors.slice().sort((a, b) => {
                        if (a.name === defaultMon) return -1;
                        if (b.name === defaultMon) return 1;
                        return 0;
                    });
                    displayConfigPage.monitors = sorted;
                }
            }
            readHyprlandConfProc.output = "";
        }
    }

    // ── ICC profile management ─────────────────────────────────────────────

    // Ensure ~/.icc-profiles/ exists and scan it for profiles
    Process {
        id: iccScanProc
        property string output: ""
        command: ["bash", "-c",
            `mkdir -p '${displayConfigPage.iccProfileDir}' && ` +
            `find '${displayConfigPage.iccProfileDir}' -maxdepth 1 -type f \\( -iname '*.icc' -o -iname '*.icm' \\) -print0 | ` +
            `xargs -0 -r ls`]
        stdout: SplitParser {
            onRead: data => iccScanProc.output += data + "\n"
        }
        onExited: {
            let profiles = [];
            iccScanProc.output.split("\n").forEach(line => {
                let p = line.trim();
                if (!p) return;
                let filename = p.split("/").pop();
                let name = filename.replace(/\.[^.]+$/, "");
                profiles.push({ name: name, path: p });
            });
            displayConfigPage.iccProfiles = profiles;
            iccScanProc.output = "";
        }
    }

    // Pick a new ICC file using a multi-method fallback chain:
    //   zenity → kdialog → yad → python3 tkinter
    // This avoids the python3-gi / xdg-desktop-portal dependency that caused
    // the original D-Bus implementation to silently fail on many setups.
    Process {
        id: iccPickerProc
        property string targetMonitor: ""
        property string output: ""
        command: ["python3", "-c", `
import subprocess, sys, os

def try_zenity():
    r = subprocess.run(
        ['zenity', '--file-selection',
         '--title=Import ICC Profile',
         '--file-filter=ICC Profiles (*.icc *.icm) | *.icc *.icm'],
        capture_output=True, text=True, timeout=300)
    if r.returncode == 0:
        return r.stdout.strip() or None
    return None

def try_kdialog():
    r = subprocess.run(
        ['kdialog', '--getopenfilename',
         os.path.expanduser('~'), '*.icc *.icm|ICC Profiles'],
        capture_output=True, text=True, timeout=300)
    if r.returncode == 0:
        return r.stdout.strip() or None
    return None

def try_yad():
    r = subprocess.run(
        ['yad', '--file-selection', '--title=Import ICC Profile',
         '--file-filter=*.icc|ICC Profile', '--file-filter=*.icm|ICM Profile'],
        capture_output=True, text=True, timeout=300)
    if r.returncode == 0:
        p = r.stdout.strip().rstrip('|')
        return p or None
    return None

def try_tkinter():
    import tkinter as tk
    from tkinter import filedialog
    root = tk.Tk()
    root.withdraw()
    root.wm_attributes('-topmost', True)
    p = filedialog.askopenfilename(
        title='Import ICC Profile',
        filetypes=[('ICC Profiles', '*.icc *.icm'), ('All Files', '*')])
    root.destroy()
    return p or None

for fn in [try_zenity, try_kdialog, try_yad, try_tkinter]:
    try:
        path = fn()
        if path:
            print(path)
            sys.exit(0)
    except Exception:
        pass
`]
        stdout: SplitParser {
            onRead: data => iccPickerProc.output += data
        }
        stderr: SplitParser {
            onRead: data => console.warn("iccPickerProc stderr:", data)
        }
        onExited: (code) => {
            let src = iccPickerProc.output.trim();
            let mon = iccPickerProc.targetMonitor;
            // Clear state immediately so a quick re-click starts fresh
            iccPickerProc.output = "";
            iccPickerProc.targetMonitor = "";
            if (src !== "" && mon !== "") {
                let filename = src.split("/").pop();
                iccCopyProc.targetMonitor = mon;
                iccCopyProc.destPath = `${displayConfigPage.iccProfileDir}/${filename}`;
                iccCopyProc.command = ["cp", "--", src, iccCopyProc.destPath];
                iccCopyProc.running = false;
                iccCopyProc.running = true;
            }
        }
    }

    // Copy the chosen file then rescan and auto-select it
    Process {
        id: iccCopyProc
        property string targetMonitor: ""
        property string destPath: ""
        command: []
        onExited: (code) => {
            if (code === 0 && iccCopyProc.targetMonitor !== "") {
                displayConfigPage.updatePending(iccCopyProc.targetMonitor, "iccProfile", iccCopyProc.destPath);
            }
            iccCopyProc.targetMonitor = "";
            iccCopyProc.destPath = "";
            // Rescan library
            iccScanProc.running = false;
            iccScanProc.running = true;
        }
    }

    // Delete a profile file (called after user confirms)
    Process {
        id: iccDeleteProc
        property string deletedPath: ""
        property string targetMonitor: ""
        command: []
        onExited: {
            // If the deleted profile was active for any monitor, clear it
            let mon = iccDeleteProc.targetMonitor;
            if (mon) {
                let cur = displayConfigPage.pendingChanges[mon]?.iccProfile ?? "";
                if (cur === iccDeleteProc.deletedPath)
                    displayConfigPage.updatePending(mon, "iccProfile", "");
            }
            iccDeleteProc.deletedPath = "";
            iccDeleteProc.targetMonitor = "";
            iccScanProc.running = false;
            iccScanProc.running = true;
        }
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: displayConfigPage.parseMonitorsConf()
    }

    Component.onCompleted: {
        capabilitiesProc.running = true;
        readHyprlandConfProc.running = true;
        iccScanProc.running = true;
        parseMonitorsConf();
    }

    // ── Arrangement canvas ─────────────────────────────────────────────────
    ContentSection {
        icon: "monitor"
        title: Translation.tr("Display Arrangement")

        // Canvas area
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 220
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal

            // Re-compute layout whenever pendingChanges or size changes
            property var layout: displayConfigPage.canvasLayout(width, height, 16)
            onWidthChanged:  layout = displayConfigPage.canvasLayout(width, height, 16)
            onHeightChanged: layout = displayConfigPage.canvasLayout(width, height, 16)

            Connections {
                target: displayConfigPage
                function onPendingChangesChanged() {
                    canvasContainer.layout = displayConfigPage.canvasLayout(
                        canvasContainer.width, canvasContainer.height, 16);
                }
                function onMonitorsChanged() {
                    canvasContainer.layout = displayConfigPage.canvasLayout(
                        canvasContainer.width, canvasContainer.height, 16);
                }
            }

            id: canvasContainer

            StyledText {
                visible: displayConfigPage.monitors.length === 0
                anchors.centerIn: parent
                text: Translation.tr("No monitors detected")
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: displayConfigPage.monitors

                delegate: Item {
                    id: monRect
                    required property var modelData
                    required property int index

                    property var mon: modelData
                    property string monName: mon.name
                    property var pending: displayConfigPage.pendingChanges[monName] ?? {}
                    property var layout: canvasContainer.layout
                    property color monColor: displayConfigPage.monitorColors[index % displayConfigPage.monitorColors.length]

                    // Position and size on canvas
                    property var effectivePos: displayConfigPage.resolveEffectivePos(monName, pending, mon)
                    x: effectivePos.x * layout.scale + layout.offsetX
                    y: effectivePos.y * layout.scale + layout.offsetY
                    width:  (pending.width  ?? mon.width)  * layout.scale
                    height: (pending.height ?? mon.height) * layout.scale

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(monRect.monColor, (pending.enabled ?? true) ? 0.35 : 0.15)
                        border.color: Qt.alpha(monRect.monColor, 0.8)
                        border.width: 1
                        radius: Appearance.rounding.small

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        // Monitor name
                        StyledText {
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 6
                            }
                            text: monRect.monName
                            font.pixelSize: Math.max(9, Math.min(14, parent.height * 0.16))
                            color: monRect.monColor
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Resolution
                        StyledText {
                            anchors.centerIn: parent
                            text: `${pending.width ?? mon.width}×${pending.height ?? mon.height}`
                            font.pixelSize: Math.max(8, Math.min(12, parent.height * 0.13))
                            color: Appearance.m3colors.m3onSurface
                            opacity: 0.7
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Disabled badge
                        Rectangle {
                            visible: !(pending.enabled ?? true)
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: parent.height * 0.18
                            color: Qt.alpha(Appearance.m3colors.m3error, 0.8)
                            radius: Appearance.rounding.full
                            implicitWidth: disabledLabel.implicitWidth + 8
                            implicitHeight: disabledLabel.implicitHeight + 4
                            StyledText {
                                id: disabledLabel
                                anchors.centerIn: parent
                                text: Translation.tr("OFF")
                                font.pixelSize: 9
                                color: Appearance.m3colors.m3onError
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Use the Position setting under each monitor below to arrange displays")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignRight
            nerdIcon: ""
            mainText: Translation.tr("Refresh")
            onClicked: displayConfigPage.refreshMonitors()
        }
    }

    // ── Per-monitor settings ───────────────────────────────────────────────
    Repeater {
        model: displayConfigPage.monitors

        delegate: ContentSection {
            id: monitorSection
            required property var modelData
            required property int index

            property var mon: modelData
            property string monName: mon.name
            property var pending: displayConfigPage.pendingChanges[monName] ?? {}
            property var availableModes: mon.availableModes || []
            property color monColor: displayConfigPage.monitorColors[index % displayConfigPage.monitorColors.length]

            // Support detection via capabilitiesProc, which:
            //   - Reads HYPR_VRR_ALLOWED / HYPR_10BIT_ALLOWED from env.conf
            //     directly (post-install writes these for known-dangerous hardware)
            //   - Detects the DRM driver and per-connector sysfs capabilities
            //   - Applies env.conf overrides on top of sysfs results
            // Defaults to true when no caps entry exists (hardware not known to
            // be dangerous) so working features are never incorrectly blocked.
            readonly property bool vrrSupported: {
                let caps = displayConfigPage.monitorCapabilities[monitorSection.monName];
                if (caps) return caps.vrr ?? false;
                return true;
            }
            readonly property bool tenBitSupported: {
                let caps = displayConfigPage.monitorCapabilities[monitorSection.monName];
                if (caps) return caps.tenBit ?? false;
                if (mon.supports10bit !== undefined) return mon.supports10bit;
                return true;
            }
            readonly property bool hdrSupported: {
                let caps = displayConfigPage.monitorCapabilities[monitorSection.monName];
                if (caps) return caps.hdr ?? false;
                return false;
            }
            readonly property var supportedColorModes: {
                let modes = [
                    { key: "auto",   label: Translation.tr("Auto")      },
                    { key: "srgb",   label: Translation.tr("sRGB")      },
                    { key: "dcip3",  label: Translation.tr("DCI P3")    },
                    { key: "adobe",  label: Translation.tr("Adobe RGB") },
                    { key: "dp3",    label: Translation.tr("Apple RGB") },
                    { key: "wide",   label: Translation.tr("BT2020")    },
                ];
                if (monitorSection.hdrSupported)
                    modes.push({ key: "hdr", label: Translation.tr("HDR") });
                return modes;
            }

            icon: "tv"
            title: `${mon.name}  —  ${mon.make} ${mon.model}${displayConfigPage.defaultMonitor === mon.name ? " (Default)" : ""}`

            // Enable / disable + Set Default
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                ConfigSwitch {
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Enabled")
                    checked: monitorSection.pending.enabled ?? true
                    onCheckedChanged: displayConfigPage.updatePending(monitorSection.monName, "enabled", checked)
                }

                // Set Default button — lights up with monColor when this is the default
                MouseArea {
                    id: setDefaultArea
                    implicitWidth: 30
                    implicitHeight: 30
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    property bool isDefault: displayConfigPage.defaultMonitor === monitorSection.monName

                    onClicked: displayConfigPage.setDefaultMonitor(monitorSection.monName)

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: setDefaultArea.isDefault
                            ? monitorSection.monColor
                            : (setDefaultArea.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2)
                        border.width: setDefaultArea.isDefault ? 0 : 1
                        border.color: Appearance.colors.colOutlineVariant
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "home"
                            iconSize: Appearance.font.pixelSize.normal
                            color: setDefaultArea.isDefault
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colSubtext
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        StyledToolTip {
                            visible: setDefaultArea.containsMouse
                            text: setDefaultArea.isDefault
                                ? Translation.tr("This is the default monitor (position 0×0)")
                                : Translation.tr("Set as default monitor")
                        }
                    }
                }
            }

            // ── Unified settings card ─────────────────────────────────────
            Rectangle {
                id: settingsCard
                Layout.fillWidth: true
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                implicitHeight: settingsCardCol.implicitHeight

                ColumnLayout {
                    id: settingsCardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 0

                    // ── Row: Mode ──────────────────────────────────────────
                    Item {
                        id: modeRow
                        Layout.fillWidth: true
                        implicitHeight: 44

                        property bool popupOpen: modePopup.visible

                        property var modeModel: {
                            let seen = new Set();
                            let out = [];
                            monitorSection.availableModes.forEach(modeStr => {
                                let m = displayConfigPage.parseMode(modeStr);
                                if (!m) return;
                                let key = `${m.width}x${m.height}@${Math.round(m.refreshRate)}`;
                                if (seen.has(key)) return;
                                seen.add(key);
                                out.push(m);
                            });
                            out.sort((a, b) => {
                                let pd = (b.width * b.height) - (a.width * a.height);
                                return pd !== 0 ? pd : b.refreshRate - a.refreshRate;
                            });
                            return out;
                        }

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: Appearance.rounding.normal
                            topRightRadius: Appearance.rounding.normal
                            color: modeArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Mode")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: {
                                    let p = monitorSection.pending;
                                    let m = monitorSection.mon;
                                    return `${p.width ?? m.width}×${p.height ?? m.height} @ ${(p.refreshRate ?? m.refreshRate).toFixed(2)} Hz`;
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: modeRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: modeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modePopup.visible ? modePopup.close() : modePopup.open()
                        }

                        Popup {
                            id: modePopup
                            y: modeRow.height + 4
                            width: modeRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: modeBg }
                                Rectangle { id: modeBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: Math.min(contentHeight, 300)
                                clip: true
                                spacing: 2
                                model: modeRow.modeModel
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: {
                                        let p = monitorSection.pending;
                                        let m = monitorSection.mon;
                                        return modelData.width === (p.width ?? m.width) &&
                                               modelData.height === (p.height ?? m.height) &&
                                               Math.abs(modelData.refreshRate - (p.refreshRate ?? m.refreshRate)) < 0.1;
                                    }
                                    color: modeDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: modeDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePendingBatch(monitorSection.monName, {
                                                width: modelData.width,
                                                height: modelData.height,
                                                refreshRate: modelData.refreshRate,
                                            });
                                            modePopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                    // ── Row: Scale ─────────────────────────────────────────
                    Item {
                        id: scaleRow
                        Layout.fillWidth: true
                        implicitHeight: 44

                        property bool popupOpen: scalePopup.visible

                        property var scaleOptions: [
                            { label: "100%", value: 1.0   },
                            { label: "125%", value: 1.25  },
                            { label: "150%", value: 1.5   },
                            { label: "167%", value: 5/3   },
                            { label: "188%", value: 1.875 },
                            { label: "200%", value: 2.0   },
                        ]

                        Rectangle {
                            anchors.fill: parent
                            color: scaleArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Scale")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `${Math.round((monitorSection.pending.scale ?? monitorSection.mon.scale) * 100)}%`
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: scaleRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: scaleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: scalePopup.visible ? scalePopup.close() : scalePopup.open()
                        }

                        Popup {
                            id: scalePopup
                            y: scaleRow.height + 4
                            width: scaleRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: scaleBg }
                                Rectangle { id: scaleBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: scaleRow.scaleOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: Math.abs((monitorSection.pending.scale ?? monitorSection.mon.scale) - modelData.value) < 0.001
                                    color: scaleDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: scaleDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePending(monitorSection.monName, "scale", modelData.value);
                                            scalePopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                    // ── Row: Rotation ──────────────────────────────────────
                    Item {
                        id: rotationRow
                        Layout.fillWidth: true
                        implicitHeight: 44

                        property bool popupOpen: rotationPopup.visible

                        property var rotationOptions: [
                            { label: Translation.tr("Landscape"),          value: 0 },
                            { label: Translation.tr("Portrait"),           value: 1 },
                            { label: Translation.tr("Landscape (Flipped)"), value: 2 },
                            { label: Translation.tr("Portrait (Flipped)"), value: 3 },
                        ]

                        property string rotationLabel: {
                            let t = monitorSection.pending.transform ?? monitorSection.mon.transform;
                            let opt = rotationOptions.find(o => o.value === t);
                            return opt ? opt.label : Translation.tr("0°");
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: rotationArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Orientation")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: rotationRow.rotationLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: rotationRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: rotationArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rotationPopup.visible ? rotationPopup.close() : rotationPopup.open()
                        }

                        Popup {
                            id: rotationPopup
                            y: rotationRow.height + 4
                            width: rotationRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: rotBg }
                                Rectangle { id: rotBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: rotationRow.rotationOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: (monitorSection.pending.transform ?? monitorSection.mon.transform) === modelData.value
                                    color: rotDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: rotDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePending(monitorSection.monName, "transform", modelData.value);
                                            rotationPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                    // ── Row: VRR ───────────────────────────────────────────
                    Item {
                        id: vrrRow
                        Layout.fillWidth: true
                        implicitHeight: 44
                        opacity: monitorSection.vrrSupported ? 1.0 : 0.4

                        property bool popupOpen: vrrPopup.visible

                        property var vrrOptions: [
                            { label: Translation.tr("Off"),              value: 0 },
                            { label: Translation.tr("Always On"),        value: 1 },
                            { label: Translation.tr("Fullscreen Only"),  value: 2 },
                        ]

                        property string vrrLabel: {
                            let v = monitorSection.pending.vrr ?? 0;
                            let opt = vrrOptions.find(o => o.value === v);
                            return opt ? opt.label : Translation.tr("Off");
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: (vrrArea.containsMouse && monitorSection.vrrSupported) ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("VRR")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: vrrRow.vrrLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: vrrRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: vrrArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: monitorSection.vrrSupported
                            cursorShape: monitorSection.vrrSupported ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: vrrPopup.visible ? vrrPopup.close() : vrrPopup.open()
                        }

                        StyledToolTip {
                            visible: !monitorSection.vrrSupported
                            text: Translation.tr("VRR is not supported by this display or driver.")
                        }

                        Popup {
                            id: vrrPopup
                            y: vrrRow.height + 4
                            width: vrrRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: vrrBg }
                                Rectangle { id: vrrBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: vrrRow.vrrOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: (monitorSection.pending.vrr ?? 0) === modelData.value
                                    color: vrrDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: vrrDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePending(monitorSection.monName, "vrr", modelData.value);
                                            vrrPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                    // ── Row: 10-bit ────────────────────────────────────────
                    Item {
                        id: tenBitRow
                        Layout.fillWidth: true
                        implicitHeight: 44
                        opacity: monitorSection.tenBitSupported ? 1.0 : 0.4

                        property bool popupOpen: tenBitPopup.visible
                        property bool is10bit: (displayConfigPage.pendingChanges[monitorSection.monName]?.bitdepth ?? 8) === 10

                        property var tenBitOptions: [
                            { label: Translation.tr("Off"), value: false },
                            { label: Translation.tr("On"),  value: true  },
                        ]

                        Rectangle {
                            anchors.fill: parent
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            color: (tenBitArea.containsMouse && monitorSection.tenBitSupported) ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("10-bit")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: tenBitRow.is10bit ? Translation.tr("On") : Translation.tr("Off")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: tenBitRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: tenBitArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: monitorSection.tenBitSupported
                            cursorShape: monitorSection.tenBitSupported ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: tenBitPopup.visible ? tenBitPopup.close() : tenBitPopup.open()
                        }

                        StyledToolTip {
                            visible: !monitorSection.tenBitSupported
                            text: Translation.tr("10-bit colour is not supported by this display or driver.")
                        }

                        Popup {
                            id: tenBitPopup
                            y: tenBitRow.height + 4
                            width: tenBitRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: tenBitBg }
                                Rectangle { id: tenBitBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: tenBitRow.tenBitOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: tenBitRow.is10bit === modelData.value
                                    color: tenBitDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: tenBitDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            let current10bit = (displayConfigPage.pendingChanges[monitorSection.monName]?.bitdepth ?? 8) === 10;
                                            if (current10bit === modelData.value) { tenBitPopup.close(); return; }
                                            displayConfigPage.updatePending(monitorSection.monName, "bitdepth", modelData.value ? 10 : 8);
                                            tenBitPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Position relative to default monitor (hidden for the default monitor itself)
            Item { implicitHeight: 8; visible: positionCard.visible }

            Rectangle {
                id: positionCard
                visible: displayConfigPage.defaultMonitor !== "" &&
                         monitorSection.monName !== displayConfigPage.defaultMonitor
                Layout.fillWidth: true
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                implicitHeight: positionCardCol.implicitHeight

                ColumnLayout {
                    id: positionCardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 0

                    Item {
                        id: positionRow
                        Layout.fillWidth: true
                        implicitHeight: 44

                        property bool popupOpen: positionPopup.visible

                        property var positionOptions: [
                            { label: Translation.tr("To Right of Default Display"), value: "auto-center-right" },
                            { label: Translation.tr("To Left of Default Display"),  value: "auto-center-left"  },
                            { label: Translation.tr("Above Default Display"),       value: "auto-center-up"    },
                            { label: Translation.tr("Below Default Display"),       value: "auto-center-down"  },
                        ]

                        property string positionLabel: {
                            let v = monitorSection.pending.positionMode ?? "auto-center-right";
                            let opt = positionOptions.find(o => o.value === v);
                            return opt ? opt.label : Translation.tr("To Right of Default");
                        }

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: Appearance.rounding.normal
                            topRightRadius: Appearance.rounding.normal
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            color: positionArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Position")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: positionRow.positionLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: positionRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: positionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: positionPopup.visible ? positionPopup.close() : positionPopup.open()
                        }

                        Popup {
                            id: positionPopup
                            y: positionRow.height + 4
                            width: positionRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: posBg }
                                Rectangle { id: posBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: positionRow.positionOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: (monitorSection.pending.positionMode ?? "auto-center-right") === modelData.value
                                    color: posDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: posDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePending(monitorSection.monName, "positionMode", modelData.value);
                                            positionPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Color Management card ─────────────────────────────────────
            Rectangle {
                id: colorMgmtCard
                Layout.fillWidth: true
                Layout.topMargin: 8
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                implicitHeight: colorMgmtCol.implicitHeight
                opacity: (monitorSection.pending.iccProfile ?? "") !== "" ? 0.38 : 1.0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                // Block interaction when ICC profile is active
                MouseArea {
                    anchors.fill: parent
                    enabled: (monitorSection.pending.iccProfile ?? "") !== ""
                    propagateComposedEvents: false
                }

                ColumnLayout {
                    id: colorMgmtCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 0

                    // ── Header ────────────────────────────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                            spacing: 8
                            MaterialSymbol {
                                text: "palette"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Color Management")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                    // ── Color mode pill selector ───────────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 52

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                            spacing: 6

                            Repeater {
                                model: monitorSection.supportedColorModes

                                delegate: MouseArea {
                                    id: cmPillArea
                                    required property var modelData
                                    required property int index
                                    property bool isActive: {
                                        let cm = monitorSection.pending.colorMode ?? "srgb";
                                        // hdredid is a sub-mode of hdr, so the HDR pill stays active
                                        if (modelData.key === "hdr") return cm === "hdr" || cm === "hdredid";
                                        return cm === modelData.key;
                                    }
                                    implicitWidth: cmPill.implicitWidth
                                    implicitHeight: 30
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true

                                    onClicked: {
                                        let updates = { colorMode: modelData.key };
                                        // HDR forces 10-bit and defaults to "Always On" mode
                                        if (modelData.key === "hdr" || modelData.key === "hdredid") {
                                            updates.bitdepth = 10;
                                            if (!(monitorSection.pending.hdrMode > 0))
                                                updates.hdrMode = 1;
                                        }
                                        displayConfigPage.updatePendingBatch(monitorSection.monName, updates);
                                    }

                                    Rectangle {
                                        id: cmPill
                                        anchors.fill: parent
                                        implicitWidth: cmPillTxt.implicitWidth + 20
                                        radius: Appearance.rounding.small
                                        color: cmPillArea.isActive
                                            ? monitorSection.monColor
                                            : (cmPillArea.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2)
                                        border.width: cmPillArea.isActive ? 0 : 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        StyledText {
                                            id: cmPillTxt
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: cmPillArea.isActive
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    // ── HDR activation dropdown (HDR-capable monitors only) ─
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.m3colors.m3outlineVariant
                        opacity: 0.5
                        visible: { let cm = monitorSection.pending.colorMode ?? "srgb"; return cm === "hdr" || cm === "hdredid"; }
                    }

                    Item {
                        id: hdrModeRow
                        Layout.fillWidth: true
                        implicitHeight: 44
                        visible: { let cm = monitorSection.pending.colorMode ?? "srgb"; return cm === "hdr" || cm === "hdredid"; }

                        property bool popupOpen: hdrModePopup.visible
                        property var hdrModeOptions: [
                            { label: Translation.tr("Always On"),      value: 1 },
                            { label: Translation.tr("Fullscreen Only"), value: 2 },
                        ]
                        property string hdrModeLabel: {
                            let v = monitorSection.pending.hdrMode || 1;
                            let opt = hdrModeOptions.find(o => o.value === v);
                            return opt ? opt.label : Translation.tr("Always On");
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: hdrModeArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("HDR Mode")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: hdrModeRow.hdrModeLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: hdrModeRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: hdrModeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: hdrModePopup.visible ? hdrModePopup.close() : hdrModePopup.open()
                        }

                        Popup {
                            id: hdrModePopup
                            y: hdrModeRow.height + 4
                            width: hdrModeRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: hdrModeBg }
                                Rectangle { id: hdrModeBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: hdrModeRow.hdrModeOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: (monitorSection.pending.hdrMode || 1) === modelData.value
                                    color: hdrModeDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: hdrModeDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePendingBatch(monitorSection.monName, {
                                                hdrMode: modelData.value,
                                                bitdepth: 10,  // force 10-bit for HDR
                                            });
                                            hdrModePopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Use EDID dropdown ─────────────────────────────────
                    Item {
                        id: edidRow
                        Layout.fillWidth: true
                        implicitHeight: 44
                        visible: {
                            let cm = monitorSection.pending.colorMode ?? "srgb";
                            return cm === "hdr" || cm === "hdredid";
                        }

                        property bool popupOpen: edidPopup.visible
                        property var edidOptions: [
                            { label: Translation.tr("No"),  value: "hdr" },
                            { label: Translation.tr("Yes"), value: "hdredid" },
                        ]
                        property string edidLabel: {
                            let cm = monitorSection.pending.colorMode ?? "srgb";
                            return cm === "hdredid" ? Translation.tr("Yes") : Translation.tr("No");
                        }

                        property bool isFullscreenOnly: (monitorSection.pending.hdrMode || 1) === 2
                        opacity: isFullscreenOnly ? 0.38 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Rectangle {
                            anchors.fill: parent
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            color: edidArea.containsMouse && !edidRow.isFullscreenOnly ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            StyledText {
                                text: Translation.tr("Use EDID")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: edidRow.edidLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: edidRow.popupOpen ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: edidArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !edidRow.isFullscreenOnly
                            cursorShape: edidRow.isFullscreenOnly ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: edidPopup.visible ? edidPopup.close() : edidPopup.open()
                        }

                        Popup {
                            id: edidPopup
                            y: edidRow.height + 4
                            width: edidRow.width
                            padding: 8
                            enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            background: Item {
                                StyledRectangularShadow { target: edidBg }
                                Rectangle { id: edidBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                spacing: 2
                                model: edidRow.edidOptions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: ListView.view.width
                                    height: 36
                                    radius: Appearance.rounding.small
                                    property bool isCurrent: (monitorSection.pending.colorMode ?? "srgb") === modelData.value
                                    color: edidDelegate.containsMouse
                                        ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                        : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                    StyledText {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                    }
                                    MouseArea {
                                        id: edidDelegate
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            displayConfigPage.updatePending(monitorSection.monName, "colorMode", modelData.value);
                                            edidPopup.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            }

            // ── Fine Tune card (separate from Color Management) ──────────
            Rectangle {
                id: fineTuneCard
                Layout.fillWidth: true
                Layout.topMargin: 8
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                visible: {
                    let cm = monitorSection.pending.colorMode ?? "srgb";
                    return cm === "hdr" || cm === "hdredid";
                }
                implicitHeight: fineTuneCol.implicitHeight

                ColumnLayout {
                    id: fineTuneCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 0

                    // ── Fine Tune dropdown header ─────────────────────────
                    Item {
                        id: fineTuneHeader
                        Layout.fillWidth: true
                        implicitHeight: 44

                        property bool expanded: false

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius:     Appearance.rounding.normal
                            topRightRadius:    Appearance.rounding.normal
                            bottomLeftRadius:  fineTuneHeader.expanded ? 0 : Appearance.rounding.normal
                            bottomRightRadius: fineTuneHeader.expanded ? 0 : Appearance.rounding.normal
                            color: fineTuneTitleArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                            spacing: 8
                            MaterialSymbol {
                                text: "sliders"
                                iconSize: Appearance.font.pixelSize.larger
                                color: monitorSection.monColor
                            }
                            StyledText {
                                text: Translation.tr("Fine Tune")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            Item { Layout.fillWidth: true }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: fineTuneHeader.expanded ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                            }
                        }

                        MouseArea {
                            id: fineTuneTitleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fineTuneHeader.expanded = !fineTuneHeader.expanded
                        }
                    }

                    // ── Fine-tune: SDR category header ────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: visible ? 32 : 0
                        visible: fineTuneHeader.expanded && fineTuneHeader.visible
                        clip: true
                        opacity: (monitorSection.pending.hdrMode || 1) === 2 ? 0.38 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on implicitHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            implicitHeight: 1
                            color: Appearance.m3colors.m3outlineVariant
                            opacity: 0.5
                        }
                        StyledText {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                            text: Translation.tr("SDR")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // ── SDR sliders ────────────────────────────────────────
                    Repeater {
                        model: [
                            { label: Translation.tr("SDR Brightness"),        prop: "sdrBrightness",   minV: 0.5, maxV: 3.0, step: 0.01,  dec: 3 },
                            { label: Translation.tr("SDR Saturation"),        prop: "sdrSaturation",   minV: 0.5, maxV: 2.0, step: 0.01,  dec: 3 },
                            { label: Translation.tr("SDR Minimum Luminance"), prop: "sdrMinLuminance", minV: 0.0, maxV: 0.1, step: 0.001, dec: 4 },
                            { label: Translation.tr("SDR Max Luminance"),     prop: "sdrMaxLuminance", minV: 80,  maxV: 1000, step: 5,     dec: 0 },
                        ]
                        delegate: Item {
                            id: sdrSliderRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: visible ? 44 : 0
                            visible: fineTuneHeader.expanded && fineTuneHeader.visible
                            clip: true
                            opacity: (monitorSection.pending.hdrMode || 1) === 2 ? 0.38 : 1.0
                            enabled: (monitorSection.pending.hdrMode || 1) !== 2
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on implicitHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            Rectangle {
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                implicitHeight: 1
                                color: Appearance.m3colors.m3outlineVariant
                                opacity: 0.25
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                                spacing: 10
                                StyledText {
                                    text: sdrSliderRow.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                    Layout.minimumWidth: 172
                                }
                                Slider {
                                    id: sdrFineSlider
                                    Layout.fillWidth: true
                                    from:     sdrSliderRow.modelData.minV
                                    to:       sdrSliderRow.modelData.maxV
                                    stepSize: sdrSliderRow.modelData.step
                                    value: {
                                        let p = monitorSection.pending;
                                        let prop = sdrSliderRow.modelData.prop;
                                        return p[prop] ?? displayConfigPage.hdrDefaults[prop] ?? 0;
                                    }
                                    onMoved: displayConfigPage.updatePending(monitorSection.monName, sdrSliderRow.modelData.prop, value)
                                    background: Rectangle {
                                        x: sdrFineSlider.leftPadding
                                        y: sdrFineSlider.topPadding + sdrFineSlider.availableHeight / 2 - height / 2
                                        width: sdrFineSlider.availableWidth; height: 3; radius: 2
                                        color: Appearance.colors.colLayer3
                                        Rectangle {
                                            width: sdrFineSlider.visualPosition * parent.width
                                            height: parent.height; radius: 2
                                            color: monitorSection.monColor
                                        }
                                    }
                                    handle: Rectangle {
                                        x: sdrFineSlider.leftPadding + sdrFineSlider.visualPosition * (sdrFineSlider.availableWidth - width)
                                        y: sdrFineSlider.topPadding + sdrFineSlider.availableHeight / 2 - height / 2
                                        width: 14; height: 14; radius: 7
                                        color: sdrFineSlider.pressed ? Qt.lighter(monitorSection.monColor, 1.2) : monitorSection.monColor
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }
                                }
                                StyledText {
                                    text: {
                                        let p = monitorSection.pending;
                                        let prop = sdrSliderRow.modelData.prop;
                                        return (p[prop] ?? displayConfigPage.hdrDefaults[prop] ?? 0).toFixed(sdrSliderRow.modelData.dec);
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: "monospace"
                                    color: Appearance.colors.colSubtext
                                    horizontalAlignment: Text.AlignRight
                                    Layout.minimumWidth: 56
                                }
                            }
                        }
                    }

                    // ── Fine-tune: HDR category header ────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: visible ? 32 : 0
                        visible: fineTuneHeader.expanded && fineTuneHeader.visible
                        clip: true
                        Behavior on implicitHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            implicitHeight: 1
                            color: Appearance.m3colors.m3outlineVariant
                            opacity: 0.5
                        }
                        StyledText {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                            text: Translation.tr("HDR")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // ── HDR sliders ────────────────────────────────────────
                    Repeater {
                        model: [
                            { label: Translation.tr("HDR Minimum Luminance"), prop: "minLuminance",    minV: 0.0, maxV: 0.5,  step: 0.001, dec: 4 },
                            { label: Translation.tr("HDR Maximum Luminance"), prop: "maxLuminance",    minV: 100, maxV: 2000, step: 10,    dec: 0 },
                            { label: Translation.tr("HDR Average Luminance"), prop: "maxAvgLuminance", minV: 100, maxV: 1600, step: 10,    dec: 0 },
                        ]
                        delegate: Item {
                            id: hdrSliderRow
                            required property var modelData
                            required property int index
                            property bool isLast: index === 2
                            Layout.fillWidth: true
                            implicitHeight: visible ? 44 : 0
                            visible: fineTuneHeader.expanded && fineTuneHeader.visible
                            clip: true
                            Behavior on implicitHeight { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                            Rectangle {
                                anchors.fill: parent
                                bottomLeftRadius:  hdrSliderRow.isLast ? Appearance.rounding.normal : 0
                                bottomRightRadius: hdrSliderRow.isLast ? Appearance.rounding.normal : 0
                                color: "transparent"
                            }
                            Rectangle {
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                implicitHeight: 1
                                color: Appearance.m3colors.m3outlineVariant
                                opacity: 0.25
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                                spacing: 10
                                StyledText {
                                    text: hdrSliderRow.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                    Layout.minimumWidth: 172
                                }
                                Slider {
                                    id: hdrFineSlider
                                    Layout.fillWidth: true
                                    from:     hdrSliderRow.modelData.minV
                                    to:       hdrSliderRow.modelData.maxV
                                    stepSize: hdrSliderRow.modelData.step
                                    value: {
                                        let p = monitorSection.pending;
                                        let prop = hdrSliderRow.modelData.prop;
                                        return p[prop] ?? displayConfigPage.hdrDefaults[prop] ?? 0;
                                    }
                                    onMoved: displayConfigPage.updatePending(monitorSection.monName, hdrSliderRow.modelData.prop, value)
                                    background: Rectangle {
                                        x: hdrFineSlider.leftPadding
                                        y: hdrFineSlider.topPadding + hdrFineSlider.availableHeight / 2 - height / 2
                                        width: hdrFineSlider.availableWidth; height: 3; radius: 2
                                        color: Appearance.colors.colLayer3
                                        Rectangle {
                                            width: hdrFineSlider.visualPosition * parent.width
                                            height: parent.height; radius: 2
                                            color: monitorSection.monColor
                                        }
                                    }
                                    handle: Rectangle {
                                        x: hdrFineSlider.leftPadding + hdrFineSlider.visualPosition * (hdrFineSlider.availableWidth - width)
                                        y: hdrFineSlider.topPadding + hdrFineSlider.availableHeight / 2 - height / 2
                                        width: 14; height: 14; radius: 7
                                        color: hdrFineSlider.pressed ? Qt.lighter(monitorSection.monColor, 1.2) : monitorSection.monColor
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }
                                }
                                StyledText {
                                    text: {
                                        let p = monitorSection.pending;
                                        let prop = hdrSliderRow.modelData.prop;
                                        return (p[prop] ?? displayConfigPage.hdrDefaults[prop] ?? 0).toFixed(hdrSliderRow.modelData.dec);
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: "monospace"
                                    color: Appearance.colors.colSubtext
                                    horizontalAlignment: Text.AlignRight
                                    Layout.minimumWidth: 56
                                }
                            }
                        }
                    }
                }
            }

            // ── Calibrate Monitor for HDR card ───────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 8
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                implicitHeight: 52
                visible: {
                    let cm = monitorSection.pending.colorMode ?? "srgb";
                    return cm === "hdr" || cm === "hdredid";
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: calibrateArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 10

                    MaterialSymbol {
                        text: "tune"
                        iconSize: Appearance.font.pixelSize.larger
                        color: monitorSection.monColor
                    }
                    StyledText {
                        text: Translation.tr("Calibrate Monitor for HDR")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                        Layout.fillWidth: true
                    }
                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    id: calibrateArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        hdrCalLoader.active = false;
                        hdrCalLoader.active = true;
                    }
                }
            }

            // ── HDR Calibration window loader ─────────────────────────────
            Loader {
                id: hdrCalLoader
                active: false
                source: "HdrCalibration.qml"
                onLoaded: {
                    let p = displayConfigPage.pendingChanges[monitorSection.monName] ?? {};
                    item.monitorName        = monitorSection.monName;
                    item.fullscreenOnly     = (monitorSection.pending.hdrMode || 1) === 2;
                    let d = displayConfigPage.hdrDefaults;
                    item.valMaxLuminance    = p.maxLuminance    ?? d.maxLuminance;
                    item.valMaxAvgLuminance = p.maxAvgLuminance ?? d.maxAvgLuminance;
                    item.valMinLuminance    = p.minLuminance    ?? d.minLuminance;
                    item.valSdrMaxLuminance = p.sdrMaxLuminance ?? d.sdrMaxLuminance;
                    item.valSdrMinLuminance = p.sdrMinLuminance ?? d.sdrMinLuminance;
                    item.valSdrBrightness   = p.sdrBrightness   ?? d.sdrBrightness;
                    item.valSdrSaturation   = p.sdrSaturation   ?? d.sdrSaturation;
                    // Pass previous values for review comparison (null if never calibrated)
                    let isCal = displayConfigPage.hdrCalibratedMonitors[monitorSection.monName] ?? false;
                    item.previousValues = isCal ? {
                        maxLuminance:    p.maxLuminance    ?? d.maxLuminance,
                        maxAvgLuminance: p.maxAvgLuminance ?? d.maxAvgLuminance,
                        minLuminance:    p.minLuminance    ?? d.minLuminance,
                        sdrMaxLuminance: p.sdrMaxLuminance ?? d.sdrMaxLuminance,
                        sdrMinLuminance: p.sdrMinLuminance ?? d.sdrMinLuminance,
                        sdrBrightness:   p.sdrBrightness   ?? d.sdrBrightness,
                        sdrSaturation:   p.sdrSaturation   ?? d.sdrSaturation,
                    } : null;
                    item.done.connect(function(values) {
                        displayConfigPage.updatePendingBatch(monitorSection.monName, values);
                        // Mark this monitor as calibrated so fine-tune sliders appear
                        let cal = Object.assign({}, displayConfigPage.hdrCalibratedMonitors);
                        cal[monitorSection.monName] = true;
                        displayConfigPage.hdrCalibratedMonitors = cal;
                        // Auto-apply: write to monitors.conf and reload Hyprland
                        displayConfigPage.applyMonitorChanges(monitorSection.monName);
                        hdrCalLoader.active = false;
                    });
                    item.cancelled.connect(function() { hdrCalLoader.active = false; });
                    item.showFullScreen();
                }
            }

            // ── ICC Profile card (disabled — to be re-enabled later) ─────
            /* Rectangle {
                id: iccCard
                Layout.fillWidth: true
                Layout.topMargin: 8
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.normal
                clip: true
                implicitHeight: iccCardCol.implicitHeight

                ColumnLayout {
                    id: iccCardCol
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 0

                    // ── Header row with Add button ────────────────────────
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 52

                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: Appearance.rounding.normal
                            topRightRadius: Appearance.rounding.normal
                            color: iccImportArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                            spacing: 10

                            MaterialSymbol {
                                text: "upload_file"
                                iconSize: Appearance.font.pixelSize.larger
                                color: monitorSection.monColor
                            }
                            StyledText {
                                text: Translation.tr("Import ICC Profile")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }

                            // Tooltip badge — to the right of the text
                            MouseArea {
                                id: iccInfoArea
                                implicitWidth: 22
                                implicitHeight: 22
                                hoverEnabled: true
                                cursorShape: Qt.ArrowCursor

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "info"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                                StyledToolTip {
                                    visible: iccInfoArea.containsMouse
                                    text: Translation.tr("An active ICC profile disables all other color management")
                                }
                            }

                            Item { Layout.fillWidth: true }

                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                        }

                        MouseArea {
                            id: iccImportArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                iccPickerProc.targetMonitor = monitorSection.monName;
                                iccPickerProc.running = false;
                                iccPickerProc.running = true;
                            }
                        }
                    }

                    // ── Profile list ──────────────────────────────────────
                    Repeater {
                        model: displayConfigPage.iccProfiles

                        delegate: Item {
                            id: iccProfileRow
                            required property var modelData
                            required property int index

                            property bool isActive: monitorSection.pending.iccProfile === modelData.path
                            property bool isLast: index === displayConfigPage.iccProfiles.length - 1

                            Layout.fillWidth: true
                            implicitWidth: parent ? parent.width : 0
                            implicitHeight: 40

                            // Delete confirmation state
                            property bool confirmingDelete: false

                            Rectangle {
                                anchors.fill: parent
                                topLeftRadius: 0
                                topRightRadius: 0
                                bottomLeftRadius: iccProfileRow.isLast ? Appearance.rounding.normal : 0
                                bottomRightRadius: iccProfileRow.isLast ? Appearance.rounding.normal : 0
                                color: iccRowHover.containsMouse && !iccProfileRow.confirmingDelete
                                    ? Appearance.colors.colLayer3 : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                implicitHeight: 1
                                color: Appearance.m3colors.m3outlineVariant
                                opacity: 0.5
                            }

                            // Normal row content
                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                spacing: 8
                                visible: !iccProfileRow.confirmingDelete

                                // Radio indicator
                                MouseArea {
                                    id: iccRowHover
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: displayConfigPage.updatePending(monitorSection.monName, "iccProfile", iccProfileRow.isActive ? "" : iccProfileRow.modelData.path)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        radius: 8
                                        color: "transparent"
                                        border.width: 2
                                        border.color: iccProfileRow.isActive
                                            ? monitorSection.monColor
                                            : Appearance.colors.colOutlineVariant
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 8; height: 8
                                            radius: 4
                                            color: monitorSection.monColor
                                            visible: iccProfileRow.isActive
                                        }
                                    }
                                }

                                // Profile name — clicking also toggles
                                StyledText {
                                    text: iccProfileRow.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: iccProfileRow.isActive
                                        ? monitorSection.monColor
                                        : Appearance.colors.colOnLayer2
                                    Layout.fillWidth: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: displayConfigPage.updatePending(monitorSection.monName, "iccProfile", iccProfileRow.isActive ? "" : iccProfileRow.modelData.path)
                                    }
                                }

                                // Delete button
                                MouseArea {
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: iccProfileRow.confirmingDelete = true
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "remove"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            // Confirmation row
                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                spacing: 8
                                visible: iccProfileRow.confirmingDelete

                                MaterialSymbol {
                                    text: "warning"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.m3colors.m3error
                                }
                                StyledText {
                                    text: Translation.tr("Delete \"%1\"?").arg(iccProfileRow.modelData?.name ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                    Layout.fillWidth: true
                                }
                                // Confirm delete
                                MouseArea {
                                    implicitWidth: 52
                                    implicitHeight: 24
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        let path = iccProfileRow.modelData.path;
                                        iccDeleteProc.deletedPath = path;
                                        iccDeleteProc.targetMonitor = monitorSection.monName;
                                        iccDeleteProc.command = ["rm", "--", path];
                                        iccDeleteProc.running = false;
                                        iccDeleteProc.running = true;
                                        iccProfileRow.confirmingDelete = false;
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Appearance.rounding.small
                                        color: Appearance.m3colors.m3error
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: Translation.tr("Delete")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3onError
                                        }
                                    }
                                }
                                // Cancel
                                MouseArea {
                                    implicitWidth: 52
                                    implicitHeight: 24
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: iccProfileRow.confirmingDelete = false
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer3
                                        border.width: 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        StyledText {
                                            anchors.centerIn: parent
                                            text: Translation.tr("Cancel")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        visible: displayConfigPage.iccProfiles.length === 0

                        Rectangle {
                            anchors.fill: parent
                            bottomLeftRadius: Appearance.rounding.normal
                            bottomRightRadius: Appearance.rounding.normal
                            color: "transparent"
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            implicitHeight: 1
                            color: Appearance.m3colors.m3outlineVariant
                            opacity: 0.5
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("No profiles imported")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            } */
            ContentSubsection {
                id: wsSubsection
                visible: displayConfigPage.monitors.length > 1
                title: Translation.tr("Workspaces")
                tooltip: Translation.tr("Assign workspaces to this monitor")

                // How many 10-workspace rows this monitor currently shows
                property int rowCount: displayConfigPage.wsRowCounts[monitorSection.monName] ?? 1

                function setRowCount(n) {
                    let rc = Object.assign({}, displayConfigPage.wsRowCounts);
                    rc[monitorSection.monName] = Math.max(1, n);
                    displayConfigPage.wsRowCounts = rc;
                }

                // Clear workspace assignments for a range when a row is removed
                function clearRowAssignments(rowIndex) {
                    let a = Object.assign({}, displayConfigPage.workspaceAssignments);
                    let start = rowIndex * 10 + 1;
                    let end   = rowIndex * 10 + 10;
                    for (let ws = start; ws <= end; ws++) delete a[ws];
                    displayConfigPage.workspaceAssignments = a;
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    // Dynamic workspace rows — row 0 shares its line with the Custom pill
                    Repeater {
                        model: wsSubsection.rowCount

                        delegate: RowLayout {
                            id: wsRow
                            required property int index
                            Layout.fillWidth: true
                            spacing: 4

                            property int rowIndex: index
                            property bool isLastRow: rowIndex === wsSubsection.rowCount - 1

                            // Custom mode toggle — only shown on the first row, inline with pills
                            MouseArea {
                                visible: wsRow.rowIndex === 0
                                implicitWidth: customPill.implicitWidth
                                implicitHeight: 26
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (displayConfigPage.wsBindingMode === "custom") {
                                        displayConfigPage.wsBindingMode = "default";
                                        displayConfigPage.clearAllAssignments();
                                    } else {
                                        displayConfigPage.wsBindingMode = "custom";
                                    }
                                }
                                readonly property bool active: displayConfigPage.wsBindingMode === "custom"

                                Rectangle {
                                    id: customPill
                                    anchors.fill: parent
                                    implicitWidth: customPillTxt.implicitWidth + 16
                                    radius: Appearance.rounding.small
                                    color: parent.active
                                        ? Appearance.colors.colPrimary
                                        : (parent.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2)
                                    border.width: parent.active ? 0 : 1
                                    border.color: Appearance.colors.colOutlineVariant
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    StyledText {
                                        id: customPillTxt
                                        anchors.centerIn: parent
                                        text: Translation.tr("Custom")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: parent.parent.active
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            // 10 numbered pills for this row
                            Repeater {
                                model: 10
                                delegate: MouseArea {
                                    id: wsPillArea
                                    required property int index
                                    property int wsNum: wsRow.rowIndex * 10 + index + 1
                                    property bool assigned: displayConfigPage.workspaceAssignments[wsNum] === monitorSection.monName
                                    property string assignedTo: displayConfigPage.workspaceAssignments[wsNum] ?? ""
                                    property bool takenByOther: assignedTo !== "" && assignedTo !== monitorSection.monName
                                    property bool isCustom: displayConfigPage.wsBindingMode === "custom"

                                    implicitWidth: wsPill.implicitWidth
                                    implicitHeight: 26
                                    cursorShape: isCustom ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: isCustom

                                    onClicked: {
                                        if (isCustom) displayConfigPage.assignWorkspace(wsNum, monitorSection.monName);
                                    }

                                    Rectangle {
                                        id: wsPill
                                        anchors.fill: parent
                                        implicitWidth: Math.max(26, wsPillTxt.implicitWidth + 12)
                                        radius: Appearance.rounding.small
                                        color: {
                                            if (!wsPillArea.isCustom) return Appearance.colors.colLayer2;
                                            if (wsPillArea.assigned) return monitorSection.monColor;
                                            if (wsPillArea.takenByOther) return Appearance.colors.colLayer2;
                                            return wsPillArea.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2;
                                        }
                                        border.width: wsPillArea.assigned ? 0 : 1
                                        border.color: Appearance.colors.colOutlineVariant
                                        opacity: {
                                            if (!wsPillArea.isCustom) return 0.35;
                                            if (wsPillArea.takenByOther) return 0.35;
                                            return 1.0;
                                        }
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on opacity { NumberAnimation { duration: 150 } }

                                        StyledText {
                                            id: wsPillTxt
                                            anchors.centerIn: parent
                                            text: String(wsPillArea.wsNum)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: wsPillArea.assigned
                                                ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }

                            // Remove row button — shown on every row after the first
                            MouseArea {
                                visible: wsRow.isLastRow && wsRow.rowIndex > 0
                                implicitWidth: 26
                                implicitHeight: 26
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // Only remove if this is the last row (can only remove from the end)
                                    if (wsRow.isLastRow) {
                                        wsSubsection.clearRowAssignments(wsRow.rowIndex);
                                        wsSubsection.setRowCount(wsSubsection.rowCount - 1);
                                    }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.small
                                    color: parent.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "remove"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }

                            // Add row button — only shown on the last row
                            MouseArea {
                                visible: wsRow.isLastRow
                                implicitWidth: 26
                                implicitHeight: 26
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wsSubsection.setRowCount(wsSubsection.rowCount + 1)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.small
                                    color: parent.containsMouse ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant
                                    Behavior on color { ColorAnimation { duration: 100 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "add"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Apply button — standalone row, clearly separated from workspace assignment
            Item { implicitHeight: 4 }

            RowLayout {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitHeight: 30
                    implicitWidth: 140
                    colBackground: monitorSection.monColor
                    colBackgroundHover: Qt.lighter(monitorSection.monColor, 1.1)
                    colRipple: Qt.lighter(monitorSection.monColor, 1.2)

                    contentItem: StyledText {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Apply %1").arg(monitorSection.monName)
                        color: Appearance.colors.colOnPrimary
                    }

                    onClicked: displayConfigPage.applyMonitorChanges(monitorSection.monName)
                }
            }
        }
    }
}
