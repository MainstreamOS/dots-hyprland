pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * SystemKernels: the kernels Settings installs and removes, and which kernel
 * the boot menu starts next. Shown in Settings > Gaming.
 *
 * scripts/security/kernel-status.sh reads unprivileged system state. Every
 * change runs through /usr/lib/mainstream/mainstream-kernels via pkexec.
 * Results are shown through SystemSecurity, whose messages the sections of
 * the page share.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/security/kernel-status.sh")
    readonly property string helperPath: "/usr/lib/mainstream/mainstream-kernels"
    readonly property string mockEnv: String(Quickshell.env("QS_KERNELS_MOCK_JSON") ?? "").trim()
    readonly property string messageScope: "kernel"

    readonly property string standardKernel: "linux"
    readonly property string eacKernel: "mainstream-performance-eac"

    property bool loaded: false
    // The last probe gave no usable answer. What was read before stays.
    property bool probeFailed: false
    property string unsupportedReason: ""
    property bool helper: false
    // Whether the helper installs and removes the standard kernel too. Older
    // ones refuse it.
    property bool canChangeStandard: false
    // Whether the helper knows Mainstream's kernels by their package names today.
    // Older ones know only the names the packages had before.
    property bool canUseNewNames: false
    // Whether the helper knows the anti-cheat kernel.
    property bool canUseEac: false
    property bool uefi: false
    // -1 while not known. Only root can read most EFI partitions, so the size
    // of the boot image is often not known here and the helper checks it.
    property real espFreeBytes: -1
    property real standardImageBytes: -1
    // The kernel the boot menu starts next, when the firmware's record of it
    // can be read, and whether that record can be changed from here.
    property string nextKernel: ""
    property bool canChooseNext: false
    // One entry per kernel, as the probe prints them.
    property var kernels: []
    // The package of every kernel this system can start, linux-lts and the
    // like included, as the helper counts them before a removal.
    property var installedKernels: []

    readonly property var unknownKernel: ({
        name: "",
        package: "",
        installed: false,
        version: "",
        running: false,
        available: false,
        cpuSupported: true,
        downloadBytes: -1,
        driverMissing: false,
        driverUnsupported: false
    })

    function info(name) {
        for (const kernel of root.kernels) {
            if (kernel.name === name)
                return kernel;
        }
        return root.unknownKernel;
    }

    // The helper refuses to remove the last kernel.
    function othersInstalled(name) {
        return root.installedKernels.some(base => base !== name);
    }

    function label(name) {
        switch (name) {
        case "linux":
            return Translation.tr("Standard");
        case "mainstream":
            return Translation.tr("Mainstream");
        case "mainstream-performance":
            return Translation.tr("Mainstream Performance");
        case "mainstream-performance-eac":
            return Translation.tr("Mainstream Anti-Cheat");
        default:
            return name;
        }
    }

    readonly property string unsupportedText: {
        switch (root.unsupportedReason) {
        case "":
            return "";
        case "snapshot":
            return Translation.tr("You started this session from a snapshot. Restart into the installed system to change these settings.");
        case "boot-tools":
            return Translation.tr("These settings need Mainstream's Limine boot tools, which this system does not use.");
        default:
            return Translation.tr("These settings cannot be changed on this system.");
        }
    }

    // A kernel takes its boot image twice, since the snapshot tooling keeps a
    // copy, and 32 MiB stays free. The helper refuses below the same line.
    readonly property bool roomShort: root.espFreeBytes >= 0 && root.standardImageBytes > 0
        && root.espFreeBytes < root.standardImageBytes * 2 + 32 * 1048576

    readonly property bool stateKnown: root.loaded && !root.probeFailed
    readonly property bool canChange: root.stateKnown && root.helper && !root.busy
        && !SystemSecurity.busy && root.unsupportedReason === ""
    readonly property string pendingPill: root.probeFailed ? Translation.tr("Unknown") : Translation.tr("Checking…")

    // Kept here so it survives the page being rebuilt on a theme change.
    // "install" | "remove" | "next" | ""
    property string busyAction: ""
    property string busyKernel: ""
    readonly property bool busy: root.busyAction !== ""

    // Closing Settings while the helper runs would cut a change short.
    property bool closeRefused: false
    onBusyChanged: {
        if (!root.busy)
            root.closeRefused = false;
    }

    signal actionSucceeded(string action, string kernel)

    property int watchers: 0

    function watch() {
        root.watchers += 1;
        if (root.watchers === 1)
            root.refresh(true);
    }

    function unwatch() {
        root.watchers = Math.max(0, root.watchers - 1);
    }

    // Set by Settings while its window is not the active one.
    property bool paused: false
    onPausedChanged: {
        if (!root.paused && root.watchers > 0)
            root.refresh(false);
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.watchers > 0 && !root.busy && !root.paused && root.mockEnv.length === 0
        onTriggered: root.refresh(false)
    }

    property string lastStatus: ""
    property bool forceApply: false
    property bool refreshQueued: false
    property bool statusBusy: false
    property int generation: 0

    function refresh(force) {
        if (force)
            root.forceApply = true;
        if (root.mockEnv.length > 0 && root.mockEnv.startsWith("{")) {
            root.applyStatus(root.mockEnv);
            return;
        }
        if (root.statusBusy) {
            root.refreshQueued = true;
            return;
        }
        root.statusBusy = true;
        statusProc.startedAt = root.generation;
        statusProc.command = root.mockEnv.length > 0
            ? ["cat", "--", root.mockEnv]
            : ["bash", root.scriptPath];
        statusProc.running = true;
    }

    Process {
        id: statusProc
        property int startedAt: 0
        stdout: StdioCollector {
            id: statusOut
        }
        onExited: root.statusFinished()
    }

    function statusFinished() {
        root.statusBusy = false;
        if (statusProc.startedAt === root.generation)
            root.applyStatus(statusOut.text);
        else
            root.refreshQueued = true;
        if (root.refreshQueued) {
            root.refreshQueued = false;
            Qt.callLater(() => root.refresh(false));
        }
    }

    function parseJson(text) {
        try {
            return JSON.parse(String(text ?? "").trim());
        } catch (e) {
            return null;
        }
    }

    function bytesOrUnknown(value) {
        return typeof value === "number" && value >= 0 ? value : -1;
    }

    function applyStatus(text) {
        const force = root.forceApply;
        root.forceApply = false;
        if (!force && root.loaded && text === root.lastStatus)
            return;
        root.lastStatus = text;

        const s = root.parseJson(text);
        if (!s || typeof s !== "object" || Array.isArray(s) || !Array.isArray(s.kernels)) {
            root.lastStatus = "";
            root.probeFailed = true;
            return;
        }

        const kernels = [];
        for (const k of s.kernels) {
            if (!k || typeof k !== "object" || typeof k.name !== "string")
                continue;
            kernels.push({
                name: k.name,
                // The package the kernel is installed or offered as, which can still
                // carry its old name.
                package: typeof k.package === "string" && k.package.length > 0 ? k.package : k.name,
                installed: k.installed === true,
                version: typeof k.version === "string" ? k.version : "",
                running: k.running === true,
                available: k.available === true,
                cpuSupported: k.cpuSupported === true,
                downloadBytes: root.bytesOrUnknown(k.downloadBytes),
                driverMissing: k.driverMissing === true,
                // The NVIDIA driver in use cannot load on this kernel.
                driverUnsupported: k.driverUnsupported === true
            });
        }

        root.unsupportedReason = typeof s.unsupportedReason === "string" ? s.unsupportedReason : "";
        root.helper = s.helper === true;
        root.canChangeStandard = s.canChangeStandard === true;
        root.canUseNewNames = s.canUseNewNames === true;
        root.canUseEac = s.canUseEac === true;
        root.uefi = s.uefi === true;
        root.espFreeBytes = root.bytesOrUnknown(s.espFreeBytes);
        root.standardImageBytes = root.bytesOrUnknown(s.standardImageBytes);
        root.nextKernel = typeof s.nextKernel === "string" ? s.nextKernel : "";
        root.canChooseNext = s.canChooseNext === true;
        root.kernels = kernels;
        root.installedKernels = Array.isArray(s.installedKernels)
            ? s.installedKernels.filter(base => typeof base === "string" && base.length > 0)
            : [];
        root.probeFailed = false;
        root.loaded = true;
    }

    function runHelper(action, kernel) {
        if (root.busy || SystemSecurity.busy)
            return;
        SystemSecurity.clearError();
        SystemSecurity.clearStatus();
        root.busyAction = action;
        root.busyKernel = kernel;
        helperProc.action = action;
        helperProc.kernel = kernel;
        helperProc.command = ["pkexec", root.helperPath, action, root.info(kernel).package || kernel];
        helperProc.running = true;
    }

    Process {
        id: helperProc
        property string action: ""
        property string kernel: ""
        stderr: StdioCollector {
            id: helperErr
        }
        onExited: code => root.helperFinished(code)
    }

    Process {
        id: helperCheck
        command: ["sh", "-c", 'test -x "$0"', root.helperPath]
        onExited: code => {
            if (root.busyAction !== "")
                return;
            if (code !== 0)
                SystemSecurity.fail(root.messageScope, Translation.tr("Update Mainstream to manage kernels."));
        }
    }

    // The helper's own message is English and written for the log, so the
    // exit code picks the sentence shown.
    function failureText(action, kernel, code) {
        const name = root.label(kernel);
        switch (code) {
        case 3:
            return root.unsupportedText.length > 0
                ? root.unsupportedText
                : Translation.tr("These settings cannot be changed on this system.");
        case 4:
            return action === "remove"
                ? Translation.tr("%1 could not be removed.").arg(name)
                : Translation.tr("%1 could not be installed. Check your internet connection and try again.").arg(name);
        case 5:
            return Translation.tr("This processor cannot run this kernel. It needs AVX2 (Intel from about 2013, AMD from about 2015).");
        case 6:
            return Translation.tr("The boot partition does not have room for another kernel.");
        case 7:
            return Translation.tr("%1 is installed, but the graphics driver could not be built for it. Keep using the kernel you are on.").arg(name);
        case 8:
            return Translation.tr("%1 cannot be removed right now.").arg(name);
        case 9:
            return Translation.tr("This computer cannot store the choice. Choose it in the boot menu when the computer starts.");
        case 10:
            return Translation.tr("An update or another system change is running. Try again when it has finished.");
        case 11:
            return Translation.tr("Not available yet.");
        case 12:
            return Translation.tr("The graphics driver is not built for this kernel. Keep using the kernel you are on.");
        case 13:
            return Translation.tr("NVIDIA's driver does not load on this kernel yet.");
        default:
            return Translation.tr("The change could not be applied.");
        }
    }

    function successSummary(action, kernel) {
        const name = root.label(kernel);
        switch (action) {
        case "install":
            return root.canChooseNext
                ? Translation.tr("%1 is installed. Choose \"Use at next start\", then restart to use it.").arg(name)
                : Translation.tr("%1 is installed. To use it, restart and choose it in the boot menu.").arg(name);
        case "remove":
            return Translation.tr("%1 was removed.").arg(name);
        case "next":
            return Translation.tr("%1 starts the next time the computer starts.").arg(name);
        default:
            return "";
        }
    }

    function helperFinished(code) {
        const action = helperProc.action;
        const kernel = helperProc.kernel;
        root.busyAction = "";
        root.busyKernel = "";

        if (code === 0) {
            const summary = root.successSummary(action, kernel);
            if (summary.length > 0)
                SystemSecurity.succeed(root.messageScope, summary);
            root.actionSucceeded(action, kernel);
        } else if (code === 126 || code === 127) {
            // pkexec uses 126/127 both when the user dismisses the auth prompt
            // and when the helper binary is missing. Stay quiet on cancel, and
            // show an update notice only if the helper does not exist.
            helperCheck.running = true;
        } else {
            const detail = helperErr.text.trim();
            if (detail.length > 0)
                console.warn(`[SystemKernels] ${action} ${kernel} exited with ${code}: ${detail}`);
            SystemSecurity.fail(root.messageScope, root.failureText(action, kernel, code));
        }

        root.generation += 1;
        root.refresh(true);
    }

    function install(kernel) {
        root.runHelper("install", kernel);
    }

    function remove(kernel) {
        root.runHelper("remove", kernel);
    }

    function useNext(kernel) {
        root.runHelper("next", kernel);
    }
}
