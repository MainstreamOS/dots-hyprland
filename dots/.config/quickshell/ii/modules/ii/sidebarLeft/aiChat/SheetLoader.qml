import QtQuick

// Builds a sheet on first use and keeps it, so its state survives a close.
Loader {
    readonly property bool shown: item?.shown ?? false
    function load(): var {
        active = true;
        return item;
    }
    anchors.fill: parent
    z: 100
    active: false
}
