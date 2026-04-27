import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")

        // Mainstream branding is inlined here rather than overlaying
        // /etc/os-release so the About panel renders the same info on any
        // distro without an installer step. SystemInfo stays generic so
        // anything else keyed off os-release (package managers, tools that
        // read ID/ID_LIKE) keeps working.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath("mainstream-logo")
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    // Two literal backslashes are part of the brand name.
                    text: "Mainstream OS\\\\"
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: "https://mainstreamos.org/"
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://mainstreamos.org/docs")
            }
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Issues")
                onClicked: Qt.openUrlExternally("https://github.com/MainstreamOS/dots-hyprland/issues")
            }
            RippleButtonWithIcon {
                materialIcon: "forum"
                mainText: Translation.tr("Discussions")
                onClicked: Qt.openUrlExternally("https://github.com/MainstreamOS/discussions")
            }
            RippleButtonWithIcon {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: Qt.openUrlExternally("https://mainstreamos.org/privacy")
            }
            RippleButtonWithIcon {
                materialIcon: "favorite"
                mainText: Translation.tr("Donate")
                onClicked: Qt.openUrlExternally("https://mainstreamos.org/donate")
            }
        }

    }
    ContentSection {
        Layout.topMargin: 40
        icon: "fork_right"
        title: Translation.tr("Forked Projects")

        RowLayout {
            Layout.fillWidth: true
            spacing: 60
            Layout.topMargin: 10
            Layout.bottomMargin: 10

            // illogical-impulse (left). Wrapped in an Item that splits the
            // row evenly; the inner Column is anchor-centered so the icon,
            // name, subtitle and buttons all align on the column's vertical
            // axis instead of left-edge of a stretched ColumnLayout.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: leftCol.implicitHeight
                ColumnLayout {
                    id: leftCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 80
                        sourceSize.width: 80
                        sourceSize.height: 80
                        fillMode: Image.PreserveAspectFit
                        source: `${Directories.home}/.local/share/icons/illogical-impulse.svg`
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("illogical-impulse")
                        font.pixelSize: Appearance.font.pixelSize.title
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Dotfiles")
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        RippleButtonWithIcon {
                            materialIcon: "code"
                            mainText: Translation.tr("Original Project")
                            onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
                        }
                        RippleButtonWithIcon {
                            materialIcon: "favorite"
                            mainText: Translation.tr("Donate")
                            onClicked: Qt.openUrlExternally("https://github.com/sponsors/end-4")
                        }
                    }
                }
            }

            // xCaptaiN09 (right)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: rightCol.implicitHeight
                ColumnLayout {
                    id: rightCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 80
                        sourceSize.width: 80
                        sourceSize.height: 80
                        fillMode: Image.PreserveAspectFit
                        source: `${Directories.home}/.local/share/icons/xcaptain09.png`
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: "xCaptaiN09"
                        font.pixelSize: Appearance.font.pixelSize.title
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: "Pixie - SDDM Theme"
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignHCenter
                        materialIcon: "code"
                        mainText: Translation.tr("Original Project")
                        onClicked: Qt.openUrlExternally("https://github.com/xCaptaiN09/pixie-sddm")
                    }
                }
            }
        }
    }
}
