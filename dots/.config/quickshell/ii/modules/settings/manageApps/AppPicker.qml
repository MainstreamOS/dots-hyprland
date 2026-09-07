pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// A field naming an app, and a popup to choose another one. Given a role, the
// apps offered are the ones that can do that job, best fit first; given none,
// every app on the machine.
Item {
    id: picker

    // The job being filled, as scripts/apps/default-apps.sh names it. Empty
    // offers everything installed.
    property string roleKey: ""
    // The app shown in the field, by desktop id.
    property string currentId: ""
    property string placeholderText: Translation.tr("Choose an app")
    // Shown instead of an app icon when the field stands for an action rather
    // than a current choice.
    property string fieldIcon: ""
    property bool busy: false

    signal picked(string entryId)

    implicitHeight: 40

    function entryFor(entryId) {
        // byId() is a plain call and registers no dependency, so a binding
        // through it would keep whatever it got while the catalog was still
        // filling in: the raw id in place of the app's name, for the life of
        // the page. Reading the entry list makes the catalog itself the
        // dependency. The value, not its length: a rescan after a .desktop
        // file changes replaces the entries while the count stays put.
        DesktopEntries.applications.values;
        if (!entryId || entryId.length === 0) return null;
        return DesktopEntries.byId(entryId) ?? DesktopEntries.heuristicLookup(entryId);
    }

    function nameFor(entryId) {
        const entry = picker.entryFor(entryId);
        if (entry && entry.name.length > 0) return entry.name;
        // A default set by something else can name an app that is no longer
        // installed. Saying the id is more use than saying nothing.
        return entryId ?? "";
    }

    function iconFor(entryId) {
        const entry = picker.entryFor(entryId);
        const name = (entry?.icon && entry.icon.length > 0) ? entry.icon : AppSearch.guessIcon(entryId);
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // Every app the machine has, for the "show everything" case and as the
    // fallback when a role's own list comes back empty.
    readonly property var allEntries: Array.from(DesktopEntries.applications.values)
        .filter((entry, index, self) => !entry.noDisplay
            && index === self.findIndex(other => other.id === entry.id))
        .map(entry => ({ id: entry.id, rank: 1 }))

    // Ids the role's script offered, in the order it ranked them.
    property var roleCandidates: []
    property bool candidatesLoaded: false

    function refreshCandidates() {
        if (picker.roleKey.length === 0) {
            picker.candidatesLoaded = true;
            return;
        }
        candidateReader.running = false;
        candidateReader.running = true;
    }

    readonly property var offeredEntries: {
        const base = (picker.roleKey.length === 0 || showAllSwitch.checked || (picker.candidatesLoaded && picker.roleCandidates.length === 0))
            ? picker.allEntries
            : picker.roleCandidates;
        const query = searchField.text.trim().toLowerCase();
        const rows = base.map(item => ({
            id: item.id,
            rank: item.rank,
            name: picker.nameFor(item.id),
        }));
        const matching = query.length === 0 ? rows : rows.filter(row =>
            row.name.toLowerCase().includes(query) || row.id.toLowerCase().includes(query));
        matching.sort((a, b) => a.rank !== b.rank ? a.rank - b.rank : a.name.localeCompare(b.name));
        return matching;
    }

    // Ask again for what can do the job, then show the list where there is
    // room for it: a row near the bottom of a page drops upward rather than
    // getting a sliver.
    function openList() {
        searchField.text = "";
        showAllSwitch.checked = false;
        picker.candidatesLoaded = false;
        picker.refreshCandidates();
        const overlay = Overlay.overlay;
        const topY = field.mapToItem(overlay, 0, 0).y;
        const overlayHeight = overlay ? overlay.height : 750;
        const spaceBelow = overlayHeight - (topY + field.height) - 8;
        const spaceAbove = topY - 8;
        popup.dropUp = spaceBelow < 300 && spaceAbove > spaceBelow;
        popup.listHeight = Math.max(180, Math.min(360, popup.dropUp ? spaceAbove : spaceBelow));
        popup.open();
    }

    Process {
        id: candidateReader
        command: [DefaultApps.scriptPath, "candidates", picker.roleKey]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => candidateReader.buf += data + "\n" }
        onExited: {
            const seen = ({});
            const rows = [];
            for (const line of candidateReader.buf.split("\n")) {
                if (line.length === 0) continue;
                const parts = line.split("\t");
                if (parts.length < 2) continue;
                const id = parts[1].trim();
                if (id.length === 0 || seen[id]) continue;
                seen[id] = true;
                rows.push({ id: id, rank: parseInt(parts[0], 10) });
            }
            picker.roleCandidates = rows;
            picker.candidatesLoaded = true;
        }
    }

    Rectangle {
        id: field
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: fieldArea.containsMouse && !picker.busy
            ? Appearance.colors.colSecondaryContainerHover
            : Appearance.colors.colSecondaryContainer
        opacity: picker.busy ? 0.6 : 1

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 8

            MaterialSymbol {
                visible: picker.fieldIcon.length > 0
                text: picker.fieldIcon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
            }

            IconImage {
                visible: picker.fieldIcon.length === 0 && picker.currentId.length > 0
                implicitSize: 22
                source: picker.currentId.length > 0 ? picker.iconFor(picker.currentId) : ""
            }

            StyledText {
                Layout.fillWidth: true
                text: picker.currentId.length > 0 ? picker.nameFor(picker.currentId) : picker.placeholderText
                color: picker.currentId.length > 0
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colSubtext
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            MaterialSymbol {
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSecondaryContainer
                rotation: popup.visible ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        MouseArea {
            id: fieldArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !picker.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: picker.openList()
        }
    }

    Popup {
        id: popup
        property bool dropUp: false
        property real listHeight: 340
        y: dropUp ? -(height + 4) : (field.height + 4)
        width: Math.max(field.width, 300)
        x: field.width - width
        height: listHeight
        padding: 8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: searchField.forceActiveFocus()

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
                placeholderText: Translation.tr("Search apps…")
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Working out which apps can do the job means reading every
                // desktop entry on the machine, which takes a moment the first
                // time a role is opened. Saying so beats an empty box.
                StyledText {
                    anchors.centerIn: parent
                    visible: !picker.candidatesLoaded && picker.offeredEntries.length === 0
                    text: Translation.tr("Looking for apps…")
                    color: Appearance.colors.colSubtext
                }

                StyledListView {
                    anchors.fill: parent
                    clip: true
                    animateAppearance: false
                    model: picker.offeredEntries

                    delegate: Rectangle {
                        id: option
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: 44
                        radius: Appearance.rounding.small
                        color: option.modelData.id === picker.currentId
                            ? Appearance.colors.colSecondaryContainer
                            : optionArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            IconImage {
                                implicitSize: 26
                                source: picker.iconFor(option.modelData.id)
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: option.modelData.name
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                            MaterialSymbol {
                                visible: option.modelData.id === picker.currentId
                                text: "check"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        MouseArea {
                            id: optionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popup.close();
                                picker.picked(option.modelData.id);
                            }
                        }
                    }
                }
            }

            ConfigSwitch {
                id: showAllSwitch
                visible: picker.roleKey.length > 0
                Layout.fillWidth: true
                text: Translation.tr("Show every app")
                checked: false
            }
        }
    }
}
