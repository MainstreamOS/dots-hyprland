import QtQuick

WheelHandler {
    id: root
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    signal stepped(int direction)
    property real accumulated: 0
    onWheel: event => {
        // Wayland can supply both deltas for a physical wheel notch. Prefer
        // its angle so one notch always adjusts the control by one step.
        const angle = event.angleDelta.y;
        const delta = angle || event.pixelDelta.y;
        if (!delta) return;
        if (accumulated * delta < 0) accumulated = 0;
        accumulated += delta;
        const threshold = angle ? 120 : 20;
        while (Math.abs(accumulated) >= threshold) {
            const direction = accumulated > 0 ? 1 : -1;
            root.stepped(direction);
            accumulated -= direction * threshold;
        }
        event.accepted = true;
        reset.restart();
    }
    property Timer resetTimer: Timer {
        id: reset
        interval: 250
        onTriggered: root.accumulated = 0
    }
}
