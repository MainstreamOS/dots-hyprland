import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window

// HDR Calibration Wizard
// Opened fullscreen by DisplayConfig when the user clicks "Calibrate Monitor for HDR".
// Exposes seven writable properties (one per Hyprland HDR luminance setting) and emits
// done(values) with the final object when the user clicks Apply, or cancelled() if they
// exit early.  The caller (DisplayConfig) writes the returned values into pendingChanges.

Window {
    id: root

    // ── Public API ─────────────────────────────────────────────────────────
    property string monitorName: ""

    property real valMaxLuminance:    600
    property real valMaxAvgLuminance: 400
    property real valMinLuminance:    0
    property real valSdrMaxLuminance: 250
    property real valSdrMinLuminance: 0.005
    property real valSdrBrightness:   1.0
    property real valSdrSaturation:   1.0

    // When true, SDR calibration steps are skipped (HDR Mode = Fullscreen Only)
    property bool fullscreenOnly: false

    // Previous values (set by caller) — used to show comparison on review page
    property var previousValues: null

    signal done(var values)
    signal cancelled()

    // Quick presets — pre-fill all values from a known panel type
    readonly property var presets: [
        { label: "OLED / QD-OLED",  icon: "✦", desc: "True black, high peak",
          v: { maxLuminance: 1000, maxAvgLuminance: 600, minLuminance: 0,
               sdrMaxLuminance: 280, sdrMinLuminance: 0.003, sdrBrightness: 1.0, sdrSaturation: 1.0 }},
        { label: "LCD HDR 600",     icon: "◧", desc: "Mid-range HDR LCD",
          v: { maxLuminance: 600, maxAvgLuminance: 400, minLuminance: 0.05,
               sdrMaxLuminance: 250, sdrMinLuminance: 0.008, sdrBrightness: 1.0, sdrSaturation: 1.0 }},
        { label: "LCD HDR 1000",    icon: "◨", desc: "High-end HDR LCD",
          v: { maxLuminance: 1000, maxAvgLuminance: 600, minLuminance: 0.03,
               sdrMaxLuminance: 300, sdrMinLuminance: 0.005, sdrBrightness: 1.0, sdrSaturation: 1.0 }},
        { label: "Custom",          icon: "◇", desc: "Start from current values",
          v: null },
    ]

    function loadPreset(preset) {
        if (preset.v) {
            root.valMaxLuminance    = preset.v.maxLuminance;
            root.valMaxAvgLuminance = preset.v.maxAvgLuminance;
            root.valMinLuminance    = preset.v.minLuminance;
            if (!root.fullscreenOnly) {
                root.valSdrMaxLuminance = preset.v.sdrMaxLuminance;
                root.valSdrMinLuminance = preset.v.sdrMinLuminance;
                root.valSdrBrightness   = preset.v.sdrBrightness;
                root.valSdrSaturation   = preset.v.sdrSaturation;
            }
        }
        root.currentStep = 1;  // Advance past intro
    }

    // ── Window setup ───────────────────────────────────────────────────────
    title: "HDR Calibration — " + root.monitorName
    color: "#000000"
    // Caller uses showFullScreen(); this is the fallback visibility
    minimumWidth:  900
    minimumHeight: 600

    // ── Step definitions ───────────────────────────────────────────────────
    // propName must match the val* property names on root exactly.
    readonly property var steps: [
        {
            stepType: "intro",
        },
        {
            stepType:    "slider",
            patternType: "peak",
            title:       "Peak Brightness",
            setting:     "max_luminance",
            hint:        "Set this to your display's rated peak brightness in nits.\n\nThe small centre patch represents a brief HDR highlight — on a real HDR display it would be blindingly bright. Look up your monitor's Peak Luminance specification (often listed as HDR400 / HDR600 / HDR1000 / HDR1400).\n\nThe reference bar at the bottom shows common display tiers.",
            propName:    "valMaxLuminance",
            minVal: 100, maxVal: 2000, sliderStep: 10, decimals: 0, unit: " nits",
            recMin: 400, recMax: 1400,
        },
        {
            stepType:    "slider",
            patternType: "avg",
            title:       "Sustained Brightness",
            setting:     "max_avg_luminance",
            hint:        "Monitors reduce brightness when large bright areas are displayed for extended periods (ABL / APL limiting). Set this to 60–70 % of your peak brightness.\n\nThe large patch simulates a bright scene. Typical values: 300–600 nits.",
            propName:    "valMaxAvgLuminance",
            minVal: 100, maxVal: 1600, sliderStep: 10, decimals: 0, unit: " nits",
            recMin: 300, recMax: 600,
        },
        {
            stepType:    "slider",
            patternType: "blackFloor",
            title:       "Black Floor",
            setting:     "min_luminance",
            hint:        "The absolute minimum brightness your panel can produce. OLED and QD-OLED panels can reach true 0; LCD panels typically fall between 0.02 and 0.1 nits.\n\nIncrease until the second-lightest shadow bar is just barely visible. Leave at 0 for OLED/QD-OLED.",
            propName:    "valMinLuminance",
            minVal: 0, maxVal: 0.5, sliderStep: 0.001, decimals: 3, unit: " nits",
            recMin: 0, recMax: 0.1,
        },
        {
            stepType:    "slider",
            patternType: "sdrWhite",
            title:       "SDR Paper White",
            setting:     "sdr_max_luminance",
            hint:        "The brightness of 100 % white in SDR applications (the 'paper white' reference). The broadcast standard is 203 nits; a comfortable desktop value is 250–350 nits.\n\nRaise if SDR windows look too dim next to HDR content. Lower if SDR feels too harsh.",
            propName:    "valSdrMaxLuminance",
            minVal: 80, maxVal: 1000, sliderStep: 5, decimals: 0, unit: " nits",
            recMin: 203, recMax: 350,
        },
        {
            stepType:    "slider",
            patternType: "sdrBlack",
            title:       "SDR Shadow Detail",
            setting:     "sdr_min_luminance",
            hint:        "Lifts the black floor for SDR content only, recovering shadow detail that can be crushed during the SDR→HDR conversion. Values of 0.003–0.01 suit most displays.\n\nIncrease until the checkerboard texture in the dark area becomes just visible.",
            propName:    "valSdrMinLuminance",
            minVal: 0, maxVal: 0.1, sliderStep: 0.001, decimals: 3, unit: " nits",
            recMin: 0.003, recMax: 0.01,
        },
        {
            stepType:    "slider",
            patternType: "brightness",
            title:       "SDR Brightness",
            setting:     "sdrbrightness",
            hint:        "Scales the overall brightness of SDR content in HDR mode. 1.0 is the reference level; increase if SDR applications look dim compared to native HDR content.\n\nThe grey ramp updates in real time to show how all SDR tones shift.",
            propName:    "valSdrBrightness",
            minVal: 0.5, maxVal: 3.0, sliderStep: 0.05, decimals: 2, unit: "×",
            recMin: 0.9, recMax: 1.3,
        },
        {
            stepType:    "slider",
            patternType: "saturation",
            title:       "SDR Saturation",
            setting:     "sdrsaturation",
            hint:        "Adjusts the colour saturation of SDR content. 1.0 is accurate sRGB; increase slightly if SDR apps look desaturated next to HDR, or decrease if they look over-vivid.\n\nThe colour swatches update in real time.",
            propName:    "valSdrSaturation",
            minVal: 0.5, maxVal: 2.0, sliderStep: 0.05, decimals: 2, unit: "×",
            recMin: 0.9, recMax: 1.1,
        },
        {
            stepType: "review",
        },
    ]

    property int currentStep: 0
    readonly property var step: steps[currentStep]
    readonly property int lastStep: steps.length - 1

    // SDR steps should be skipped in fullscreen-only mode
    function isSdrStep(idx) {
        let s = steps[idx];
        return s && s.propName && s.propName.startsWith("valSdr");
    }
    function goNext() {
        let next = currentStep + 1;
        while (next < lastStep && fullscreenOnly && isSdrStep(next)) next++;
        currentStep = next;
    }
    function goBack() {
        let prev = currentStep - 1;
        while (prev > 0 && fullscreenOnly && isSdrStep(prev)) prev--;
        currentStep = prev;
    }

    // ── Value accessors (explicit switch — avoids dynamic [] property access) ──
    function currentValue() {
        switch (root.step ? root.step.propName : "") {
            case "valMaxLuminance":    return root.valMaxLuminance;
            case "valMaxAvgLuminance": return root.valMaxAvgLuminance;
            case "valMinLuminance":    return root.valMinLuminance;
            case "valSdrMaxLuminance": return root.valSdrMaxLuminance;
            case "valSdrMinLuminance": return root.valSdrMinLuminance;
            case "valSdrBrightness":   return root.valSdrBrightness;
            case "valSdrSaturation":   return root.valSdrSaturation;
            default: return 0;
        }
    }

    function setValue(v) {
        switch (root.step ? root.step.propName : "") {
            case "valMaxLuminance":    root.valMaxLuminance    = v; break;
            case "valMaxAvgLuminance": root.valMaxAvgLuminance = v; break;
            case "valMinLuminance":    root.valMinLuminance    = v; break;
            case "valSdrMaxLuminance": root.valSdrMaxLuminance = v; break;
            case "valSdrMinLuminance": root.valSdrMinLuminance = v; break;
            case "valSdrBrightness":   root.valSdrBrightness   = v; break;
            case "valSdrSaturation":   root.valSdrSaturation   = v; break;
        }
    }

    // Sync slider when step changes — Qt.callLater ensures from/to are set first
    onCurrentStepChanged: Qt.callLater(function() {
        stepSlider.value = root.currentValue();
    })
    Component.onCompleted: stepSlider.value = root.currentValue()

    // ── Root layout ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Top bar ────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: 52

                RowLayout {
                    anchors { fill: parent; leftMargin: 28; rightMargin: 28 }
                    spacing: 6

                    // Progress dots
                    Repeater {
                        model: root.steps.length
                        delegate: Rectangle {
                            required property int index
                            visible: !(root.fullscreenOnly && root.isSdrStep(index))
                            implicitHeight: 5
                            implicitWidth: index === root.currentStep ? 24 : 5
                            radius: 3
                            color: index === root.currentStep
                                ? "#ffffff"
                                : (index < root.currentStep ? "#555555" : "#222222")
                            Behavior on implicitWidth { NumberAnimation { duration: 180 } }
                            Behavior on color         { ColorAnimation  { duration: 180 } }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Monitor badge
                    Text {
                        text: root.monitorName
                        color: "#444444"
                        font.pixelSize: 12
                        font.family: "monospace"
                    }

                    Item { implicitWidth: 12 }

                    // Cancel
                    MouseArea {
                        id: cancelArea
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        implicitWidth: cancelRect.implicitWidth
                        implicitHeight: cancelRect.implicitHeight
                        onClicked: root.cancelled()

                        Rectangle {
                            id: cancelRect
                            anchors.fill: parent
                            implicitWidth: cancelTxt.implicitWidth + 28
                            implicitHeight: 32
                            radius: 5
                            color: cancelArea.containsMouse ? "#1c1c1c" : "transparent"
                            border.width: 1
                            border.color: cancelArea.containsMouse ? "#3a3a3a" : "#1e1e1e"
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text {
                                id: cancelTxt
                                anchors.centerIn: parent
                                text: "✕  Cancel"
                                color: "#666666"
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            // Thin separator
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#111111" }

            // ── Pattern / content area ─────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Intro ──────────────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.step && root.step.stepType === "intro"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 20
                        width: Math.min(parent.width * 0.55, 520)

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "◈"
                            font.pixelSize: 64
                            color: "#333333"
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "HDR Calibration"
                            color: "#ffffff"
                            font.pixelSize: 34
                            font.weight: Font.Light
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "This wizard guides you through calibrating the HDR luminance settings for\n\n    " + root.monitorName + "\n\nFor best results:\n\n  •  Dim the room — avoid bright light falling on the screen\n  •  Let the monitor warm up for 20–30 minutes\n  •  Disable auto-brightness and ambient light sensors"
                            color: "#666666"
                            font.pixelSize: 14
                            lineHeight: 1.65
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignLeft
                        }

                        Text {
                            Layout.topMargin: 8
                            text: "Choose a starting preset, then fine-tune each value:"
                            color: "#555555"
                            font.pixelSize: 13
                        }

                        // Preset grid
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 10

                            Repeater {
                                model: root.presets
                                delegate: MouseArea {
                                    required property var modelData
                                    required property int index
                                    id: presetArea
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    Layout.fillWidth: true
                                    implicitHeight: presetRect.implicitHeight
                                    onClicked: root.loadPreset(modelData)

                                    Rectangle {
                                        id: presetRect
                                        anchors.fill: parent
                                        implicitHeight: presetCol.implicitHeight + 20
                                        radius: 8
                                        color: presetArea.containsMouse ? "#1a1a1a" : "#0e0e0e"
                                        border.width: 1
                                        border.color: presetArea.containsMouse ? "#3a3a3a" : "#1e1e1e"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                        ColumnLayout {
                                            id: presetCol
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                                            spacing: 4
                                            RowLayout {
                                                spacing: 8
                                                Text {
                                                    text: presetArea.modelData.icon
                                                    color: "#ffffff"
                                                    font.pixelSize: 16
                                                }
                                                Text {
                                                    text: presetArea.modelData.label
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.weight: Font.Medium
                                                }
                                            }
                                            Text {
                                                text: presetArea.modelData.desc
                                                color: "#555555"
                                                font.pixelSize: 12
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Review ─────────────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: root.step && root.step.stepType === "review"

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        width: Math.min(parent.width * 0.55, root.previousValues !== null ? 560 : 440)

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: 28
                            text: "Review Settings"
                            color: "#ffffff"
                            font.pixelSize: 26
                            font.weight: Font.Light
                        }

                        // Column headers (only when previous values exist)
                        RowLayout {
                            visible: root.previousValues !== null
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            anchors { leftMargin: 12; rightMargin: 12 }
                            Text { text: "setting"; color: "#333333"; font.pixelSize: 11; font.family: "monospace"; Layout.fillWidth: true }
                            Text { text: "previous"; color: "#333333"; font.pixelSize: 11; font.family: "monospace"; horizontalAlignment: Text.AlignRight; Layout.minimumWidth: 80 }
                            Text { text: "→"; color: "#222222"; font.pixelSize: 11; Layout.minimumWidth: 20; horizontalAlignment: Text.AlignHCenter }
                            Text { text: "new"; color: "#333333"; font.pixelSize: 11; font.family: "monospace"; horizontalAlignment: Text.AlignRight; Layout.minimumWidth: 80 }
                        }

                        // Value rows
                        Repeater {
                            model: {
                                let prev = root.previousValues;
                                let rows = [
                                    { lbl: "max_luminance",     val: root.valMaxLuminance.toFixed(0)    + " nits", prev: prev ? prev.maxLuminance.toFixed(0)    + " nits" : "" },
                                    { lbl: "max_avg_luminance", val: root.valMaxAvgLuminance.toFixed(0) + " nits", prev: prev ? prev.maxAvgLuminance.toFixed(0) + " nits" : "" },
                                    { lbl: "min_luminance",     val: root.valMinLuminance.toFixed(3)    + " nits", prev: prev ? prev.minLuminance.toFixed(3)    + " nits" : "" },
                                ];
                                if (!root.fullscreenOnly) {
                                    rows.push(
                                        { lbl: "sdr_max_luminance", val: root.valSdrMaxLuminance.toFixed(0) + " nits", prev: prev ? prev.sdrMaxLuminance.toFixed(0) + " nits" : "" },
                                        { lbl: "sdr_min_luminance", val: root.valSdrMinLuminance.toFixed(3) + " nits", prev: prev ? prev.sdrMinLuminance.toFixed(3) + " nits" : "" },
                                        { lbl: "sdrbrightness",     val: root.valSdrBrightness.toFixed(2)   + "×",    prev: prev ? prev.sdrBrightness.toFixed(2)   + "×"    : "" },
                                        { lbl: "sdrsaturation",     val: root.valSdrSaturation.toFixed(2)   + "×",    prev: prev ? prev.sdrSaturation.toFixed(2)   + "×"    : "" },
                                    );
                                }
                                return rows;
                            }
                            delegate: Item {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 36

                                Rectangle {
                                    anchors.fill: parent
                                    color: index % 2 === 0 ? "#0a0a0a" : "transparent"
                                }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    Text {
                                        text: modelData.lbl
                                        color: "#555555"
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        Layout.fillWidth: true
                                    }
                                    // Previous value (dimmed)
                                    Text {
                                        visible: root.previousValues !== null
                                        text: modelData.prev
                                        color: modelData.prev !== modelData.val ? "#444444" : "#333333"
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        horizontalAlignment: Text.AlignRight
                                        Layout.minimumWidth: 80
                                    }
                                    Text {
                                        visible: root.previousValues !== null
                                        text: "→"
                                        color: modelData.prev !== modelData.val ? "#555555" : "#222222"
                                        font.pixelSize: 11
                                        Layout.minimumWidth: 20
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    // New value (bright if changed)
                                    Text {
                                        text: modelData.val
                                        color: (root.previousValues !== null && modelData.prev !== modelData.val) ? "#ffffff" : "#dddddd"
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        font.weight: (root.previousValues !== null && modelData.prev !== modelData.val) ? Font.Medium : Font.Normal
                                        horizontalAlignment: Text.AlignRight
                                        Layout.minimumWidth: 80
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.topMargin: 24
                            Layout.alignment: Qt.AlignHCenter
                            text: "Clicking Apply will save these values to monitors.conf\nand reload Hyprland immediately."
                            color: "#444444"
                            font.pixelSize: 12
                            lineHeight: 1.6
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // ── Test pattern canvas ────────────────────────────────────
                Canvas {
                    id: patternCanvas
                    anchors.fill: parent
                    visible: root.step && root.step.stepType === "slider"

                    property real liveValue: {
                        if (!root.step) return 0;
                        switch (root.step.propName) {
                            case "valMaxLuminance":    return root.valMaxLuminance;
                            case "valMaxAvgLuminance": return root.valMaxAvgLuminance;
                            case "valMinLuminance":    return root.valMinLuminance;
                            case "valSdrMaxLuminance": return root.valSdrMaxLuminance;
                            case "valSdrMinLuminance": return root.valSdrMinLuminance;
                            case "valSdrBrightness":   return root.valSdrBrightness;
                            case "valSdrSaturation":   return root.valSdrSaturation;
                            default: return 0;
                        }
                    }

                    property string patternType: root.step && root.step.patternType ? root.step.patternType : ""

                    onPatternTypeChanged: requestPaint()
                    onLiveValueChanged:   requestPaint()
                    onWidthChanged:       requestPaint()
                    onHeightChanged:      requestPaint()
                    onVisibleChanged:     if (visible) requestPaint()

                    onPaint: {
                        let ctx = getContext("2d");
                        let w = width, h = height;
                        ctx.clearRect(0, 0, w, h);
                        ctx.fillStyle = "#000000";
                        ctx.fillRect(0, 0, w, h);
                        let v = liveValue;
                        if      (patternType === "peak")       drawPeak(ctx, w, h, v);
                        else if (patternType === "avg")        drawAvg(ctx, w, h, v);
                        else if (patternType === "blackFloor") drawBlackFloor(ctx, w, h, v);
                        else if (patternType === "sdrWhite")   drawSdrWhite(ctx, w, h, v);
                        else if (patternType === "sdrBlack")   drawSdrBlack(ctx, w, h, v);
                        else if (patternType === "brightness") drawBrightness(ctx, w, h, v);
                        else if (patternType === "saturation") drawSaturation(ctx, w, h, v);
                    }

                    // ── Pattern: 10% window — peak brightness ──────────────
                    function drawPeak(ctx, w, h, nits) {
                        let side = Math.sqrt(w * h * 0.10);
                        let px = (w - side) / 2;
                        let py = (h - side) / 2 - 28;
                        ctx.fillStyle = "#ffffff";
                        ctx.fillRect(px, py, side, side);

                        // Tier reference strip
                        let stripW = w * 0.58;
                        let stripH = 6;
                        let stripX = (w - stripW) / 2;
                        let stripY = h - 96;
                        let grad = ctx.createLinearGradient(stripX, 0, stripX + stripW, 0);
                        grad.addColorStop(0,   "#111111");
                        grad.addColorStop(0.2, "#444444");
                        grad.addColorStop(0.5, "#aaaaaa");
                        grad.addColorStop(1,   "#ffffff");
                        ctx.fillStyle = grad;
                        ctx.fillRect(stripX, stripY, stripW, stripH);

                        let tiers = [{v:400,"l":"400"},{v:600,"l":"600"},{v:1000,"l":"1000"},{v:1400,"l":"1400"},{v:2000,"l":"2000"}];
                        for (let i = 0; i < tiers.length; i++) {
                            let tx = stripX + (tiers[i].v / 2000) * stripW;
                            ctx.fillStyle = "#222222";
                            ctx.fillRect(tx, stripY - 5, 1, stripH + 10);
                            ctx.fillStyle = "#444444";
                            ctx.font = "10px monospace";
                            ctx.textAlign = "center";
                            ctx.fillText(tiers[i].l, tx, stripY + stripH + 18);
                        }
                        // Current position needle
                        let needleX = stripX + Math.min(1, nits / 2000) * stripW;
                        ctx.fillStyle = "#ffffff";
                        ctx.fillRect(needleX - 1, stripY - 10, 2, stripH + 20);

                        ctx.fillStyle = "#444444";
                        ctx.font = "11px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("nits", stripX + stripW / 2, stripY + stripH + 34);

                        ctx.fillStyle = "#333333";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("10 % window  ·  " + nits.toFixed(0) + " nits", w / 2, py - 18);
                    }

                    // ── Pattern: 50% APL — sustained brightness ────────────
                    function drawAvg(ctx, w, h, nits) {
                        let areaW = w * 0.68;
                        let areaH = h * 0.52;
                        let areaX = (w - areaW) / 2;
                        let areaY = (h - areaH) / 2 - 20;
                        let brightness = 0.12 + Math.min(1, nits / 1200) * 0.83;
                        let c = Math.round(brightness * 255);
                        ctx.fillStyle = "rgb(" + c + "," + c + "," + c + ")";
                        ctx.fillRect(areaX, areaY, areaW, areaH);
                        ctx.fillStyle = "#2a2a2a";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("50 % APL  ·  " + nits.toFixed(0) + " nits", w / 2, areaY + areaH + 26);
                    }

                    // ── Pattern: PLUGE — black floor ───────────────────────
                    function drawBlackFloor(ctx, w, h, nits) {
                        // Fixed near-black levels shown as sRGB-space bars
                        let levels = [0, 0.003, 0.006, 0.012, 0.025, 0.05, 0.10, 0.18];
                        let count = levels.length;
                        let gap = 6;
                        let bw = (w * 0.72 - gap * (count - 1)) / count;
                        let bh = h * 0.48;
                        let startX = (w - (bw + gap) * count + gap) / 2;
                        let startY = (h - bh) / 2 - 14;

                        for (let i = 0; i < count; i++) {
                            let lum = levels[i];
                            // Gamma-expand for perceptual visibility on SDR canvas
                            let c = Math.round(Math.pow(lum, 1 / 2.2) * 255);
                            ctx.fillStyle = "rgb(" + c + "," + c + "," + c + ")";
                            ctx.fillRect(startX + i * (bw + gap), startY, bw, bh);

                            // Highlight the bar closest to the current min_luminance
                            if (Math.abs(lum - nits) === levels.reduce((prev, cur) =>
                                    Math.abs(cur - nits) < Math.abs(prev - nits) ? cur : prev, Infinity) - 0) {
                                // simple closest: skip complex reduce, just mark i===0 special
                            }
                            ctx.fillStyle = "#2a2a2a";
                            ctx.font = "10px monospace";
                            ctx.textAlign = "center";
                            ctx.fillText((lum * 100).toFixed(1) + "%", startX + i * (bw + gap) + bw / 2, startY + bh + 18);
                        }

                        // Needle line at current value position on the scale
                        let maxLevel = levels[levels.length - 1];
                        let barsTotalW = (bw + gap) * count - gap;
                        let needleX = startX + Math.min(1, nits / maxLevel) * barsTotalW;
                        ctx.strokeStyle = "#555555";
                        ctx.lineWidth = 1;
                        ctx.setLineDash([4, 4]);
                        ctx.beginPath();
                        ctx.moveTo(needleX, startY - 8);
                        ctx.lineTo(needleX, startY + bh + 8);
                        ctx.stroke();
                        ctx.setLineDash([]);

                        ctx.fillStyle = "#333333";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("Black floor  ·  " + nits.toFixed(3) + " nits — raise until lightest shadow bar becomes just visible", w / 2, startY - 22);
                    }

                    // ── Pattern: white reference — SDR paper white ─────────
                    function drawSdrWhite(ctx, w, h, nits) {
                        let bw = w * 0.34;
                        let bh = h * 0.48;
                        let bx = (w - bw) / 2;
                        let by = (h - bh) / 2 - 10;

                        // Reference at 203 nits = "broadcast white"
                        let refNits = 203;
                        let scaledBrightness = Math.min(1, nits / 400);
                        let c = Math.round(200 + scaledBrightness * 55);
                        ctx.fillStyle = "rgb(" + c + "," + c + "," + c + ")";
                        ctx.fillRect(bx, by, bw, bh);

                        ctx.fillStyle = c > 180 ? "#000000" : "#aaaaaa";
                        ctx.font = "bold 14px sans-serif";
                        ctx.textAlign = "center";
                        ctx.textBaseline = "middle";
                        ctx.fillText("SDR White", bx + bw / 2, by + bh / 2 - 12);
                        ctx.font = "12px monospace";
                        ctx.fillText(nits.toFixed(0) + " nits", bx + bw / 2, by + bh / 2 + 14);
                        ctx.textBaseline = "alphabetic";

                        // Reference marker
                        ctx.fillStyle = "#2a2a2a";
                        ctx.font = "11px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("← 203 nits (broadcast standard)    250–350 nits (desktop comfortable) →", w / 2, by + bh + 30);
                    }

                    // ── Pattern: near-black checkerboard — SDR shadow ──────
                    function drawSdrBlack(ctx, w, h, nits) {
                        let areaW = w * 0.68;
                        let areaH = h * 0.48;
                        let areaX = (w - areaW) / 2;
                        let areaY = (h - areaH) / 2 - 10;

                        // Dark background
                        ctx.fillStyle = "#050505";
                        ctx.fillRect(areaX, areaY, areaW, areaH);

                        // Checkerboard that emerges from black as sdrMinLuminance rises
                        let liftFrac = Math.min(1, nits / 0.08);
                        let liftBrightness = liftFrac * 0.10; // 0 → 10% gray
                        let c = Math.round(liftBrightness * 255);
                        let cell = 14;
                        for (let row = 0; row < areaH / cell; row++) {
                            for (let col = 0; col < areaW / cell; col++) {
                                if ((row + col) % 2 === 0) {
                                    ctx.fillStyle = "rgb(" + c + "," + c + "," + c + ")";
                                    ctx.fillRect(areaX + col * cell, areaY + row * cell, cell, cell);
                                }
                            }
                        }

                        ctx.fillStyle = "#282828";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("Shadow detail  ·  " + nits.toFixed(3) + " nits — raise until checkerboard becomes just visible", w / 2, areaY + areaH + 24);
                    }

                    // ── Pattern: grey ramp — SDR brightness ────────────────
                    function drawBrightness(ctx, w, h, mult) {
                        let steps = 11;
                        let sw = Math.floor(w * 0.72 / steps);
                        let sh = Math.round(h * 0.36);
                        let sx = Math.round((w - sw * steps) / 2);
                        let sy = Math.round((h - sh) / 2 - 10);

                        for (let i = 0; i < steps; i++) {
                            let base = i / (steps - 1);
                            let boosted = Math.min(1, base * mult);
                            let c = Math.round(boosted * 255);
                            ctx.fillStyle = "rgb(" + c + "," + c + "," + c + ")";
                            ctx.fillRect(sx + i * sw, sy, sw, sh);
                            ctx.fillStyle = "#303030";
                            ctx.font = "10px monospace";
                            ctx.textAlign = "center";
                            ctx.fillText(Math.round(base * 100) + "%", sx + i * sw + sw / 2, sy + sh + 18);
                        }

                        // Reference white marker
                        let refX = sx + sw * (steps - 1) + sw / 2;
                        ctx.strokeStyle = "#444444";
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(refX, sy - 20);
                        ctx.lineTo(refX, sy - 6);
                        ctx.stroke();
                        ctx.fillStyle = "#333333";
                        ctx.font = "10px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("ref white", refX, sy - 24);

                        ctx.fillStyle = "#303030";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("SDR brightness  ·  " + mult.toFixed(2) + "×", w / 2, sy - 36);
                    }

                    // ── Pattern: colour swatches — SDR saturation ──────────
                    function drawSaturation(ctx, w, h, sat) {
                        let hues = [0, 30, 60, 120, 180, 240, 270, 300];
                        let count = hues.length;
                        let sw = Math.floor(w * 0.72 / count);
                        let sh = Math.round(h * 0.4);
                        let sx = Math.round((w - sw * count) / 2);
                        let sy = Math.round((h - sh) / 2 - 10);
                        let satPct = Math.round(Math.min(100, sat * 85));

                        for (let i = 0; i < count; i++) {
                            ctx.fillStyle = "hsl(" + hues[i] + "," + satPct + "%,50%)";
                            ctx.fillRect(sx + i * sw, sy, sw, sh);
                        }

                        // Gray reference strip below
                        let gsh = 12;
                        ctx.fillStyle = "#808080";
                        ctx.fillRect(sx, sy + sh + 8, sw * count, gsh);
                        ctx.fillStyle = "#333333";
                        ctx.font = "10px monospace";
                        ctx.textAlign = "right";
                        ctx.fillText("neutral ref", sx - 6, sy + sh + gsh + 2);

                        ctx.fillStyle = "#303030";
                        ctx.font = "12px monospace";
                        ctx.textAlign = "center";
                        ctx.fillText("SDR saturation  ·  " + sat.toFixed(2) + "×  (effective: " + satPct + " %)", w / 2, sy - 20);
                    }
                }
            }

            // ── Control panel ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                color: "#0c0c0c"

                // Top edge separator
                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1
                    color: "#1a1a1a"
                }

                ColumnLayout {
                    id: controlPanelLayout
                    anchors {
                        top: parent.top; left: parent.left; right: parent.right
                        topMargin: 18; leftMargin: 32; rightMargin: 32; bottomMargin: 18
                    }
                    spacing: 10

                    // Step title
                    Text {
                        visible: root.step && root.step.title !== undefined
                        text: root.step && root.step.title ? root.step.title : ""
                        color: "#ffffff"
                        font.pixelSize: 19
                        font.weight: Font.Medium
                    }

                    // Hint / description (slider steps only)
                    Text {
                        visible: root.step && root.step.hint !== undefined
                        Layout.fillWidth: true
                        text: root.step && root.step.hint ? root.step.hint : ""
                        color: "#606060"
                        font.pixelSize: 13
                        lineHeight: 1.55
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                    }

                    // Slider row
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.step && root.step.stepType === "slider"
                        spacing: 14

                        // Setting key label
                        Text {
                            text: root.step && root.step.setting ? root.step.setting : ""
                            color: "#363636"
                            font.pixelSize: 12
                            font.family: "monospace"
                            Layout.minimumWidth: 140
                        }

                        Slider {
                            id: stepSlider
                            Layout.fillWidth: true
                            from:     root.step && root.step.minVal     !== undefined ? root.step.minVal     : 0
                            to:       root.step && root.step.maxVal     !== undefined ? root.step.maxVal     : 1
                            stepSize: root.step && root.step.sliderStep !== undefined ? root.step.sliderStep : 0.01
                            onMoved: root.setValue(value)

                            background: Rectangle {
                                x: stepSlider.leftPadding
                                y: stepSlider.topPadding + stepSlider.availableHeight / 2 - height / 2
                                width: stepSlider.availableWidth
                                height: 4
                                radius: 2
                                color: "#1e1e1e"

                                // Recommended range highlight
                                Rectangle {
                                    visible: root.step && root.step.recMin !== undefined
                                    property real rangeFrom: root.step ? (root.step.minVal ?? 0) : 0
                                    property real rangeTo:   root.step ? (root.step.maxVal ?? 1) : 1
                                    property real span: rangeTo - rangeFrom
                                    x: span > 0 ? ((root.step.recMin ?? 0) - rangeFrom) / span * parent.width : 0
                                    width: span > 0 ? ((root.step.recMax ?? 0) - (root.step.recMin ?? 0)) / span * parent.width : 0
                                    height: parent.height
                                    radius: 2
                                    color: "#1a2a1a"
                                }

                                Rectangle {
                                    width: stepSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: 2
                                    color: "#ffffff"
                                }
                            }
                            handle: Rectangle {
                                x: stepSlider.leftPadding + stepSlider.visualPosition * (stepSlider.availableWidth - width)
                                y: stepSlider.topPadding + stepSlider.availableHeight / 2 - height / 2
                                width: 18; height: 18; radius: 9
                                color: stepSlider.pressed ? "#cccccc" : "#ffffff"
                                Behavior on color { ColorAnimation { duration: 80 } }
                            }
                        }

                        // Numeric readout — reactive binding reads each val* directly
                        Text {
                            text: {
                                if (!root.step || root.step.stepType !== "slider") return "";
                                let dec = root.step.decimals !== undefined ? root.step.decimals : 0;
                                let unit = root.step.unit ?? "";
                                switch (root.step.propName) {
                                    case "valMaxLuminance":    return root.valMaxLuminance.toFixed(dec)    + unit;
                                    case "valMaxAvgLuminance": return root.valMaxAvgLuminance.toFixed(dec) + unit;
                                    case "valMinLuminance":    return root.valMinLuminance.toFixed(dec)    + unit;
                                    case "valSdrMaxLuminance": return root.valSdrMaxLuminance.toFixed(dec) + unit;
                                    case "valSdrMinLuminance": return root.valSdrMinLuminance.toFixed(dec) + unit;
                                    case "valSdrBrightness":   return root.valSdrBrightness.toFixed(dec)   + unit;
                                    case "valSdrSaturation":   return root.valSdrSaturation.toFixed(dec)   + unit;
                                    default: return "";
                                }
                            }
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                            Layout.minimumWidth: 88
                        }
                    }

                    // Recommended range label
                    Text {
                        visible: root.step && root.step.recMin !== undefined
                        text: {
                            if (!root.step || root.step.recMin === undefined) return "";
                            let dec = root.step.decimals ?? 0;
                            return "▪ Recommended range: " + root.step.recMin.toFixed(dec) + " – " + root.step.recMax.toFixed(dec) + (root.step.unit ?? "");
                        }
                        color: "#2a5a2a"
                        font.pixelSize: 11
                    }

                    // Navigation row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 10

                        // Back
                        MouseArea {
                            visible: root.currentStep > 0
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            implicitWidth: backRect.implicitWidth
                            implicitHeight: backRect.implicitHeight
                            onClicked: root.goBack()

                            Rectangle {
                                id: backRect
                                anchors.fill: parent
                                implicitWidth: backTxt.implicitWidth + 32
                                implicitHeight: 38
                                radius: 5
                                color: parent.containsMouse ? "#1a1a1a" : "transparent"
                                border.width: 1
                                border.color: "#2c2c2c"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: backTxt
                                    anchors.centerIn: parent
                                    text: "← Back"
                                    color: "#666666"
                                    font.pixelSize: 14
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Skip (slider steps only)
                        MouseArea {
                            visible: root.step && root.step.stepType === "slider"
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            implicitWidth: skipRect.implicitWidth
                            implicitHeight: skipRect.implicitHeight
                            onClicked: root.goNext()

                            Rectangle {
                                id: skipRect
                                anchors.fill: parent
                                implicitWidth: skipTxt.implicitWidth + 32
                                implicitHeight: 38
                                radius: 5
                                color: parent.containsMouse ? "#141414" : "transparent"
                                border.width: 1
                                border.color: "#222222"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: skipTxt
                                    anchors.centerIn: parent
                                    text: "Skip"
                                    color: "#484848"
                                    font.pixelSize: 14
                                }
                            }
                        }

                        // Next / Apply
                        MouseArea {
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            implicitWidth: nextRect.implicitWidth
                            implicitHeight: nextRect.implicitHeight
                            onClicked: {
                                if (root.currentStep < root.lastStep) {
                                    root.goNext();
                                } else {
                                    root.done({
                                        maxLuminance:    root.valMaxLuminance,
                                        maxAvgLuminance: root.valMaxAvgLuminance,
                                        minLuminance:    root.valMinLuminance,
                                        sdrMaxLuminance: root.valSdrMaxLuminance,
                                        sdrMinLuminance: root.valSdrMinLuminance,
                                        sdrBrightness:   root.valSdrBrightness,
                                        sdrSaturation:   root.valSdrSaturation,
                                    });
                                }
                            }

                            Rectangle {
                                id: nextRect
                                anchors.fill: parent
                                implicitWidth: nextTxt.implicitWidth + 44
                                implicitHeight: 38
                                radius: 5
                                color: parent.containsMouse ? "#dddddd" : "#ffffff"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: nextTxt
                                    anchors.centerIn: parent
                                    text: root.currentStep < root.lastStep ? "Next →" : "✓  Apply"
                                    color: "#000000"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }
                // Panel height driven by its content column
                implicitHeight: controlPanelLayout.implicitHeight + 36
            }
        }
    }
}
