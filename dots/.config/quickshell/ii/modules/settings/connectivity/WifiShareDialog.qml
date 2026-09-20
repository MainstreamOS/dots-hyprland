import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A QR code another device can scan to join a saved network. The password
// is read from the saved connection, never shown, and never put on a command
// line: it goes to the encoder on stdin, and the image lives in the user's
// runtime directory until this closes.
Popup {
    id: root

    required property string ssid

    property string keyMgmt: ""
    property string psk: ""
    property bool hidden: false
    property string error: ""
    property bool ready: false
    // The file is made under a 077 umask, so even the fallback stays private.
    readonly property string imageDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell"
    readonly property string imagePath: imageDir + "/wifi-share.png"
    property int imageRevision: 0

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 24

    Overlay.modal: Rectangle { color: Appearance.colors.colScrim }

    background: Item {
        StyledRectangularShadow { target: bg }
        Rectangle { id: bg; anchors.fill: parent; radius: Appearance.rounding.large; color: Appearance.m3colors.m3surfaceContainerHigh }
    }

    onOpened: {
        root.error = "";
        root.ready = false;
        root.psk = "";
        secretsProc.running = true;
    }
    onClosed: cleanupProc.running = true

    // The characters the format gives meaning to are escaped in both fields.
    function esc(s) {
        return String(s).replace(/([\\;,:"])/g, "\\$1");
    }

    function payload() {
        const mgmt = root.keyMgmt.toLowerCase();
        let type = "nopass";
        if (mgmt.indexOf("psk") !== -1 || mgmt.indexOf("sae") !== -1) type = "WPA";
        else if (mgmt.indexOf("wep") !== -1) type = "WEP";
        let out = "WIFI:T:" + type + ";S:" + root.esc(root.ssid) + ";";
        if (type !== "nopass") out += "P:" + root.esc(root.psk) + ";";
        if (root.hidden) out += "H:true;";
        return out + ";";
    }

    // Profiles are usually named after the network, but not always, so the
    // one whose stored network name matches is the one read.
    Process {
        id: secretsProc
        command: ["sh", "-c",
            'target="$0"; found=0;'
            + ' nmcli -t -f NAME,TYPE connection show 2>/dev/null | while IFS= read -r line; do'
            + '   case "$line" in *:802-11-wireless) ;; *) continue ;; esac;'
            + '   name="${line%:802-11-wireless}"; name="$(printf "%s" "$name" | sed "s/\\\\\\\\:/:/g")";'
            + '   ssid="$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null)";'
            + '   [ "$ssid" = "$target" ] || continue;'
            + '   printf "keymgmt=%s\\n" "$(nmcli -s -g 802-11-wireless-security.key-mgmt connection show "$name" 2>/dev/null)";'
            + '   printf "psk=%s\\n" "$(nmcli -s -g 802-11-wireless-security.psk connection show "$name" 2>/dev/null)";'
            + '   printf "hidden=%s\\n" "$(nmcli -g 802-11-wireless.hidden connection show "$name" 2>/dev/null)";'
            + '   echo found=1; exit 0;'
            + ' done',
            root.ssid]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text;
                const val = k => { const m = out.match(new RegExp("^" + k + "=(.*)$", "m")); return m ? m[1] : ""; };
                if (!/^found=1$/m.test(out)) {
                    root.error = Translation.tr("This network's saved details could not be read.");
                    return;
                }
                root.keyMgmt = val("keymgmt");
                root.psk = val("psk");
                root.hidden = val("hidden") === "yes";
                if (root.keyMgmt.length > 0 && root.keyMgmt !== "none" && root.psk.length === 0) {
                    root.error = Translation.tr("The password for this network is not stored where it can be read.");
                    return;
                }
                encodeProc.running = true;
            }
        }
    }

    Process {
        id: encodeProc
        command: ["sh", "-c", 'umask 077; mkdir -p "$0" && qrencode -o "$0/wifi-share.png" -s 10 -m 2 -l M', root.imageDir]
        stdinEnabled: true
        onRunningChanged: {
            if (running) {
                write(root.payload() + "\n");
                stdinEnabled = false;
            }
        }
        onExited: (code) => {
            if (code === 127) {
                root.error = Translation.tr("The QR code tool (qrencode) is not installed.");
            } else if (code !== 0) {
                root.error = Translation.tr("The QR code could not be made.");
            } else {
                root.imageRevision += 1;
                root.ready = true;
            }
        }
    }

    Process {
        id: cleanupProc
        command: ["rm", "-f", root.imagePath]
    }

    contentItem: ColumnLayout {
        spacing: 14

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: 300
            text: root.ssid
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer3
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 260
            implicitHeight: 260
            radius: Appearance.rounding.normal
            color: "white"

            Image {
                anchors.fill: parent
                anchors.margins: 10
                visible: root.ready
                cache: false
                fillMode: Image.PreserveAspectFit
                smooth: false
                source: root.ready ? ("file://" + root.imagePath + "?" + root.imageRevision) : ""
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - 32
                visible: !root.ready
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.error.length > 0 ? Appearance.m3colors.m3error : Appearance.m3colors.m3outline
                text: root.error.length > 0 ? root.error : Translation.tr("Preparing...")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: 300
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Point a phone's camera at this to join the network. The password stays inside the code.")
        }

        DialogButton {
            Layout.alignment: Qt.AlignHCenter
            buttonText: Translation.tr("Close")
            onClicked: root.close()
        }
    }
}
