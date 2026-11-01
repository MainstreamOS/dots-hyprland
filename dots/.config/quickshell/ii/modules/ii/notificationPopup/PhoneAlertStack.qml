import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

// Calls and messages from the phone, above the desktop's notifications. With the Dynamic
// Island as the bar, only those whose own panel has been turned off land here.
ColumnLayout {
    id: root

    readonly property bool shown: IslandState.phoneWanted
        && Config.options.bar.island.automaticAlerts && !IslandPhonePrivacy.suppressed && !Notifications.silent
    function ownedByIsland(panel) {
        return Appearance.sizes.barIsIsland && IslandPanels.enabled(panel);
    }
    readonly property bool showsCalls: root.shown && !root.ownedByIsland("call")
    readonly property bool showsMessages: root.shown && !root.ownedByIsland("text")
    readonly property var calls: root.showsCalls ? IslandState.calls : []
    readonly property bool hasCards: root.calls.length > 0 || messageCards.count > 0
    property int replyingCards: 0
    readonly property bool replying: root.replyingCards > 0
    // A phone left off overnight can catch up all at once when it reconnects.
    readonly property int newestAlertAge: 120000
    spacing: 6

    function addCard(entry) {
        if (!entry || Date.now() - (entry.time || 0) > root.newestAlertAge
                || !Phone.keepMessages([entry], entry.deviceId).length)
            return;
        // A conversation is its phone plus its thread, or else its number. A name alone can
        // belong to two people, on one phone or on two.
        const digits = String(entry.number || entry.address || "").replace(/\D/g, "");
        const conversation = entry.thread !== undefined && entry.thread !== null && entry.thread >= 0 ? "thread:" + entry.thread
            : digits ? "number:" + digits : "name:" + (entry.name || entry.id);
        const key = JSON.stringify([entry.deviceId || "", conversation]);
        const json = JSON.stringify(entry);
        // A conversation holds one card, showing what was last said.
        for (let i = 0; i < messageCards.count; i++) {
            if (messageCards.get(i).key === key) {
                messageCards.setProperty(i, "json", json);
                return;
            }
        }
        messageCards.insert(0, {key, json});
        while (messageCards.count > 3)
            messageCards.remove(messageCards.count - 1);
    }

    function removeCard(key) {
        for (let i = 0; i < messageCards.count; i++) {
            if (messageCards.get(i).key === key) {
                messageCards.remove(i);
                return;
            }
        }
    }

    onShowsMessagesChanged: if (!root.showsMessages) messageCards.clear()

    function purgeDeletedCards() {
        for (let i = messageCards.count - 1; i >= 0; i--) {
            const entry = JSON.parse(messageCards.get(i).json);
            if (!Phone.keepMessages([entry], entry.deviceId).length) messageCards.remove(i);
        }
    }

    Connections {
        target: Phone
        function onConversationsDeleted(device, threads, before) { root.purgeDeletedCards(); }
        function onSavedLocalSentChanged() { root.purgeDeletedCards(); }
    }

    ListModel {
        id: messageCards
    }

    Connections {
        target: IslandState
        function onMessageReceived(id) {
            // IslandState.message follows this list, and may not have yet when this arrives.
            if (root.showsMessages)
                root.addCard(IslandState.messages[0]);
        }
    }

    // What an iPhone mirrors over Bluetooth has no desktop notification of its own.
    property string lastPhoneNotification: ""
    readonly property var phoneNotification: IslandState.phoneNotifications[0] ?? null
    onPhoneNotificationChanged: {
        const id = root.phoneNotification?.id ?? "";
        if (id && id !== root.lastPhoneNotification && root.calls.length === 0
                && root.shown && !root.ownedByIsland("notifications")) {
            root.addCard({
                id: id,
                name: root.phoneNotification.name,
                body: root.phoneNotification.body,
                picture: root.phoneNotification.picture,
                time: root.phoneNotification.time || Date.now()
            });
        }
        root.lastPhoneNotification = id;
    }

    Repeater {
        model: root.calls
        PhoneCallCard {
            required property var modelData
            entry: modelData
        }
    }

    Repeater {
        model: messageCards
        PhoneMessageCard {
            required property string key
            required property string json
            entry: JSON.parse(json)
            onDismissed: root.removeCard(key)
            onReplyingChanged: root.replyingCards += replying ? 1 : -1
            Component.onDestruction: if (replying) root.replyingCards--
        }
    }
}
