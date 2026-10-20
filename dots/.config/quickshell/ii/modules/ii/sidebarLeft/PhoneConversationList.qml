import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

// The phone's conversations, newest first.
Item {
    id: root
    signal opened(int thread)
    signal newMessage()
    signal sendFilesRequested()

    property string searchQuery: ""

    readonly property var filteredConversations: {
        const all = Phone.conversations ?? [];
        const deduped = [];
        const seenThreads = new Set();
        for (const item of all) {
            if (!item) continue;
            if (item.thread !== undefined && item.thread !== null && item.thread >= 0) {
                if (seenThreads.has(item.thread)) continue;
                seenThreads.add(item.thread);
                deduped.push(item);
            } else {
                const hasReal = all.some(c => c && c.thread >= 0 && Phone.sameAddresses(c.addresses, item.addresses));
                if (!hasReal) deduped.push(item);
            }
        }
        const q = root.searchQuery.trim().toLowerCase();
        if (q.length === 0) return deduped;
        return deduped.filter(item => {
            const title = String(Phone.conversationTitle(item) ?? "").toLowerCase();
            const preview = String(Phone.previewText(item) ?? "").toLowerCase();
            const addr = String((item.addresses && item.addresses[0]) || item.sender || "").toLowerCase();
            return title.includes(q) || preview.includes(q) || addr.includes(q);
        });
    }

    // Today shows the time, this week the day, older the date.
    function when(ms): string {
        const date = new Date(ms);
        const now = new Date();
        if (date.toDateString() === now.toDateString())
            return date.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        if (now - date < 6 * 24 * 3600 * 1000)
            return date.toLocaleDateString(Qt.locale(), "ddd");
        return date.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
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
                radius: 10
                color: Appearance.surfaces.raised

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
                        placeholderText: Translation.tr("Search conversations…")
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.colors.colSubtext
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        background: null
                        onTextChanged: root.searchQuery = text
                        Keys.onEscapePressed: {
                            if (text.length > 0) text = "";
                            else focus = false;
                        }
                    }

                    RippleButton {
                        visible: searchInput.text.length > 0
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            RippleButton {
                implicitHeight: 38
                implicitWidth: composeRow.implicitWidth + 24
                buttonRadius: Appearance.rounding.small
                enabled: Phone.reachable
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: root.newMessage()

                contentItem: RowLayout {
                    id: composeRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "edit_square"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Compose")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            cacheBuffer: 2000
            popin: false
            animateAppearance: false
            model: root.filteredConversations

            delegate: Item {
                id: row
                required property int index
                required property var modelData
                readonly property string title: Phone.conversationTitle(row.modelData)
                readonly property bool unread: !Phone.isOutgoing(row.modelData) && !row.modelData.read

                width: list.width
                implicitHeight: 64

                GroupedRowBackground {
                    id: rowBg
                    anchors.fill: parent
                    // The Dynamic Island's grouped rows, raised on the page frame.
                    index: row.index
                    count: list.count
                    color: {
                        if (rowMouse.pressed) {
                            return row.unread
                                ? ColorUtils.mix(Appearance.colors.colPrimaryContainerActive, Appearance.colors.colLayer2Active, 0.55)
                                : Appearance.colors.colLayer2Active;
                        }
                        if (rowMouse.containsMouse) {
                            return row.unread
                                ? ColorUtils.mix(Appearance.colors.colPrimaryContainerHover, Appearance.colors.colLayer2Hover, 0.55)
                                : Appearance.colors.colLayer2Hover;
                        }
                        return row.unread ? Appearance.surfaces.unread : Appearance.surfaces.raised;
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.opened(row.modelData.thread)
                }

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 14
                    spacing: 12

                    ClippingRectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: ColorUtils.mix(Appearance.colors.colLayer3, Appearance.colors.colLayer2, 0.65)

                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            source: Phone.conversationPicture(row.modelData)
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(84, 84)
                            asynchronous: true
                            visible: status === Image.Ready
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: /^[\d+(]/.test(row.title) || row.title.length === 0 ? "#" : row.title.charAt(0).toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                text: row.title
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: row.unread ? Font.DemiBold : Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: root.when(row.modelData.date)
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: Appearance.colors.colSubtext
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                text: (Phone.isOutgoing(row.modelData) ? Translation.tr("You: ") : "")
                                    + Phone.previewText(row.modelData)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: row.unread ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                            }
                            Rectangle {
                                visible: row.unread
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }

        IslandButton {
            Layout.fillWidth: true
            contentColors: Appearance.colors
            enabled: Phone.reachable
            symbol: "send_to_mobile"
            text: Translation.tr("Drop files anywhere to send to %1").arg(Phone.device?.name ?? Translation.tr("your phone"))
            onClicked: root.sendFilesRequested()
        }
    }

    PagePlaceholder {
        shown: Phone.conversations.length === 0
        icon: "sms"
        title: Phone.conversationsLoaded ? Translation.tr("No conversations") : Translation.tr("Loading conversations")
        description: Phone.reachable ? "" : Translation.tr("Your phone is not reachable right now.")
    }
}
