import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../services/PhoneContacts.js" as Contacts

// The paired phone through KDE Connect: its text conversations, sending it
// files, and browsing the files on it.
Item {
    id: root
    property real padding: 4
    // "list", "thread" or "new"
    property string view: "list"
    property string notice: ""
    property bool choosingPhone: false
    // The file sheet adds to the message being written rather than sending to the phone.
    property bool sheetAttaches: false
    // Files dropped on an open conversation go with its next message.
    readonly property bool attachesToMessage: Phone.device !== null && tabBar.currentIndex === 0 && root.view !== "list"

    QtObject {
        id: tabBar
        property int currentIndex: 0
    }

    // Opening the tab starts the daemon for a first pairing.
    property bool onScreen: false
    Binding { target: Phone; property: "setupVisible"; value: root.onScreen }
    Component.onCompleted: {
        if (Phone.openThread >= 0) {
            tabBar.currentIndex = 0;
            root.view = "thread";
            threadView.snapToBottom();
        }
    }

    function postNotice(text): void {
        root.notice = text;
        noticeTimer.restart();
    }

    function sendPaths(paths): void {
        if (!Phone.reachable) {
            root.postNotice(Translation.tr("%1 is not reachable right now.").arg(Phone.device?.name ?? Translation.tr("The phone")));
            return;
        }
        if (Phone.shareFiles(paths))
            root.postNotice(Translation.tr("Sending to %1…").arg(Phone.device?.name ?? ""));
    }

    function takeFiles(paths, attach): void {
        if (attach) threadView.addAttachments(paths);
        else root.sendPaths(paths);
    }

    function openFileSheet(attach): void {
        root.sheetAttaches = attach;
        fileSheetLoader.load().open();
    }

    function openThread(thread): void {
        if (root.view !== "list") threadView.saveDraft();
        Phone.openConversation(thread);
        root.view = "thread";
        threadView.restoreDraft();
        threadView.snapToBottom();
    }

    function backToList(): void {
        threadView.saveDraft();
        Phone.closeConversation();
        root.view = "list";
    }

    function composeTo(number, name): void {
        const target = Contacts.dialNumber(number);
        if (!/^\+?[0-9]+$/.test(target) || !Phone.reachable || !Phone.canMessage) return;
        // Resolve this contact explicitly. A previously open thread or a
        // group containing the contact is not the requested recipient.
        const thread = Phone.matchTargetToThread({number: target, name: name || "", deviceId: Phone.deviceId, directOnly: true});
        if (root.view !== "list") threadView.saveDraft();
        Phone.pendingTarget = null;
        Phone.closeConversation();
        root.view = "list";
        tabBar.currentIndex = 0;
        if (thread >= 0) root.openThread(thread);
        else {
            root.view = "new";
            threadView.setRecipient(target);
        }
    }

    function dialNumber(number): void {
        const target = Contacts.dialNumber(number);
        if (target && PhoneCalls.dial(target)) root.postNotice(Translation.tr("Calling %1…").arg(target));
    }

    Connections {
        target: PhoneCalls
        function onDialErrorChanged() {
            if (PhoneCalls.dialError) root.postNotice(PhoneCalls.dialError);
        }
    }

    Connections {
        target: Phone
        function onCanBrowseChanged() {
            if (!Phone.canMessage && Phone.canBrowse) tabBar.currentIndex = 2;
        }
        function onOpenThreadChanged() {
            if (Phone.openThread >= 0) {
                tabBar.currentIndex = 0;
                root.view = "thread";
                threadView.snapToBottom();
            }
        }
        function onConversationOpened(thread) {
            if (thread >= 0) {
                tabBar.currentIndex = 0;
                root.view = "thread";
                threadView.snapToBottom();
            }
        }
        function onShared(count) {
            root.postNotice(count === 1 ? Translation.tr("Sent a file to %1.").arg(Phone.device?.name ?? "")
                : Translation.tr("Sent %1 files to %2.").arg(count).arg(Phone.device?.name ?? ""));
        }
        function onAttachmentTimedOut() {
            root.postNotice(Phone.reachable ? Translation.tr("%1 did not send the file. Try again.").arg(Phone.device?.name ?? Translation.tr("The phone"))
                : Translation.tr("%1 is not reachable right now.").arg(Phone.device?.name ?? Translation.tr("The phone")));
        }
        function onFailed(context, message) {
            root.postNotice(Translation.tr("%1 could not do that: %2").arg(Phone.backendName).arg(message));
        }
    }

    Timer {
        id: noticeTimer
        interval: 4000
        onTriggered: root.notice = ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 8

        PhonePairCard {
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.choosingPhone
            IslandButton {
                symbol: "arrow_back"
                onClicked: root.choosingPhone = false
                StyledToolTip { text: Translation.tr("Back") }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Choose a phone")
                font.weight: Font.DemiBold
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.choosingPhone
            clip: true
            spacing: 8
            model: Phone.devices
            ScrollBar.vertical: StyledScrollBar {}
            delegate: PhoneDeviceCard {
                required property var modelData
                width: ListView.view.width
                device: modelData
                selected: modelData.id === Phone.deviceId
                onChosen: {
                    // Save the old device's draft before changing its context.
                    if (root.view !== "list") threadView.saveDraft();
                    Phone.selectDevice(modelData.id);
                    root.view = "list";
                    tabBar.currentIndex = 0;
                    root.choosingPhone = false;
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerColumn.implicitHeight + 16
            radius: 14
            color: Appearance.surfaces.raised
            // Cached contacts alone only head the Contacts page; they are not a phone.
            visible: !root.choosingPhone && (Phone.device !== null || (ContactService.records.length > 0 && tabBar.currentIndex === 1)) && (tabBar.currentIndex === 1 || tabBar.currentIndex === 2 || root.view === "list")

            ColumnLayout {
                id: headerColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                PhoneIdentityRow {
                    Layout.fillWidth: true
                    device: Phone.device
                    name: Phone.device?.name ?? (ContactService.records.length > 0 ? Translation.tr("Contacts") : "")

                    IslandButton {
                        visible: Phone.devices.length > 1
                        contentColors: Appearance.colors
                        symbol: "swap_horiz"
                        onClicked: root.choosingPhone = true
                        StyledToolTip { text: Translation.tr("Choose a phone") }
                    }

                    IslandButton {
                        contentColors: Appearance.colors
                        enabled: Phone.connected
                        symbol: "refresh"
                        onClicked: Phone.refreshConnection()
                        StyledToolTip { text: Translation.tr("Refresh phone connection") }
                    }

                    IslandButton {
                        contentColors: Appearance.colors
                        enabled: Phone.reachable && Phone.canShare
                        symbol: "upload_file"
                        onClicked: root.openFileSheet(false)
                        StyledToolTip {
                            text: Translation.tr("Send files to your phone\nOr drop them on this tab outside a conversation")
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 10
                    color: Appearance.surfaces.row

                    RowLayout {
                        id: switcherRow
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 0 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 0
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            visible: Phone.canMessage || Phone.conversations.length > 0
                            onClicked: tabBar.currentIndex = 0

                            contentItem: Item {
                                RowLayout {
                                    id: msgTabRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "chat_bubble"
                                        iconSize: 13
                                        color: tabBar.currentIndex === 0
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: Translation.tr("Messages")
                                        font.pixelSize: Appearance.font.scaled(11)
                                        font.weight: tabBar.currentIndex === 0 ? Font.DemiBold : Font.Medium
                                        color: tabBar.currentIndex === 0
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 3 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 3
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            onClicked: tabBar.currentIndex = 3

                            contentItem: Item {
                                RowLayout {
                                    id: callsTabRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "call"
                                        iconSize: 13
                                        color: tabBar.currentIndex === 3
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: Translation.tr("Calls")
                                        font.pixelSize: Appearance.font.scaled(11)
                                        font.weight: tabBar.currentIndex === 3 ? Font.DemiBold : Font.Medium
                                        color: tabBar.currentIndex === 3
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 1 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 1
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            onClicked: tabBar.currentIndex = 1

                            contentItem: Item {
                                RowLayout {
                                    id: contactsTabRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "contacts"
                                        iconSize: 13
                                        color: tabBar.currentIndex === 1
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: Translation.tr("Contacts")
                                        font.pixelSize: Appearance.font.scaled(11)
                                        font.weight: tabBar.currentIndex === 1 ? Font.DemiBold : Font.Medium
                                        color: tabBar.currentIndex === 1
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 2 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 2
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            visible: Phone.canBrowse
                            onClicked: {
                                tabBar.currentIndex = 2;
                                if (Phone.reachable && !Phone.mounted && !Phone.mounting) {
                                    Phone.mountFiles();
                                }
                            }

                            contentItem: Item {
                                RowLayout {
                                    id: filesTabRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "folder"
                                        iconSize: 13
                                        color: tabBar.currentIndex === 2
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        text: Translation.tr("Files")
                                        font.pixelSize: Appearance.font.scaled(11)
                                        font.weight: tabBar.currentIndex === 2 ? Font.DemiBold : Font.Medium
                                        color: tabBar.currentIndex === 2
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        StackLayout {
            visible: !root.choosingPhone
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: {
                if (tabBar.currentIndex === 1) return 2;
                if (tabBar.currentIndex === 3) return 5;
                if (tabBar.currentIndex === 2 && Phone.canBrowse && Phone.reachable) return 3;
                if (Phone.device === null && Phone.conversations.length === 0) return 0;
                if (tabBar.currentIndex === 0 && (Phone.canMessage || Phone.conversations.length > 0)) return 1;
                return 4;
            }

            Item {
                PagePlaceholder {
                    icon: "smartphone"
                    title: Phone.connected ? Translation.tr("Connect your phone") : Translation.tr("Looking for your phone")
                    description: Translation.tr("1. Install the free KDE Connect app on your phone. On Android, get it from the Google Play Store or F-Droid. On iPhone, get it from the App Store.\n2. Connect the phone to the same Wi-Fi network as this computer.\n3. Open KDE Connect on the phone, tap this computer in its list, then tap the button to pair with it. Pairing connects the two over Wi-Fi. It does not use Bluetooth or a cable.\n4. A request then appears at the top of this tab. Check that its code matches the one on your phone, then click Accept.") + "\n5. " + Translation.tr("On Android, allow contact access and enable contact sync in KDE Connect to see contact names and photos here. If you do this after pairing, click Refresh phone connection beside the phone name.")
                }
            }

            Item {
                PhoneConversationList {
                    anchors.fill: parent
                    visible: root.view === "list"
                    onOpened: thread => root.openThread(thread)
                    onNewMessage: {
                        Phone.pendingTarget = null;
                        Phone.closeConversation();
                        root.view = "new";
                        threadView.setRecipient("");
                    }
                    onSendFilesRequested: root.openFileSheet(false)
                }
                PhoneThreadView {
                    id: threadView
                    anchors.fill: parent
                    visible: root.view !== "list"
                    composing: root.view === "new"
                    onBack: root.backToList()
                    onAttachRequested: root.openFileSheet(true)
                    onNotice: text => root.postNotice(text)
                }
            }

            PhoneContactsView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onStartCall: num => root.dialNumber(num)
                onStartMessage: (num, name) => root.composeTo(num, name)
            }

            Loader {
                active: tabBar.currentIndex === 2 && Phone.canBrowse && Phone.reachable
                sourceComponent: PhoneFilesView {}
            }
            Item {
                PagePlaceholder {
                    icon: "smartphone"
                    title: Phone.reachable
                        ? Translation.tr("Connected to %1").arg(Phone.device?.name || Translation.tr("phone"))
                        : Translation.tr("%1 is not reachable right now.").arg(Phone.device?.name || Translation.tr("The phone"))
                    description: Phone.reachable
                        ? Translation.tr("This phone does not offer message history or remote file browsing. Use the send-file button to share files when supported.")
                        : Translation.tr("Keep your phone and this computer on the same Wi-Fi network, then open KDE Connect on your phone. Bluetooth pairing alone does not connect messages or files.")
                }
            }

            PhoneCallsView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onStartCall: number => root.dialNumber(number)
                onStartMessage: (number, name) => root.composeTo(number, name)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.notice.length > 0
            implicitHeight: noticeLabel.implicitHeight + 14
            radius: 10
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                MaterialSymbol {
                    text: "info"
                    iconSize: 15
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    id: noticeLabel
                    Layout.fillWidth: true
                    text: root.notice
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    SheetLoader {
        id: fileSheetLoader
        sourceComponent: FileSelectionSheet {
            onFileSelected: fileUrl => {
                const path = FileUtils.pathFromUrl(fileUrl);
                if (path.startsWith("/")) root.takeFiles([path], root.sheetAttaches);
            }
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        z: 100
        enabled: Phone.device !== null && !root.choosingPhone

        function localPaths(drag): var {
            if (!drag.hasUrls) return [];
            return drag.urls.map(url => String(url)).filter(text => text.startsWith("file:"))
                .map(FileUtils.pathFromUrl).filter(path => path.length > 0);
        }

        onEntered: drag => {
            if (dropArea.localPaths(drag).length === 0) {
                drag.accepted = false;
                return;
            }
            drag.accept(Qt.CopyAction);
        }
        onPositionChanged: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => {
            const paths = dropArea.localPaths(drop);
            if (paths.length === 0) return;
            drop.accept(Qt.CopyAction);
            if (fileSheetLoader.shown) fileSheetLoader.item.close();
            root.takeFiles(paths, root.attachesToMessage);
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: root.padding
            radius: 16
            color: ColorUtils.transparentize(Appearance.colors.colLayer2Base, 0.12)
            visible: opacity > 0
            opacity: dropArea.containsDrag ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.attachesToMessage ? "attach_file" : "send_to_mobile"
                        iconSize: 32
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.attachesToMessage ? Translation.tr("Drop to attach to this message")
                        : Translation.tr("Drop to send to %1").arg(Phone.device?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
