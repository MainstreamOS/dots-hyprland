pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * SystemSecurity: Secure Boot, and what Easy Anti-Cheat on Linux checks
 * before it lets a protected game start. Shown in Settings > Gaming.
 *
 * scripts/security/security-status.sh reads unprivileged system state and the
 * cache in /var/lib/mainstream/security-state.json. Every privileged change
 * runs through /usr/lib/mainstream/system-security via pkexec.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/security/security-status.sh")
    readonly property string helperPath: "/usr/lib/mainstream/system-security"
    readonly property string mockEnv: String(Quickshell.env("QS_SECURITY_MOCK_JSON") ?? "").trim()

    property bool loaded: false
    // The last probe gave no usable answer. What was read before stays, since
    // an empty answer would otherwise read as "Legacy BIOS".
    property bool probeFailed: false
    property string unsupportedReason: ""
    property bool helper: false
    property bool uefi: false
    property bool secureBoot: false
    property bool setupMode: false
    property bool sbctlKeysExist: false
    property bool sbctlVerified: false
    // The keys are on their own subvolume, which a restored snapshot leaves
    // alone, so a system that lost sight of them can have signing set up again.
    property bool signingKeysKept: false
    property bool windowsDetected: false
    property bool bitlockerDetected: false

    // What Easy Anti-Cheat reads, as it stands in this session.
    property bool tpm2: false
    property bool measuredBoot: false
    property bool iommu: false
    property bool iommuPassthrough: false
    property string lockdown: "unknown"
    property bool kexecDisabled: false
    property bool bpfLsm: false
    // The anti-cheat start: the kernel, its separate signed start, and whether this
    // session came through it.
    property bool acKernelInstalled: false
    property bool acStartReady: false
    property bool acCertificateEnrolled: false
    property bool acStartedThroughIt: false
    readonly property bool lockedDown: root.lockdown === "integrity" || root.lockdown === "confidentiality"

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

    readonly property bool stateKnown: root.loaded && !root.probeFailed
    readonly property bool canChangeBoot: root.stateKnown && root.helper && !root.busy && !SystemKernels.busy
        && root.unsupportedReason === ""
    readonly property string pendingPill: root.probeFailed ? Translation.tr("Unknown") : Translation.tr("Checking…")

    // Kept here so it survives the page being rebuilt on a theme change.
    property string busyAction: ""
    readonly property bool busy: root.busyAction !== ""
    property string errorScope: ""
    property string lastError: ""
    property string statusScope: ""
    property string statusMessage: ""

    // Closing Settings while the helper runs would cut a change short.
    property bool closeRefused: false
    onBusyChanged: {
        if (!root.busy)
            root.closeRefused = false;
    }

    signal actionSucceeded(string action)

    function clearError() {
        root.lastError = "";
        root.errorScope = "";
    }

    function clearStatus() {
        root.statusMessage = "";
        root.statusScope = "";
    }

    function fail(scope, message) {
        root.clearStatus();
        root.errorScope = scope;
        root.lastError = message;
    }

    function succeed(scope, message) {
        root.clearError();
        root.statusScope = scope;
        root.statusMessage = message;
    }

    property int watchers: 0

    function watch() {
        root.watchers += 1;
        leaveTimer.stop();
        if (root.watchers === 1)
            root.refresh(true);
    }

    function unwatch() {
        root.watchers = Math.max(0, root.watchers - 1);
        if (root.watchers === 0)
            leaveTimer.restart();
    }

    Timer {
        id: leaveTimer
        interval: 1000
        onTriggered: {
            if (root.watchers > 0)
                return;
            root.clearError();
            root.clearStatus();
        }
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

    function applyStatus(text) {
        const force = root.forceApply;
        root.forceApply = false;
        if (!force && root.loaded && text === root.lastStatus)
            return;
        root.lastStatus = text;

        const s = root.parseJson(text);
        if (!s || typeof s !== "object" || Array.isArray(s) || s.error !== undefined) {
            root.lastStatus = "";
            root.probeFailed = true;
            return;
        }

        const ac = (s.antiCheat && typeof s.antiCheat === "object") ? s.antiCheat : {};

        root.unsupportedReason = typeof s.unsupportedReason === "string" ? s.unsupportedReason : "";
        root.helper = s.helper === true;
        root.uefi = s.uefi === true;
        root.secureBoot = s.secureBoot === true;
        root.setupMode = s.setupMode === true;
        root.sbctlKeysExist = s.sbctlKeysExist === true;
        root.sbctlVerified = s.sbctlVerified === true;
        root.signingKeysKept = s.signingKeysKept === true;
        root.windowsDetected = s.windowsDetected === true;
        root.bitlockerDetected = s.bitlockerDetected === true;
        root.tpm2 = ac.tpm2 === true;
        root.measuredBoot = ac.measuredBoot === true;
        root.iommu = ac.iommu === true;
        root.iommuPassthrough = ac.iommuPassthrough === true;
        root.lockdown = typeof ac.lockdown === "string" ? ac.lockdown : "unknown";
        root.kexecDisabled = ac.kexecDisabled === true;
        root.bpfLsm = ac.bpfLsm === true;
        root.acKernelInstalled = ac.kernelInstalled === true;
        root.acStartReady = ac.startReady === true;
        root.acCertificateEnrolled = ac.certificateEnrolled === true;
        root.acStartedThroughIt = ac.startedThroughIt === true;
        root.probeFailed = false;
        root.loaded = true;
    }

    function runHelper(action, scope) {
        if (root.busy || SystemKernels.busy)
            return;
        root.clearError();
        root.clearStatus();
        root.busyAction = action;
        helperProc.action = action;
        helperProc.scope = scope;
        helperProc.command = ["pkexec", root.helperPath, action];
        helperProc.running = true;
    }

    Process {
        id: helperProc
        property string action: ""
        property string scope: ""
        stderr: StdioCollector {
            id: helperErr
        }
        onExited: code => root.helperFinished(code)
    }

    Process {
        id: helperCheck
        property string scope: ""
        command: ["sh", "-c", 'test -x "$0"', root.helperPath]
        onExited: code => {
            if (root.busyAction !== "")
                return;
            if (code !== 0)
                root.fail(helperCheck.scope, Translation.tr("Update Mainstream to manage security settings."));
        }
    }

    // The helper's own message is English and written for the log, so the
    // exit code picks the sentence shown.
    function failureText(action, code) {
        if (code === 4)
            return Translation.tr("A required package could not be installed. Check your internet connection and try again.");
        if (code === 3 && action === "sb-restore" && root.unsupportedText.length === 0)
            return Translation.tr("This system's signing keys could not be found. Turn Secure Boot off in UEFI setup, or clear its keys there and set it up again.");
        if (code === 3) {
            return root.unsupportedText.length > 0
                ? root.unsupportedText
                : Translation.tr("This computer does not meet the requirements for that right now.");
        }
        switch (action) {
        case "sb-enable":
            return Translation.tr("Could not create and enroll Secure Boot keys.");
        case "sb-sign":
            return Translation.tr("Could not re-sign boot files.");
        case "sb-restore":
            return Translation.tr("Could not set up signing again.");
        case "ac-setup":
            return code === 6
                ? Translation.tr("The boot partition does not have room for the anti-cheat start.")
                : Translation.tr("Could not set up the anti-cheat start.");
        case "ac-start":
            return Translation.tr("Could not restart into the anti-cheat start.");
        case "ac-remove":
            return Translation.tr("Could not remove the anti-cheat start.");
        default:
            return Translation.tr("The change could not be applied.");
        }
    }

    function successSummary(action) {
        switch (action) {
        case "sb-enable":
            return Translation.tr("Secure Boot keys enrolled and boot files signed. Restart and turn on Secure Boot in UEFI setup if it is not on already.");
        case "sb-sign":
            return Translation.tr("Boot files re-signed and verified.");
        case "sb-restore":
            return Translation.tr("Signing is set up again, and the boot files are signed and verified.");
        case "ac-setup":
            return Translation.tr("The anti-cheat start is set up. Restart into it before playing a protected game.");
        case "ac-remove":
            return Translation.tr("The anti-cheat start was removed.");
        default:
            return "";
        }
    }

    function helperFinished(code) {
        const action = helperProc.action;
        const scope = helperProc.scope;
        root.busyAction = "";

        if (code === 0) {
            const summary = root.successSummary(action);
            if (summary.length > 0)
                root.succeed(scope, summary);
            root.actionSucceeded(action);
        } else if (code === 126 || code === 127) {
            // pkexec uses 126/127 both when the user dismisses the auth prompt
            // and when the helper binary is missing. Stay quiet on cancel, and
            // show an update notice only if the helper does not exist.
            helperCheck.scope = scope;
            helperCheck.running = true;
        } else {
            const detail = helperErr.text.trim();
            if (detail.length > 0)
                console.warn(`[SystemSecurity] ${action} exited with ${code}: ${detail}`);
            root.fail(scope, root.failureText(action, code));
        }

        root.generation += 1;
        root.refresh(true);
    }

    function enableSecureBoot() {
        root.runHelper("sb-enable", "secureBoot");
    }

    function resignBoot() {
        root.runHelper("sb-sign", "secureBoot");
    }

    function restoreSigning() {
        root.runHelper("sb-restore", "secureBoot");
    }

    function setUpAntiCheat() {
        root.runHelper("ac-setup", "antiCheat");
    }

    function startAntiCheat() {
        root.runHelper("ac-start", "antiCheat");
    }

    function removeAntiCheat() {
        root.runHelper("ac-remove", "antiCheat");
    }
}
