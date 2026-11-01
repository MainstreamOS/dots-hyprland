pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

// Calls seen by this computer, newest first.
ColumnLayout {
    id: root

    signal startCall(string number)
    signal startMessage(string number, string name)
    readonly property var privacy: Config.options.sidebar.phone.privacy
    readonly property var entries: IslandState.recentCalls
    readonly property bool canCall: PhoneCalls.canDial && !PhoneCalls.dialing && PhoneCalls.calls.length === 0
    readonly property bool canMessage: Phone.reachable && Phone.canMessage
    spacing: 6

    function title(entry) {
        if (root.privacy.showContactName && entry.name && entry.name !== entry.number)
            return entry.name;
        if (root.privacy.showPhoneNumber && entry.number)
            return entry.number;
        return Translation.tr("Private contact");
    }

    function when(time) {
        const date = new Date(time);
        return Qt.formatDateTime(date, date.toDateString() === new Date().toDateString()
            ? Config.options.time.format : Config.options.time.shortDateFormat + " " + Config.options.time.format);
    }

    function direction(entry) {
        if (!entry.incoming)
            return Translation.tr("Outgoing");
        return entry.answered ? Translation.tr("Answered") : Translation.tr("Missed");
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: root.entries.length > 0
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Recent calls")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }
        RippleButtonWithIcon {
            materialIcon: "delete_sweep"
            mainText: Translation.tr("Clear")
            onClicked: IslandPhoneHistory.clearCalls()
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.entries.length === 0
        PagePlaceholder {
            icon: "call"
            title: Translation.tr("No calls yet")
            description: Translation.tr("Calls your phone gets while it is connected show up here.")
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.entries.length > 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}
        model: root.entries

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 56
            readonly property bool missed: row.modelData.incoming && !row.modelData.answered

            GroupedRowBackground {
                anchors.fill: parent
                index: row.index
                count: list.count
                color: Appearance.surfaces.row
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 10

                ClippingRectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 18
                    color: Appearance.surfaces.raised

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: photo.status !== Image.Ready
                        text: "person"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                    }
                    Image {
                        id: photo
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: root.privacy.showContactPicture ? (row.modelData.picture ?? "") : ""
                        sourceSize: Qt.size(72, 72)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title(row.modelData)
                        elide: Text.ElideRight
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MaterialSymbol {
                            text: !row.modelData.incoming ? "call_made" : (row.modelData.answered ? "call_received" : "call_missed")
                            iconSize: Appearance.font.pixelSize.small
                            color: row.missed ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${root.direction(row.modelData)} · ${root.when(row.modelData.time)}`
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: row.missed ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                        }
                    }
                }

                PhoneContactActions {
                    visible: !!row.modelData.number
                    number: row.modelData.number ?? ""
                    name: row.modelData.name ?? ""
                    canCall: root.canCall
                    canMessage: root.canMessage
                    compact: true
                    onCallRequested: number => root.startCall(number)
                    onMessageRequested: (number, name) => root.startMessage(number, name)
                }
            }
        }
    }
}
