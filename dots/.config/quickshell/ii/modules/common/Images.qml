pragma Singleton

import Quickshell

Singleton {
    // Formats
    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "tif", "tiff", "svg"]

    function isValidImageByName(name: string): bool {
        return validImageExtensions.some(t => name.endsWith(`.${t}`));
    }

    // Thumbnails
    // https://specifications.freedesktop.org/thumbnail-spec/latest/directory.html
    readonly property var thumbnailSizes: ({
        "normal": 128,
        "large": 256,
        "x-large": 512,
        "xx-large": 1024
    })
    // The two places that show the current wallpaper — Quick Setup's preview and
    // the Themes save card — ask for it at this size so they land on one cache
    // entry between them: Qt keys pixmaps on the requested size and the fill
    // mode as well as the URL, and a mismatch is silent. Fixed rather than the
    // drawn width because StyledImage's default sourceSize is a binding on its
    // own geometry, which only settles after the layout pass — too late for the
    // cache hit to land during component creation, so the fade-in replays every
    // time the page is rebuilt.
    readonly property size wallpaperPreviewSourceSize: Qt.size(768, 432)

    // For a Process that runs ImageMagick on a picture the user chose. Left
    // alone it may take all of memory and then spill to disk, and /tmp is
    // memory as well, so a picture too big to handle would freeze the system
    // instead of failing. A picture's pixels must fit in one of the three, so
    // the 2 GiB of memory is what lets a 16K still through, and the three
    // together cap a runaway at about 4 GiB.
    readonly property var magickEnvironment: ({
        "MAGICK_MEMORY_LIMIT": "2GiB",
        "MAGICK_MAP_LIMIT": "1GiB",
        "MAGICK_DISK_LIMIT": "1GiB"
    })

    function thumbnailSizeNameForDimensions(width: int, height: int): string {
        const sizeNames = Object.keys(thumbnailSizes);
        for(let i = 0; i < sizeNames.length; i++) {
            const sizeName = sizeNames[i];
            const maxSize = thumbnailSizes[sizeName];
            if (width <= maxSize && height <= maxSize) return sizeName;
        }
        return "xx-large";
    }
}
