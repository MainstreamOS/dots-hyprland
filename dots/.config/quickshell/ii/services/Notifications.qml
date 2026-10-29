pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "IslandNotificationPolicy.js" as IslandNotificationPolicy
import "IslandText.js" as IslandText
import "NotificationIcons.js" as NotificationIcons

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property var savedActions: []
        readonly property var rawActions: (notification && notification.actions.length > 0)
            ? notification.actions.map((action) => ({
                "identifier": action.identifier,
                "text": action.text,
            }))
            : savedActions
        property bool popup: false
        // The Island shows phone notifications itself while the bar is the island.
        readonly property bool islandOwned: phoneOrigin && Appearance.sizes.barIsIsland && Config.options.bar.island.phoneIntegration
            && (IslandPhonePrivacy.suppressed || IslandPanels.enabled(islandPanel))
        function clearTimer() {
            timer?.stop();
            timer?.destroy();
            timer = null;
        }
        property bool phoneOrigin: notification ? IslandNotificationPolicy.isPhone(notification) : false
        property string islandPanel: notification ? IslandNotificationPolicy.panelFor(notification) : "notifications"
        property string sourceApp: notification?.hints?.["x-kde-display-appname"] || appName
        readonly property string effectiveApp: IslandNotificationPolicy.application(wrapper)
        property string kdeIdentity: ""
        // Set when a newer copy takes over, so closing this one keeps the entry.
        property bool replaced: false
        onNotificationChanged: if (notification === null && !replaced) root.discardNotification(notificationId)
        // Stable phone identity keeps history unique across backend restarts.
        property string phoneKey: notification?.hints?.["x-mainstream-notification-key"] || ""
        property string imageRole: {
            const role = notification?.hints?.["x-mainstream-image-role"] || "";
            return role === "app-icon" ? "notification-image" : role;
        }
        property string iconHash: notification?.hints?.["x-mainstream-icon-hash"] || ""
        property string kdeDeviceId: ""
        property string kdeInternalId: ""
        property string kdeReplyId: ""
        property string replyDraft: ""
        property string actionError: ""
        property bool actionPending: false
        property bool savedCanReply: false
        property string savedReplyPlaceholder: ""
        readonly property bool hasInlineReply: (notification?.hasInlineReply ?? false) || savedCanReply
        readonly property string inlineReplyPlaceholder: notification?.inlineReplyPlaceholder || savedReplyPlaceholder || ""
        readonly property bool canReply: IslandNotificationPolicy.hasReplyCapability(
            rawActions, hasInlineReply, kdeReplyId, phoneOrigin, effectiveApp, notification !== null
        ) && (!phoneOrigin || notification?.hasInlineReply || (!!kdeDeviceId && !!kdeIdentity && !!kdeInternalId && !!kdeReplyId))
        property list<var> actions: IslandNotificationPolicy.filterActions(
            rawActions, phoneOrigin, effectiveApp, notification !== null
        )
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        readonly property string headerIcon: root.resolveAppIcon(wrapper)
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        readonly property string plainBody: IslandText.body(body, true)
        property string sourceImage: root.imageSource(notification?.image ?? "")
        property string cachedImage: ""
        property string lastImage: ""
        property string lastImageHash: ""
        property string image: cachedImage || sourceImage
        onSourceImageChanged: {
            cachedImage = "";
        }
        property bool ready: false
        Component.onCompleted: {
            ready = true;
            NotificationImageCache.store(notificationId, sourceImage, iconHash);
        }
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer
        property Connections lifecycle: Connections {
            target: wrapper.notification
            function onAppIconChanged() { wrapper.scheduleUpdate(); }
            function onImageChanged() { wrapper.scheduleUpdate(); }
            function onAppNameChanged() { wrapper.scheduleUpdate(); }
            function onSummaryChanged() { wrapper.scheduleUpdate(); }
            function onBodyChanged() { wrapper.scheduleUpdate(); }
            function onActionsChanged() { wrapper.scheduleUpdate(); }
            function onHintsChanged() { wrapper.scheduleUpdate(); }
        }
        property Timer updateTimer: Timer {
            interval: 0
            onTriggered: root.notificationUpdated(wrapper)
        }
        function scheduleUpdate() { if (ready) updateTimer.restart(); }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.rawActions,
            "canReply": notif.canReply,
            "replyPlaceholder": notif.inlineReplyPlaceholder,
            "kdeIdentity": notif.kdeIdentity,
            "phoneKey": notif.phoneKey,
            "imageRole": notif.imageRole,
            "iconHash": notif.iconHash,
            "kdeDeviceId": notif.kdeDeviceId,
            "kdeInternalId": notif.kdeInternalId,
            "replyDraft": notif.replyDraft,
            "kdeReplyId": notif.kdeReplyId,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            // A provider URL is only valid in this shell generation. The
            // cache completion saves the durable file URL separately.
            "image": notif.image.startsWith("image://qsimage/") ? "" : notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
            "phoneOrigin": notif.phoneOrigin,
            "islandPanel": notif.islandPanel,
            "sourceApp": notif.sourceApp,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property bool historyReady: false
    property var incomingNotifications: []
    property bool writing: false
    property bool writeAgain: false
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter(notif => notif.popup && !notif.islandOwned);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    function appIconFor(name) { return NotificationIcons.appIconFor(name, AppSearch.list); }
    function resolveAppIcon(entry) {
        if (!entry) return "";
        const icon = String(entry.appIcon || "");
        const transport = /^(kde\s*connect|kdeconnectd|org\.kde\.kdeconnect|rust-connect)(\.desktop)?$/i.test(icon);
        // Android sends its large icon first, which may be a person's photo.
        // Keep that artwork in the body instead of substituting it for the app.
        const contentImage = entry.phoneOrigin && ["notification-image", "app-icon", "contact"].includes(entry.imageRole)
            && /^(file:|\/|image:\/\/icon\/\/)/.test(icon);
        if (icon && !transport && !contentImage && !icon.includes("image-missing")) {
            const source = root.iconSource(icon);
            if (source) return source;
        }
        for (const name of [entry.sourceApp, entry.appName]) {
            const source = root.iconSource(root.appIconFor(name));
            if (source) return source;
        }
        return "";
    }
    function imageSource(source) {
        const value = String(source || "");
        return value.startsWith("image://icon//") ? "file://" + value.slice("image://icon".length) : value;
    }
    function iconSource(icon) {
        const value = String(icon || "");
        if (!value) return "";
        if (/^(file:|image:|data:)/.test(value)) return value;
        if (value.startsWith("/")) return "file://" + value;
        return Quickshell.iconPath(value, "");
    }
    Connections {
        target: NotificationImageCache
        function onStored(notificationId, original, cached) {
            const notif = root.list.find(n => n.notificationId === notificationId && n.sourceImage === original);
            if (!notif) return;
            notif.cachedImage = cached;
            notif.lastImage = cached;
            notif.lastImageHash = notif.iconHash;
            root.saveSoon();
        }
    }
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.headerIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        inlineReplySupported: true
        // KDE Connect can send the app and contact as separate header fields
        // instead of joining the sender and message into one HTML body.
        extraHints: ["x-kde-display-appname", "x-kdeconnect-source-device", "x-kde-origin-name", "x-kde-eventId", "x-kde-appname", "desktop-entry", "x-mainstream-notification-key", "x-mainstream-image-role", "x-mainstream-icon-hash"]
        keepOnReload: true
        persistenceSupported: true

        onNotification: notification => root.receiveNotification(notification)
    }

    function receiveNotification(notification) {
        notification.tracked = true;
        if (!root.historyReady) {
            root.incomingNotifications = root.incomingNotifications.concat([notification]);
            return;
        }

        const mappedActions = notification.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        }));
        const notificationId = notification.id + root.idOffset;
        const phoneKey = notification.hints?.["x-mainstream-notification-key"] || "";
        const previous = root.list.find(n => n.notificationId === notificationId)
            || (phoneKey ? root.list.find(n => n.phoneKey === phoneKey) : null);
        const replay = !!previous && !!phoneKey && notification.hints?.["suppress-sound"] === true
            && previous.summary === notification.summary && previous.body === notification.body
            && previous.sourceApp === (notification.hints?.["x-kde-display-appname"] || notification.appName)
            && previous.iconHash === (notification.hints?.["x-mainstream-icon-hash"] || "");
        const retainedImage = !notification.image && previous?.iconHash
            && previous.iconHash === notification.hints?.["x-mainstream-icon-hash"]
            && previous.image.startsWith("file:") ? previous.image : "";
        previous?.clearTimer();
        const newNotifObject = notifComponent.createObject(root, {
            "notificationId": notificationId,
            "notification": notification,
            "savedActions": mappedActions,
            "savedCanReply": notification.hasInlineReply || mappedActions.some(a => IslandNotificationPolicy.isReplyAction(a)),
            "savedReplyPlaceholder": notification.inlineReplyPlaceholder || "",
            "replyDraft": previous?.replyDraft || "",
            "cachedImage": retainedImage,
            "lastImage": retainedImage,
            "lastImageHash": retainedImage ? previous.iconHash : "",
            "time": replay ? previous.time : Date.now(),
        });
        root.list = root.list.filter(n => n !== previous && n.notificationId !== notificationId).concat([newNotifObject]);
        if (previous) {
            // A backend restart allocates new desktop IDs for the same phone
            // keys. Expiry closes only the obsolete desktop copy, not the phone.
            previous.replaced = true;
            if (previous.notification && previous.notification !== notification) previous.notification.expire();
            previous.destroy();
        }
        if (newNotifObject.phoneOrigin) {
            root.inspectKdeNotification(newNotifObject);
        }

        if (!replay) {
            root.showPopup(newNotifObject);
            root.notify(newNotifObject);
        }
        root.saveSoon();
    }

    function notificationUpdated(notif) {
        if (!notif.notification || !root.list.includes(notif)) return;
        // Quickshell mutates a replacement in place; NotificationServer's
        // notification signal only fires when a new server ID is allocated.
        notif.time = Date.now();
        // Image and hints change separately. Copy after both have settled so
        // new pixels cannot be saved under the previous image's content hash.
        NotificationImageCache.store(notif.notificationId, notif.sourceImage, notif.iconHash);
        if (!notif.sourceImage && notif.iconHash && notif.lastImageHash === notif.iconHash) {
            notif.cachedImage = notif.lastImage;
        } else if (!notif.sourceImage) notif.cachedImage = "";
        notif.savedActions = notif.rawActions;
        notif.savedCanReply = notif.notification.hasInlineReply || notif.rawActions.some(a => IslandNotificationPolicy.isReplyAction(a));
        root.inspectKdeNotification(notif);
        root.triggerListChange();
        root.showPopup(notif, false);
        root.notify(notif);
        root.saveSoon();
    }

    function showPopup(newNotifObject, counted = true) {
        const notification = newNotifObject.notification;
        newNotifObject.clearTimer();
        newNotifObject.popup = false;
        if (!root.popupInhibited && !newNotifObject.islandOwned) {
            newNotifObject.popup = true;
            if (notification.expireTimeout != 0) {
                newNotifObject.timer = notifTimerComponent.createObject(root, {
                    "notificationId": newNotifObject.notificationId,
                    "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                });
            }
            if (counted) root.unread++;
        } else if (counted && newNotifObject.islandOwned && !root.popupInhibited) {
            root.unread++;
        }
    }

    // Saved artwork is kept while a notification or the Island's phone history
    // shows it. The Island's history loads on its own, so wait until it has.
    function pruneImages() {
        if (!IslandPhoneHistory.ready) {
            pruneImagesTimer.restart();
            return;
        }
        // QML's JavaScript has no flatMap on these lists.
        const history = [];
        for (const m of IslandPhoneHistory.messages) history.push(m.picture, m.previewImage, ...(m.images ?? []));
        for (const c of IslandPhoneHistory.calls) history.push(c.picture);
        for (const c of IslandPhoneHistory.contactPhotos) history.push(c.picture);
        NotificationImageCache.prune(root.list.map(n => n.image).concat(history));
    }
    Timer { id: pruneImagesTimer; interval: 30000; onTriggered: root.pruneImages() }

    function historyLoaded() {
        root.historyReady = true;
        pruneImagesTimer.restart();
        const incoming = root.incomingNotifications;
        root.incomingNotifications = [];
        for (const notification of incoming) root.receiveNotification(notification);
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            const removed = root.list[index];
            removed.clearTimer();
            root.list.splice(index, 1);
            // Cards showing it are still bound until the list change and their remove animation finish.
            removed.destroy(1000);
            root.saveSoon();
            triggerListChange()
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
        pruneImagesTimer.restart();
    }

    function discardAllNotifications() {
        pruneImagesTimer.restart();
        for (const item of root.list) { item.clearTimer(); item.destroy(); }
        root.list = []
        triggerListChange()
        root.saveSoon();
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        root.list[index]?.timer?.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    property var phoneJobs: []
    property var inspectPending: []
    property var activePhoneJob: null
    property int phoneSequence: 0
    signal phoneActionFinished(notificationId: int, success: bool)

    function saveSoon() { saveNotifications.restart(); }
    Timer {
        id: saveNotifications
        interval: 250
        onTriggered: root.writeNotifications()
    }

    function writeNotifications() {
        if (!root.historyReady) return;
        if (root.writing) { root.writeAgain = true; return; }
        const text = root.stringifyList(root.list);
        if (text === notifFileView.text()) return;
        root.writing = true;
        notifFileView.setText(text);
    }
    function notificationWriteDone() {
        root.writing = false;
        if (root.writeAgain) { root.writeAgain = false; root.saveSoon(); }
    }
    function queuePhoneJob(job): bool {
        if (root.phoneJobs.length >= 64) return false;
        job.id = String(++root.phoneSequence);
        root.phoneJobs = root.phoneJobs.concat([job]);
        root.pumpPhoneJobs();
        return true;
    }
    function pumpPhoneJobs() {
        if (!Phone.connected || root.activePhoneJob || !root.phoneJobs.length) return;
        if (!Phone.notificationJob(root.phoneJobs[0])) return;
        root.activePhoneJob = root.phoneJobs[0];
        root.phoneJobs = root.phoneJobs.slice(1);
        phoneDeadline.restart();
    }
    function phoneJobDone(result) {
        const job = root.activePhoneJob;
        if (!job || String(result.id) !== job.id) return;
        phoneDeadline.stop();
        root.activePhoneJob = null;
        if (job.cmd === "inspect") {
            for (const value of result.result || []) {
                const item = job.items.find(i => i.notificationId === value.notificationId);
                const target = root.list.find(n => n.notificationId === value.notificationId);
                const info = value.info;
                if (!target || !item || !info?.device || target.plainBody !== item.body || target.summary !== item.summary) continue;
                target.kdeIdentity = info.identity || "";
                target.kdeDeviceId = info.device;
                target.kdeInternalId = info.internalId || "";
                target.kdeReplyId = info.replyId || "";
            }
            root.saveSoon();
        } else {
            const target = root.list.find(n => n.notificationId === job.notificationId);
            if (target) {
                target.actionPending = false;
                target.actionError = result.ok ? "" : Translation.tr("The phone could not complete this action. Your reply has been kept.");
                if (result.ok) target.replyDraft = "";
            }
            root.phoneActionFinished(job.notificationId, !!result.ok);
            if (result.ok) root.discardNotification(job.notificationId);
            else root.saveSoon();
        }
        Qt.callLater(root.pumpPhoneJobs);
    }
    function inspectKdeNotification(notif) {
        if (!notif?.phoneOrigin || !notif.notification || root.inspectPending.includes(notif.notificationId)) return;
        root.inspectPending = root.inspectPending.concat([notif.notificationId]);
        inspectBatch.restart();
    }
    Timer {
        id: inspectBatch
        interval: 100
        onTriggered: {
            const ids = root.inspectPending.slice(0, 64);
            root.inspectPending = root.inspectPending.slice(64);
            const items = ids.map(id => root.list.find(n => n.notificationId === id)).filter(n => !!n?.notification).map(n => ({
                notificationId: n.notificationId,
                app: n.effectiveApp || n.sourceApp || n.appName || "",
                summary: n.summary, body: n.plainBody,
                source: n.notification?.hints?.["x-kdeconnect-source-device"] || ""
            }));
            if (items.length) root.queuePhoneJob({cmd: "inspect", items});
            if (root.inspectPending.length) inspectBatch.restart();
        }
    }
    Connections {
        target: Phone
        function onConnectedChanged() {
            if (!Phone.connected && root.activePhoneJob) root.phoneJobDone({id: root.activePhoneJob.id, ok: false});
            root.pumpPhoneJobs();
        }
        function onNotificationResult(result) { root.phoneJobDone(result); }
    }
    Timer {
        id: phoneDeadline
        interval: 30000
        onTriggered: if (root.activePhoneJob) root.phoneJobDone({id: root.activePhoneJob.id, ok: false})
    }

    function attemptInvokeAction(id, notifIdentifier, actionLabel) {
        const notif = root.list.find(n => n.notificationId === id);
        if (!notif || notif.actionPending) return;
        const matched = (notif.rawActions || []).find(a => a.identifier === notifIdentifier || a.text === notifIdentifier || (actionLabel && a.text === actionLabel));
        const label = actionLabel || matched?.text || notifIdentifier || "";
        // A phone's Copy action would copy on the phone; copy here instead.
        if (notif.phoneOrigin && /^copy\b/i.test(label.trim())) {
            const code = (label + " " + notif.plainBody).match(/\b([0-9]{4,8}|[A-Z0-9]{5,8})\b/);
            Quickshell.clipboardText = code ? code[1] : notif.plainBody;
            root.discardNotification(id);
            return;
        }
        const action = notif.notification?.actions.find(a => a.identifier === notifIdentifier || a.text === label);
        if (action) {
            action.invoke();
            root.discardNotification(id);
            return;
        }
        if (notif.phoneOrigin && root.queuePhoneJob({cmd: "action", notificationId: id,
            device: notif.kdeDeviceId, internalId: notif.kdeInternalId, identity: notif.kdeIdentity, label})) {
            notif.actionPending = true;
            notif.actionError = "";
        }
    }

    function sendReply(id, replyText): bool {
        const text = (replyText || "").trim();
        const notif = root.list.find(n => n.notificationId === id);
        if (!text || !notif || notif.actionPending) return false;
        notif.replyDraft = text;
        root.saveSoon();
        // The phone confirms a reply sent to its notification object. rust-connect
        // does not deliver inline replies, so a phone reply waits for that identity.
        if (notif.phoneOrigin && notif.kdeDeviceId && notif.kdeInternalId && notif.kdeReplyId) {
            const queued = root.queuePhoneJob({cmd: "reply", notificationId: id, device: notif.kdeDeviceId,
                internalId: notif.kdeInternalId, identity: notif.kdeIdentity, replyId: notif.kdeReplyId, text});
            notif.actionPending = queued;
            notif.actionError = queued ? "" : Translation.tr("Phone connection busy. Try again.");
            return queued;
        }
        if (notif.notification?.hasInlineReply && !(notif.phoneOrigin && Phone.backendName === "rust-connect")) {
            notif.notification.sendInlineReply(text);
            root.phoneActionFinished(id, true);
            root.discardNotification(id);
            return true;
        }
        if (notif.phoneOrigin) {
            root.inspectKdeNotification(notif);
            notif.actionError = Translation.tr("Still checking this notification with the phone. Try again in a moment.");
        }
        return false;
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(root.filePath)
        onSaved: root.notificationWriteDone()
        onSaveFailed: root.notificationWriteDone()
        onLoaded: {
            const fileContents = notifFileView.text()
            let saved = [];
            try { saved = JSON.parse(fileContents); }
            catch (error) { console.warn("[Notifications] Invalid saved history:", error); }
            // Collapse old backend-restart copies before creating wrappers.
            // Preserve the newest record and any unsent draft from its copies.
            const keyed = new Map();
            for (const entry of Array.isArray(saved) ? saved : []) {
                entry.phoneKey = entry.phoneKey || entry.traceKey || "";
                if (entry.phoneKey && entry.imageRole === "app-icon") {
                    entry.imageRole = "notification-image";
                    entry.appIcon = "";
                }
                if (!entry.phoneKey) continue;
                const old = keyed.get(entry.phoneKey);
                if (!old || entry.time >= old.time) {
                    entry.replyDraft = entry.replyDraft || old?.replyDraft || "";
                    keyed.set(entry.phoneKey, entry);
                } else old.replyDraft = old.replyDraft || entry.replyDraft || "";
            }
            // Builds without the closed-notification discard saved closed entries with no text.
            saved = (Array.isArray(saved) ? saved : []).filter(entry => (entry.appName || entry.summary || entry.body)
                && (!entry.phoneKey || keyed.get(entry.phoneKey) === entry));
            root.list = (Array.isArray(saved) ? saved : []).map((notif) => {
                const image = NotificationImageCache.historySource(
                    root.imageSource(notif.image), notif.iconHash);
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "savedActions": notif.actions || [],
                    "savedCanReply": notif.canReply ?? false,
                    "savedReplyPlaceholder": notif.replyPlaceholder || "",
                    "kdeIdentity": notif.kdeIdentity || "",
                    "phoneKey": notif.phoneKey || "",
                    "imageRole": notif.imageRole || "",
                    "iconHash": notif.iconHash || "",
                    "kdeDeviceId": notif.kdeDeviceId || "",
                    "kdeInternalId": notif.kdeInternalId || "",
                    "replyDraft": notif.replyDraft || "",
                    "kdeReplyId": notif.kdeReplyId || "",
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": image.startsWith("image://qsimage/") ? "" : image,
                    "lastImage": image.startsWith("file:") ? image : "",
                    "lastImageHash": image ? notif.iconHash || "" : "",
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                    "phoneOrigin": notif.phoneOrigin ?? false,
                    "islandPanel": notif.islandPanel ?? "notifications",
                    "sourceApp": notif.sourceApp || notif.appName,
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.initDone()
            root.historyLoaded()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                root.saveSoon();
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
            root.historyLoaded()
        }
    }
}
