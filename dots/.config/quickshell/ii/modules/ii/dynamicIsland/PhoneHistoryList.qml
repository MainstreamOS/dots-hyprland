pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property bool calls
    required property var entries
    signal selected(entryId: string)
    signal clearRequested()
    implicitHeight: 204 * Appearance.sizes.islandScale
    spacing: 6 * Appearance.sizes.islandScale


    function contact(entry) {
        const privacy = Config.options.bar.island;
        if (privacy.showContactName && entry.name && (entry.name !== entry.number || privacy.showPhoneNumber)) return entry.name;
        if (privacy.showPhoneNumber && entry.number) return entry.number;
        return Translation.tr("Private contact");
    }
    function timestamp(time) {
        const date = new Date(time);
        return Qt.formatDateTime(date, date.toDateString() === new Date().toDateString()
            ? Config.options.time.format : Config.options.time.shortDateFormat + " " + Config.options.time.format);
    }
    function messagePreview(entry) {
        if (!Config.options.bar.island.showMessage) return Translation.tr("Message contents hidden");
        const text = String(entry.body || "").replace(/\s+/g, " ").trim();
        const count = entry.audioClips?.length || 0;
        if (count) return (count === 1 ? Translation.tr("Audio clip") : Translation.tr("%1 audio clips").arg(count)) + (text ? " · " + text : "");
        const isGif = entry.images?.some(img => typeof img === "string" && (img.toLowerCase().includes(".gif") || img.startsWith("data:image/gif")));
        return text || (isGif ? Translation.tr("GIF") : entry.images?.length ? Translation.tr("Photo message") : Translation.tr("Message"));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8 * Appearance.sizes.islandScale

        StyledText {
            Layout.fillWidth: true
            text: root.calls ? Translation.tr("Recent calls") : Translation.tr("Recent messages")
            font.pixelSize: 12 * Appearance.sizes.islandScale
            font.weight: Font.DemiBold
            color: Appearance.islandContent.colOnSurfaceVariant
        }

        RippleButton {
            implicitHeight: 28 * Appearance.sizes.islandScale
            topPadding: 0
            bottomPadding: 0
            leftPadding: 10 * Appearance.sizes.islandScale
            rightPadding: 10 * Appearance.sizes.islandScale
            buttonRadius: 8 * Appearance.sizes.islandScale
            colBackground: Appearance.surfaces.raised
            colBackgroundHover: Appearance.colors.colLayer2Hover
            Accessible.name: root.calls ? Translation.tr("Clear call history") : Translation.tr("Clear message history")
            enabled: root.entries.length > 0
            onClicked: root.clearRequested()
            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 4 * Appearance.sizes.islandScale
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "delete_sweep"
                    iconSize: 15 * Appearance.sizes.islandScale
                    color: Appearance.islandContent.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Clear")
                    font.pixelSize: 11 * Appearance.sizes.islandScale
                    font.weight: Font.Medium
                    color: Appearance.islandContent.colOnLayer1
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    ClippingRectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: ((Appearance?.rounding?.normal ?? 17) - 3) * Appearance.sizes.islandScale
        color: "transparent"

        ListView {
            id: historyList
            anchors.fill: parent
            clip: true
            spacing: 2 * Appearance.sizes.islandScale
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: StyledScrollBar {}
            onWidthChanged: Qt.callLater(() => historyList.forceLayout())
            model: root.entries

        delegate: RippleButton {
            id: row
            required property var modelData
            required property int index
            readonly property int totalCount: historyList.count
            width: ListView.view.width
            height: 50 * Appearance.sizes.islandScale
            clip: true
            padding: 6 * Appearance.sizes.islandScale
            leftPadding: 10 * Appearance.sizes.islandScale
            rightPadding: 10 * Appearance.sizes.islandScale

            colBackground: Appearance.surfaces.raised
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.selected(modelData.id)

            background: GroupedRowBackground {
                anchors.fill: parent
                index: row.index
                count: row.totalCount
                color: row.buttonColor
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            contentItem: RowLayout {
                spacing: 10 * Appearance.sizes.islandScale

                ClippingRectangle {
                    Layout.preferredWidth: 34 * Appearance.sizes.islandScale
                    Layout.preferredHeight: 34 * Appearance.sizes.islandScale
                    radius: 17 * Appearance.sizes.islandScale
                    color: Appearance.surfaces.row

                    Image {
                        id: contactPhoto
                        anchors.fill: parent
                        source: Config.options.bar.island.showContactPicture ? (row.modelData.picture || ContactService.pictureFor(row.modelData.number, row.modelData.name) || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(68, 68)
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: contactPhoto.status !== Image.Ready
                        text: "person"
                        iconSize: 20 * Appearance.sizes.islandScale
                        color: Appearance.islandContent.colOnLayer1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1 * Appearance.sizes.islandScale

                    StyledText {
                        Layout.fillWidth: true
                        text: root.contact(row.modelData)
                        textFormat: Text.PlainText
                        font.pixelSize: 13 * Appearance.sizes.islandScale
                        font.weight: Font.DemiBold
                        color: Appearance.islandContent.colOnLayer1
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.calls ? (Config.options.bar.island.showPhoneNumber && row.modelData.number
                            && row.modelData.number !== root.contact(row.modelData) ? row.modelData.number
                            : row.modelData.answered ? Translation.tr("Call ended") : row.modelData.incoming ? Translation.tr("Incoming call") : Translation.tr("Call"))
                            : root.messagePreview(row.modelData)
                        textFormat: Text.PlainText
                        font.pixelSize: 11 * Appearance.sizes.islandScale
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        color: Appearance.islandContent.colSubtext
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    text: root.timestamp(row.modelData.time)
                    font.pixelSize: 10 * Appearance.sizes.islandScale
                    color: Appearance.islandContent.colSubtext
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            width: parent.width
            visible: !root.entries.length
            text: root.calls ? Translation.tr("Recent calls will appear here.") : Translation.tr("Recent messages will appear here.")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 13 * Appearance.sizes.islandScale
            color: Appearance.islandContent.colOnSurfaceVariant
        }
    }
}
}
