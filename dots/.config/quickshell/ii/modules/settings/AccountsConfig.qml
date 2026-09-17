import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property var accounts: []
    property string currentUser: ""
    property string statusMessage: ""
    // Provisioning a home runs a font cache rebuild and a pile of xdg-mime
    // calls, which outlasts the banner's own four-second timeout, so the
    // banner is held open for as long as something is actually working.
    readonly property bool busy: createAccountProc.running || adminProc.running || repairProc.running
    // The clear timer can fire mid-run, which would otherwise leave the last
    // message pinned forever, so it is restarted the moment work finishes.
    onBusyChanged: if (!busy) statusClearTimer.restart()
    property bool statusIsError: false

    Component.onCompleted: {
        currentUserProc.running = true
    }

    function refresh() {
        accountListProc.running = false
        accountListProc.running = true
    }

    // The helper writes "ERROR: <reason>" to stderr before it exits, and that
    // reason is the only thing that distinguishes a taken login name from a
    // refused password. Without it every failure read the same.
    //
    // The LAST such line is the one that ended the run: the provisioning
    // library logs to the same stream, so an earlier warning would otherwise
    // win. The reason is shown beside the translated sentence rather than in
    // place of it, because it comes back in English whatever the locale.
    function helperReason(raw, fallback) {
        if (!raw) return fallback
        const all = String(raw).match(/ERROR:\s*([^\n]+)/g)
        if (!all || all.length === 0) return fallback
        const last = all[all.length - 1].replace(/^ERROR:\s*/, "").trim()
        return last.length > 0 ? fallback + " (" + last + ")" : fallback
    }

    function showStatus(msg, isError) {
        root.statusMessage = msg
        root.statusIsError = isError
        statusClearTimer.restart()
    }

    Timer {
        id: statusClearTimer
        interval: 4000
        running: false
        onTriggered: if (!root.busy) root.statusMessage = ""
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
        // The helper knows what the passwd file alone cannot say: whether an
        // account is an administrator. Same command the create path uses, so
        // the list can never describe accounts by different rules than the
        // ones that made them.
        command: ["/usr/local/bin/user-manager", "list"]
        property string buf: ""
        property string err: ""
        onRunningChanged: { if (running) { buf = ""; err = "" } }
        stdout: StdioCollector { onStreamFinished: accountListProc.buf += this.text }
        stderr: StdioCollector { onStreamFinished: accountListProc.err += this.text }
        onExited: (code) => {
            if (code !== 0) {
                root.showStatus(Translation.tr("Could not load accounts: ") + err.trim(), true)
                buf = ""; err = ""
                return
            }
            let parsed = []
            try { parsed = JSON.parse(buf) } catch (e) {
                root.showStatus(Translation.tr("Could not read the account list."), true)
                buf = ""; err = ""
                return
            }
            buf = ""; err = ""
            parsed = parsed.map(a => Object.assign({}, a, { isCurrent: a.name === root.currentUser }))
            parsed.sort((a, b) => a.isCurrent ? -1 : (b.isCurrent ? 1 : a.name.localeCompare(b.name)))
            root.accounts = parsed
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
            property string pendingPassword: ""
            property string err: ""
            stderr: StdioCollector { onStreamFinished: actionProc.err = this.text }
            // A password handed over as an argument is readable in ps by
            // anyone on the machine for as long as the command runs, so it
            // goes down stdin instead. stdinEnabled must be on before running
            // flips, or the write lands after the helper has already read.
            onRunningChanged: {
                if (running) err = ""
                if (running && pendingPassword.length > 0) {
                    write(pendingPassword + "\n")
                    pendingPassword = ""
                    stdinEnabled = false
                }
            }
            onExited: (code) => {
                if (code === 0) {
                    root.showStatus(Translation.tr("Done! Changes have been saved."), false)
                    item.showChangePassword = false
                    item.showChangeName = false
                    item.showRemove = false
                    root.refresh()
                    item.expanded = false
                } else {
                    root.showStatus(root.helperReason(actionProc.err,
                        Translation.tr("Something went wrong. Please try again.")), true)
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
                imageApplyProc.command = ["pkexec", "/usr/local/bin/user-manager",
                    "set-avatar", account.name, src]
                imageApplyProc.running = true
            }
        }

        Process {
            id: imageApplyProc
            // The helper reports the edge length it settled on, so the status
            // line can say when a picture is smaller than the login screen will
            // draw it instead of letting the result be a surprise at logout.
            property string buf: ""
            property string err: ""
            onRunningChanged: if (running) { buf = ""; err = "" }
            stdout: SplitParser { onRead: data => imageApplyProc.buf += data }
            stderr: StdioCollector { onStreamFinished: imageApplyProc.err = this.text }
            onExited: (code) => {
                if (code === 0) {
                    const edge = parseInt(imageApplyProc.buf.trim(), 10)
                    if (edge > 0 && edge < 512)
                        root.showStatus(Translation.tr("Login image updated. At %1 pixels it may look soft on the login screen.").arg(edge), false)
                    else
                        root.showStatus(Translation.tr("Login image updated!"), false)
                    faceImage.source = ""
                    faceImage.source = "file:///var/lib/AccountsService/icons/" + account.name
                } else {
                    root.showStatus(root.helperReason(imageApplyProc.err,
                        Translation.tr("Could not update the login image.")), true)
                }
            }
        }

        function pickAndApplyLoginImage() {
            imagePickerProc.command = ["bash", "-c",
                'zenity --file-selection --filename="$1/" --file-filter="Image Files | *.png *.jpg *.jpeg *.webp *.bmp" --title="$2"',
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
                            ? (account.admin ? Translation.tr("Signed in, administrator") : Translation.tr("Signed in"))
                            : (account.admin ? Translation.tr("Administrator") : Translation.tr("Standard account"))
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

                // Action buttons, wrapping: there are more of them than fit
                // one line at this card width, and a fixed row pushed the last
                // of them outside the card.
                Flow {
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
                        enabled: !item.working
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
                                text: Translation.tr("Change Full Name")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: item.showChangeName ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }

                Flow {
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

                    // An account with no administrator rights is asked for
                    // somebody else's password to use its own machine, so the
                    // state is shown here rather than left to be discovered.
                    RippleButton {
                        implicitWidth: adminContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working && !adminProc.running && !account.isCurrent
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            adminProc.command = ["pkexec", "/usr/local/bin/user-manager",
                                "set-admin", account.name, account.admin ? "no" : "yes"]
                            adminProc.running = true
                            root.showStatus(account.admin
                                ? Translation.tr("Removing administrator rights from %1…").arg(account.name)
                                : Translation.tr("Making %1 an administrator…").arg(account.name), false)
                        }
                        StyledToolTip {
                            text: account.isCurrent
                                ? Translation.tr("You cannot change your own administrator rights.")
                                : Translation.tr("An administrator can install software, change system settings and manage other accounts.")
                        }
                        contentItem: RowLayout {
                            id: adminContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: account.admin ? "shield_person" : "person"
                                iconSize: 14
                                color: account.admin ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: account.admin ? Translation.tr("Administrator") : Translation.tr("Standard")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: account.admin ? Appearance.m3colors.m3primary : Appearance.colors.colOnLayer2
                            }
                        }
                    }


                    // Repairing and creating are the same code path, so an
                    // account made before that path existed can be brought up
                    // to what a fresh install would have given it.
                    RippleButton {
                        implicitWidth: repairContent.implicitWidth + 28
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        enabled: !item.working && !repairProc.running
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            repairProc.target = account.name
                            repairProc.command = ["pkexec", "/usr/local/bin/user-manager",
                                "provision", account.name]
                            repairProc.running = true
                            root.showStatus(Translation.tr("Setting up %1's desktop…").arg(account.name), false)
                        }
                        StyledToolTip {
                            text: Translation.tr("Give this account the groups, settings and first-run setup a newly installed system gives its first user. Safe to run more than once.")
                        }
                        contentItem: RowLayout {
                            id: repairContent
                            anchors.centerIn: parent; spacing: 5
                            MaterialSymbol {
                                text: repairProc.running && repairProc.target === account.name ? "hourglass_top" : "healing"
                                iconSize: 14
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: Translation.tr("Repair Account")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }


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
                                // Changing your own password sends the current
                                // one first, on its own line, for the helper to
                                // check against the stored hash. Requiring it in
                                // the field and then not sending it made the
                                // page look like it verified something.
                                const pass = account.isCurrent
                                    ? oldPassField.text + "\n" + newPassField.text
                                    : newPassField.text
                                oldPassField.text = ""; newPassField.text = ""; confirmPassField.text = ""
                                actionProc.pendingPassword = pass
                                actionProc.command = ["pkexec", "/usr/local/bin/user-manager",
                                    "set-password", user].concat(account.isCurrent ? ["verify"] : [])
                                actionProc.stdinEnabled = true
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

                // ── Change display name form ──────────────────────────────────
                ColumnLayout {
                    visible: item.showChangeName
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: Translation.tr("The name shown on the login screen. The name used to sign in does not change.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    MaterialTextField {
                        id: newNameField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Full name")
                        text: account.fullName ?? ""
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
                            onClicked: { item.showChangeName = false; newNameField.text = account.fullName ?? "" }
                            contentItem: StyledText { anchors.centerIn: parent; text: Translation.tr("Cancel"); color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small }
                        }
                        RippleButton {
                            implicitWidth: 80; implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            enabled: newNameField.text.trim().length >= 1
                                     && newNameField.text.trim() !== (account.fullName ?? "")
                                     && !item.working
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            onClicked: {
                                const oldName = account.name
                                const newName = newNameField.text.trim()
                                actionProc.command = ["pkexec", "/usr/local/bin/user-manager", "rename", oldName, newName]
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
                                    ? ["pkexec", "/usr/local/bin/user-manager", "delete", account.name, "remove-home"]
                                    : ["pkexec", "/usr/local/bin/user-manager", "delete", account.name, "keep-home"]
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
            color: root.busy ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.88)
                : (root.statusIsError ? Qt.rgba(0.85, 0.2, 0.2, 0.12) : Qt.rgba(0.2, 0.75, 0.3, 0.12))
            border.width: 1
            border.color: root.busy ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.6)
                : (root.statusIsError ? Qt.rgba(0.85, 0.2, 0.2, 0.3) : Qt.rgba(0.2, 0.75, 0.3, 0.3))
            RowLayout {
                id: statusMsgRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 8
                MaterialSymbol {
                    text: root.busy ? "progress_activity" : (root.statusIsError ? "error" : "check_circle")
                    iconSize: 14
                    color: root.busy ? Appearance.m3colors.m3primary
                        : (root.statusIsError ? Appearance.colors.colError : "#4caf50")
                    RotationAnimator on rotation {
                        running: root.busy
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 1100
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.busy ? Appearance.m3colors.m3primary
                        : (root.statusIsError ? Appearance.colors.colError : "#4caf50")
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
                id: fullNameField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Full name")
            }
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
            id: makeAdminSwitch
            buttonIcon: "shield_person"
            text: Translation.tr("Let this person administer the computer")
            checked: false
        }

        // Says what is still missing instead of leaving the button dead and
        // silent, which reads as the page being broken.
        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: {
                if (createAccountProc.running) return ""
                const login = newUserField.text.trim()
                if (login.length === 0) return Translation.tr("Choose a login name to continue.")
                if (newUserField.text.includes(" ")) return Translation.tr("A login name cannot contain spaces.")
                if (!/^[a-z_][a-z0-9_-]*$/.test(login)) return Translation.tr("A login name can use lowercase letters, digits, dashes and underscores, and cannot start with a digit.")
                if (newUserPassField.text.length === 0) return Translation.tr("Set a password so they can sign in.")
                return ""
            }
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 150; implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                enabled: !createAccountProc.running
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: {
                    const username = newUserField.text.trim()
                    const password = newUserPassField.text
                    if (username.length === 0) {
                        root.showStatus(Translation.tr("Choose a login name first."), true); return
                    }
                    if (!(new RegExp("^[a-z_][a-z0-9_-]*$")).test(username)) {
                        root.showStatus(Translation.tr("A login name can use lowercase letters, digits, dashes and underscores, and cannot start with a digit."), true); return
                    }
                    if (username.length > 31) {
                        root.showStatus(Translation.tr("That login name is too long."), true); return
                    }
                    if (password.length === 0) {
                        root.showStatus(Translation.tr("Set a password so they can sign in."), true); return
                    }
                    // Nothing is copied out of this account. useradd -m seeds the new
                    // home from /etc/skel, and the helper provisions it the same way
                    // the installer provisions the first user, so the person who
                    // signs in gets a fresh desktop rather than a copy of this one.
                    createAccountProc.pendingPassword = password
                    // Held on the process, because the fields below are cleared
                    // the moment this returns and the result arrives later.
                    createAccountProc.pendingUser = username
                    // Asked for as part of create, so there is no second
                    // authentication to dismiss and no window in which the
                    // account is usable but not an administrator.
                    createAccountProc.command = ["pkexec", "/usr/local/bin/user-manager",
                        "create", username, fullNameField.text.trim()]
                        .concat(makeAdminSwitch.checked ? ["admin"] : [])
                    createAccountProc.stdinEnabled = true
                    createAccountProc.running = true
                    root.showStatus(Translation.tr("Creating %1 and setting up their desktop…").arg(username), false)
                    newUserField.text = ""
                    newUserPassField.text = ""
                    fullNameField.text = ""
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
        id: adminProc
        property string err: ""
        onRunningChanged: if (running) err = ""
        stderr: StdioCollector { onStreamFinished: adminProc.err = this.text }
        onExited: (code) => {
            if (code !== 0)
                root.showStatus(root.helperReason(adminProc.err,
                    Translation.tr("Could not change who administers this computer.")), true)
            accountListProc.running = true
        }
    }

    Process {
        id: repairProc
        property string target: ""
        property string err: ""
        onRunningChanged: if (running) err = ""
        stderr: StdioCollector { onStreamFinished: repairProc.err = this.text }
        onExited: (code) => {
            root.showStatus(code === 0
                ? Translation.tr("Account repaired. The desktop finishes setting itself up the next time they sign in.")
                : root.helperReason(repairProc.err, Translation.tr("Could not repair that account.")), code !== 0)
            accountListProc.running = true
        }
    }

    Process {
        id: createAccountProc
        property string pendingPassword: ""
        property string pendingUser: ""
        property string err: ""
        stderr: StdioCollector { onStreamFinished: createAccountProc.err = this.text }
        // stdinEnabled has to be on before running goes true, or the write
        // lands after the helper has already read. Closing the stream is what
        // lets the helper's read return instead of blocking.
        onRunningChanged: {
            // Cleared as the run starts, or a run that fails without saying
            // anything reports the previous failure's reason.
            if (running) err = ""
            if (running && pendingPassword.length > 0) {
                write(pendingPassword + "\n")
                pendingPassword = ""
                stdinEnabled = false
            }
        }
        onExited: (code) => {
            if (code === 0) {
                createAccountProc.pendingUser = ""
                root.showStatus(Translation.tr("Account created. They can sign in now, and the desktop finishes setting itself up the first time they do."), false)
                postCreateRefreshTimer.start()
            } else {
                root.showStatus(root.helperReason(createAccountProc.err,
                    Translation.tr("Could not create the account. That login name may already be taken, or it contained invalid characters.")), true)
                root.refresh()
            }
        }
    }
}
