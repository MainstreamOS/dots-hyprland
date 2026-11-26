.pragma library

// The backlight Automatic drives. brightnessctl takes the first one it finds,
// which on a MacBook Pro with a Touch Bar can be the Touch Bar's own, and the
// brightness keys then dim the strip instead of the screen. With that one
// present the pick is made here instead: apple-gmux's when the kernel chose it
// for the panel, otherwise the first other backlight. Empty leaves the choice
// to brightnessctl. After Omarchy (MIT).
var touchBar = "appletb_backlight";

function automaticDevice(devices) {
    const others = [];
    let touchBarFound = false;
    for (let i = 0; i < devices.length; i++) {
        if (devices[i] === touchBar)
            touchBarFound = true;
        else
            others.push(devices[i]);
    }
    if (!touchBarFound)
        return "";
    if (others.indexOf("gmux_backlight") !== -1)
        return "gmux_backlight";
    return others[0] ?? "";
}
