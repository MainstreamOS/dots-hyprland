pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import Quickshell.Widgets

ComboBox {
    id: root
    readonly property QtObject fontSizes: Appearance.font.sizesFor(QsWindow.window)

    property string buttonIcon: ""
    property string buttonAppIcon: ""
    property string appIconRole: "appIcon"
    readonly property var currentEntry: currentIndex >= 0 && typeof model?.[currentIndex] === 'object' ? model[currentIndex] : null
    readonly property string currentAppIcon: buttonAppIcon || (currentEntry?.[appIconRole] ?? "")
    readonly property real appIconSize: root.fontSizes.larger + 4
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    // Grows by the same factor as the widths drop-downs are given, so their shape holds at any text size.
    implicitHeight: Math.round(40 * root.fontSizes.small / Appearance.font.basePixelSize.small)
    readonly property real contentInset: 16
    leftPadding: 0
    rightPadding: indicator.width + root.contentInset
    Layout.fillWidth: true

    function choiceEnabled(index) {
        const entry = root.model?.[index];
        return typeof entry !== 'object' || (entry?.enabled ?? true);
    }

    // The arrow keys, Home, End and typing a letter pass over dimmed choices, as clicks do.
    Keys.onPressed: event => {
        if (root.moveChoice(event.key) || root.typeToChoice(event))
            event.accepted = true;
    }
    function moveChoice(key): bool {
        const dir = (key === Qt.Key_Up || key === Qt.Key_Home) ? -1 : (key === Qt.Key_Down || key === Qt.Key_End) ? 1 : 0;
        if (!dir) return false;
        const from = root.popup.visible ? root.highlightedIndex : root.currentIndex;
        const jump = key === Qt.Key_Home || key === Qt.Key_End;
        let target = jump ? (dir > 0 ? root.count - 1 : 0) : from + dir;
        while (target >= 0 && target < root.count && !root.choiceEnabled(target))
            target += jump ? -dir : dir;
        if (target >= 0 && target < root.count)
            root.selectChoice(target);
        return true;
    }
    // In place of the built-in search, which lands on dimmed choices too: the next choice on
    // offer that starts with the letter, round from the one after the current.
    function typeToChoice(event): bool {
        if (root.editable || event.text.length !== 1 || event.text.trim() === ""
                || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            return false;
        const letter = event.text.toLowerCase();
        const from = root.popup.visible ? root.highlightedIndex : root.currentIndex;
        for (let step = 1; step <= root.count; step++) {
            const i = (from + step + root.count) % root.count;
            if (root.choiceEnabled(i) && root.textAt(i).toLowerCase().startsWith(letter)) {
                root.selectChoice(i);
                break;
            }
        }
        return true;
    }
    function selectChoice(target) {
        const from = root.popup.visible ? root.highlightedIndex : root.currentIndex;
        if (target === from) return;
        if (root.popup.visible) {
            // Moving the highlight one step at a time is all the popup offers.
            for (let i = from; i !== target; i += target > from ? 1 : -1)
                target > from ? root.incrementCurrentIndex() : root.decrementCurrentIndex();
        } else {
            root.currentIndex = target;
            root.activated(target);
        }
    }

    function iconSource(icon) {
        if (!icon) return "";
        return (icon.startsWith("/") || icon.startsWith("file://")) ? icon : Quickshell.iconPath(icon, "multimedia-audio-player");
    }

    background: Rectangle {
        radius: root.buttonRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: root.fontSizes.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitWidth: buttonLayout.implicitWidth + root.contentInset + 8
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: root.contentInset
            anchors.rightMargin: 8

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.currentAppIcon.length > 0
                visible: active
                sourceComponent: IconImage {
                    implicitSize: root.appIconSize
                    source: root.iconSource(root.currentAppIcon)
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: !root.currentAppIcon && (root.buttonIcon.length > 0 || !!root.currentEntry?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: root.currentEntry?.icon || root.buttonIcon
                    iconSize: root.fontSizes.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                visible: text.length > 0
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view ? ListView.view.width : root.width
        implicitHeight: Math.max(40, implicitContentHeight + topPadding + bottomPadding)
        topPadding: 8
        bottomPadding: 8
        // The popup's own padding also contributes to the icon's screen position.
        leftPadding: Math.max(0, root.contentInset - root.popup.leftPadding)
        rightPadding: 12

        required property var model
        required property int index
        // A choice can be shown without being on offer: dimmed, and not picked by a click.
        enabled: (typeof model === 'object' ? model?.enabled : undefined) ?? true
        opacity: enabled ? 1 : 0.5
        readonly property string appIcon: typeof model === 'object' ? (model?.[root.appIconRole] ?? "") : ""
        property color color: {
            if (root.currentIndex === itemDelegate.index) {
                if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                if (itemDelegate.hovered) return Appearance.colors.colSecondaryContainerHover;
                return Appearance.colors.colSecondaryContainer;
            } else {
                if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                if (itemDelegate.hovered) return Appearance.colors.colLayer3Hover;
                return ColorUtils.transparentize(Appearance.colors.colLayer3);
            }
        }
        property color colText: (root.currentIndex === itemDelegate.index) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

        background: Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: itemDelegate.color

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        contentItem: RowLayout {
            spacing: 8

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: itemDelegate.appIcon.length > 0
                visible: active
                sourceComponent: IconImage {
                    implicitSize: root.appIconSize
                    source: root.iconSource(itemDelegate.appIcon)
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: root.fontSizes.larger
                active: !itemDelegate.appIcon && typeof itemDelegate.model === 'object' && itemDelegate.model?.icon?.length > 0
                visible: active

                sourceComponent: Item {
                    implicitWidth: icon.implicitWidth
                    implicitHeight: root.fontSizes.larger

                    MaterialSymbol {
                        id: icon
                        anchors.centerIn: parent
                        text: itemDelegate.model?.icon ?? ""
                        iconSize: root.fontSizes.larger
                        color: itemDelegate.colText
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: itemDelegate.colText
                text: root.textRole ? (itemDelegate.model[root.textRole] ?? "") : (itemDelegate.model.modelData ?? "")
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        height: Math.min(listView.contentHeight + topPadding + bottomPadding, 300)
        padding: 8

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        exit: Transition {
            PropertyAnimation {
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }

            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: StyledListView {
            id: listView
            clip: true
            implicitHeight: contentHeight
            spacing: 2
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
        }
    }
}
