import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    // Avatar cropped to a circle at a fixed size so every card in the
    // credits grid renders uniformly regardless of source image shape.
    component CircleAvatar: Image {
        id: avatar
        property real size: 80
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: size
        Layout.preferredHeight: size
        sourceSize.width: size
        sourceSize.height: size
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: avatar.size
                height: avatar.size
                radius: Appearance.rounding.full
            }
        }
    }

    component ForkCard: Item {
        id: forkCard
        property string image
        property string name
        property string subtitle
        property string link
        property string donateLink: ""
        Layout.fillWidth: true
        Layout.preferredHeight: forkCardColumn.implicitHeight
        ColumnLayout {
            id: forkCardColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            CircleAvatar {
                source: forkCard.image
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: forkCard.name
                font.pixelSize: Appearance.font.pixelSize.title
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: forkCard.subtitle
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "code"
                    mainText: Translation.tr("Original Project")
                    onClicked: Qt.openUrlExternally(forkCard.link)
                }
                RippleButtonWithIcon {
                    visible: forkCard.donateLink !== ""
                    materialIcon: "favorite"
                    mainText: Translation.tr("Donate")
                    onClicked: Qt.openUrlExternally(forkCard.donateLink)
                }
            }
        }
    }

    component BuiltWithCard: Item {
        id: builtWithCard
        property string image
        property string name
        property string link
        Layout.fillWidth: true
        Layout.preferredHeight: builtWithColumn.implicitHeight
        ColumnLayout {
            id: builtWithColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            CircleAvatar {
                size: 48
                source: builtWithCard.image
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: builtWithCard.name
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }
        MouseArea {
            anchors.fill: builtWithColumn
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(builtWithCard.link)
        }
    }

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
                onClicked: Qt.openUrlExternally("https://github.com/MainstreamOS/dots-hyprland/discussions")
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
                onClicked: Qt.openUrlExternally("https://github.com/sponsors/MainstreamOS")
            }
        }

    }
    ContentSection {
        Layout.topMargin: 40
        icon: "fork_right"
        title: Translation.tr("Forked Projects")

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 30
            rowSpacing: 30
            Layout.topMargin: 10
            Layout.bottomMargin: 10

            ForkCard {
                image: `${Directories.home}/.local/share/icons/illogical-impulse.svg`
                name: Translation.tr("illogical-impulse")
                subtitle: Translation.tr("end-4 — Dotfiles")
                link: "https://github.com/end-4/dots-hyprland"
                donateLink: "https://github.com/sponsors/end-4"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-outfoxxed.png`
                name: "Quickshell"
                subtitle: Translation.tr("outfoxxed — Shell framework")
                link: "https://git.outfoxxed.me/quickshell/quickshell"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-yayuuu.png`
                name: Translation.tr("Scroll Overview")
                subtitle: Translation.tr("yayuuu — Hyprland plugin")
                link: "https://github.com/yayuuu/hyprland-scroll-overview"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-calamares.png`
                name: "Calamares"
                subtitle: Translation.tr("Calamares Team — Installer")
                link: "https://calamares.io"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-ful1e5.png`
                name: "Bibata Cursor"
                subtitle: Translation.tr("ful1e5 — Cursor theme")
                link: "https://github.com/ful1e5/Bibata_Cursor"
                donateLink: "https://github.com/sponsors/ful1e5"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/xcaptain09.png`
                name: "xCaptaiN09"
                subtitle: "Pixie - SDDM Theme"
                link: "https://github.com/xCaptaiN09/pixie-sddm"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-bluemancz.png`
                name: "hyprmod"
                subtitle: Translation.tr("BlueManCZ — Keybinds Settings")
                link: "https://github.com/BlueManCZ/hyprmod"
            }
            ForkCard {
                image: `${Directories.home}/.local/share/icons/about-archlinux.png`
                name: "Arch Linux"
                subtitle: Translation.tr("Base distribution & archiso")
                link: "https://archlinux.org"
                donateLink: "https://github.com/sponsors/archlinux"
            }
        }
    }

    ContentSection {
        Layout.topMargin: 40
        icon: "construction"
        title: Translation.tr("Built With")

        RowLayout {
            Layout.fillWidth: true
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10

            BuiltWithCard {
                image: `${Directories.home}/.local/share/icons/about-hyprwm.png`
                name: "Hyprland"
                link: "https://hypr.land"
            }
            BuiltWithCard {
                image: `${Directories.home}/.local/share/icons/about-iniox.png`
                name: "Matugen"
                link: "https://github.com/InioX/matugen"
            }
            BuiltWithCard {
                image: `${Directories.home}/.local/share/icons/about-papirus.png`
                name: "Papirus"
                link: "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme"
            }
            BuiltWithCard {
                image: `${Directories.home}/.local/share/icons/about-zesko.png`
                name: Translation.tr("Limine tools")
                link: "https://gitlab.com/Zesko/limine-entry-tool"
            }
        }
    }
}
