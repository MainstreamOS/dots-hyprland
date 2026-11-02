import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// A phone message on the traditional bar, with a reply box. The conversation itself opens in the sidebar.
Item {
    id: root

    required property var entry
    signal dismissed
    // The switches of whichever bar is in use; both name them alike.
    readonly property var privacy: Appearance.sizes.barIsIsland ? Config.options.bar.island : Config.options.sidebar.phone.privacy
    property bool replying: false
    property string error: ""
    property string sendRequest: ""
    property int mirroredReply: -1
    readonly property bool sending: root.sendRequest.length > 0 || root.mirroredReply >= 0

    readonly property string number: root.entry?.number || root.entry?.address || ""
    // Carried beside the message's id, which is reshaped for telling replays apart.
    readonly property int notificationId: Number.isInteger(root.entry?.notificationId) ? root.entry.notificationId : -1
    readonly property bool canMessage: !!root.number && Phone.canMessage && Phone.reachable
        && (!root.entry?.deviceId || root.entry.deviceId === Phone.deviceId)
    readonly property bool canReplyToNotification: Notifications.list.find(n => n.notificationId === root.notificationId)?.canReply ?? false
    readonly property bool canReply: root.canMessage || root.canReplyToNotification
    readonly property string contactName: {
        if (root.privacy.showContactName && root.entry?.name && root.entry.name !== root.number)
            return root.entry.name;
        if (root.privacy.showPhoneNumber && root.number)
            return root.number;
        return Translation.tr("Private contact");
    }
    readonly property string preview: {
        if (!root.privacy.showMessage)
            return Translation.tr("Message contents hidden");
        const text = String(root.entry?.body ?? "").replace(/\s+/g, " ").trim();
        if (text)
            return text;
        if (root.entry?.audioClips?.length)
            return Translation.tr("Audio clip");
        return root.entry?.images?.length ? Translation.tr("Photo message") : Translation.tr("New message");
    }

    function send() {
        const text = replyField.text.trim();
        if (!text || root.sending)
            return;
        root.error = "";
        if (root.canMessage) {
            if (Phone.sendNew([root.number], text, []))
                root.sendRequest = Phone.lastSendRequest;
            else
                root.error = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        } else if (Notifications.sendReply(root.notificationId, text)) {
            root.mirroredReply = root.notificationId;
        } else {
            root.error = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        }
    }

    function openInSidebar() {
        Phone.wanted = true;
        SidebarLeftTabs.showTab("phone");
        Phone.openEntryConversation(root.entry);
        root.dismissed();
    }

    Connections {
        target: Phone
        enabled: root.sendRequest.length > 0
        function onSendFinished(request, success) {
            if (request !== root.sendRequest)
                return;
            root.sendRequest = "";
            if (success)
                root.dismissed();
            else
                root.error = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        }
    }

    Connections {
        target: Notifications
        enabled: root.mirroredReply >= 0
        function onPhoneActionFinished(notificationId, success) {
            if (notificationId !== root.mirroredReply)
                return;
            root.mirroredReply = -1;
            if (success)
                root.dismissed();
            else
                root.error = Translation.tr("Your reply could not be sent. Check the connection and try again.");
        }
    }

    // The card stays for as long as it is being read or answered.
    Timer {
        interval: Math.max(3, Config.options.bar.island.alertSeconds) * 1000
        running: !hover.hovered && !root.replying && !root.sending
        onTriggered: root.dismissed()
    }

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight

    HoverHandler {
        id: hover
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 24
        color: Appearance.colors.colBackgroundSurfaceContainer
        radius: RoundedCorners.on ? Appearance.rounding.normal : 0

        ColumnLayout {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ClippingRectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 20
                    color: Appearance.colors.colSecondaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: photo.status !== Image.Ready
                        text: "chat"
                        fill: 1
                        iconSize: 20
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    Image {
                        id: photo
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: root.privacy.showContactPicture ? (root.entry?.picture ?? "") : ""
                        sourceSize: Qt.size(80, 80)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.contactName
                        elide: Text.ElideRight
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.preview
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.dismissed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.replying
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 6

                    StyledTextInput {
                        id: replyField
                        Layout.fillWidth: true
                        clip: true
                        color: Appearance.colors.colOnLayer1
                        Keys.onReturnPressed: root.send()
                        Keys.onEnterPressed: root.send()
                        Keys.onEscapePressed: root.replying = false

                        StyledText {
                            visible: replyField.text.length === 0
                            text: Translation.tr("Write a reply")
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        enabled: replyField.text.trim().length > 0 && !root.sending
                        onClicked: root.send()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "send"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.error.length > 0
                text: root.error
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3error
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !root.replying
                spacing: 8
                Item {
                    Layout.fillWidth: true
                }
                RippleButtonWithIcon {
                    materialIcon: "open_in_new"
                    mainText: Translation.tr("Open")
                    onClicked: root.openInSidebar()
                }
                RippleButtonWithIcon {
                    visible: root.canReply
                    materialIcon: "reply"
                    mainText: Translation.tr("Reply")
                    onClicked: {
                        root.replying = true;
                        replyField.forceActiveFocus();
                    }
                }
            }
        }
    }
}
