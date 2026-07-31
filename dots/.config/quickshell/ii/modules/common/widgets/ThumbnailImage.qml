import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 *
 * Two modes, split by generateThumbnail:
 *
 * Off, which is what the wallpaper picker uses, is the plain form: point at the
 * name the bulk generator wrote and show it if it is there.
 *
 * On makes this responsible for the file as well, and that brings the problem
 * the plain form doesn't have — the name is an md5 of the *path*, so a source
 * rewritten in place keeps the same thumbnail name and the same URL. Neither
 * the file on disk nor Qt's pixmap cache would notice. So the generator also
 * reports the mtime of whatever it settled on, and that goes in the URL as a
 * ?v= token: a replaced source arrives under a URL nothing has decoded, and an
 * unchanged one keeps hitting the cache.
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return "";
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

    // The file the generator settled on and its mtime, as one object so the two
    // can never be read apart: assigned separately, a source that changed both
    // would publish the new file under the old token for a pass and decode a
    // URL describing neither. Empty until the generator has spoken, so nothing
    // decodes a placeholder and then the real thing.
    property var resolved: ({ path: "", stamp: "" })

    source: {
        if (!root.generateThumbnail) return root.thumbnailPath;
        if (root.resolved.path.length === 0) return "";
        return `file://${root.resolved.path}?v=${root.resolved.stamp}`;
    }

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    function refresh() {
        if (!root.generateThumbnail) return;
        if (FileUtils.trimFileProtocol(root.sourcePath).length === 0) return;
        thumbnailGeneration.running = false;
        thumbnailGeneration.running = true;
    }

    onSourcePathChanged: root.refresh()
    onThumbnailSizeNameChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Process {
        id: thumbnailGeneration
        property string buf: ""
        // Paths go in as arguments rather than interpolated, so spaces in them
        // survive. A source newer than its thumbnail means it was replaced under
        // a name the thumbnail is still keyed on, so the thumbnail is rebuilt;
        // `>` on the resize keeps a source smaller than the bucket from being
        // blown up to fill it. A source we can't thumbnail — no magick, cache
        // not writable — is reported as itself, so the worst case is reading the
        // full-size file rather than showing nothing at all.
        command: ["bash", "-c", `
            src="$0"; thumb="$1"; max="$2"
            [ -f "$src" ] || exit 0
            use="$src"
            if [ -f "$thumb" ] && [ ! "$src" -nt "$thumb" ]; then
                use="$thumb"
            elif mkdir -p "\${thumb%/*}" 2>/dev/null && magick "$src" -resize "\${max}x\${max}>" "$thumb" 2>/dev/null; then
                use="$thumb"
            fi
            printf '%s\\t%s\\n' "$(stat -c %.9Y "$use" 2>/dev/null || stat -c %Y "$use")" "$use"
        `,
            FileUtils.trimFileProtocol(root.sourcePath),
            FileUtils.trimFileProtocol(root.thumbnailPath),
            String(Images.thumbnailSizes[root.thumbnailSizeName])
        ]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => thumbnailGeneration.buf += data }
        onExited: {
            const parts = (thumbnailGeneration.buf || "").trim().split("\t");
            if (parts.length !== 2 || parts[0].length === 0 || parts[1].length === 0) return;
            root.resolved = { path: parts[1], stamp: parts[0] };
        }
    }
}
