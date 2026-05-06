import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        // sourcePath is already a raw filesystem path (e.g. fileModelData.filePath
        // from FolderListModel — literal spaces, no percent-encoding). Wrapping it
        // in Qt.resolvedUrl() yields a URL with `%20` etc. already in place, after
        // which the per-segment encodeURIComponent below double-encodes (`%` → `%25`)
        // and the resulting md5 no longer matches what generate-thumbnails-magick.sh
        // wrote, so files in directories with whitespace render as transparent
        // tiles in the wallpaper picker. Encode straight from the raw path.
        const rawPath = FileUtils.trimFileProtocol(sourcePath);
        const encodedPath = rawPath.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedPath}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }
    Process {
        id: thumbnailGeneration
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            return ["bash", "-c", 
                `[ -f '${FileUtils.trimFileProtocol(root.thumbnailPath)}' ] && exit 0 || { magick '${root.sourcePath}' -resize ${maxSize}x${maxSize} '${FileUtils.trimFileProtocol(root.thumbnailPath)}' && exit 1; }`
            ]
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 1) { // Force reload if thumbnail had to be generated
                root.source = "";
                root.source = root.thumbnailPath; // Force reload
            }
        }
    }
}
