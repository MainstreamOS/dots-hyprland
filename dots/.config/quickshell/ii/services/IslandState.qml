pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import "PhoneIdentity.js" as PhoneIdentity
import "IslandNotificationPolicy.js" as NotificationPolicy
import "PhoneReactions.js" as PhoneReactions
import "IslandPhoneHistory.js" as History

Singleton {
    id: root
    readonly property bool kdePhoneConnected: Phone.devices.some(d => d.reachable)
    readonly property bool callAvailable: PhoneCalls.calls.length > 0 || PhoneCalls.devices.some(d => d.callAlerts)
        || Phone.devices.some(d => d.reachable && d.plugins?.includes("kdeconnect_telephony"))
        || recentCalls.length > 0
    readonly property bool textAvailable: PhoneCalls.messages.length > 0 || PhoneCalls.devices.some(d => d.messageAlerts)
        || Phone.devices.some(d => d.reachable && d.plugins?.includes("kdeconnect_sms"))
        || recentMessages.length > 0
    property var messageDrafts: ({})
    property var messageRequests: ({})
    signal messageReplyFinished(key: string, success: bool, text: string)
    Connections {
        target: Phone
        function onSendFinished(request, success) {
            const pending = root.messageRequests[request];
            if (!pending) return;
            const remaining = Object.assign({}, root.messageRequests);
            delete remaining[request];
            root.messageRequests = remaining;
            if (success && root.messageDrafts[pending.key] === pending.text) {
                root.messageDrafts = Object.assign({}, root.messageDrafts, {[pending.key]: ""});
            }
            root.messageReplyFinished(pending.key, success, pending.text);
        }
    }
    readonly property var panels: {
        return IslandPanels.order.filter(id => id !== "localsend" && IslandPanels.enabled(id)
            && (!IslandPhonePrivacy.suppressed || !["call", "text"].includes(id))
            && (id !== "call" || callAvailable) && (id !== "text" || textAvailable));
    }
    onPanelsChanged: {
        if (!panels.includes(selected) && !(selected === "localsend" && IslandPanels.enabled("localsend"))) {
            selected = panels[0] ?? "";
            alertOpen = false;
        }
    }
    property bool transferSession: false
    property string panelBeforeTransfer: "media"
    readonly property bool enabled: Appearance.sizes.barIsIsland
    property string selected: "system"
    property bool alertOpen: false
    Connections {
        target: IslandPhonePrivacy
        function onSuppressedChanged() {
            if (IslandPhonePrivacy.suppressed) root.alertOpen = false;
        }
    }
    readonly property var contacts: ContactService.records
    onContactsChanged: IslandPhoneHistory.enrichContacts(contacts)
    function contactFor(entry) { return ContactService.withContact(entry); }
    readonly property bool phoneWanted: root.enabled && Config.options.bar.island.phoneIntegration
    Binding { target: PhoneCalls; property: "islandWanted"; value: root.phoneWanted }
    property string phoneError: ""
    readonly property string phoneStatus: PhoneCalls.error || (PhoneCalls.devices.length || root.kdePhoneConnected
        ? Translation.tr("Phone services connected")
        : Translation.tr("Pair a phone in Bluetooth for call controls. Android messages also require KDE Connect."))
    property string lastCall: ""
    property string lastMessage: ""
    property string lastPhoneNotification: ""
    property var dismissedPhoneNotifications: []
    property string preferredPlayer: ""
    readonly property var players: MprisController.orderByRecency(MprisController.players)
    readonly property var dedicatedPlayingPlayer: players.find(p => p.isPlaying
        && !/(firefox|chromium|chrome|brave|opera|vivaldi|edge|zen|browser|playerctld)/i.test((p.dbusName || "") + " " + (p.identity || ""))) || null
    onDedicatedPlayingPlayerChanged: {
        if (!dedicatedPlayingPlayer) return;
        preferredPlayer = dedicatedPlayingPlayer.dbusName;
        if (panels.includes("media") && !alertOpen && !calls.length && selected !== "localsend") selected = "media";
    }
    // An alert leaves its panel selected, so each opening starts from here: the media player
    // while a dedicated one is playing, otherwise the system panel.
    function showDefaultPanel() {
        if (panels.includes("media") && dedicatedPlayingPlayer) {
            preferredPlayer = dedicatedPlayingPlayer.dbusName;
            selected = "media";
        } else if (panels.includes("system")) {
            selected = "system";
        }
    }
    readonly property var player: players.find(p => p.dbusName === preferredPlayer)
        || players.find(p => p.playbackState === MprisPlaybackState.Playing) || players[0] || null
    readonly property var kdeCalls: PhoneIdentity.mergeNotifications(Notifications.list.filter(n => n.notification && n.phoneOrigin
        && NotificationPolicy.panelFor(n) === "call" && NotificationPolicy.incomingCall(n))
        .map(n => Object.assign(PhoneIdentity.forNotification(n, Phone.callDetails), {
            id: "notification:" + n.notificationId, backend: "KDE Connect", deviceId: n.kdeDeviceId,
            picture: n.image, canPositive: n.actions.length > 0, canNegative: false,
            time: n.time, nativeEvent: n.notification?.hints?.["x-kde-eventId"] === "callReceived",
            deviceName: n.notification?.hints?.["x-kdeconnect-source-device"]
                || (n.notification?.hints?.["x-kde-eventId"] === "callReceived" ? n.summary : ""),
            positiveLabel: n.actions[0]?.text || "", negativeLabel: ""})));
    readonly property var calls: {
        const native = PhoneCalls.calls;
        if (!native.length) return kdeCalls.map(contactFor);
        return native.map(c => contactFor(PhoneIdentity.enrichCall(c, kdeCalls, native.length === 1)));
    }
    readonly property var messages: {
        const native = PhoneCalls.messages.concat(Phone.recentMessages).filter(m => !PhoneReactions.isReaction(m.body));
        const mirrored = [];
        for (const n of Notifications.list) {
            if (!n.phoneOrigin || NotificationPolicy.panelFor(n) !== "text") continue;
            const base = Object.assign(NotificationPolicy.messageFor(n), { live: !!n.notification });
            const body = String(base.body || "");
            if (PhoneReactions.isReaction(body)) continue;
            if (body.includes("\n")) {
                const parts = PhoneReactions.extractIndividualMessages(body);
                if (parts.length === 0) {
                    if ((base.images && base.images.length) || (base.audioClips && base.audioClips.length)) {
                        mirrored.push(Object.assign({}, base, { body: "" }));
                    }
                } else {
                    for (let i = 0; i < parts.length; i++) {
                        mirrored.push(Object.assign({}, base, {
                            id: base.id + ":" + i,
                            body: parts[i],
                            time: (base.time || 0) + i
                        }));
                    }
                }
            } else {
                mirrored.push(base);
            }
        }
        const filteredMirrored = mirrored.filter(m => !native.some(n => History.sameText(n, m)));
        return native.concat(filteredMirrored).map(contactFor).sort((a, b) => b.time - a.time);
    }
    // Only artwork the phone marks as the contact's picture; a notification's
    // own image can be a photo someone sent.
    readonly property var notificationContactPhotos: Notifications.list
        .filter(n => n.phoneOrigin && n.image && n.imageRole === "contact" && ["call", "text"].includes(NotificationPolicy.panelFor(n)))
        .map(n => {
            const identity = NotificationPolicy.panelFor(n) === "text" ? NotificationPolicy.messageFor(n)
                : PhoneIdentity.forNotification(n, Phone.callDetails);
            return Object.assign({}, identity, {picture: n.image});
        })
    onNotificationContactPhotosChanged: IslandPhoneHistory.rememberContactPictures(notificationContactPhotos)
    readonly property var recentCalls: IslandPhoneHistory.calls
    readonly property var recentMessages: History.groupMessages(IslandPhoneHistory.messages, LinkPreviewService.extractUrls)
    signal messageReceived(id: string)
    readonly property var phoneNotifications: PhoneCalls.notifications.filter(n => !dismissedPhoneNotifications.includes(n.id))
    readonly property var notifications: (IslandPhonePrivacy.suppressed ? [] : phoneNotifications.map(n => ({
        id: n.id, summary: n.name, body: n.body, image: n.picture,
        sourceApp: n.appName || "iPhone", phoneOrigin: true, actions: [], time: n.time || 0
    }))).concat(Notifications.list.filter(n => (!IslandPhonePrivacy.suppressed || !n.phoneOrigin)
        && (!n.phoneOrigin || NotificationPolicy.panelFor(n) === "notifications")).map(n => ({
        id: "notification:" + n.notificationId, notificationId: n.notificationId,
        summary: n.summary, body: n.body, image: n.image, sourceApp: n.sourceApp, appName: n.appName,
        appIcon: n.headerIcon, imageRole: n.imageRole,
        phoneOrigin: n.phoneOrigin, actions: n.actions, time: n.time
    }))).sort((a, b) => b.time - a.time)
    readonly property var call: calls[0] ?? null
    readonly property var message: messages[0] ?? null

    function step(direction) {
        const current = selected === "localsend" ? panelBeforeTransfer : selected;
        const available = panels;
        if (!available.length) return;
        const idx = available.indexOf(current);
        const start = idx >= 0 ? idx : 0;
        selected = available[(start + direction + available.length) % available.length];
    }
    function beginTransfer() {
        if (!IslandPanels.enabled("localsend")) return;
        if (selected !== "localsend") panelBeforeTransfer = selected;
        transferSession = true;
        alertOpen = false;
        selected = "localsend";
    }
    function endTransferView() {
        transferSession = false;
        if (selected === "localsend") selected = panels.includes(panelBeforeTransfer) ? panelBeforeTransfer : (panels[0] ?? "");
    }
    function alert(panel) {
        if (!enabled || !panels.includes(panel) || !Config.options.bar.island.automaticAlerts
            || IslandPhonePrivacy.suppressed || Notifications.silent) return;
        if ((panel === "call" && !callAvailable) || (panel === "text" && !textAvailable)) return;
        // With phone services off, the phone's events are not the Island's to show.
        if (["call", "text"].includes(panel) && !phoneWanted) return;
        // Calls and texts retain priority for their alert's duration. A later
        // mirrored notification must not replace the phone event's panel.
        if (panel === "notifications" && (calls.length || (alertOpen && ["call", "text"].includes(selected)))) return;
        selected = panel;
        alertOpen = true;
        alertTimer.restart();
    }
    Connections {
        target: PhoneCalls
        function onReadyChanged() { IslandPhoneHistory.observeCalls(root.calls, PhoneCalls.ready); }
    }
    onCallsChanged: {
        IslandPhoneHistory.observeCalls(calls, PhoneCalls.ready);
        const id = calls[0]?.id || "";
        if (id && id !== lastCall && callAvailable) alert("call");
        lastCall = id;
    }
    property var lastMessageEntry: null
    onMessagesChanged: {
        IslandPhoneHistory.observeMessages(messages);
        const top = messages[0] ?? null;
        const id = top?.id || "";
        // The native text replacing the notification already alerted for it is not news.
        const replacesAlerted = History.sameText(top, lastMessageEntry) || History.sameText(lastMessageEntry, top);
        if (id && id !== lastMessage && !replacesAlerted && !calls.length && top.live !== false && textAvailable) {
            alert("text");
            messageReceived(recentMessages[0]?.id || "");
        }
        lastMessage = id;
        lastMessageEntry = top;
    }
    onPhoneNotificationsChanged: {
        const id = phoneNotifications[0]?.id || "";
        if (id && id !== lastPhoneNotification && !calls.length && phoneWanted) alert("notifications");
        lastPhoneNotification = id;
    }
    function dismissNotification(entry) {
        if (entry.notificationId !== undefined) Notifications.discardNotification(entry.notificationId);
        else dismissedPhoneNotifications = [...dismissedPhoneNotifications, entry.id].slice(-100);
    }
    Connections {
        target: Notifications
        function onNotify(notification) {
            if (!notification.phoneOrigin || !root.phoneWanted || root.calls.length || NotificationPolicy.panelFor(notification) !== "notifications") return;
            root.alert("notifications");
        }
    }
    function action(id, name) {
        if (id.startsWith("notification:") && name === "positive") {
            const notificationId = Number(id.slice("notification:".length));
            const n = Notifications.list.find(n => n.notificationId === notificationId);
            if (n?.actions.length) Notifications.attemptInvokeAction(notificationId, n.actions[0].identifier);
            return;
        }
        phoneError = "";
        PhoneCalls.action(id, name);
    }
    Timer {
        id: alertTimer
        interval: Math.max(3, Config.options.bar.island.alertSeconds) * 1000
        onTriggered: root.alertOpen = false
    }
    signal replyRequested()
    IpcHandler {
        target: "island"
        function next(): void { root.step(1); }
        function previous(): void { root.step(-1); }
        function panel(name: string): void { if (root.panels.includes(name)) root.selected = name; }
        function open(name: string): void { if (root.panels.includes(name)) { root.selected = name; root.alert(name); } }
        function reply(): void { if (!root.panels.includes("notifications")) return; root.selected = "notifications"; root.alert("notifications"); root.replyRequested(); }
        function state(): string { return JSON.stringify({panel: root.selected, kdeConnected: root.kdePhoneConnected, alert: root.alertOpen, player: root.player?.identity ?? "", dedicatedPlayer: root.dedicatedPlayingPlayer?.identity ?? "", players: root.players.map(p => p.identity), calls: root.calls.length, messages: root.messages.length, phoneStatus: root.phoneStatus, phoneError: root.phoneError, notifications: root.notifications.length, phonePopups: Notifications.popupList.filter(n => n.phoneOrigin).length, desktopPopups: Notifications.popupList.filter(n => !n.phoneOrigin).length, transferFiles: GlobalStates.mediaTransferUrls.length, transferActive: GlobalStates.mediaTransferActive}); }
    }
}
