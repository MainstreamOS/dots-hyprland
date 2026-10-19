import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// Saves a message attachment at full quality: a spinner while it comes from
// the phone, then a check (or an error mark) for a moment.
RippleButton {
    id: root
    required property var attachment
    property color iconColor: Appearance.colors.colOnLayer1
    // "", "done" or "failed"
    property string result: ""
    readonly property bool busy: Phone.attachmentBusy(root.attachment?.uid ?? "")

    implicitWidth: 28
    implicitHeight: 28
    buttonRadius: Appearance.rounding.full
    scale: root.down ? 0.88 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    onClicked: {
        root.result = "";
        Phone.useAttachment(root.attachment, "save");
    }

    contentItem: Item {
        anchors.fill: parent
        MaterialSymbol {
            id: icon
            anchors.centerIn: parent
            visible: !root.busy
            text: root.result === "done" ? "check" : root.result === "failed" ? "error" : "download"
            iconSize: Appearance.font.pixelSize.normal
            color: root.result === "failed" ? Appearance.m3colors.m3error : root.iconColor
        }
        MaterialLoadingIndicator {
            anchors.centerIn: parent
            visible: root.busy
            implicitSize: 22
            loading: visible
        }
    }

    function show(result): void {
        root.result = result;
        pop.restart();
        resetTimer.restart();
    }

    SequentialAnimation {
        id: pop
        NumberAnimation { target: icon; property: "scale"; to: 1.4; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: icon; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
    }
    Timer {
        id: resetTimer
        interval: 1800
        onTriggered: root.result = ""
    }
    Connections {
        target: Phone
        function onLastSaveChanged() {
            const save = Phone.lastSave;
            if (save && save.uid === root.attachment?.uid) root.show(save.ok ? "done" : "failed");
        }
    }

    StyledToolTip {
        text: /^image/.test(root.attachment?.mime ?? "") ? Translation.tr("Save to Pictures") : Translation.tr("Save to Downloads")
    }
}
