pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property var left: null
    property var right: null
    readonly property var entries: [left, right].filter(preview => preview !== null)
}
