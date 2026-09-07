import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background
import Quickshell.Io

ContentPage {
    id: backgroundRoot
    forceWidth: true

    // The rotation itself lives in the main shell, so asking for one now goes
    // over IPC rather than calling into this process's passive copy.
    Process { id: slideshowNextProc }

    ContentSection {
        icon: "transition_fade"
        title: Translation.tr("Wallpaper transition")

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                OptionalMaterialSymbol {
                    icon: "animation"
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 6
                    text: Translation.tr("How one wallpaper gives way to the next")
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            WallpaperTransitionPreview {
                Layout.fillWidth: true
                Layout.maximumHeight: 220
                effect: Config.options.background.wallpaperTransition
            }
            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: Config.options.background.wallpaperTransition
                onSelected: newValue => {
                    Config.options.background.wallpaperTransition = newValue;
                }
                options: TransitionEffects.options
            }
        }
    }

    ContentSection {
        icon: "gallery_thumbnail"
        title: Translation.tr("Slideshow")

        ConfigSwitch {
            buttonIcon: "slideshow"
            text: Translation.tr("Change the wallpaper automatically")
            checked: Config.options.background.slideshow.enable
            onCheckedChanged: {
                Config.options.background.slideshow.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Rotate through the wallpapers in the slideshow folder automatically")
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "shuffle"
                text: Translation.tr("Shuffle")
                checked: Config.options.background.slideshow.shuffle
                onCheckedChanged: {
                    Config.options.background.slideshow.shuffle = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Off, wallpapers follow the folder in name order.")
                }
            }
            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Recolor the desktop each time")
                checked: Config.options.background.slideshow.recolor
                onCheckedChanged: {
                    Config.options.background.slideshow.recolor = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Change the UI color for each new wallpaper.")
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Change every")
                suffix: Translation.tr(" min")
                value: Math.max(WallpaperSlideshow.minimumInterval, Config.options.background.slideshow.intervalMinutes)
                from: WallpaperSlideshow.minimumInterval
                to: 720
                stepSize: 5
                onValueChanged: {
                    Config.options.background.slideshow.intervalMinutes = value;
                }
            }
            // Holds the right half open at its own size so the spin box keeps
            // the left half, with the button sitting at its natural width
            // against the far edge rather than stretched across the gap.
            Item {
                Layout.fillWidth: true
                implicitHeight: showNextButton.implicitHeight

                RippleButtonWithIcon {
                    id: showNextButton
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.verticalCenter: parent.verticalCenter
                    materialIcon: "skip_next"
                    mainText: Translation.tr("Show next")
                    enabled: Config.options.background.slideshow.enable
                    onClicked: {
                        slideshowNextProc.command = ["qs", "-c", "ii", "ipc", "call", "slideshow", "next"]
                        slideshowNextProc.running = false
                        slideshowNextProc.running = true
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "sync_alt"
        title: Translation.tr("Wallpaper panning")

        ConfigSwitch {
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Vertical")
            checked: Config.options.background.parallax.vertical
            onCheckedChanged: {
                Config.options.background.parallax.vertical = checked;
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "counter_1"
                text: Translation.tr("Depends on workspace")
                checked: Config.options.background.parallax.enableWorkspace
                onCheckedChanged: {
                    Config.options.background.parallax.enableWorkspace = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "side_navigation"
                text: Translation.tr("Depends on sidebars")
                checked: Config.options.background.parallax.enableSidebar
                onCheckedChanged: {
                    Config.options.background.parallax.enableSidebar = checked;
                }
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Preferred wallpaper zoom (%)")
            value: Config.options.background.parallax.workspaceZoom * 100
            from: 10
            to: 200
            stepSize: 1
            onValueChanged: {
                Config.options.background.parallax.workspaceZoom = value / 100;
            }
        }
    }

    ContentSection {
        id: settingsClock
        icon: "clock_loader_40"
        title: Translation.tr("Widget: Clock")

        function stylePresent(styleName) {
            // A clock that is switched off is wearing no style, so the panels
            // that dress one go away with it.
            if (!Config.options.background.widgets.clock.enable) {
                return false;
            }
            if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                return true;
            }
            if (Config.options.background.widgets.clock.styleLocked === styleName) {
                return true;
            }
            return false;
        }

        readonly property bool digitalPresent: stylePresent("digital")
        readonly property bool cookiePresent: stylePresent("cookie")

        ConfigRow {
            Layout.fillWidth: true

            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.clock.enable
                onCheckedChanged: {
                    Config.options.background.widgets.clock.enable = checked;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                visible: Config.options.background.widgets.clock.enable
                currentValue: Config.options.background.widgets.clock.placementStrategy
                onSelected: newValue => {
                    Config.options.background.widgets.clock.placementStrategy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "lock_clock"
            visible: Config.options.background.widgets.clock.enable
            text: Translation.tr("Show only when locked")
            checked: Config.options.background.widgets.clock.showOnlyWhenLocked
            onCheckedChanged: {
                Config.options.background.widgets.clock.showOnlyWhenLocked = checked;
            }
        }

        ConfigRow {
            visible: Config.options.background.widgets.clock.enable
            ContentSubsection {
                visible: !Config.options.background.widgets.clock.showOnlyWhenLocked
                title: Translation.tr("Clock style")
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_on",
                            value: "pixel"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Clock style (locked)")
                Layout.fillWidth: false
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Digital"),
                            icon: "timer_10",
                            value: "digital"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Pixel"),
                            icon: "grid_on",
                            value: "pixel"
                        }
                    ]
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.digitalPresent
            title: Translation.tr("Digital clock settings")
            tooltip: Translation.tr("Font width and roundness settings are only available for some fonts like Google Sans Flex")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_distribute"
                    text: Translation.tr("Vertical")
                    checked: Config.options.background.widgets.clock.digital.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.vertical = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate time change")
                    checked: Config.options.background.widgets.clock.digital.animateChange
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.animateChange = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "date_range"
                    text: Translation.tr("Show date")
                    checked: Config.options.background.widgets.clock.digital.showDate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.showDate = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "activity_zone"
                    text: Translation.tr("Use adaptive alignment")
                    checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.adaptiveAlignment = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Aligns the date and quote to left, center or right depending on its position on the screen.")
                    }
                }
            }

            FontPicker {
                value: Config.options.background.widgets.clock.digital.font.family
                onFontSelected: family => {
                    Config.options.background.widgets.clock.digital.font.family = family;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font weight")
                value: Config.options.background.widgets.clock.digital.font.weight
                usePercentTooltip: false
                buttonIcon: "format_bold"
                from: 1
                to: 1000
                stopIndicatorValues: [350]
                onMoved: {
                    Config.options.background.widgets.clock.digital.font.weight = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.clock.digital.font.size
                usePercentTooltip: false
                buttonIcon: "format_size"
                from: 50
                to: 700
                stopIndicatorValues: [90]
                onMoved: {
                    Config.options.background.widgets.clock.digital.font.size = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font width")
                value: Config.options.background.widgets.clock.digital.font.width
                usePercentTooltip: false
                buttonIcon: "fit_width"
                from: 25
                to: 125
                stopIndicatorValues: [100]
                onMoved: {
                    Config.options.background.widgets.clock.digital.font.width = value;
                }
            }
            ConfigSlider {
                text: Translation.tr("Font roundness")
                value: Config.options.background.widgets.clock.digital.font.roundness
                usePercentTooltip: false
                buttonIcon: "line_curve"
                from: 0
                to: 100
                onMoved: {
                    Config.options.background.widgets.clock.digital.font.roundness = value;
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Cookie clock settings")

            ConfigSwitch {
                buttonIcon: "wand_stars"
                text: Translation.tr("Auto styling with Gemini")
                checked: Config.options.background.widgets.clock.cookie.aiStyling
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.aiStyling = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Uses Gemini to categorize the wallpaper then picks a preset based on it.\nYou'll need to set Gemini API key on the left sidebar first.\nImages are downscaled for performance, but just to be safe,\ndo not select wallpapers with sensitive information.")
                }
            }

            ConfigSwitch {
                buttonIcon: "airwave"
                text: Translation.tr("Use old sine wave cookie implementation")
                checked: Config.options.background.widgets.clock.cookie.useSineCookie
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Looks a bit softer and more consistent with different number of sides,\nbut has less impressive morphing")
                }
            }

            ConfigSpinBox {
                icon: "add_triangle"
                text: Translation.tr("Sides")
                value: Config.options.background.widgets.clock.cookie.sides
                from: 0
                to: 40
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock.cookie.sides = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
                checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Makes the clock always rotate. This is extremely expensive\n(expect 50% usage on Intel UHD Graphics) and thus impractical.")
                }
            }

            ConfigRow {

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                    buttonIcon: "brightness_7"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock.cookie.hourMarks
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.hourMarks;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.hourMarks = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can only be turned on using the 'Dots' or 'Full' dial style for aesthetic reasons")
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                    buttonIcon: "timer_10"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock.cookie.timeIndicators
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Can't be turned on when using 'Numbers' dial style for aesthetic reasons")
                    }
                }
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Dial style")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                    if (newValue !== "dots" && newValue !== "full") {
                        Config.options.background.widgets.clock.cookie.hourMarks = false;
                    }
                    if (newValue === "numbers") {
                        Config.options.background.widgets.clock.cookie.timeIndicators = false;
                    }
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "none"
                    },
                    {
                        displayName: Translation.tr("Dots"),
                        icon: "graph_6",
                        value: "dots"
                    },
                    {
                        displayName: Translation.tr("Full"),
                        icon: "history_toggle_off",
                        value: "full"
                    },
                    {
                        displayName: Translation.tr("Numbers"),
                        icon: "counter_1",
                        value: "numbers"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Hour hand")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Hollow"),
                        icon: "circle",
                        value: "hollow"
                    },
                    {
                        displayName: Translation.tr("Fill"),
                        icon: "eraser_size_5",
                        value: "fill"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Minute hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Thin"),
                        icon: "line_end",
                        value: "thin"
                    },
                    {
                        displayName: Translation.tr("Medium"),
                        icon: "eraser_size_2",
                        value: "medium"
                    },
                    {
                        displayName: Translation.tr("Bold"),
                        icon: "eraser_size_4",
                        value: "bold"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Second hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "radio",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Line"),
                        icon: "line_end",
                        value: "line"
                    },
                    {
                        displayName: Translation.tr("Dot"),
                        icon: "adjust",
                        value: "dot"
                    },
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.cookiePresent
            title: Translation.tr("Date style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                }
                options: [
                    {
                        displayName: "",
                        icon: "block",
                        value: "hide"
                    },
                    {
                        displayName: Translation.tr("Bubble"),
                        icon: "bubble_chart",
                        value: "bubble"
                    },
                    {
                        displayName: Translation.tr("Border"),
                        icon: "rotate_right",
                        value: "border"
                    },
                    {
                        displayName: Translation.tr("Rect"),
                        icon: "rectangle",
                        value: "rect"
                    }
                ]
            }
        }

        ContentSubsection {
            visible: settingsClock.stylePresent("pixel")
            title: Translation.tr("Pixel clock settings")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.pixel.orientation
                onSelected: newValue => {
                    Config.options.background.widgets.clock.pixel.orientation = newValue;
                }
                options: [
                    { displayName: Translation.tr("Vertical"),   icon: "swap_vert",  value: "vertical" },
                    { displayName: Translation.tr("Horizontal"), icon: "swap_horiz", value: "horizontal" }
                ]
            }
        }

        ContentSubsection {
            visible: Config.options.background.widgets.clock.enable
            title: Translation.tr("Quote")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.background.widgets.clock.quote.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.quote.enable = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "font_download"
                    text: Translation.tr("Use the clock's font")
                    checked: Config.options.background.widgets.clock.quote.followClock
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.quote.followClock = checked;
                    }
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Quote")
                text: Config.options.background.widgets.clock.quote.text
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.background.widgets.clock.quote.text = text;
                }
            }
        }
    }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Widget: Weather")

        ConfigRow {
            Layout.fillWidth: true

            ConfigSwitch {
                Layout.fillWidth: false
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.background.widgets.weather.enable
                onCheckedChanged: {
                    Config.options.background.widgets.weather.enable = checked;
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.background.widgets.weather.placementStrategy
                onSelected: newValue => {
                    Config.options.background.widgets.weather.placementStrategy = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Draggable"),
                        icon: "drag_pan",
                        value: "free"
                    },
                    {
                        displayName: Translation.tr("Least busy"),
                        icon: "category",
                        value: "leastBusy"
                    },
                    {
                        displayName: Translation.tr("Most busy"),
                        icon: "shapes",
                        value: "mostBusy"
                    },
                ]
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("More widgets")

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: {
                Config.options.background.widgetsLocked = checked;
            }
            StyledToolTip {
                text: Translation.tr("Draggable widgets stay where they are, and their resize handles hide.")
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            columns: 3
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: [
                    { key: "media",       icon: "music_note",     name: Translation.tr("Media player") },
                    { key: "calendar",    icon: "calendar_month", name: Translation.tr("Calendar") },
                    { key: "worldClock",  icon: "public",         name: Translation.tr("World clock") },
                    { key: "notes",       icon: "note_stack_add", name: Translation.tr("Notes") },
                    { key: "todo",        icon: "add_task",       name: Translation.tr("To do") },
                    { key: "timers",      icon: "timer",          name: Translation.tr("Timers") },
                    { key: "resources",   icon: "memory",         name: Translation.tr("Resources") },
                    { key: "visualizer",  icon: "graphic_eq",     name: Translation.tr("Visualizer") },
                    { key: "customImage", icon: "image",          name: Translation.tr("Picture") }
                ]
                delegate: Rectangle {
                    id: widgetCard
                    required property var modelData
                    readonly property bool on: Config.options.background.widgets[modelData.key].enable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    ColumnLayout {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            margins: 12
                        }
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            MaterialSymbol {
                                text: widgetCard.modelData.icon
                                iconSize: Appearance.font.pixelSize.normal + 5
                                color: Appearance.colors.colPrimary
                            }
                            Item { Layout.fillWidth: true }
                            ConfigSwitch {
                                Layout.fillWidth: false
                                checked: widgetCard.on
                                onCheckedChanged: {
                                    Config.options.background.widgets[widgetCard.modelData.key].enable = checked;
                                }
                            }
                        }
                        StyledText {
                            text: widgetCard.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: widgetCard.on ? Translation.tr("On") : Translation.tr("Off")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        ContentSubsection {
            visible: Config.options.background.widgets.customImage.enable
            title: Translation.tr("Picture")
            ConfigSpinBox {
                icon: "photo_size_select_large"
                text: Translation.tr("Size")
                value: Config.options.background.widgets.customImage.size
                from: 80
                to: 800
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.customImage.size = value;
                }
            }
            ConfigSelectionShapeArray {
                currentValue: Config.options.background.widgets.customImage.shape
                shapeColor: Appearance.colors.colPrimary
                backgroundColor: Appearance.colors.colPrimaryContainer
                options: [
                    "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
                    "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
                    "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
                    "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
                    "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
                ]
                onSelected: newValue => {
                    Config.options.background.widgets.customImage.shape = newValue;
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: Translation.tr("Drop an image onto the widget to set the picture.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        ContentSubsection {
            visible: Config.options.background.widgets.worldClock.enable
            title: Translation.tr("World clock")
            ConfigSpinBox {
                icon: "schedule"
                text: Translation.tr("Clocks")
                value: Config.options.background.widgets.worldClock.clockCount
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.worldClock.clockCount = value;
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: Translation.tr("Pick each city on the widget itself.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }
        }

        ContentSubsection {
            visible: Config.options.background.widgets.resources.enable || Config.options.background.widgets.timers.enable
            title: Translation.tr("Layout")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    visible: Config.options.background.widgets.resources.enable
                    buttonIcon: "memory"
                    text: Translation.tr("Resources stacked vertically")
                    checked: Config.options.background.widgets.resources.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.resources.vertical = checked;
                    }
                }
                ConfigSwitch {
                    visible: Config.options.background.widgets.timers.enable
                    buttonIcon: "timer"
                    text: Translation.tr("Timers stacked vertically")
                    checked: Config.options.background.widgets.timers.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.timers.vertical = checked;
                    }
                }
            }
        }
    }
}
