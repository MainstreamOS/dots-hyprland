pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property Component captureProxy: Component {
        ShaderEffectSource { visible: false }
    }

    function grab(item: Item, callback, targetSize: size): bool {
        const window = item.Window.window;
        if (!window?.visible) return false;
        // An unfinished grab is deleted with its item, even mid-render, so grab
        // through a proxy the window owns that outlives a removed tray icon.
        const proxy = root.captureProxy.createObject(window.contentItem, {
            sourceItem: item, width: item.width, height: item.height,
            textureSize: targetSize
        });
        const started = proxy.grabToImage(result => {
            try {
                if (item) callback(result);
            } finally {
                proxy.destroy();
            }
        }, targetSize);
        if (!started) proxy.destroy();
        return started;
    }
}
