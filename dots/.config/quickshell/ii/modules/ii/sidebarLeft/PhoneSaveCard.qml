import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Where a saved file went, with ways to open it or its folder.
Rectangle {
    id: root
    // The saves this card reports: "message" or "files".
    required property string from
    // Kept while the card collapses so its text stays put.
    property var save: null
    property bool shown: false
    readonly property bool failed: root.save?.ok === false

    readonly property string shownPath: {
        const home = FileUtils.trimFileProtocol(Directories.home);
        const path = root.save?.path ?? "";
        return path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    Connections {
        target: Phone
        function onLastSaveChanged() {
            const save = Phone.lastSave;
            if (!save || save.from !== root.from) return;
            root.save = save;
            root.shown = true;
            hideTimer.restart();
        }
        function onDeviceIdChanged() {
            root.shown = false;
        }
    }

    // Stays while the pointer is on it.
    Timer {
        id: hideTimer
        interval: 8000
        onTriggered: {
            if (hover.hovered) restart();
            else root.shown = false;
        }
    }
    HoverHandler {
        id: hover
    }

    visible: implicitHeight > 0
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: ColorUtils.transparentize(root.failed ? Appearance.m3colors.m3error : Appearance.colors.colPrimary, 0.4)
    implicitHeight: root.shown ? (mainCol.implicitHeight + 20) : 0
    opacity: root.shown ? 1 : 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    // Clicks between its buttons stop here instead of reaching what lies under the card.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: mainCol
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: root.failed ? "error" : "download_done"
                iconSize: Appearance.font.pixelSize.larger
                color: root.failed ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.failed ? Translation.tr("Could not save") : Translation.tr("Saved to %1").arg(root.save?.folder ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: root.failed ? (root.save?.name ?? "") : root.shownPath
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: root.shown = false
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.failed
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            RippleButton {
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                horizontalPadding: 12
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: FileSearch.showInFiles(root.save.path)

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "folder_open"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("Show in folder")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            RippleButton {
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                horizontalPadding: 12
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: Phone.openLocal(root.save.path)

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Open")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }
}
