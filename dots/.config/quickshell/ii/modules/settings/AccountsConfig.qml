import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property var accounts: []
    property string currentUser: ""
    property string currentUserHome: ""
    property string statusMessage: ""
    property bool statusIsError: false

    Component.onCompleted: {
        currentUserProc.running = true
    }

    function refresh() {
        accountListProc.running = false
        accountListProc.running = true
    }

    function showStatus(msg, isError) {
        root.statusMessage = msg
        root.statusIsError = isError
        statusClearTimer.restart()
    }

    Timer {
        id: statusClearTimer
        interval: 4000
        onTriggered: root.statusMessage = ""
    }

    Process {
        id: currentUserProc
        command: ["id", "-un"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => currentUserProc.buf += data + "\n" }
        onExited: {
            root.currentUser = currentUserProc.buf.trim()
            currentUserProc.buf = ""
            accountListProc.running = true
        }
    }

    Process {
        id: accountListProc
        // Read /etc/passwd directly — no shell, no awk, no quoting issues.
        // SplitParser strips the newline before calling onRead, so we add it
        // back manually so split("\n") works correctly in onExited.
        command: ["cat", "/etc/passwd"]
        property string buf: ""
        property string err: ""
        onRunningChanged: { if (running) { buf = ""; err = "" } }
        stdout: SplitParser { onRead: data => accountListProc.buf += data + "\n" }
        stderr: SplitParser { onRead: data => accountListProc.err += data + "\n" }
        onExited: (code) => {
            if (code !== 0) {
                root.showStatus(Translation.tr("Could not load accounts: ") + err.trim(), true)
                buf = ""; err = ""
                return
            }
            const lines = buf.trim().split("\n").filter(l => l.length > 0)
            buf = ""; err = ""
            // Parse colon-separated /etc/passwd fields:
            // name:pw:uid:gid:gecos:home:shell
            const noLoginShells = ["nologin", "false", "halt", "shutdown", "sync"]
            const parsed = lines
                .map(line => {
                    const p = line.split(":")
                    return {
                        name:      p[0] ?? "",
                        uid:       parseInt(p[2] ?? "0"),
                        home:      p[5] ?? "",
                        shell:     p[6] ?? "",
                        isCurrent: (p[0] ?? "") === root.currentUser
                    }
                })
                .filter(a => a.uid >= 1000 && a.uid < 65534
                             && !noLoginShells.some(s => a.shell.includes(s)))
            // Cache current user's home before stripping fields
            const me = parsed.find(a => a.isCurrent)
            if (me) root.currentUserHome = me.home
            parsed.sort((a, b) => {
                if (a.isCurrent) return -1
                if (b.isCurrent) return 1
                return a.name.localeCompare(b.name)
            })
            root.accounts = parsed.map(a => ({ name: a.name, isCurrent: a.isCurrent }))
        }
    }

    // ── Account card ──────────────────────────────────────────────────────────
    component AccountItem: Rectangle {
        id: item
        required property var account

        property bool expanded: false
        property bool showChangePassword: false
        property bool showChangeName: false
        property bool showRemove: false
        property bool working: actionProc.running || imageApplyProc.running

        Layout.fillWidth: true
        implicitHeight: itemColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: account.isCurrent
            ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08)
            : (hoverArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)

        Behavior on implicitHeight { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on color          { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                item.expanded = !item.expanded
                item.showChangePassword = false
                item.showChangeName = false
                item.showRemove = false
            }
        }

        Process {
            id: actionProc
            onExited: (code) => {
                if (code === 0) {
                    root.showStatus(Translation.tr("Done! Changes have been saved."), false)
                    item.showChangePassword = false
                    item.showChangeName = false
                    item.showRemove = false
                    root.refresh()
                    item.expanded = false
                } else {
                    root.showStatus(Translation.tr("Something went wrong. Please try again."), true)
                }
            }
        }


        Process {
            id: imagePickerProc
            property string buf: ""
            onRunningChanged: if (running) buf = ""
            stdout: SplitParser { onRead: data => imagePickerProc.buf += data }
            onExited: (code) => {
                if (code !== 0 || imagePickerProc.buf.trim().length === 0) return
                const src = imagePickerProc.buf.trim()
                const user = account.name
                const dest = "/var/lib/AccountsService/icons/" + user
                const conf = "/var/lib/AccountsService/users/" + user
                imageApplyProc.command = ["pkexec", "bash", "-c",
                    'mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users'
                    + ' && cp "$1" "$2" && chmod 644 "$2"'
                    + ' && if [ -f "$3" ] && grep -q "^Icon=" "$3"; then'
                    + '   sed -i "s|^Icon=.*|Icon=$2|" "$3";'
                    + ' elif [ -f "$3" ]; then'
                    + '   sed -i "/^\\[User\\]/a Icon=$2" "$3";'
                    + ' else'
                    + '   printf \'[User]\\nIcon=%s\\n\' "$2" > "$3";'
                    + ' fi',
                    "--", src, dest, conf
                ]
                imageApplyProc.running = true
            }
        }

        Process {
            id: imageApplyProc
            onExited: (code) => {
                if (code === 0) {
                    root.showStatus(Translation.tr("Login image updated!"), false)
                    faceImage.source = ""
                    faceImage.source = "file:///var/lib/AccountsService/icons/" + account.name
                } else {
                    root.showStatus(Translation.tr("Could not update the login image."), true)
                }
            }
        }

        function pickAndApplyLoginImage() {
            imagePickerProc.command = ["bash", "-c",
                'kdialog --getopenfilename "$1" "Image Files (*.png *.jpg *.jpeg *.webp *.bmp)" --title "$2"',
                "--", Directories.home, Translation.tr("Choose login image")
            ]
            imagePickerProc.running = true
        }

        ColumnLayout {
            id: itemColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            // ── Card header ───────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    id: avatarCircle
                    implicitWidth: 38; implicitHeight: 38
                    radius: 19
                    color: account.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    layer.enabled: faceImage.status === Image.Ready
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: avatarCircle.width
                            height: avatarCircle.height
                            radius: avatarCircle.radius
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: faceImage.status !== Image.Ready
                        text: (account.name.charAt(0) ?? "?").toUpperCase()
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: account.isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    Image {
                        id: faceImage
                        anchors.fill: parent
                        source: "file:///var/lib/AccountsService/icons/" + account.name
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        cache: false
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    RowLayout {
                        spacing: 8
                        StyledText {
                            text: account.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        Rectangle {
                            visible: account.isCurrent
                            implicitWidth: youLabel.implicitWidth + 12
                            implicitHeight: 18
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colPrimary
                            StyledText {
                                id: youLabel
                                anchors.centerIn: parent
                                text: Translation.tr("You")
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                    StyledText {
                        text: account.isCurrent
                            ? Translation.tr("Signed in")
                            : Translation.tr("Standard account")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                MaterialSymbol {
                    visible: item.working
                    text: "sync"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                    RotationAnimation on rotation {
                        running: item.working
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 900
                    }
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                    rotation: item.expanded ? 180 : 0
                    Behavior on rotation { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
            }

            // ── Expanded actions ──────────────────────────────────────────────
            ColumnLayout {
                visible: item.expanded
                Layout.fillWidth: true
                Layout.leftMargin: 50
                spacing: 10

                Rectangle { Layout.fillWidth: true; height: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.4 }

                // Action buttons row 1
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        implicitWidth: changePassContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working
                        colBackground: item.showChangePassword ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        colBackgroundHover: item.showChangePassword ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                        onClicked: {
                            item.showChangePassword = !item.showChangePassword
                            item.showChangeName = false
                            item.showRemove = false
                        }
                        contentItem: RowLayout {
                            id: changePassContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: "lock"
                                iconSize: 14
                                color: item.showChangePassword ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Change Password")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: item.showChangePassword ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    RippleButton {
                        id: changeNameButton
                        implicitWidth: changeNameContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working && !account.isCurrent
                        opacity: account.isCurrent ? 0.35 : 1.0
                        colBackground: item.showChangeName ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        colBackgroundHover: item.showChangeName ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                        onClicked: {
                            item.showChangeName = !item.showChangeName
                            item.showChangePassword = false
                            item.showRemove = false
                        }
                        contentItem: RowLayout {
                            id: changeNameContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: "edit"
                                iconSize: 14
                                color: item.showChangeName ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Change Login Name")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: item.showChangeName ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                        }
                        StyledToolTip {
                            extraVisibleCondition: account.isCurrent
                            text: Translation.tr("You cannot change the login name of the account you are currently signed in to.")
                        }
                    }
                }

                // Action buttons row 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        implicitWidth: changeImageContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working && !imagePickerProc.running
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: item.pickAndApplyLoginImage()
                        contentItem: RowLayout {
                            id: changeImageContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: "account_circle"
                                iconSize: 14
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Change Login Image")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitWidth: removeContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working && !account.isCurrent
                        opacity: account.isCurrent ? 0.35 : 1.0
                        colBackground: item.showRemove ? Appearance.colors.colError : Appearance.colors.colLayer2
                        colBackgroundHover: item.showRemove ? Qt.rgba(0.9,0.2,0.2,0.9) : Appearance.colors.colLayer2Hover
                        onClicked: {
                            item.showRemove = !item.showRemove
                            item.showChangePassword = false
                            item.showChangeName = false
                        }
                        contentItem: RowLayout {
                            id: removeContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: "person_remove"
                                iconSize: 14
                                color: item.showRemove ? Appearance.colors.colOnError : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Remove Account")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: item.showRemove ? Appearance.colors.colOnError : Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }

                // Can't remove yourself note
                StyledText {
                    visible: account.isCurrent
                    text: Translation.tr("You cannot remove the account you are currently signed in to.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }


                // ── Change password form ──────────────────────────────────────
                ColumnLayout {
                    visible: item.showChangePassword
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialTextField {
                        id: oldPassField
                        visible: account.isCurrent
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Current password")
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                    }
                    MaterialTextField {
                        id: newPassField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("New password")
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                    }
                    MaterialTextField {
                        id: confirmPassField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Type the new password again to confirm")
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData
                    }
                    StyledText {
                        visible: newPassField.text.length > 0
                                 && confirmPassField.text.length > 0
                                 && newPassField.text !== confirmPassField.text
                        text: Translation.tr("The passwords don't match — please check and try again.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colError
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitWidth: 80; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: { item.showChangePassword = false; oldPassField.text = ""; newPassField.text = ""; confirmPassField.text = "" }
                            contentItem: StyledText { anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                        }
                        RippleButton {
                            implicitWidth: savePassContent.implicitWidth + 28; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            enabled: newPassField.text.length >= 1
                                     && newPassField.text === confirmPassField.text
                                     && (!account.isCurrent || oldPassField.text.length >= 1)
                                     && !item.working
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                const user = account.name
                                const pass = newPassField.text
                                oldPassField.text = ""; newPassField.text = ""; confirmPassField.text = ""
                                actionProc.command = ["pkexec", "bash", "-c",
                                    'printf "%s:%s\\n" "$1" "$2" | chpasswd',
                                    "--", user, pass
                                ]
                                actionProc.running = true
                            }
                            contentItem: RowLayout {
                                id: savePassContent
                                anchors.centerIn: parent; spacing: 4
                                MaterialSymbol { text: "lock_reset"; iconSize: 14; color: Appearance.colors.colOnPrimary }
                                StyledText { text: Translation.tr("Save New Password"); color: Appearance.colors.colOnPrimary; font.pixelSize: Appearance.font.pixelSize.small }
                            }
                        }
                    }
                }

                // ── Change login name form ────────────────────────────────────
                ColumnLayout {
                    visible: item.showChangeName
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: Translation.tr("This is the name used to sign in. It must have no spaces.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    MaterialTextField {
                        id: newNameField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("New login name")
                        text: account.name
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitWidth: 80; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: { item.showChangeName = false; newNameField.text = account.name }
                            contentItem: StyledText { anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                        }
                        RippleButton {
                            implicitWidth: 80; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            enabled: newNameField.text.length >= 1
                                     && newNameField.text !== account.name
                                     && !newNameField.text.includes(" ")
                                     && !item.working
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                const oldName = account.name
                                const newName = newNameField.text.trim()
                                actionProc.command = ["pkexec", "usermod", "-l", newName, oldName]
                                actionProc.running = true
                            }
                            contentItem: RowLayout {
                                anchors.centerIn: parent; spacing: 4
                                MaterialSymbol { text: "check"; iconSize: 14; color: Appearance.colors.colOnPrimary }
                                StyledText { text: Translation.tr("Save"); color: Appearance.colors.colOnPrimary; font.pixelSize: Appearance.font.pixelSize.small }
                            }
                        }
                    }
                }

                // ── Remove account confirmation ────────────────────────────────
                ColumnLayout {
                    visible: item.showRemove
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: removeWarnRow.implicitHeight + 14
                        radius: Appearance.rounding.normal
                        color: Qt.rgba(0.85, 0.2, 0.2, 0.1)
                        border.width: 1
                        border.color: Qt.rgba(0.85, 0.2, 0.2, 0.3)
                        RowLayout {
                            id: removeWarnRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                            spacing: 8
                            MaterialSymbol { text: "warning"; iconSize: 14; color: Appearance.colors.colError }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Are you sure you want to remove the account \"") + account.name + Translation.tr("\"? This cannot be undone.")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colError
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    ConfigSwitch {
                        id: deleteFilesSwitch
                        text: Translation.tr("Also delete their files and folders")
                        checked: false
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitWidth: 80; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: item.showRemove = false
                            contentItem: StyledText { anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                        }
                        RippleButton {
                            implicitWidth: 150; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            enabled: !item.working
                            colBackground: Appearance.colors.colError
                            colBackgroundHover: Qt.rgba(0.9, 0.2, 0.2, 0.9)
                            onClicked: {
                                actionProc.command = deleteFilesSwitch.checked
                                    ? ["pkexec", "userdel", "-r", account.name]
                                    : ["pkexec", "userdel", account.name]
                                actionProc.running = true
                            }
                            contentItem: RowLayout {
                                anchors.centerIn: parent; spacing: 4
                                MaterialSymbol { text: "delete_forever"; iconSize: 14; color: Appearance.colors.colOnError }
                                StyledText { text: Translation.tr("Yes"); color: Appearance.colors.colOnError; font.pixelSize: Appearance.font.pixelSize.small }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── User accounts list ────────────────────────────────────────────────────
    ContentSection {
        icon: "manage_accounts"
        title: Translation.tr("User Accounts")

        headerExtra: [
            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Refresh")
                onClicked: root.refresh()
            }
        ]

        // Status banner
        Rectangle {
            visible: root.statusMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: statusMsgRow.implicitHeight + 12
            radius: Appearance.rounding.normal
            color: root.statusIsError ? Qt.rgba(0.85, 0.2, 0.2, 0.12) : Qt.rgba(0.2, 0.75, 0.3, 0.12)
            border.width: 1
            border.color: root.statusIsError ? Qt.rgba(0.85, 0.2, 0.2, 0.3) : Qt.rgba(0.2, 0.75, 0.3, 0.3)
            RowLayout {
                id: statusMsgRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 8
                MaterialSymbol {
                    text: root.statusIsError ? "error" : "check_circle"
                    iconSize: 14
                    color: root.statusIsError ? Appearance.colors.colError : "#4caf50"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.statusIsError ? Appearance.colors.colError : "#4caf50"
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            visible: root.accounts.length === 0
            Layout.fillWidth: true
            Layout.topMargin: 20; Layout.bottomMargin: 20
            spacing: 8
            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "person_off"; iconSize: 40; color: Appearance.colors.colLayer3 }
            StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("No accounts found"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
        }

        Repeater {
            model: root.accounts
            AccountItem {
                required property var modelData
                account: modelData
                Layout.fillWidth: true
            }
        }
    }

    // ── Add an account ────────────────────────────────────────────────────────
    ContentSection {
        icon: "person_add"
        title: Translation.tr("Add an Account")

        ConfigRow {
            uniform: true
            MaterialTextField {
                id: newUserField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Login name (no spaces)")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            }
            MaterialTextField {
                id: newUserPassField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
            }
        }

        ConfigSwitch {
            id: createHomeSwitch
            buttonIcon: "folder"
            text: Translation.tr("Set up a personal folder for this account")
            checked: true
        }

        ConfigSwitch {
            id: copyConfigSwitch
            buttonIcon: "content_copy"
            enabled: createHomeSwitch.checked
            opacity: createHomeSwitch.checked ? 1.0 : 0.4
            text: Translation.tr("Copy your app settings into their account")
            checked: true
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 150; implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: newUserField.text.length >= 1
                         && !newUserField.text.includes(" ")
                         && !createAccountProc.running
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: {
                    const username = newUserField.text.trim()
                    const password = newUserPassField.text
                    const homeFlag = createHomeSwitch.checked ? "-m" : "-M"
                    const srcConfig = root.currentUserHome + "/.config"
                    const srcLocalShare = root.currentUserHome + "/.local/share"
                    const srcVenv = root.currentUserHome + "/.local/state/quickshell/.venv"
                    // Build script using positional args to avoid shell injection
                    // $1 = homeFlag, $2 = username, $3 = password, $4 = srcConfig, $5 = srcLocalShare, $6 = srcVenv
                    let script = 'useradd $1 -s /bin/bash "$2"'
                    if (password.length > 0)
                        script += ' && printf "%s:%s\\n" "$2" "$3" | chpasswd'
                    if (createHomeSwitch.checked) {
                        // 1. Create standard XDG home directories
                        script += ' && mkdir -p "/home/$2/Desktop" "/home/$2/Documents" "/home/$2/Downloads" "/home/$2/Music" "/home/$2/Pictures" "/home/$2/Public" "/home/$2/Templates" "/home/$2/Videos"'
                        script += ' && chown "$2:$2" "/home/$2/Desktop" "/home/$2/Documents" "/home/$2/Downloads" "/home/$2/Music" "/home/$2/Pictures" "/home/$2/Public" "/home/$2/Templates" "/home/$2/Videos"'
                    }
                    if (createHomeSwitch.checked && copyConfigSwitch.checked) {
                        // Copy .config from current user
                        script += ' && mkdir -p "/home/$2/.config"'
                        script += ' && [ -d "$4" ] && cp -a "$4/." "/home/$2/.config/" && chown -R "$2:$2" "/home/$2/.config"'
                        // 2. Write canonical user-dirs.dirs so Nautilus recognises the standard folders
                        //    (written after config copy so it always reflects the dirs we just created)
                        script += " && { echo 'XDG_DESKTOP_DIR=\"$HOME/Desktop\"'; echo 'XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"'; echo 'XDG_TEMPLATES_DIR=\"$HOME/Templates\"'; echo 'XDG_PUBLICSHARE_DIR=\"$HOME/Public\"'; echo 'XDG_DOCUMENTS_DIR=\"$HOME/Documents\"'; echo 'XDG_MUSIC_DIR=\"$HOME/Music\"'; echo 'XDG_PICTURES_DIR=\"$HOME/Pictures\"'; echo 'XDG_VIDEOS_DIR=\"$HOME/Videos\"'; } > \"/home/$2/.config/user-dirs.dirs\""
                        script += ' && chown "$2:$2" "/home/$2/.config/user-dirs.dirs"'
                        // 3. Copy hidden .desktop app entries from ~/.local/share/applications
                        script += ' && if [ -d "$5/applications" ]; then mkdir -p "/home/$2/.local/share/applications" && cp -a "$5/applications/." "/home/$2/.local/share/applications/" && chown -R "$2:$2" "/home/$2/.local/share/applications"; fi'
                        // 4. Copy Google Sans Flex font (illogical-impulse-google-sans-flex) and rebuild font cache
                        script += ' && if [ -d "$5/fonts/illogical-impulse-google-sans-flex" ]; then mkdir -p "/home/$2/.local/share/fonts" && cp -a "$5/fonts/illogical-impulse-google-sans-flex" "/home/$2/.local/share/fonts/" && chown -R "$2:$2" "/home/$2/.local/share/fonts" && fc-cache -f "/home/$2/.local/share/fonts"; fi'
                        // 5. Copy Python venv and re-home all hardcoded paths from source user to new user
                        //    Mirrors the "pre-baked venv" branch in post-install: fix shebangs, activate scripts, pyvenv.cfg
                        script += ' && if [ -d "$6" ]; then'
                        script += '   SRC_HOME="${4%/.config}";'
                        script += '   DEST_VENV="/home/$2/.local/state/quickshell/.venv";'
                        script += '   mkdir -p "/home/$2/.local/state/quickshell" && cp -a "$6/." "$DEST_VENV/";'
                        script += '   find "$DEST_VENV/bin" -type f -exec sed -i "1s|#!$SRC_HOME/|#!/home/$2/|" {} + 2>/dev/null || true;'
                        script += '   for _act in "$DEST_VENV/bin/activate" "$DEST_VENV/bin/activate.csh" "$DEST_VENV/bin/activate.fish"; do [ -f "$_act" ] && sed -i "s|$SRC_HOME/|/home/$2/|g" "$_act"; done;'
                        script += '   sed -i "s|$SRC_HOME/|/home/$2/|g" "$DEST_VENV/pyvenv.cfg" 2>/dev/null || true;'
                        script += '   chown -R "$2:$2" "/home/$2/.local/state/quickshell";'
                        script += ' fi'
                    }
                    createAccountProc.command = ["pkexec", "bash", "-c", script, "--", homeFlag, username, password, srcConfig, srcLocalShare, srcVenv]
                    createAccountProc.running = true
                    newUserField.text = ""
                    newUserPassField.text = ""
                }
                contentItem: RowLayout {
                    anchors.centerIn: parent; spacing: 6
                    MaterialSymbol {
                        text: createAccountProc.running ? "hourglass_top" : "person_add"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: createAccountProc.running
                            ? Translation.tr("Creating…")
                            : Translation.tr("Create Account")
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // Short delay before refreshing after account creation so the system
    // has time to fully write the new user to /etc/passwd
    Timer {
        id: postCreateRefreshTimer
        interval: 500
        onTriggered: root.refresh()
    }

    Process {
        id: createAccountProc
        onExited: (code) => {
            if (code === 0) {
                root.showStatus(Translation.tr("Account created! They can now sign in."), false)
                postCreateRefreshTimer.start()
            } else {
                root.showStatus(Translation.tr("Could not create the account. That login name may already be taken, or it contained invalid characters."), true)
            }
        }
    }
}
