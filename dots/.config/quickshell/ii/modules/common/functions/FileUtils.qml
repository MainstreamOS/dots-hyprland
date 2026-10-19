pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        return s.startsWith("file://") ? s.slice(7) : s;
    }

    /**
     * Extracts the file name from a file path
     * @param {string} str
     * @returns {string}
     */
    function fileNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        return trimmed.split(/[\\/]/).pop();
    }

    /**
     * Extracts the folder name from a directory path
     * @param {string} str
     * @returns {string}
     */
    function folderNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        // Remove trailing slash if present
        const noTrailing = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
        if (!noTrailing) return "";
        return noTrailing.split(/[\\/]/).pop();
    }

    /**
     * Removes the file extension from a file path or name
     * @param {string} str
     * @returns {string}
     */
    function trimFileExt(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const lastDot = trimmed.lastIndexOf(".");
        if (lastDot > -1 && lastDot > trimmed.lastIndexOf("/")) {
            return trimmed.slice(0, lastDot);
        }
        return trimmed;
    }

    /**
     * Returns the parent directory of a given file path
     * @param {string} str
     * @returns {string}
     */
    function parentDirectory(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const parts = trimmed.split(/[\\/]/);
        if (parts.length <= 1) return "";
        parts.pop();
        return parts.join("/");
    }

    /**
     * A file:// URL for a path, each segment percent-encoded so a name holding '#', '?' or '%' stays part of the path
     * @param {string} path
     * @returns {string}
     */
    function fileUrl(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    // A file URL (or a plain path) as a local path; "" when its escapes are malformed.
    function pathFromUrl(url) {
        try {
            return decodeURIComponent(trimFileProtocol(String(url ?? "")));
        } catch (e) {
            return "";
        }
    }

    // A local path (with or without file://) as an encoded file URL; web, data and qrc URLs pass through.
    function mediaUrl(path) {
        const s = String(path ?? "");
        if (!s.length) return "";
        if (s.startsWith("http://") || s.startsWith("https://") || s.startsWith("data:") || s.startsWith("qrc:/")) return s;
        return fileUrl(trimFileProtocol(s));
    }
}
