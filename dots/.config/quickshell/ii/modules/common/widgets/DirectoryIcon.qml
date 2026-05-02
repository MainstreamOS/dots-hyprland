import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

Image {
    id: root
    required property var fileModelData
    property int currentFallbackIndex: 0
    property var sourceFallbacks: []
    asynchronous: true
    cache: false
    fillMode: Image.PreserveAspectFit

    function papirusIcon(iconName) {
        return `file://${FileUtils.trimFileProtocol(Directories.home)}/.local/share/icons/Papirus-Matugen/48x48/places/${iconName}.svg`;
    }

    function directoryIconName() {
        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return `folder-${fileModelData.fileName.toLowerCase()}`;

        return "folder";
    }

    function systemDirectoryIconName() {
        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return `folder-${fileModelData.fileName.toLowerCase()}`;

        return "inode-directory";
    }

    function rebuildSourceFallbacks() {
        currentFallbackIndex = 0;
        if (!fileModelData.fileIsDir) {
            sourceFallbacks = [Quickshell.iconPath("application-x-zerosize")];
        } else {
            sourceFallbacks = [
                papirusIcon(directoryIconName()),
                papirusIcon("folder"),
                Quickshell.iconPath(systemDirectoryIconName()),
                Quickshell.iconPath("inode-directory")
            ];
        }
        source = sourceFallbacks[0];
    }

    Component.onCompleted: rebuildSourceFallbacks()
    onFileModelDataChanged: rebuildSourceFallbacks()

    onStatusChanged: {
        if (status !== Image.Error)
            return;

        currentFallbackIndex += 1;
        if (currentFallbackIndex < sourceFallbacks.length)
            source = sourceFallbacks[currentFallbackIndex];
        else
            source = Quickshell.iconPath("error");
    }

    Process {
        running: !fileModelData.fileIsDir
        command: ["file", "--mime", "-b", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.split(";")[0].replace("/", "-");
                root.source = Images.validImageTypes.some(t => mime === `image-${t}`) ? fileModelData.fileUrl : Quickshell.iconPath(mime, "image-missing");
            }
        }
    }
}
