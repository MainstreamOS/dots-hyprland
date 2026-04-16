import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: TimerService.countdownDuration > 0 ? TimerService.countdownSecondsLeft / TimerService.countdownDuration : 0
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                Item {
                    id: timeItem
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 120
                    implicitHeight: 50

                    property bool editMode: false

                    function applyEdit() {
                        editMode = false;
                        let raw = timeField.text.replace(/[^0-9:]/g, "");
                        let parts = raw.split(":");
                        let newSeconds = 0;
                        if (parts.length >= 2) {
                            let mins = parseInt(parts[0]);
                            let secs = parseInt(parts[1]);
                            newSeconds = (isNaN(mins) ? 0 : mins) * 60 + (isNaN(secs) ? 0 : secs);
                        } else {
                            let s = parseInt(parts[0]);
                            newSeconds = isNaN(s) ? 0 : s;
                        }
                        TimerService.setCountdownTime(newSeconds);
                    }

                    StyledText {
                        visible: !timeItem.editMode
                        anchors.centerIn: parent
                        text: {
                            let minutes = Math.floor(TimerService.countdownSecondsLeft / 60).toString().padStart(2, '0');
                            let seconds = Math.floor(TimerService.countdownSecondsLeft % 60).toString().padStart(2, '0');
                            return `${minutes}:${seconds}`;
                        }
                        font.pixelSize: 40
                        color: Appearance.m3colors.m3onSurface
                    }

                    MouseArea {
                        anchors.fill: parent
                        visible: !timeItem.editMode
                        cursorShape: Qt.IBeamCursor
                        acceptedButtons: Qt.LeftButton

                        onClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton && !TimerService.countdownRunning) {
                                let minutes = Math.floor(TimerService.countdownDuration / 60).toString().padStart(2, '0');
                                let seconds = Math.floor(TimerService.countdownDuration % 60).toString().padStart(2, '0');
                                timeField.text = `${minutes}:${seconds}`;
                                timeItem.editMode = true;
                                timeField.forceActiveFocus();
                                timeField.selectAll();
                            }
                        }
                    }

                    StyledTextInput {
                        id: timeField
                        visible: timeItem.editMode
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: TextInput.AlignHCenter
                        font.pixelSize: 40
                        font.hintingPreference: Font.PreferDefaultHinting
                        renderType: Text.NativeRendering
                        color: Appearance.m3colors.m3onSurface

                        Keys.onReturnPressed: timeItem.applyEdit()
                        Keys.onEnterPressed: timeItem.applyEdit()
                        Keys.onEscapePressed: timeItem.editMode = false

                        onActiveFocusChanged: {
                            if (!activeFocus && timeItem.editMode)
                                timeItem.applyEdit();
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.countdownRunning ? Translation.tr("Running") : Translation.tr("Timer")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.countdownRunning ? Translation.tr("Pause") : (TimerService.countdownSecondsLeft === TimerService.countdownDuration) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.countdownRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.toggleCountdown()
                colBackground: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90

                onClicked: TimerService.resetCountdown()
                enabled: TimerService.countdownSecondsLeft < TimerService.countdownDuration

                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}
