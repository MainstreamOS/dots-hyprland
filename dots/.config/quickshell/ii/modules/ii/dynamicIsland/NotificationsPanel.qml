pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    implicitHeight: 204
    spacing: 6
    property int currentIndex: 0
    readonly property var entries: IslandState.notifications
    readonly property string newestId: entries[0]?.id ?? ""
    onNewestIdChanged: currentIndex = 0
    readonly property var entry: entries[Math.min(currentIndex, entries.length - 1)] ?? null
    readonly property bool privateContact: Boolean(entry?.phoneOrigin && !Config.options.bar.island.showContactName)
    readonly property bool privateBody: Boolean(entry?.phoneOrigin && !Config.options.bar.island.showMessage)
    onEntriesChanged: currentIndex = Math.max(0, Math.min(currentIndex, entries.length - 1))

    readonly property string resolvedIcon: Notifications.resolveAppIcon(root.entry)
    readonly property bool isVectorIcon: resolvedIcon.startsWith("image://icon/")
    readonly property var extraImages: {
        if (!entry || root.privateBody) return [];
        function normalize(src) {
            if (!src) return "";
            const s = src.toString();
            if (s.startsWith("image://icon//")) {
                return "file://" + s.slice("image://icon".length);
            }
            if (s.startsWith("image://icon/") && !s.startsWith("image://icon//")) {
                return "";
            }
            if (s.startsWith("/") && !s.startsWith("//")) {
                return "file://" + s;
            }
            return s;
        }
        if (entry.images && entry.images.length > 0) {
            return entry.images.map(normalize).filter(s => !!s);
        }
        if (entry.image && typeof entry.image === "string" && entry.image.length > 0) {
            const normalized = normalize(entry.image);
            if (!normalized) return [];
            // An image already shown as the main icon is not repeated in the body.
            if (root.resolvedIcon && (root.resolvedIcon === entry.image || root.resolvedIcon === normalized)) {
                return [];
            }
            return [normalized];
        }
        return [];
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 12
        color: Appearance.surfaces.raised

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 10

            ClippingRectangle {
                visible: !root.privateContact && (!root.entry?.phoneOrigin || Config.options.bar.island.showContactPicture)
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 10
                color: Appearance.colors.colSecondaryContainer

                IconImage {
                    id: iconDisplay
                    anchors.fill: parent
                    anchors.margins: root.isVectorIcon ? 3 : 0
                    visible: !!source.toString() && status !== Image.Error
                    source: root.resolvedIcon
                    backer.sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                    mipmap: !root.isVectorIcon
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !iconDisplay.visible || iconDisplay.status === Image.Error
                    text: "notifications"
                    color: Appearance.colors.colOnSecondaryContainer
                    iconSize: 18
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.entry?.sourceApp || Translation.tr("Notifications")
                    font.pixelSize: 10
                    color: Appearance.islandContent.colSubtext
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                StyledText {
                    Layout.fillWidth: true
                    text: !root.entry ? Translation.tr("You're all caught up") : root.privateContact ? Translation.tr("Private notification") : root.entry.summary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Appearance.islandContent.colOnLayer0
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            RippleButton {
                visible: !!root.entry
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 9
                colBackground: Appearance.surfaces.row
                colBackgroundHover: Appearance.colors.colLayer2Hover
                Accessible.name: Translation.tr("Dismiss notification")
                onClicked: IslandState.dismissNotification(root.entry)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.islandContent.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    MessageBody {
        Layout.fillWidth: true
        Layout.fillHeight: true
        images: root.extraImages
        imagesOnRight: true
        markup: true
        text: !root.entry ? Translation.tr("New notifications will appear here.") : root.privateBody ? Translation.tr("Message contents hidden") : root.entry.body
    }

    property bool replying: false
    readonly property bool busy: replying || replyInput.focus || replyInput.activeFocus || replyInput.text.trim().length > 0
    readonly property bool needsKeyboardFocus: replying || replyInput.focus || replyInput.activeFocus
    readonly property var liveNotif: root.entry?.notificationId !== undefined
        ? (Notifications.list.find(n => n.notificationId === root.entry.notificationId) ?? null)
        : null
    readonly property bool entryCanReply: Boolean(liveNotif?.canReply)
    readonly property string entryReplyPlaceholder: liveNotif?.inlineReplyPlaceholder || ""

    Connections {
        target: root
        function onNewestIdChanged() { root.cancelReply(); }
        function onEntryChanged() {
            if (!root.entry) root.cancelReply();
            else if (root.liveNotif?.replyDraft) {
                replyInput.text = root.liveNotif.replyDraft;
                root.replying = true;
            }
        }
    }
    Connections {
        target: IslandState
        function onReplyRequested() {
            if (root.entryCanReply) {
                root.replying = true;
                Qt.callLater(() => replyInput.forceActiveFocus());
            }
        }
    }

    Connections {
        target: Notifications
        function onPhoneActionFinished(id, success) {
            if (id === root.entry?.notificationId && success) root.cancelReply();
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: !!root.liveNotif?.actionError
        text: root.liveNotif?.actionError || ""
        color: Appearance.barStripContent.colErrorMark
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    function cancelReply() {
        replying = false;
        replyInput.text = "";
        replyInput.focus = false;
    }

    function submitReply() {
        const text = (replyInput.text || "").trim();
        if (!text || !entry || entry.notificationId === undefined) return;
        const targetId = entry.notificationId;
        Notifications.sendReply(targetId, text);
    }

    function actionSymbol(text, id) {
        const raw = (text || id || "").toLowerCase().trim();
        if (/^(delete|trash|remove|discard)\b/.test(raw)) return "delete";
        if (/^(archive)\b/.test(raw)) return "archive";
        if (/^(read|mark\s*as\s*read|mark\s*read|seen)\b/.test(raw)) return "mark_chat_read";
        if (/^(done|mark\s*as\s*done|complete)\b/.test(raw)) return "check";
        if (/^(copy)\b/.test(raw)) return "content_copy";
        if (/^(mute|silence)\b/.test(raw)) return "volume_off";
        if (/^(unmute)\b/.test(raw)) return "volume_up";
        if (/^(approve|accept)\b/.test(raw)) return "check_circle";
        if (/^(deny|reject|decline)\b/.test(raw)) return "cancel";
        if (/^(cancel|dismiss|clear|stop|close)\b/.test(raw)) return "close";
        if (/^(reply|respond)\b/.test(raw)) return "reply";
        return "open_in_new";
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !root.replying
        spacing: 6

        IslandButton { symbol: "chevron_left"; enabled: root.currentIndex > 0; onClicked: { root.cancelReply(); root.currentIndex--; } }

        Rectangle {
            implicitHeight: 24
            implicitWidth: countText.implicitWidth + 12
            radius: 6
            color: Appearance.surfaces.row

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: root.entries.length ? (root.currentIndex + 1) + " / " + root.entries.length : "0"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Appearance.islandContent.colOnLayer1
            }
        }

        IslandButton { symbol: "chevron_right"; enabled: root.currentIndex + 1 < root.entries.length; onClicked: { root.cancelReply(); root.currentIndex++; } }
        Item { Layout.fillWidth: true }
        RowLayout {
            spacing: 6
            Repeater {
                model: (root.entry?.actions ?? []).filter(a => a && (a.text || a.identifier))
                delegate: IslandButton {
                    required property var modelData
                    required property int index

                    readonly property string actionText: modelData.text || modelData.identifier || ""
                    readonly property string actionId: modelData.identifier || modelData.text || ""
                    readonly property int totalButtons: (root.entry?.actions?.length ?? 0) + (root.entryCanReply ? 1 : 0)

                    symbol: root.actionSymbol(actionText, actionId)
                    text: totalButtons <= 2 ? actionText : (totalButtons === 3 && actionText.length <= 7) ? actionText : ""

                    ToolTip.visible: hovered && text === "" && actionText.length > 0
                    ToolTip.text: actionText
                    ToolTip.delay: 300

                    onClicked: Notifications.attemptInvokeAction(root.entry.notificationId, actionId, actionText)
                }
            }
            IslandButton {
                visible: root.entryCanReply
                symbol: "reply"
                text: Translation.tr("Reply")
                onClicked: {
                    root.replying = true;
                    Qt.callLater(() => replyInput.forceActiveFocus());
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 10
        color: Appearance.surfaces.raised
        visible: root.replying

        TapHandler {
            onTapped: replyInput.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 4
            spacing: 6

            RippleButton {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 8
                colBackground: "transparent"
                colBackgroundHover: Appearance.surfaces.row
                Accessible.name: Translation.tr("Cancel reply")
                onClicked: root.cancelReply()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 15
                    color: Appearance.islandContent.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            ToolbarTextField {
                id: replyInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                leftPadding: 4
                rightPadding: 4
                topPadding: 0
                bottomPadding: 0
                font.pixelSize: 12
                colBackground: "transparent"
                placeholderText: root.entryReplyPlaceholder || Translation.tr("Reply…")
                onAccepted: root.submitReply()
                Keys.onEscapePressed: root.cancelReply()
            }

            RippleButton {
                id: sendNotifBtn
                readonly property bool canSend: replyInput.text.trim().length > 0
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 13
                colBackground: canSend ? Appearance.colors.colPrimary : "transparent"
                colBackgroundHover: canSend ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                enabled: canSend && !root.liveNotif?.actionPending
                Accessible.name: Translation.tr("Send reply")
                onClicked: root.submitReply()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_upward"
                    iconSize: 16
                    color: sendNotifBtn.canSend ? Appearance.colors.colOnPrimary : Appearance.islandContent.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
