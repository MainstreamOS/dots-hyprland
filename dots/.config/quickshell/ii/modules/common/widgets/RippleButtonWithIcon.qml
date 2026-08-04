import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: buttonWithIconRoot
    property string nerdIcon
    property string materialIcon
    property bool materialIconFill: true
    property string mainText: "Button text"
    // A button narrower than its label used to paint the overflow outside its
    // own background, so the tail of a word sat loose on whatever was behind.
    // Only reachable when something constrains the width — a button given room
    // for its text is measured and drawn exactly as before.
    property Component mainContentComponent: Component {
        StyledText {
            visible: text !== ""
            text: buttonWithIconRoot.mainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideRight
        }
    }
    // Icon and label sit against the left edge, which suits a wide button and
    // leaves a narrow one looking lopsided. Opting in per button keeps every
    // existing one exactly where it is.
    property bool centerContent: false

    implicitHeight: 35
    horizontalPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            y: 0
            height: parent.height
            // Never wider than the button, so a label with nowhere to go still
            // elides instead of escaping.
            width: buttonWithIconRoot.centerContent
                ? Math.min(implicitWidth, parent.width)
                : parent.width
            x: buttonWithIconRoot.centerContent
                ? Math.round((parent.width - width) / 2)
                : 0

            Item {
                // A button with no icon named would otherwise still reserve an
                // empty slot and the spacing after it, pushing its label off
                // centre. Layouts skip an invisible child entirely.
                visible: buttonWithIconRoot.materialIcon !== "" || buttonWithIconRoot.nerdIcon !== ""
                Layout.fillWidth: false
                implicitWidth: Math.max(materialIconLoader.implicitWidth, nerdIconLoader.implicitWidth)
                Loader {
                    id: materialIconLoader
                    anchors.centerIn: parent
                    active: !nerdIcon
                    sourceComponent: MaterialSymbol {
                        text: buttonWithIconRoot.materialIcon
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSecondaryContainer
                        fill: buttonWithIconRoot.materialIconFill ? 1 : 0
                    }
                }
                Loader {
                    id: nerdIconLoader
                    anchors.centerIn: parent
                    active: nerdIcon
                    sourceComponent: StyledText {
                        text: buttonWithIconRoot.nerdIcon
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.family: Appearance.font.family.iconNerd
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
            Loader {
                Layout.fillWidth: !buttonWithIconRoot.centerContent
                sourceComponent: buttonWithIconRoot.mainContentComponent
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
