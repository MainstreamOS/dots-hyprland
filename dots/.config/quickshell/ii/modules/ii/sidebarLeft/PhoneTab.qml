import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarLeft.aiChat
import QtQuick
import QtQuick.Layouts
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
    // The file sheet adds to the message being written rather than sending to the phone.
    property bool sheetAttaches: false
    // Files dropped on an open conversation go with its next message.
    readonly property bool attachesToMessage: Phone.device !== null && tabBar.currentIndex === 0 && root.view !== "list"

    QtObject {
        id: tabBar
        property int currentIndex: 0
    }

    // Opening the tab starts the phone daemon for a first pairing; the main
    // shell keeps the bridge itself running.
    property bool onScreen: false
    onOnScreenChanged: if (onScreen) Phone.wanted = true
    Component.onCompleted: {
        if (Phone.openThread >= 0) {
            tabBar.currentIndex = 0;
            root.view = "thread";
            threadView.snapToBottom();
        }
    }
    Component.onDestruction: Phone.wanted = false

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

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 50
            radius: 14
            color: Appearance.surfaces.raised
            // Cached contacts alone only head the Contacts page; they are not a phone.
            visible: (Phone.device !== null || (ContactService.records.length > 0 && tabBar.currentIndex === 1)) && (tabBar.currentIndex === 1 || tabBar.currentIndex === 2 || root.view === "list")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 9
                    color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.55)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: Phone.reachable ? "smartphone" : "phonelink_off"
                        iconSize: 17
                        color: Phone.reachable ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: Phone.device?.name ?? (ContactService.records.length > 0 ? Translation.tr("Contacts") : "")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: Phone.reachable ? Appearance.m3colors.m3success : Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                if (Phone.device !== null) {
                                    if (!Phone.reachable) return Translation.tr("Not reachable");
                                    const charge = Phone.device?.charge ?? -1;
                                    if (charge >= 0) {
                                        return Phone.device.charging
                                            ? Translation.tr("%1% · Charging").arg(charge)
                                            : Translation.tr("%1% · Connected").arg(charge);
                                    }
                                    return Translation.tr("Connected");
                                }
                                return Translation.tr("Ready");
                            }
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 32
                    implicitWidth: switcherRow.implicitWidth + 6
                    radius: 10
                    color: Appearance.surfaces.row

                    RowLayout {
                        id: switcherRow
                        anchors.centerIn: parent
                        spacing: 2

                        RippleButton {
                            implicitHeight: 26
                            implicitWidth: msgTabRow.implicitWidth + 14
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 0 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 0
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            visible: Phone.canMessage || Phone.conversations.length > 0
                            onClicked: tabBar.currentIndex = 0

                            contentItem: RowLayout {
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
                                    font.pixelSize: 11
                                    font.weight: tabBar.currentIndex === 0 ? Font.DemiBold : Font.Medium
                                    color: tabBar.currentIndex === 0
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colSubtext
                                }
                            }
                        }

                        RippleButton {
                            implicitHeight: 26
                            implicitWidth: contactsTabRow.implicitWidth + 14
                            buttonRadius: Appearance.rounding.verysmall
                            colBackground: tabBar.currentIndex === 1 ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: tabBar.currentIndex === 1
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            onClicked: tabBar.currentIndex = 1

                            contentItem: RowLayout {
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
                                    font.pixelSize: 11
                                    font.weight: tabBar.currentIndex === 1 ? Font.DemiBold : Font.Medium
                                    color: tabBar.currentIndex === 1
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colSubtext
                                }
                            }
                        }

                        RippleButton {
                            implicitHeight: 26
                            implicitWidth: filesTabRow.implicitWidth + 14
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

                            contentItem: RowLayout {
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
                                    font.pixelSize: 11
                                    font.weight: tabBar.currentIndex === 2 ? Font.DemiBold : Font.Medium
                                    color: tabBar.currentIndex === 2
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
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
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: {
                if (tabBar.currentIndex === 1) return 2;
                if (tabBar.currentIndex === 2 && Phone.canBrowse) return 3;
                if (Phone.device === null && Phone.conversations.length === 0) return 0;
                if (tabBar.currentIndex === 0 && (Phone.canMessage || Phone.conversations.length > 0)) return 1;
                return 4;
            }

            Item {
                PagePlaceholder {
                    icon: "smartphone"
                    title: Phone.connected ? Translation.tr("Connect your phone") : Translation.tr("Looking for your phone")
                    description: Translation.tr("1. Install the free KDE Connect app on your phone. On Android, get it from the Google Play Store or F-Droid. On iPhone, get it from the App Store.\n2. Connect the phone to the same Wi-Fi network as this computer.\n3. Open KDE Connect on the phone, tap this computer in its list, then tap the button to pair with it. Pairing connects the two over Wi-Fi. It does not use Bluetooth or a cable.\n4. A request then appears at the top of this tab. Check that its code matches the one on your phone, then click Accept.")
                }
                // rust-connect has no pairing window of its own; KDE Connect's app may be installed.
                Process {
                    id: pairingApp
                    property bool found: false
                    running: true
                    command: ["sh", "-c", "command -v kdeconnect-app"]
                    onExited: exitCode => pairingApp.found = exitCode === 0
                }
                RippleButtonWithIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    visible: Phone.connected && pairingApp.found
                    materialIcon: "devices"
                    mainText: Translation.tr("Open KDE Connect")
                    onClicked: Quickshell.execDetached(["kdeconnect-app"])
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
                    title: Translation.tr("Connected to %1").arg(Phone.device?.name || Translation.tr("phone"))
                    description: Translation.tr("This phone does not offer message history or remote file browsing. Use the send-file button to share files when supported.")
                }
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
        enabled: Phone.device !== null

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
