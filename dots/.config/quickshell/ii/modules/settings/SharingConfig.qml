import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Only what a form is doing right now lives here. Settings rebuilds this
    // page on every switch and color change, so anything that has to outlast
    // that (a run in flight, an error, the folder Files asked for) is kept by
    // FileSharing instead.
    property bool showPassword: false
    property bool changingPassword: false
    property bool renaming: false

    readonly property var currentNetwork: FileSharing.currentConnection
    // Everything past the notices needs the helper, and a Samba setup this
    // page is allowed to manage.
    readonly property bool canManage: FileSharing.loaded && FileSharing.helper && !FileSharing.foreign

    Component.onCompleted: FileSharing.watch()
    Component.onDestruction: FileSharing.unwatch()

    Connections {
        target: FileSharing
        // A click breaks the binding, so a refused or canceled prompt would
        // otherwise leave the switch showing a change that never happened.
        function onRefreshed() {
            mainSwitch.checked = FileSharing.isOn;
        }
        function onPasswordSuggested(suggestion) {
            newPasswordField.text = suggestion;
        }
        function onPasswordSaved() {
            root.changingPassword = false;
            newPasswordField.text = "";
        }
        function onRenamed() {
            root.renaming = false;
        }
    }

    component Intro: StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
    }

    // Red, as on the Gaming page, under the section the failed change
    // belongs to rather than at the top of a page that may be scrolled.
    component SharingError: StyledText {
        property string forScope
        Layout.fillWidth: true
        visible: FileSharing.errorScope === forScope && FileSharing.lastError.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.m3colors.m3error
        text: FileSharing.lastError
    }

    // One thing to type on the other computer, and a button that copies it
    // and briefly turns into a check.
    component CopyRow: Rectangle {
        id: copyRow
        property string iconName
        property string label
        property string value
        property string shownValue: value
        property string hint: ""
        property bool justCopied: false
        default property alias buttons: buttonRow.data

        Layout.fillWidth: true
        implicitHeight: 60
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 6
            spacing: 12

            MaterialSymbol {
                text: copyRow.iconName
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: copyRow.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    MaterialSymbol {
                        visible: copyRow.hint.length > 0
                        text: "info"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                        MouseArea {
                            id: hintMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.WhatsThisCursor
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: hintMouseArea.containsMouse
                                text: copyRow.hint
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: copyRow.shownValue
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: buttonRow
                spacing: 0
            }

            RowIconButton {
                iconName: copyRow.justCopied ? "check" : "content_copy"
                tip: Translation.tr("Copy")
                enabled: copyRow.value.length > 0
                onClicked: {
                    Quickshell.clipboardText = copyRow.value;
                    copyRow.justCopied = true;
                    copiedTimer.restart();
                }
                Timer {
                    id: copiedTimer
                    interval: 1500
                    onTriggered: copyRow.justCopied = false
                }
            }
        }
    }

    component RowIconButton: RippleButton {
        id: iconButton
        property string iconName
        property string tip
        buttonRadius: Appearance.rounding.full
        implicitWidth: 34
        implicitHeight: 34
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.iconName
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: iconButton.tip
        }
    }

    component NoticeAction: RippleButtonWithIcon {
        Layout.fillWidth: false
        buttonRadius: Appearance.rounding.small
        colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colRipple: Appearance.colors.colPrimaryContainerActive
    }

    // ── Sharing ───────────────────────────────────────────────────────────────
    ContentSection {
        icon: "folder_shared"
        title: Translation.tr("Sharing")

        Intro {
            visible: !FileSharing.loaded || FileSharing.helper
            text: Translation.tr("Let other computers on your home network open folders on this one. Works with Windows, Mac and Linux.")
        }

        // The page arrives with dots updates, before the package that carries
        // the helper, so an older install is told what it is missing.
        StyledText {
            Layout.fillWidth: true
            visible: FileSharing.loaded && !FileSharing.helper
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Update Mainstream to turn on sharing.")
        }

        // Nothing has failed when this shows, so it is a notice with a way
        // forward. Once the file is gone the page takes over by itself, since
        // it keeps reading while open.
        NoticeBox {
            Layout.fillWidth: true
            visible: FileSharing.loaded && FileSharing.helper && FileSharing.foreign
            materialIcon: "settings"
            text: Translation.tr("This computer has its own Samba setup in /etc/samba/smb.conf, so this page leaves sharing to it. To manage sharing here instead, rename or move that file.")
        }

        // Nothing but the firewall keeps SMB to the home network, so the
        // helper will not share without it. Said here, since the switch and
        // Share on This Network would otherwise fail after the prompt. Samba
        // that was already running when the firewall stopped keeps running,
        // and then the folders are not safe, so that is said instead.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && !FileSharing.firewall
            materialIcon: "gpp_bad"
            text: FileSharing.serviceRunning
                ? Translation.tr("The firewall is turned off while sharing is running, so your shared folders can be reached from other networks this computer is connected to. Turn the firewall back on, or turn sharing off.")
                : FileSharing.firewallMessage()
        }

        // The switch trusts the network the computer is on, and the Networks
        // section that names it only appears afterwards. Turning sharing off
        // forgot every network trusted before, so this shows each time.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && !FileSharing.isOn && !FileSharing.busy && FileSharing.firewall
                && root.currentNetwork !== null && root.currentNetwork.eligible
            materialIcon: FileSharing.installed ? "shield" : "download"
            text: (FileSharing.installed
                    ? Translation.tr("Turning this on opens the folders you share to other computers on %1, the network you are on now.")
                    : Translation.tr("Turning this on downloads the sharing service (about 9 MB) and asks for your password once. The folders you share are then open to other computers on %1, the network you are on now."))
                .arg(root.currentNetwork?.name ?? "")
        }

        // A cable profile is not tied to one place, so trusting it trusts
        // every network it gets plugged into. The warning comes before the
        // switch or Share on This Network trusts it, since the Networks
        // section only appears afterwards.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && root.currentNetwork !== null
                && root.currentNetwork.type === "ethernet" && !root.currentNetwork.trusted
                && root.currentNetwork.eligible
                && (!FileSharing.isOn || FileSharing.ready) && !FileSharing.settingUp
                && FileSharing.firewall
            materialIcon: "settings_ethernet"
            // While sharing is on, the switch right below is not the thing to
            // change, so the way forward named here is the home Wi-Fi.
            text: FileSharing.isOn
                ? Translation.tr("%1 is a cable connection, so sharing on it applies wherever this computer is plugged in. On a laptop that leaves the house, share on your home Wi-Fi instead.")
                    .arg(root.currentNetwork?.name ?? "")
                : Translation.tr("You are connected by cable. Turning sharing on here also opens the folders you share on any other cable network this computer is plugged into. On a laptop that leaves the house, connect to your home Wi-Fi first.")
        }

        ConfigSwitch {
            id: mainSwitch
            visible: !FileSharing.loaded || root.canManage
            buttonIcon: "folder_shared"
            text: Translation.tr("Share folders with other computers")
            // True whether sharing is off, on, or on without this account.
            tooltipText: Translation.tr("Turns sharing on or off for every account on this computer. Other computers sign in with a user name and sharing password that this page shows once your account is set up.")
            // Also held while the keyring is read, or while it is locked with
            // the password inside: turning sharing back on would replace a
            // saved password that was only out of reach. Turning it on is
            // held on a network the helper would refuse too, whose notice
            // below says why. Turning it off needs none of these.
            enabled: root.canManage && !FileSharing.busy && !FileSharing.keyringPending
                && (FileSharing.isOn || (!FileSharing.passwordLocked && FileSharing.firewall
                    && root.currentNetwork?.eligible !== false))
            // Held still until the first read, so a restored switch snaps into
            // place instead of sliding across every time the page opens.
            animateChanges: FileSharing.loaded
            checked: FileSharing.isOn
            onCheckedChanged: {
                if (!root.canManage || checked === FileSharing.isOn)
                    return;
                if (checked)
                    FileSharing.enable();
                else
                    FileSharing.disable();
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: FileSharing.settingUp
            spacing: 4

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Setting up sharing. This can take a minute.")
            }
        }

        SharingError {
            forScope: "setup"
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.canManage && !FileSharing.isOn && FileSharing.account && !FileSharing.busy
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Sharing is off. Your shared folders are remembered for next time.")
        }

        // Turning sharing on needs a password to give Samba, and without the
        // one other computers saved it has to be a new one.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && !FileSharing.isOn && FileSharing.passwordMissing && !FileSharing.busy
            materialIcon: "key"
            text: Translation.tr("Your sharing password is not saved on this computer, so turning sharing back on sets a new one. Computers that saved the old one will ask again.")
        }

        // Reading the password again brings up the keyring's own unlock
        // prompt, which this page cannot answer for the user.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && FileSharing.passwordLocked && !FileSharing.busy
            materialIcon: "lock"
            text: FileSharing.isOn
                ? Translation.tr("Your keyring is locked, so your sharing password cannot be shown. Unlock it to see the password.")
                : Translation.tr("Your keyring is locked, so your sharing password cannot be read. Unlock it before turning sharing back on, so computers that saved the password can still sign in.")

            Item {
                Layout.fillWidth: true
            }
            NoticeAction {
                materialIcon: "lock_open"
                mainText: Translation.tr("Unlock")
                enabled: !FileSharing.keyringPending
                onClicked: FileSharing.readPassword()
            }
        }

        // Another account on this computer turned sharing on; this one still
        // needs its own sharing password before it can share anything.
        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && FileSharing.isOn && !FileSharing.account && !FileSharing.settingUp
            materialIcon: "person_add"
            text: Translation.tr("Sharing is on for this computer, but your account is not set up yet.")

            Item {
                Layout.fillWidth: true
            }
            NoticeAction {
                materialIcon: "person_add"
                mainText: Translation.tr("Set Up My Account")
                // A password an earlier try saved is given again, so the
                // keyring has to be read first.
                enabled: !FileSharing.busy && !FileSharing.keyringPending
                onClicked: FileSharing.setUpAccount()
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && root.currentNetwork !== null && (root.currentNetwork.reason ?? "") !== ""
            materialIcon: {
                switch (root.currentNetwork?.reason) {
                case "weak":
                    return "gpp_maybe";
                case "private":
                    return "person";
                case "zone":
                    return "security";
                }
                return "no_encryption";
            }
            text: FileSharing.ineligibleMessage(root.currentNetwork)
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && FileSharing.ready && root.currentNetwork !== null
                && !root.currentNetwork.trusted && root.currentNetwork.eligible
            materialIcon: "shield"
            text: Translation.tr("Sharing is on, but not on %1. Other computers here cannot see or open your folders.")
                .arg(root.currentNetwork?.name ?? "")

            Item {
                Layout.fillWidth: true
            }
            NoticeAction {
                materialIcon: "add_link"
                mainText: Translation.tr("Share on This Network")
                enabled: !FileSharing.busy && FileSharing.firewall
                onClicked: FileSharing.trustCurrent()
            }
        }

        // Files sent someone here to share a folder, and it goes out as soon
        // as sharing is on and their account is ready. Someone who set it up
        // before and turned it off only has to turn it back on. A folder that
        // is still shared from then keeps its access, so it is not promised
        // as View only.
        SubtleNoticeBox {
            Layout.fillWidth: true
            visible: root.canManage && FileSharing.pendingFolder.length > 0 && FileSharing.pendingChecked
            materialIcon: "folder"
            text: {
                const name = FileSharing.pendingFolder.split("/").filter(part => part.length > 0).pop() ?? "/";
                if (!FileSharing.account || FileSharing.isOn)
                    return Translation.tr("Once sharing is set up, %1 will be shared as View only.").arg(name);
                if (!FileSharing.pendingShared)
                    return Translation.tr("Once you turn sharing back on, %1 will be shared as View only.").arg(name);
                return (FileSharing.pendingAccess === "edit"
                        ? Translation.tr("%1 is already shared. Once you turn sharing back on, others can open it and make changes.")
                        : Translation.tr("%1 is already shared. Once you turn sharing back on, others can open it but not change anything."))
                    .arg(name);
            }
        }
    }

    // ── How to Connect ────────────────────────────────────────────────────────
    ContentSection {
        visible: root.canManage && FileSharing.ready
        icon: "link"
        title: Translation.tr("How to Connect")

        // Where to type differs by system: Finder has no address field, and
        // typing in most Linux file managers starts a search.
        Intro {
            text: Translation.tr("On the other computer, type one of these addresses: on Windows, in the File Explorer address bar; on a Mac, in Finder under Go > Connect to Server; on Linux, in the file manager after pressing Ctrl+L. When it asks, sign in with the user name and password below.")
        }

        // Not the bare "Windows" key, which other languages translate as
        // application windows.
        CopyRow {
            iconName: "desktop_windows"
            label: Translation.tr("For Windows")
            value: "\\\\" + FileSharing.hostname
        }
        CopyRow {
            iconName: "laptop_mac"
            label: Translation.tr("For Mac and Linux")
            value: `smb://${FileSharing.hostname}.local`
        }
        // Split like the name rows: Finder and Linux file managers only take
        // an smb:// address, and the number is what they fall back on when
        // the .local name does not resolve.
        CopyRow {
            visible: FileSharing.addresses.length > 0
            iconName: "pin"
            label: Translation.tr("By number (Windows)")
            hint: Translation.tr("Use this if the name does not work. The number can change when your router restarts.")
            value: FileSharing.addresses.length > 0 ? "\\\\" + FileSharing.addresses[0] : ""
        }
        CopyRow {
            visible: FileSharing.addresses.length > 0
            iconName: "pin"
            label: Translation.tr("By number (Mac and Linux)")
            hint: Translation.tr("Use this if the name does not work. The number can change when your router restarts.")
            value: FileSharing.addresses.length > 0 ? `smb://${FileSharing.addresses[0]}` : ""
        }
        CopyRow {
            iconName: "person"
            label: Translation.tr("User name")
            value: FileSharing.user
        }
        CopyRow {
            iconName: "password"
            label: Translation.tr("Password")
            value: FileSharing.password
            // A password shown once because there is no keyring to keep it is
            // shown plainly: dots would hide the only chance to read it.
            shownValue: {
                if (FileSharing.passwordMissing)
                    return Translation.tr("Not saved on this computer. Set a new one below.");
                if (FileSharing.passwordLocked)
                    return Translation.tr("Locked in your keyring");
                if (FileSharing.password.length === 0)
                    return "";
                if (root.showPassword || FileSharing.revealedPassword.length > 0)
                    return FileSharing.password;
                return "••••••••••••";
            }

            RowIconButton {
                visible: FileSharing.password.length > 0 && FileSharing.revealedPassword.length === 0
                iconName: root.showPassword ? "visibility_off" : "visibility"
                tip: root.showPassword ? Translation.tr("Hide") : Translation.tr("Show")
                onClicked: root.showPassword = !root.showPassword
            }
            // Offered for a locked one too: a keyring that will not open
            // should not leave the password impossible to replace.
            RowIconButton {
                visible: FileSharing.password.length > 0 || FileSharing.passwordLocked
                iconName: "edit"
                tip: Translation.tr("Change")
                enabled: !FileSharing.busy
                onClicked: root.changingPassword = !root.changingPassword
            }
        }

        SubtleNoticeBox {
            Layout.fillWidth: true
            visible: FileSharing.revealedPassword.length > 0
            materialIcon: "key"
            text: Translation.tr("Your keyring could not be reached, so this password is shown only this once. Copy it or write it down now.")
        }

        // Open by itself when there is no password to show. Setting one is
        // then the only thing to do, and an icon's name lives in a tooltip,
        // which a touch screen never shows.
        ColumnLayout {
            visible: root.changingPassword || FileSharing.passwordMissing
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialTextField {
                id: newPasswordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("New sharing password")
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            }
            StyledText {
                Layout.fillWidth: true
                visible: newPasswordField.text.length > 0 && !FileSharing.validPassword(newPasswordField.text)
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Use 8 to 128 characters. Letters with accents and emoji are not allowed.")
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("This is not your login password. Computers that saved the old one will ask again.")
            }
            SharingError {
                forScope: "password"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }
                RippleButton {
                    visible: !FileSharing.passwordMissing
                    implicitWidth: 80
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: {
                        root.changingPassword = false;
                        newPasswordField.text = "";
                    }
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                RippleButton {
                    implicitWidth: suggestContent.implicitWidth + 28
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    enabled: !FileSharing.busy
                    onClicked: FileSharing.suggestPassword()
                    contentItem: RowLayout {
                        id: suggestContent
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "casino"
                            iconSize: 14
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Suggest One")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
                RippleButton {
                    implicitWidth: savePasswordContent.implicitWidth + 28
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    enabled: FileSharing.validPassword(newPasswordField.text) && !FileSharing.busy
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: FileSharing.changePassword(newPasswordField.text)
                    contentItem: RowLayout {
                        id: savePasswordContent
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: FileSharing.busyAction === "password" ? "hourglass_top" : "lock_reset"
                            iconSize: 14
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Save Password")
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("This computer also shows up under Network in File Explorer on Windows, in the Finder sidebar on a Mac, and under Network in Files on Linux.")
        }
    }

    // ── Shared Folders ────────────────────────────────────────────────────────
    ContentSection {
        visible: root.canManage && FileSharing.ready
        icon: "folder_open"
        title: Translation.tr("Shared Folders")

        Intro {
            text: Translation.tr("Other computers can open these folders after signing in. You can share folders that belong to you.")
        }

        StyledText {
            Layout.fillWidth: true
            visible: FileSharing.shares.length === 0
            text: Translation.tr("Nothing is shared yet.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: FileSharing.shares

            delegate: Rectangle {
                id: shareRow
                required property var modelData
                readonly property bool missing: shareRow.modelData.missing === true

                Layout.fillWidth: true
                implicitHeight: 60
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                opacity: FileSharing.busyTarget === shareRow.modelData.name ? 0.6 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 12

                    MaterialSymbol {
                        text: shareRow.missing ? "folder_off" : "folder"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: shareRow.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const path = shareRow.modelData.path ?? "";
                                const home = FileSharing.home;
                                return home.length > 0 && path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                        }
                    }

                    StyledComboBox {
                        visible: !shareRow.missing
                        textRole: "displayName"
                        Layout.fillWidth: false
                        Layout.preferredWidth: 220
                        enabled: !FileSharing.busy
                        model: [
                            { displayName: Translation.tr("View only"), icon: "visibility", value: "view" },
                            { displayName: Translation.tr("Can make changes"), icon: "edit", value: "edit" }
                        ]
                        currentIndex: shareRow.modelData.access === "edit" ? 1 : 0
                        onActivated: index => {
                            const value = model[index].value;
                            if (value !== shareRow.modelData.access)
                                FileSharing.setAccess(shareRow.modelData.name, value);
                        }
                    }

                    // Nothing is served from a missing share, so there is no
                    // access to pick, only the remove button.
                    StyledText {
                        visible: shareRow.missing
                        Layout.fillWidth: false
                        Layout.preferredWidth: 220
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Folder not found")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    RowIconButton {
                        iconName: "close"
                        tip: Translation.tr("Stop sharing. The folder and its files stay where they are.")
                        enabled: !FileSharing.busy
                        onClicked: FileSharing.remove(shareRow.modelData.name)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            // Nothing is shared on its own. While no folder is served, the
            // Public folder is one click away, unless Files already named one.
            RippleButtonWithIcon {
                visible: FileSharing.liveShares.length === 0 && FileSharing.pendingFolder.length === 0
                materialIcon: "public"
                mainText: Translation.tr("Share Your Public Folder")
                enabled: !FileSharing.busy
                onClicked: FileSharing.sharePublic()
            }
            RippleButtonWithIcon {
                materialIcon: "create_new_folder"
                mainText: Translation.tr("Add a Folder")
                enabled: !FileSharing.busy && !FileSharing.picking
                onClicked: FileSharing.pickFolder()
            }
            Item {
                Layout.fillWidth: true
            }
        }

        SharingError {
            forScope: "folders"
        }
    }

    // ── Networks ──────────────────────────────────────────────────────────────
    ContentSection {
        visible: root.canManage && FileSharing.ready
        icon: "router"
        title: Translation.tr("Networks")

        Intro {
            text: Translation.tr("Your folders are only shared on the networks turned on here. Anywhere else, like a coffee shop or hotel, your folders stay closed.")
        }

        Repeater {
            model: FileSharing.connections

            // A refused change comes back as a forced read, which rebuilds
            // these rows, so each switch starts over from what is true.
            delegate: ConfigSwitch {
                id: networkSwitch
                required property var modelData
                readonly property bool wired: networkSwitch.modelData.type === "ethernet"

                buttonIcon: networkSwitch.wired ? "settings_ethernet" : "wifi"
                text: networkSwitch.modelData.name
                checked: networkSwitch.modelData.trusted
                enabled: !FileSharing.busy
                tooltipText: {
                    if ((networkSwitch.modelData.reason ?? "") !== "")
                        return FileSharing.ineligibleMessage(networkSwitch.modelData);
                    if (networkSwitch.wired)
                        return Translation.tr("A cable connection uses one setting wherever you plug in. On a laptop that leaves the house, leave this off.");
                    return "";
                }
                onCheckedChanged: {
                    if (checked === networkSwitch.modelData.trusted)
                        return;
                    FileSharing.trust(networkSwitch.modelData.uuid, checked);
                }
            }
        }

        SharingError {
            forScope: "networks"
        }
    }

    // ── Computer Name ─────────────────────────────────────────────────────────
    ContentSection {
        visible: root.canManage && FileSharing.ready
        icon: "computer"
        title: Translation.tr("Computer Name")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 60
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 6
                spacing: 12

                MaterialSymbol {
                    text: "computer"
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: FileSharing.hostname
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A short name is easier to type.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                RippleButtonWithIcon {
                    Layout.rightMargin: 6
                    materialIcon: "edit"
                    mainText: Translation.tr("Rename")
                    enabled: !FileSharing.busy
                    onClicked: {
                        renameField.text = FileSharing.hostname;
                        root.renaming = !root.renaming;
                    }
                }
            }
        }

        ColumnLayout {
            visible: root.renaming
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialTextField {
                id: renameField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Computer name")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            }
            StyledText {
                Layout.fillWidth: true
                visible: renameField.text.trim().length > 0
                    && !FileSharing.validHostname(renameField.text.trim().toLowerCase())
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Use lowercase letters, numbers and dashes, up to 63 characters. The name cannot start or end with a dash.")
            }
            // Every address on this page carries the name, and nothing keeps
            // the old one answering.
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Other computers that saved the old name will need the new address.")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }
                RippleButton {
                    implicitWidth: 80
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer3
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.renaming = false
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Cancel")
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                RippleButton {
                    implicitWidth: 80
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    enabled: FileSharing.validHostname(renameField.text.trim().toLowerCase()) && !FileSharing.busy
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    onClicked: FileSharing.rename(renameField.text)
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: FileSharing.busyAction === "rename" ? "hourglass_top" : "check"
                            iconSize: 14
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Save")
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        SharingError {
            forScope: "name"
        }
    }
}
