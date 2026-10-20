pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../../services/PhoneContacts.js" as Contacts

Rectangle {
    id: actions
    property bool canCall: false
    property bool canMessage: false
    signal callRequested(string number)
    signal messageRequested(string number, string name)
    required property string number
    property string name: number
    property bool compact: false
    implicitWidth: compact ? 60 : 70
    implicitHeight: compact ? 28 : 34
    radius: compact ? 8 : 10
    color: Appearance.surfaces.row

    RowLayout {
        anchors.fill: parent
        spacing: 2
        RippleButton {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 0
            buttonRadius: Appearance.rounding.verysmall
            enabled: actions.canCall && !!Contacts.dialNumber(actions.number)
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            Accessible.name: Translation.tr("Call %1").arg(actions.name)
            onClicked: actions.callRequested(actions.number)
            contentItem: MaterialSymbol {
                text: "call"
                iconSize: actions.compact ? 14 : 16
                color: Appearance.colors.colPrimary
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            StyledToolTip { text: Translation.tr("Call %1").arg(actions.number) }
        }
        Rectangle {
            Layout.preferredWidth: 2
            Layout.fillHeight: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.8)
        }
        RippleButton {
            Layout.fillWidth: true
            Layout.fillHeight: true
            buttonRadius: Appearance.rounding.verysmall
            padding: 0
            enabled: actions.canMessage && /^\+?[0-9]+$/.test(Contacts.dialNumber(actions.number))
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            Accessible.name: Translation.tr("Message %1").arg(actions.name)
            onClicked: actions.messageRequested(actions.number, actions.name)
            contentItem: MaterialSymbol {
                text: "chat_bubble"
                iconSize: actions.compact ? 13 : 15
                color: Appearance.colors.colOnLayer1
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            StyledToolTip { text: Translation.tr("Message %1").arg(actions.number) }
        }
    }
}
