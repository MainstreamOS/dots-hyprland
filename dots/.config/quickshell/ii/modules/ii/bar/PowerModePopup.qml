import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// Right-click popup for the BatteryIndicator. Lets the user pick a power
// profile via power-profiles-daemon (the same backend the sidebar's quick
// toggle uses). Hover-show is disabled — only the indicator's right-click
// handler flips `open`, and clicking a profile sets it back to false.
StyledPopup {
    id: root
    property bool open: false
    forceShow: open
    showOnHover: false

    function setProfile(p) {
        PowerProfiles.profile = p
        root.open = false
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "bolt"
            label: Translation.tr("Power Mode")
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 180
            visible: PowerProfiles.hasPerformanceProfile
            materialIcon: "local_fire_department"
            mainText: Translation.tr("Performance")
            colBackground: PowerProfiles.profile === PowerProfile.Performance
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            onClicked: root.setProfile(PowerProfile.Performance)
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 180
            materialIcon: "airwave"
            mainText: Translation.tr("Balanced")
            colBackground: PowerProfiles.profile === PowerProfile.Balanced
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            onClicked: root.setProfile(PowerProfile.Balanced)
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 180
            materialIcon: "energy_savings_leaf"
            mainText: Translation.tr("Power Saver")
            colBackground: PowerProfiles.profile === PowerProfile.PowerSaver
                ? Appearance.colors.colPrimaryContainer
                : Appearance.colors.colLayer2
            onClicked: root.setProfile(PowerProfile.PowerSaver)
        }
    }
}
