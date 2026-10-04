pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// Separators never reach this row: the menu draws the app's separators itself.
ContextMenuItem {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false
    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None
    readonly property bool showSpecialInteractionColumn: root.hasSpecialInteraction || root.forceSpecialInteractionColumn
    readonly property bool showIconColumn: root.hasIcon || root.forceIconColumn

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    enabled: root.menuEntry.enabled
    label: root.menuEntry.text

    releaseAction: () => {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry);
            return;
        }
        menuEntry.triggered();
        root.dismiss();
    }
    altAction: (event) => { // Not hog right-click
        event.accepted = false;
    }

    // Check and icon columns stay on every row when any row has one, so labels line up.
    leading: (root.showSpecialInteractionColumn || root.showIconColumn) ? leadingColumns : null
    trailing: root.menuEntry.hasChildren ? submenuChevron : null

    Component {
        id: leadingColumns
        RowLayout {
            spacing: 8

            // Interaction: checkbox or radio button
            Item {
                visible: root.showSpecialInteractionColumn
                implicitWidth: 20
                implicitHeight: 20

                Loader {
                    anchors.fill: parent
                    active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton

                    sourceComponent: StyledRadioButton {
                        enabled: false
                        padding: 0
                        checked: root.menuEntry.checkState === Qt.Checked
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox && root.menuEntry.checkState !== Qt.Unchecked

                    sourceComponent: MaterialSymbol {
                        text: root.menuEntry.checkState === Qt.PartiallyChecked ? "check_indeterminate_small" : "check"
                        iconSize: 20
                    }
                }
            }

            // Button icon
            Item {
                visible: root.showIconColumn
                implicitWidth: 20
                implicitHeight: 20

                Loader {
                    anchors.centerIn: parent
                    active: root.menuEntry.icon.length > 0
                    sourceComponent: IconImage {
                        source: root.menuEntry.icon
                        implicitSize: 20
                        mipmap: true
                    }
                }
            }
        }
    }

    Component {
        id: submenuChevron
        MaterialSymbol {
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.m3colors.m3onSurface
        }
    }
}
