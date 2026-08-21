import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import qs.modules.settings.keyboard

ContentPage {
    forceWidth: true

    // Layouts above the shortcut editor, sharing this page's one scroll area —
    // the editor as a page of its own would nest a flickable inside this one.
    LayoutsSection {}
    KeybindsSection {}
}
