import QtQuick
import qs.services
import qs.modules.common

// A waiting release's dot, in its urgency color for the surface it sits on.
Rectangle {
    property real size: 6
    property Appearance.SurfaceContent tones: Appearance.barContent
    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: ReleaseUpdates.dotColor(tones)
}
