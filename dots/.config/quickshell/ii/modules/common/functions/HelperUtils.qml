pragma Singleton
import Quickshell
import qs.services

// What a page shows when a root helper it ran through pkexec fails.
Singleton {
    id: root

    // pkexec's own codes: 126 a dismissed prompt, 127 a failed or refused one.
    // pkexec also gives 127 for a missing helper, so callers check for it first.
    function pkexecRefusal(code) {
        if (code === 126)
            return Translation.tr("The change was not made: authentication was canceled.");
        if (code === 127)
            return Translation.tr("The change was not made: authentication failed.");
        return "";
    }

    function helperReason(stderrText, helperName) {
        const lines = String(stderrText ?? "").trim().split("\n").filter(l => l.length > 0);
        return lines.length > 0 ? lines[lines.length - 1].replace(new RegExp(`^${helperName}:\\s*`), "") : "";
    }

    function failureMessage(code, reason) {
        return root.pkexecRefusal(code) || reason || Translation.tr("The change could not be applied.");
    }
}
