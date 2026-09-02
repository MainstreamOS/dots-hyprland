import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    id: root
    icon: "language"
    title: Translation.tr("Input Sources")

    // A curated pick list rather than fcitx5's full catalog: each entry is a
    // language people compose, wired end to end on selection, with the engine
    // installed on demand. The plain keyboard is the way back out.
    readonly property var sources: [
        { code: Translation.tr("None"), name: Translation.tr("Plain keyboard"), engine: "none" },
        { code: Translation.tr("Japanese"), name: "Mozc", engine: "mozc" },
        { code: Translation.tr("Chinese"), name: "Pinyin", engine: "pinyin" },
        { code: Translation.tr("Korean"), name: "Hangul", engine: "hangul" },
        { code: Translation.tr("Vietnamese"), name: "Unikey", engine: "unikey" }
    ]
    property bool stateLoaded: false
    property string statusText: ""

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Translation.tr("Languages that compose characters use an input method; picking one sets it up and switches to it.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    LayoutPicker {
        id: sourcePicker
        Layout.fillWidth: true
        options: root.sources
        ready: root.stateLoaded
        layoutIdOf: source => source.engine
        searchPlaceholder: Translation.tr("Search input sources…")
        onSelectedIdChanged: {
            if (!root.stateLoaded || applyProc.running) return;
            root.statusText = Translation.tr("Applying input method…");
            applyProc.command = ["bash", `${Directories.scriptPath}/keyboard/set-input-source.sh`.replace(/file:\/\//, ""), sourcePicker.selectedId];
            applyProc.running = true;
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.statusText.length > 0
        wrapMode: Text.WordWrap
        text: root.statusText
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Process {
        id: readStateProc
        running: true
        command: ["bash", "-c", "grep -oP '^DefaultIM=\\K.*' \"$HOME/.config/fcitx5/profile\" 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const current = text.trim();
                const known = root.sources.find(source => source.engine === current);
                sourcePicker.selectedId = known ? current : "none";
                root.stateLoaded = true;
            }
        }
    }

    Process {
        id: applyProc
        onExited: exitCode => {
            root.statusText = exitCode === 0
                ? Translation.tr("Input method ready.")
                : Translation.tr("Could not set the input method.");
        }
    }
}
