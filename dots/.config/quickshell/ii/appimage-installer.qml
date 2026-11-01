//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

// Opened on a double-clicked AppImage, by way of the shell's "appimage" IPC target.
// scripts/appimage/appimage.py does the work; Uninstall Apps removes what this installs.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ApplicationWindow {
    id: root
    visible: true
    width: 520
    height: 420
    minimumWidth: 520
    minimumHeight: 420
    maximumWidth: 520
    maximumHeight: 420
    color: Appearance.m3colors.m3background
    title: Translation.tr("Install AppImage")

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/appimage/appimage.py`
    readonly property string file: Quickshell.env("MAINSTREAM_APPIMAGE") || ""
    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    property var info: null
    property string folder: ""
    property string error: ""
    property bool installing: false
    property var installed: null

    readonly property bool alreadyInstalled: !!root.info && root.info.installedPath.length > 0

    function shortPath(path) {
        return path.startsWith(root.homePath) ? "~" + path.slice(root.homePath.length) : path;
    }

    function formatSize(bytes) {
        return bytes < 1073741824
            ? Translation.tr("%1 MB").arg(Math.max(1, Math.round(bytes / 1048576)))
            : Translation.tr("%1 GB").arg((bytes / 1073741824).toFixed(1));
    }

    function install() {
        root.error = "";
        root.installing = true;
        installer.command = [root.script, "install", root.file, "--dir", root.folder];
        installer.running = true;
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme();
        if (root.file.length === 0) {
            root.error = Translation.tr("No AppImage was given to install.");
            return;
        }
        inspector.command = [root.script, "inspect", root.file];
        inspector.running = true;
    }

    Process {
        id: inspector
        stdout: StdioCollector {
            id: inspectOutput
        }
        stderr: StdioCollector {
            id: inspectErrors
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.error = inspectErrors.text.trim() || Translation.tr("This file couldn't be read.");
                return;
            }
            root.info = JSON.parse(inspectOutput.text);
            // An update stays where the app already lives.
            root.folder = root.alreadyInstalled ? FileUtils.parentDirectory(root.info.installedPath) : root.info.defaultFolder;
        }
    }

    Process {
        id: installer
        stdout: StdioCollector {
            id: installOutput
        }
        stderr: StdioCollector {
            id: installErrors
        }
        onExited: exitCode => {
            root.installing = false;
            if (exitCode !== 0) {
                root.error = installErrors.text.trim() || Translation.tr("The AppImage couldn't be installed.");
                return;
            }
            root.installed = JSON.parse(installOutput.text);
        }
    }

    Process {
        id: folderPicker
        command: ["zenity", "--file-selection", "--directory", "--title", Translation.tr("Choose where to install"), `--filename=${root.folder}/`]
        stdout: StdioCollector {
            id: folderOutput
        }
        onExited: exitCode => {
            if (exitCode === 0 && folderOutput.text.trim().length > 0)
                root.folder = folderOutput.text.trim();
        }
    }

    component DialogAction: RippleButton {
        id: action
        property string label
        property bool primary: false
        implicitWidth: Math.max(110, actionText.implicitWidth + 32)
        implicitHeight: 36
        buttonRadius: Appearance.rounding.small
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        contentItem: Item {
            StyledText {
                id: actionText
                anchors.centerIn: parent
                text: action.label
                color: action.primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                implicitWidth: 72
                implicitHeight: 72
                Image {
                    id: appIcon
                    anchors.fill: parent
                    source: root.info && root.info.icon.length > 0 ? FileUtils.fileUrl(root.info.icon) : ""
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: "deployed_code"
                    iconSize: 56
                    color: Appearance.colors.colSubtext
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.info?.name ?? FileUtils.fileNameForPath(root.file)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.title
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !!root.info
                    text: [root.info?.version ? Translation.tr("Version %1").arg(root.info.version) : "",
                        root.info ? root.formatSize(root.info.size) : ""].filter(part => part.length > 0).join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: (root.info?.comment ?? "").length > 0
                    text: root.info?.comment ?? ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Before installing: where it goes.
        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.info && !root.installed
            spacing: 8

            StyledText {
                text: Translation.tr("Install to")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 10
                    MaterialSymbol {
                        text: "folder"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.shortPath(root.folder)
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colOnLayer1
                    }
                    DialogAction {
                        implicitWidth: 90
                        implicitHeight: 34
                        label: Translation.tr("Change")
                        enabled: !root.installing && !folderPicker.running
                        onClicked: folderPicker.running = true
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.alreadyInstalled
                    ? Translation.tr("This app is already installed. Installing replaces the copy you have.")
                    : Translation.tr("The file moves here and the app appears in your launcher. You can remove it later from Uninstall Apps.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("AppImages don't come from Mainstream's software sources, so only install ones you trust.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // After installing: where it went.
        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.installed
            spacing: 8
            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "check_circle"
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("Installed")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 is in your launcher now.").arg(root.installed?.name ?? "")
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: root.shortPath(root.installed?.path ?? "")
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error.length > 0
            text: root.error
            wrapMode: Text.Wrap
            color: Appearance.m3colors.m3error
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: root.installing || inspector.running
            }
            Item {
                Layout.fillWidth: true
                visible: !root.installing && !inspector.running
            }
            DialogAction {
                label: root.installed ? Translation.tr("Done") : Translation.tr("Cancel")
                enabled: !root.installing
                onClicked: root.close()
            }
            DialogAction {
                visible: !root.installed
                primary: true
                label: root.alreadyInstalled ? Translation.tr("Reinstall") : Translation.tr("Install")
                enabled: !!root.info && !root.installing && !folderPicker.running
                onClicked: root.install()
            }
            DialogAction {
                visible: !!root.installed
                primary: true
                label: Translation.tr("Open")
                onClicked: {
                    Quickshell.execDetached(["env", "DESKTOPINTEGRATION=1", root.installed.path]);
                    root.close();
                }
            }
        }
    }

    // Closing hides the window at once, and the process goes once an install under way is done.
    onClosing: quitWhenIdle.request()
    QuitWhenIdle {
        id: quitWhenIdle
    }
}
