pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    readonly property string currentFormat: Ai.currentModel?.api_format ?? ""
    // GeminiUsage is referenced only inside geminiLoader, so the singleton is
    // not created before an Antigravity model is in use.
    readonly property bool geminiWanted: root.currentFormat === "antigravity-cli" && Ai.cliReady("antigravity-cli") && Config.options.bar.geminiUsage.enable
    readonly property var gemini: geminiLoader.item

    readonly property string readyFormat: {
        if (ClaudeUsage.active)
            return "claude-code";
        if (CodexUsage.active)
            return "codex-cli";
        if (root.geminiWanted)
            return "antigravity-cli";
        return "";
    }

    readonly property var usageService: {
        switch (root.readyFormat) {
        case "claude-code":
            return ClaudeUsage;
        case "codex-cli":
            return CodexUsage;
        case "antigravity-cli":
            return root.gemini;
        default:
            return null;
        }
    }

    readonly property bool providerAvailable: root.usageService?.available ?? false

    readonly property string providerError: {
        const error = root.usageService?.lastError ?? "";
        // Both CLIs report a sign-in, so no subscription token means an API key
        // or cloud provider sign-in, which has no subscription usage to show.
        return root.readyFormat !== "antigravity-cli" && error === "no-login" ? "" : error;
    }

    readonly property string activeProvider: (root.providerAvailable || root.providerError.length > 0) ? root.readyFormat : ""

    // Every usage service reports codes; any other text gets the generic line.
    function errorText(error: string): string {
        switch (error) {
        case "no-login":
            return Translation.tr("Sign in to Antigravity to see usage.");
        case "auth":
            if (root.activeProvider === "claude-code")
                return Translation.tr("Sign in to Claude Code again to see usage.");
            if (root.activeProvider === "codex-cli")
                return Translation.tr("Sign in to Codex again to see usage.");
            return Translation.tr("Sign in to Antigravity again to see usage.");
        case "expired":
            return Translation.tr("Usage appears after your next message.");
        case "rate-limit":
            return Translation.tr("Usage checks are rate limited. Trying again soon.");
        case "network":
            return Translation.tr("Could not reach the usage service.");
        default:
            return Translation.tr("Usage could not be read.");
        }
    }

    readonly property bool providerFetching: activeProvider === "antigravity-cli" && (root.gemini?.running ?? false)

    // Failed reads keep the last good numbers; past two missed polls they
    // say how old they are.
    property double now: Date.now()
    readonly property double staleMs: {
        const at = root.usageService?.updatedAt ?? 0;
        const interval = root.usageService?.fetchInterval ?? 0;
        const age = root.now - at;
        return (at > 0 && interval > 0 && age > 2 * interval) ? age : 0;
    }

    function updatedText(ms: double): string {
        const minutes = Math.floor(ms / 60000);
        return minutes < 60 ? Translation.tr("Updated %1 min ago").arg(minutes)
            : Translation.tr("Updated %1 h ago").arg(Math.floor(minutes / 60));
    }

    Timer {
        interval: 30 * 1000
        repeat: true
        triggeredOnStart: true
        running: root.visible && root.providerAvailable
        onTriggered: root.now = Date.now()
    }

    property bool expanded: false
    readonly property real primaryPct: {
        if (root.activeProvider === "claude-code") return ClaudeUsage.fiveHour;
        if (root.activeProvider === "codex-cli") return CodexUsage.fiveHour;
        if (root.activeProvider === "antigravity-cli") return root.gemini?.session ?? 0;
        return 0;
    }
    readonly property real warningThreshold: {
        if (root.activeProvider === "claude-code") return Config.options.bar.claudeUsage.warningThreshold;
        if (root.activeProvider === "codex-cli") return Config.options.bar.codexUsage.warningThreshold;
        return Config.options.bar.geminiUsage.warningThreshold;
    }
    readonly property color usageColor: root.primaryPct >= root.warningThreshold
        ? Appearance.colors.colError : Appearance.colors.colPrimary

    visible: activeProvider !== ""
    radius: 14
    color: root.expanded ? Appearance.colors.colLayer2 : "transparent"
    implicitHeight: visible ? (mainCol.implicitHeight + 12) : 0

    readonly property string providerIcon: {
        if (activeProvider === "claude-code") return "claude-symbolic";
        if (activeProvider === "codex-cli") return "openai-symbolic";
        if (activeProvider === "antigravity-cli") return "antigravity-symbolic";
        return "";
    }

    readonly property string providerTitle: {
        if (activeProvider === "claude-code") {
            const sub = ClaudeUsage.subscriptionType;
            return sub ? `Claude (${sub.toUpperCase()})` : Translation.tr("Claude Subscription");
        }
        if (activeProvider === "codex-cli") {
            const plan = CodexUsage.planType;
            return plan ? `Codex (${plan})` : Translation.tr("Codex Subscription");
        }
        if (activeProvider === "antigravity-cli") {
            return Translation.tr("Gemini Subscription");
        }
        return "";
    }

    function refresh(): void {
        root.usageService?.getData();
    }

    component UsageMeter: ColumnLayout {
        id: meter
        required property string label
        required property real pct
        required property double resetMs
        property real warningThreshold: 90
        property var timeUntilFunc: null

        readonly property bool isWarning: pct >= warningThreshold
        readonly property bool isCaution: pct >= 75 && pct < warningThreshold

        readonly property color barColor: {
            if (isWarning) return Appearance.colors.colError;
            if (isCaution) return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colError, 0.45);
            return Appearance.colors.colPrimary;
        }

        Layout.fillWidth: true
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: meter.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: `${Math.round(meter.pct)}%`
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: meter.barColor
            }

            RowLayout {
                visible: meter.resetMs > 0 && meter.timeUntilFunc !== null
                spacing: 2
                Layout.alignment: Qt.AlignVCenter

                MaterialSymbol {
                    text: "schedule"
                    iconSize: Appearance.font.pixelSize.smaller - 2
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: meter.timeUntilFunc ? meter.timeUntilFunc(meter.resetMs) : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Appearance.colors.colLayer1
            clip: true

            Rectangle {
                id: fillBar
                height: parent.height
                radius: 3
                width: parent.width * Math.max(0, Math.min(1, meter.pct / 100))
                color: meter.barColor

                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout {
        id: mainCol
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            RippleButton {
                id: expandButton
                Layout.fillWidth: true
                implicitHeight: 28
                buttonRadius: 8
                colBackground: "transparent"
                Accessible.name: root.providerTitle + ", " + (root.expanded ? Translation.tr("Hide usage details") : Translation.tr("Show usage details"))
                Accessible.role: Accessible.Button
                onClicked: root.expanded = !root.expanded
                contentItem: RowLayout {
                    spacing: 6
                    CustomIcon {
                        visible: root.providerIcon !== ""
                        implicitWidth: 15
                        implicitHeight: 15
                        source: root.providerIcon
                        colorize: true
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.providerTitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: root.providerAvailable && !root.expanded
                        text: `${Math.round(root.primaryPct)}%`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: root.usageColor
                    }
                }
            }

            RippleButton {
                id: refreshBtn
                visible: root.expanded || root.providerError.length > 0
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 8
                Accessible.name: Translation.tr("Refresh usage")
                onClicked: {
                    if (root.activeProvider !== "antigravity-cli") spinAnim.restart();
                    root.refresh();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                    RotationAnimation on rotation {
                        id: spinAnim
                        running: false
                        from: 0
                        to: 360
                        duration: 500
                    }
                    RotationAnimation on rotation {
                        running: root.providerFetching
                        from: 0
                        to: 360
                        duration: 500
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                    }
                }
                StyledToolTip { text: Translation.tr("Refresh usage") }
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 8
                Accessible.name: root.expanded ? Translation.tr("Hide usage details") : Translation.tr("Show usage details")
                onClicked: root.expanded = !root.expanded
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.expanded ? "expand_less" : "expand_more"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.providerAvailable && !root.expanded
            implicitHeight: 3
            radius: 1.5
            color: Appearance.colors.colLayer2
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, root.primaryPct / 100))
                radius: parent.radius
                color: root.usageColor
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.providerAvailable && root.providerError.length > 0
            text: root.errorText(root.providerError)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.expanded && root.providerAvailable && root.staleMs > 0
            text: root.updatedText(root.staleMs)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
        }

        // Claude meters
        UsageMeter {
            visible: root.expanded && root.activeProvider === "claude-code" && root.providerAvailable
            label: Translation.tr("Session (5h)")
            pct: ClaudeUsage.fiveHour
            resetMs: ClaudeUsage.fiveHourReset
            warningThreshold: Config.options.bar.claudeUsage.warningThreshold
            timeUntilFunc: ClaudeUsage.timeUntil
        }
        UsageMeter {
            visible: root.expanded && root.activeProvider === "claude-code" && root.providerAvailable
            label: Translation.tr("Weekly")
            pct: ClaudeUsage.sevenDay
            resetMs: ClaudeUsage.sevenDayReset
            warningThreshold: Config.options.bar.claudeUsage.warningThreshold
            timeUntilFunc: ClaudeUsage.timeUntil
        }

        // Codex meters
        UsageMeter {
            visible: root.expanded && root.activeProvider === "codex-cli" && root.providerAvailable
            label: Translation.tr("Session (5h)")
            pct: CodexUsage.fiveHour
            resetMs: CodexUsage.fiveHourReset
            warningThreshold: Config.options.bar.codexUsage.warningThreshold
            timeUntilFunc: CodexUsage.timeUntil
        }
        UsageMeter {
            visible: root.expanded && root.activeProvider === "codex-cli" && root.providerAvailable
            label: Translation.tr("Weekly")
            pct: CodexUsage.sevenDay
            resetMs: CodexUsage.sevenDayReset
            warningThreshold: Config.options.bar.codexUsage.warningThreshold
            timeUntilFunc: CodexUsage.timeUntil
        }

        // Gemini meters
        Loader {
            id: geminiLoader
            Layout.fillWidth: true
            active: root.geminiWanted
            visible: root.expanded && root.activeProvider === "antigravity-cli" && root.providerAvailable

            sourceComponent: ColumnLayout {
                readonly property bool available: GeminiUsage.available
                readonly property string lastError: GeminiUsage.lastError
                readonly property bool running: GeminiUsage.running
                readonly property real session: GeminiUsage.session

                function getData(): void {
                    GeminiUsage.getData();
                }

                spacing: 8

                UsageMeter {
                    label: Translation.tr("Session")
                    pct: GeminiUsage.session
                    resetMs: GeminiUsage.sessionReset
                    warningThreshold: Config.options.bar.geminiUsage.warningThreshold
                    timeUntilFunc: GeminiUsage.timeUntil
                }
                UsageMeter {
                    visible: GeminiUsage.sevenDay >= 0
                    label: Translation.tr("Weekly")
                    pct: GeminiUsage.sevenDay
                    resetMs: GeminiUsage.sevenDayReset
                    warningThreshold: Config.options.bar.geminiUsage.warningThreshold
                    timeUntilFunc: GeminiUsage.timeUntil
                }
            }
        }
    }
}
