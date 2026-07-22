import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A searchable font family picker. Shows the current family rendered in its own
// typeface; clicking opens a popup with a search box and the full installed-font
// list (each entry previewed in its own family). Emits fontSelected(family).
Item {
    id: root
    property string value: ""
    signal fontSelected(string family)

    Layout.fillWidth: true
    implicitHeight: 44

    readonly property var families: Qt.fontFamilies()

    Rectangle {
        id: field
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: fieldArea.containsMouse ? Appearance.colors.colSecondaryContainerHover
                                       : Appearance.colors.colSecondaryContainer
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: (root.value && root.value.length > 0) ? root.value : Translation.tr("Choose a font…")
                color: Appearance.colors.colOnSecondaryContainer
                font.family: (root.value && root.value.length > 0) ? root.value : Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.normal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        MouseArea {
            id: fieldArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                searchField.text = "";
                // Decide drop direction + height from the room around the field in
                // the window, so a picker near the bottom flips up instead of
                // running off-screen.
                const ov = Overlay.overlay;
                const topY = field.mapToItem(ov, 0, 0).y;
                const ovH = ov ? ov.height : 750;
                const below = ovH - (topY + field.height) - 8;
                const above = topY - 8;
                popup.dropUp = below < 340 && above > below;
                popup.availH = Math.min(340, popup.dropUp ? above : below);
                popup.open();
            }
        }
    }

    Popup {
        id: popup
        // Drop down by default; flip up when the field is near the window bottom
        // (decided at open-time), and cap the height to the space actually
        // available so the search + list never run off-screen.
        property bool dropUp: false
        property real availH: 340
        y: dropUp ? -(height + 4) : (field.height + 4)
        width: field.width
        height: availH
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: searchField.forceActiveFocus()

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        exit: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 6
            MaterialTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search fonts…")
            }
            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                animateAppearance: false
                model: {
                    const q = searchField.text.trim().toLowerCase();
                    if (q.length === 0) return root.families;
                    return root.families.filter(f => f.toLowerCase().includes(q));
                }
                delegate: Rectangle {
                    id: item
                    required property string modelData
                    width: ListView.view.width
                    implicitHeight: 38
                    radius: Appearance.rounding.small
                    color: (item.modelData === root.value) ? Appearance.colors.colSecondaryContainer
                        : itemArea.containsMouse ? Appearance.colors.colLayer1Hover
                        : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: item.modelData
                            font.family: item.modelData
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        MaterialSymbol {
                            visible: item.modelData === root.value
                            text: "check"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }
                    }
                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.fontSelected(item.modelData);
                            popup.close();
                        }
                    }
                }
            }
        }
    }
}
