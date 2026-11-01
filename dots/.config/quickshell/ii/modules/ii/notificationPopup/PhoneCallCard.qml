import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// A phone call on the traditional bar. It stays until the call is answered, declined or over.
Item {
    id: root

    required property var entry
    // The switches of whichever bar is in use; both name them alike.
    readonly property var privacy: Appearance.sizes.barIsIsland ? Config.options.bar.island : Config.options.sidebar.phone.privacy
    readonly property bool canPositive: (root.entry?.canPositive ?? false) && root.entry?.state !== "active"
    readonly property bool canNegative: root.entry?.canNegative ?? false
    readonly property string contactName: {
        if (root.privacy.showContactName && root.entry?.name && root.entry.name !== root.entry.number)
            return root.entry.name;
        if (root.privacy.showPhoneNumber && root.entry?.number)
            return root.entry.number;
        return Translation.tr("Private contact");
    }
    readonly property string status: {
        switch (root.entry?.state) {
        case "dialing": return Translation.tr("Dialing…");
        case "alerting": return Translation.tr("Ringing…");
        case "active": return Translation.tr("In call");
        case "held": return Translation.tr("On hold");
        default: return Translation.tr("Incoming call");
        }
    }

    Layout.fillWidth: true
    implicitHeight: card.implicitHeight

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: content.implicitHeight + 28
        color: Appearance.colors.colBackgroundSurfaceContainer
        radius: RoundedCorners.on ? Appearance.rounding.normal : 0

        ColumnLayout {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ClippingRectangle {
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: photo.status !== Image.Ready
                        text: "call"
                        fill: 1
                        iconSize: 26
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    Image {
                        id: photo
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: root.privacy.showContactPicture ? (root.entry?.picture ?? "") : ""
                        sourceSize: Qt.size(104, 104)
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
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.status
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        Phone.wanted = true;
                        SidebarLeftTabs.showTab("phone");
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: Translation.tr("Open in sidebar")
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.canPositive && !root.canNegative && root.entry?.state !== "active"
                    || root.entry?.backend === "KDE Connect"
                text: Translation.tr("Connect your phone over Bluetooth for Accept and Decline controls.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.canPositive || root.canNegative
                spacing: 8

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    visible: root.canNegative
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colError
                    colBackgroundHover: Appearance.colors.colErrorHover
                    colRipple: Appearance.colors.colErrorActive
                    onClicked: IslandState.action(root.entry.id, "negative")
                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "call_end"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnError
                            }
                            StyledText {
                                text: root.entry?.negativeLabel || Translation.tr("Decline")
                                color: Appearance.colors.colOnError
                            }
                        }
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    visible: root.canPositive
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: IslandState.action(root.entry.id, "positive")
                    contentItem: Item {
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: root.entry?.backend === "KDE Connect" ? "volume_off" : "call"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: root.entry?.positiveLabel || Translation.tr("Answer")
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
