import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A phone asking to pair, with the code both screens show.
Rectangle {
    id: root
    readonly property var request: Phone.pairRequests[0] ?? null
    // Kept while the card collapses so its text stays put.
    property var shownRequest: null
    readonly property bool shown: root.request !== null
    onRequestChanged: if (root.request) root.shownRequest = root.request

    readonly property string code: {
        const key = String(root.shownRequest?.key ?? "");
        return key.length === 8 ? key.slice(0, 4) + " " + key.slice(4) : key;
    }

    visible: implicitHeight > 0
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
    implicitHeight: root.shown ? (mainCol.implicitHeight + 20) : 0
    opacity: root.shown ? 1 : 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
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
                text: "phonelink_ring"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("%1 wants to pair").arg(root.shownRequest?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.code.length > 0
                        ? Translation.tr("Accept if your phone shows the same code.")
                        : Translation.tr("Accept only if you just asked to pair from your phone.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.code.length > 0
            text: root.code
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
            color: Appearance.colors.colPrimary
        }

        RowLayout {
            Layout.fillWidth: true
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
                onClicked: if (root.request) Phone.declinePairing(root.request.id)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Decline")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                horizontalPadding: 12
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: if (root.request) Phone.acceptPairing(root.request.id)

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "check"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Accept")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }
}
