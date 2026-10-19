pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import "../../../services/PhoneContacts.js" as Contacts
import "../../../services/PhoneIdentity.js" as Identity

// The phone's contacts, searchable, with call and message actions.
Item {
    id: root

    signal startCall(string number)
    signal startMessage(string number, string name)

    readonly property string searchQuery: searchInput.text
    property string expandedKey: ""
    readonly property string deviceId: Phone.deviceId
    readonly property bool canCall: PhoneCalls.canDial && !PhoneCalls.dialing && PhoneCalls.calls.length === 0
    readonly property bool canMessage: Phone.reachable && Phone.canMessage
    readonly property string dialNumber: Contacts.dialNumber(searchQuery)
    readonly property bool showDirectDial: dialNumber.length > 0
        && !allContacts.some(c => c.numbers.some(n => Identity.numberMatches(n, dialNumber)))
    // Built once the page is first shown; until then the records stay unread.
    property bool shown: visible
    onVisibleChanged: if (visible) shown = true
    readonly property var allContacts: shown ? Contacts.directory(ContactService.records, deviceId) : []
    readonly property var filteredContacts: Contacts.search(allContacts, searchQuery)

    onDeviceIdChanged: {
        expandedKey = "";
        searchInput.text = "";
    }
    onSearchQueryChanged: expandedKey = ""
    onAllContactsChanged: if (!allContacts.some(c => c.key === expandedKey)) expandedKey = ""

    function call(number): void {
        const target = Contacts.dialNumber(number);
        if (canCall && target) startCall(target);
    }

    function message(number, name): void {
        const target = Contacts.dialNumber(number);
        if (canMessage && /^\+?[0-9]+$/.test(target)) startMessage(target, name);
    }


    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: 17
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Search contacts or dial number…")
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        background: null
                        Keys.onEscapePressed: {
                            if (text.length > 0) text = "";
                            else focus = false;
                        }
                    }

                    RippleButton {
                        visible: searchInput.text.length > 0
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: 11
                        Accessible.name: Translation.tr("Clear search")
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            Rectangle {
                implicitHeight: 38
                implicitWidth: countBadge.implicitWidth + 20
                radius: Appearance.rounding.small
                color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94)

                StyledText {
                    id: countBadge
                    anchors.centerIn: parent
                    text: root.filteredContacts.length === 1
                        ? Translation.tr("1 contact")
                        : Translation.tr("%1 contacts").arg(root.filteredContacts.length)
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Digits that match no contact exactly can still be dialed or texted.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 46
            radius: Appearance.rounding.small
            visible: root.showDirectDial
            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.94)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                MaterialSymbol {
                    text: "dialpad"
                    iconSize: 18
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Dial %1").arg(root.dialNumber)
                    textFormat: Text.PlainText
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                PhoneContactActions {
                    canCall: root.canCall
                    canMessage: root.canMessage
                    onCallRequested: number => root.call(number)
                    onMessageRequested: (number, name) => root.message(number, name)
                    number: root.dialNumber
                }
            }
        }

        StyledListView {
            id: contactsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: root.filteredContacts.length > 0
            spacing: 2
            cacheBuffer: 300
            popin: false
            animateAppearance: false
            model: root.filteredContacts

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool isExpanded: root.expandedKey === row.modelData.key
                readonly property string primaryNumber: (row.modelData.numbers && row.modelData.numbers.length > 0)
                    ? row.modelData.numbers[0] : ""
                readonly property int secondaryCount: Math.max(0, (row.modelData.numbers?.length || 0) - 1)

                width: contactsList.width
                implicitHeight: rowCol.implicitHeight + 16
                radius: Appearance.rounding.small
                clip: true
                color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)

                Behavior on implicitHeight {
                    NumberAnimation { duration: 160; easing.type: Easing.OutQuad }
                }

                ColumnLayout {
                    id: rowCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ClippingRectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 20
                            color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer0, 0.4)

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                source: row.modelData.picture || ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
                                asynchronous: true
                                smooth: true
                                mipmap: true
                                visible: avatarImg.status === Image.Ready
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: avatarImg.status !== Image.Ready
                                text: Contacts.initials(row.modelData.name)
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        // A click shows the contact's other numbers.
                        MouseArea {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            cursorShape: row.secondaryCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (row.secondaryCount > 0) {
                                    root.expandedKey = row.isExpanded ? "" : row.modelData.key;
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 1

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        textFormat: Text.PlainText
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: row.primaryNumber || Translation.tr("No number listed")
                                        font.pixelSize: 11
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: row.secondaryCount > 0
                                        implicitHeight: 16
                                        implicitWidth: multiBadgeLabel.implicitWidth + 8
                                        radius: 4
                                        color: row.isExpanded
                                            ? Appearance.colors.colPrimaryContainer
                                            : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                                        StyledText {
                                            id: multiBadgeLabel
                                            anchors.centerIn: parent
                                            text: Translation.tr("+%1 more").arg(row.secondaryCount)
                                            font.pixelSize: 9
                                            font.weight: Font.Medium
                                            color: row.isExpanded
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colSubtext
                                        }
                                    }
                                }
                            }
                        }

                        PhoneContactActions {
                            canCall: root.canCall
                            canMessage: root.canMessage
                            onCallRequested: number => root.call(number)
                            onMessageRequested: (number, name) => root.message(number, name)
                            number: row.primaryNumber
                            name: row.modelData.name
                            visible: !!number
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: row.isExpanded && row.secondaryCount > 0
                        spacing: 4

                        Repeater {
                            model: row.modelData.numbers ? row.modelData.numbers.slice(1) : []

                            delegate: Rectangle {
                                id: secondaryRow
                                required property string modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Appearance.rounding.verysmall
                                color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "phone"
                                        iconSize: 14
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: secondaryRow.modelData
                                        textFormat: Text.PlainText
                                        font.pixelSize: 11
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }

                                    PhoneContactActions {
                                        canCall: root.canCall
                                        canMessage: root.canMessage
                                        onCallRequested: number => root.call(number)
                                        onMessageRequested: (number, name) => root.message(number, name)
                                        number: secondaryRow.modelData
                                        name: row.modelData.name
                                        compact: true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.filteredContacts.length === 0
            spacing: 8

            Item { Layout.fillHeight: true }

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "person_search"
                iconSize: 36
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.searchQuery.length > 0
                    ? Translation.tr("No contacts matching \"%1\"").arg(root.searchQuery)
                    : Translation.tr("No contacts available")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.searchQuery.length > 0
                    ? Translation.tr("Check the spelling or try searching by phone number.")
                    : Translation.tr("Contacts synced from your paired phone will appear here.")
                font.pixelSize: 11
                color: Appearance.colors.colSubtext
            }

            Item { Layout.fillHeight: true }
        }
    }
}
