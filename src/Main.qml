import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// ROG Companion's panel. Design notes:
// - Apple-style calm: one surface, inset grouped cards, generous spacing, soft corners, quiet motion.
// - Linux personality: every number and the status line use the user's monospace font,
//   section captions read like paths (~/power), and the busy state is a blinking prompt cursor.
// - Safe settings apply as soon as they're touched; anything the backend marks `confirm`
//   (GPU mode, fan curves, power actions…) asks first.
ApplicationWindow {
    id: window
    objectName: "rogCompanionWindow"
    visible: false
    width: 372
    height: expanded ? Math.min(780, Screen.height - 48) : collapsedHeight
    minimumWidth: 372
    maximumWidth: 372
    minimumHeight: 480
    title: "ROG Companion"
    color: "transparent"
    font.family: typeof uiFont !== "undefined" ? uiFont : "sans-serif"
    font.pixelSize: 13
    Material.theme: Material.Dark
    Material.accent: accent
    Material.foreground: ink
    Material.roundedScale: Material.ExtraSmallScale

    property bool expanded: false
    property int selectedTab: 0
    readonly property int collapsedHeight: Math.ceil(mainColumn.implicitHeight) + 34

    // Design tokens ---------------------------------------------------------------------------
    readonly property color accent: typeof theme !== "undefined" ? theme.accent : "#FFD60A"
    readonly property color accentInk: typeof theme !== "undefined" ? theme.accentForeground : "#151515"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    readonly property color base: "#f20e1012"
    readonly property color surface: "#17191d"
    readonly property color raised: "#202328"
    readonly property color hairline: "#14ffffff"
    readonly property color edge: "#1fffffff"
    readonly property color ink: "#f2f3f5"
    readonly property color secondary: "#a1a7b0"
    readonly property color tertiary: "#6c737d"
    readonly property color good: "#7bd88f"
    readonly property color warm: "#ffb86b"
    readonly property color hot: "#ff6b6b"
    readonly property int rWindow: 22
    readonly property int rCard: 16
    readonly property int rControl: 10
    readonly property string mono: "monospace"
    readonly property int motion: 180

    readonly property var telemetry: backend.state
    readonly property string languageRevision: typeof translator !== "undefined" ? translator.language : "en"
    readonly property var tabs: [qsTr("Power"), qsTr("Fans"), qsTr("Lighting"), qsTr("System")]
    readonly property var tabGroups: ["Power", "Fans", "Lighting", "System"]
    readonly property var tabPaths: ["~/power", "~/fans", "~/lighting", "~/system"]
    property var pendingControl: null
    property var pendingValue: null

    onExpandedChanged: backend.raisePanel(expanded)

    // Helpers ---------------------------------------------------------------------------------
    function known(value) {
        return value !== undefined && value !== null && value !== "" && isFinite(Number(value)) && Number(value) >= 0
    }
    function number(value, decimals) {
        let language = languageRevision
        return known(value) ? Number(value).toLocaleString(Qt.locale(), 'f', decimals || 0) : "—"
    }
    function reading(value, unit, decimals) {
        return known(value) ? number(value, decimals) + unit : "—"
    }
    function titleCase(value) {
        if (!value) return qsTr("Unknown")
        return String(value).replace(/[-_]/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase() })
    }
    function heat(celsius) {
        if (!known(celsius)) return tertiary
        return celsius >= 90 ? hot : celsius >= 75 ? warm : good
    }
    function control(id) {
        const list = backend.controls || []
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    // Controls grouped the way Settings apps do it: a tab, then small titled sections.
    function sectionOf(id) {
        if (/^(batteryProfile|acProfile)$/.test(id)) return qsTr("Automation")
        if (/^(charge|oneshot)$/.test(id)) return qsTr("Battery")
        if (id === "boost") return qsTr("Processor")
        if (id === "gpu") return qsTr("Graphics")
        if (/^limit_/.test(id)) return qsTr("Firmware limits")
        if (/^fan_(cpu|gpu|mid)$/.test(id)) return qsTr("Fan curves")
        if (/^fan_/.test(id)) return qsTr("Fan control")
        if (/^(keyboard|aura|color)$/.test(id)) return qsTr("Keyboard")
        if (/^keyboard/.test(id)) return qsTr("Keyboard power")
        if (/^slash/.test(id)) return qsTr("Slash bar")
        if (/^(brightness|refreshMode)$/.test(id)) return qsTr("Display")
        if (/^(lock|sleep|reboot|shutdown)$/.test(id)) return qsTr("Session")
        return qsTr("General")
    }
    function sections(tab) {
        const list = (backend.controls || []).filter(function(c) {
            return String(c.group) === tabGroups[tab] && c.id !== "profile"
        })
        const out = []
        list.forEach(function(c) {
            const title = sectionOf(String(c.id))
            let section = out.find(function(s) { return s.title === title })
            if (!section) { section = { title: title, controls: [] }; out.push(section) }
            section.controls.push(c)
        })
        return out
    }
    function apply(control, value) {
        if (!control || control.available === false || backend.busy) return
        if (control.confirm) {
            pendingControl = control
            pendingValue = value
            confirmation.open()
        } else {
            backend.setControl(control.id, value)
        }
    }
    function destructive(control) {
        return control && /^(reboot|shutdown|fan_default)$/.test(control.id)
    }
    // Used by `--screenshot --dialog NAME` to capture the dialogs for the README.
    function showDialog(name) {
        if (name === "help") help.open()
        else if (name === "confirm") { pendingControl = control("reboot") || control("gpu"); pendingValue = true; confirmation.open() }
    }
    function activeFocusItemIsEditor() {
        const item = activeFocusItem
        return item && (item instanceof TextInput || item instanceof TextEdit)
    }

    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !confirmation.opened && !help.opened && !window.activeFocusItemIsEditor(); onActivated: backend.quit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !window.activeFocusItemIsEditor(); onActivated: backend.refresh() }
    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; enabled: !window.activeFocusItemIsEditor(); onActivated: help.open() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: expanded && !confirmation.opened && !help.opened; onActivated: expanded = false }
    Shortcut { sequence: "C"; context: Qt.ApplicationShortcut; enabled: !window.activeFocusItemIsEditor() && !confirmation.opened; onActivated: expanded = !expanded }
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            Shortcut { sequence: String(index + 1); context: Qt.ApplicationShortcut; enabled: window.expanded && !window.activeFocusItemIsEditor(); onActivated: window.selectedTab = index }
        }
    }

    // Building blocks -------------------------------------------------------------------------
    component Txt: Label {
        color: window.ink
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.pixelSize: 13
    }
    component Mono: Txt {
        font.family: window.mono
        font.pixelSize: 12
    }
    // Lowercase, path-like section captions: the quiet terminal accent of the design.
    component Caption: Mono {
        color: window.tertiary
        font.pixelSize: 10
        font.letterSpacing: 0.3
    }
    component Card: Rectangle {
        radius: window.rCard
        color: window.surface
        border.color: window.hairline
        border.width: 1
        // A one-pixel top highlight gives the card a little physical depth.
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: parent.radius / 2 }
            anchors.topMargin: 1
            height: 1
            color: "#0affffff"
        }
    }
    component IconButton: AbstractButton {
        id: iconButton
        property string glyph
        property bool spinning: false
        implicitWidth: 32
        implicitHeight: 32
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        background: Rectangle {
            radius: width / 2
            color: iconButton.down ? "#33ffffff" : iconButton.hovered ? "#1fffffff" : "#12ffffff"
            border.color: iconButton.activeFocus ? window.accent : "transparent"
            Behavior on color { ColorAnimation { duration: window.motion } }
        }
        contentItem: Txt {
            text: iconButton.glyph
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 15
            color: iconButton.enabled ? window.ink : window.tertiary
            RotationAnimation on rotation { running: iconButton.spinning; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
        }
    }
    component PillButton: AbstractButton {
        id: pill
        property bool primary: false
        property bool danger: false
        implicitHeight: 34
        implicitWidth: Math.max(72, pillText.implicitWidth + 28)
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        opacity: enabled ? 1 : 0.4
        background: Rectangle {
            radius: height / 2
            color: pill.primary ? (pill.danger ? window.hot : window.accent)
                                : (pill.down ? "#33ffffff" : pill.hovered ? "#24ffffff" : "#16ffffff")
            border.color: pill.activeFocus ? window.ink : "transparent"
            Behavior on color { ColorAnimation { duration: window.motion } }
        }
        contentItem: Txt {
            id: pillText
            text: pill.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: pill.primary ? (pill.danger ? "#ffffff" : window.accentInk) : (pill.danger ? window.hot : window.ink)
        }
    }
    // iOS-style switch, tinted with the theme accent.
    component Toggle: AbstractButton {
        id: toggle
        checkable: true
        implicitWidth: 46
        implicitHeight: 28
        focusPolicy: Qt.StrongFocus
        opacity: enabled ? 1 : 0.4
        background: Rectangle {
            radius: height / 2
            color: toggle.checked ? window.accent : "#3a3e45"
            border.color: toggle.activeFocus ? window.ink : "transparent"
            Behavior on color { ColorAnimation { duration: window.motion } }
            Rectangle {
                width: 22; height: 22; radius: 11
                y: 3
                x: toggle.checked ? parent.width - width - 3 : 3
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: window.motion; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Item {}
    }
    // Segmented control with a sliding selection, for short choices like Silent / Balanced / Turbo.
    component Segmented: Rectangle {
        id: segmented
        property var control
        property var options: control ? (control.options || []) : []
        readonly property int current: {
            for (let i = 0; i < options.length; i++) if (control && String(options[i].value) === String(control.value)) return i
            return -1
        }
        objectName: control ? "choice_" + control.id : ""
        implicitHeight: 36
        radius: height / 2
        color: "#0dffffff"
        border.color: window.hairline
        opacity: control && control.available !== false ? 1 : 0.4
        Rectangle {
            visible: segmented.current >= 0
            width: (segmented.width - 6) / Math.max(1, segmented.options.length)
            height: segmented.height - 6
            y: 3
            x: 3 + segmented.current * width
            radius: height / 2
            color: window.raised
            border.color: window.edge
            Behavior on x { NumberAnimation { duration: window.motion; easing.type: Easing.OutCubic } }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                width: 14; height: 2; radius: 1
                color: window.accent
            }
        }
        Row {
            anchors.fill: parent
            anchors.margins: 3
            Repeater {
                model: segmented.options
                delegate: AbstractButton {
                    id: segment
                    required property var modelData
                    required property int index
                    objectName: "segment_" + segmented.control.id + "_" + index
                    width: (segmented.width - 6) / Math.max(1, segmented.options.length)
                    height: segmented.height - 6
                    enabled: segmented.control.available !== false && !backend.busy
                    focusPolicy: Qt.StrongFocus
                    onClicked: if (index !== segmented.current || (segmented.control.id === "gpu" && window.telemetry.pendingGpu)) window.apply(segmented.control, modelData.value)
                    contentItem: Txt {
                        text: segment.modelData.label
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        font.weight: segment.index === segmented.current ? Font.DemiBold : Font.Normal
                        color: segment.index === segmented.current ? window.ink : window.secondary
                        Behavior on color { ColorAnimation { duration: window.motion } }
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: "transparent"
                        border.color: segment.activeFocus ? window.accent : "transparent"
                    }
                }
            }
        }
    }
    component Meter: Rectangle {
        property real fraction: 0
        property color tint: window.accent
        implicitHeight: 4
        radius: 2
        color: "#14ffffff"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.fraction))
            height: parent.height
            radius: parent.radius
            color: parent.tint
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
    component MetricTile: Card {
        id: tile
        property string caption
        property string value
        property string detail
        property real celsius: -1
        implicitHeight: 104
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 2
            Caption { text: tile.caption; Layout.fillWidth: true }
            Item { Layout.fillHeight: true }
            Mono { text: tile.value; font.pixelSize: 30; font.weight: Font.Medium; color: window.ink }
            Txt { text: tile.detail; color: window.secondary; font.pixelSize: 11; Layout.fillWidth: true }
            Meter { Layout.fillWidth: true; Layout.topMargin: 6; fraction: tile.celsius > 0 ? tile.celsius / 100 : 0; tint: window.heat(tile.celsius) }
        }
    }

    // One row in an inset grouped card. Its look depends on the kind of control.
    component ControlRow: Item {
        id: row
        required property var control
        property bool last: false
        readonly property bool available: control.available !== false
        readonly property string kind: String(control.kind)
        readonly property bool isLevels: control.id === "keyboard" && Number(control.max) === 3
        readonly property bool isCurve: kind === "text" && /^fan_(cpu|gpu|mid)$/.test(String(control.id))
        readonly property var levelControl: isLevels ? Object.assign({}, control, { options: [
            { label: qsTr("Off"), value: 0 }, { label: qsTr("Low"), value: 1 }, { label: qsTr("Med"), value: 2 }, { label: qsTr("High"), value: 3 }] }) : null
        readonly property bool shortChoice: kind === "choice" && (control.options || []).length <= 3
            && (control.options || []).every(function(o) { return String(o.label).length <= 10 })
        property var draft: control.value
        readonly property bool dirty: String(draft) !== String(control.value)
        onControlChanged: { draft = control.value; if (slider) slider.value = Number(control.value || 0) }
        implicitHeight: body.implicitHeight + 24
        opacity: available ? 1 : 0.55

        ColumnLayout {
            id: body
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Txt {
                        text: row.control.label || row.control.id
                        font.weight: Font.Medium
                        color: row.kind === "action" ? (window.destructive(row.control) ? window.hot : window.accent) : window.ink
                        Layout.fillWidth: true
                        visible: row.kind !== "action"
                    }
                    Txt {
                        text: !row.available ? (row.control.reason || qsTr("Not available on this laptop."))
                                             : row.isCurve ? qsTr("%1 profile · eight points from cool to hot, ending at 100%. Edit, then Apply.").arg(window.titleCase(window.telemetry.profile))
                                             : (row.control.description || "")
                        visible: text.length > 0 && row.kind !== "action"
                        color: window.tertiary
                        font.pixelSize: 11
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        elide: Text.ElideNone
                        maximumLineCount: row.isCurve ? 2 : 6
                        Layout.fillWidth: true
                    }
                }
                // Toggle: the switch itself is the control.
                Toggle {
                    objectName: "toggle_" + row.control.id
                    visible: row.kind === "toggle"
                    checked: !!row.control.value
                    enabled: row.available && !backend.busy
                    onClicked: { const wanted = checked; checked = Qt.binding(function() { return !!row.control.value }); window.apply(row.control, wanted) }
                    Accessible.name: row.control.label
                }
                // Number: the live value, in the terminal font.
                Mono {
                    visible: row.kind === "number" && !row.isLevels
                    text: window.reading(row.draft, row.control.unit ? (row.control.unit === "%" ? "%" : " " + row.control.unit) : "", 0)
                    color: row.dirty ? window.accent : window.secondary
                    font.pixelSize: 13
                }
                // Long choice: current value with a chevron that opens a menu.
                AbstractButton {
                    id: menuButton
                    objectName: "choice_" + row.control.id
                    visible: row.kind === "choice" && !row.shortChoice
                    enabled: row.available && !backend.busy
                    focusPolicy: Qt.StrongFocus
                    implicitHeight: 30
                    // The title keeps priority: values are short, and long ones elide instead.
                    implicitWidth: Math.min(150, menuText.implicitWidth + 30)
                    Layout.maximumWidth: 150
                    property alias menu: optionsMenu
                    onClicked: optionsMenu.open()
                    contentItem: Txt {
                        id: menuText
                        text: {
                            const options = row.control.options || []
                            for (let i = 0; i < options.length; i++) if (String(options[i].value) === String(row.control.value)) return options[i].label + "  ›"
                            return qsTr("Choose") + "  ›"
                        }
                        color: window.secondary
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideLeft
                    }
                    background: Rectangle { radius: window.rControl; color: menuButton.hovered ? "#12ffffff" : "transparent"; border.color: menuButton.activeFocus ? window.accent : "transparent" }
                    Menu {
                        id: optionsMenu
                        objectName: "menu_" + row.control.id
                        y: menuButton.height
                        x: menuButton.width - width
                        background: Rectangle { implicitWidth: 220; radius: window.rControl + 2; color: window.raised; border.color: window.edge }
                        Repeater {
                            model: row.control.options || []
                            delegate: MenuItem {
                                required property var modelData
                                objectName: "option_" + row.control.id + "_" + modelData.value
                                text: (String(modelData.value) === String(row.control.value) ? "✓  " : "     ") + modelData.label
                                font.family: window.font.family
                                onTriggered: if (String(modelData.value) !== String(row.control.value) || (row.control.id === "gpu" && window.telemetry.pendingGpu)) window.apply(row.control, modelData.value)
                            }
                        }
                    }
                }
            }

            Segmented {
                visible: row.shortChoice
                control: row.control
                Layout.fillWidth: true
            }
            Segmented {
                visible: row.isLevels
                control: row.levelControl
                objectName: "levels_" + row.control.id
                Layout.fillWidth: true
            }

            // Fan curve: a live graph of the points, redrawn as you type.
            Rectangle {
                visible: row.isCurve
                Layout.fillWidth: true
                implicitHeight: 96
                radius: window.rControl
                color: "#0affffff"
                border.color: window.hairline
                Canvas {
                    id: curve
                    objectName: "curve_" + row.control.id
                    anchors.fill: parent
                    anchors.margins: 10
                    property string points: row.draft === undefined ? "" : String(row.draft)
                    property color tint: window.accent
                    onPointsChanged: requestPaint()
                    onTintChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const parsed = points.split(",").map(function(p) {
                            const m = /^\s*(\d{1,3})c:(\d{1,3})%\s*$/.exec(p)
                            return m ? { t: Number(m[1]), v: Number(m[2]) } : null
                        }).filter(function(p) { return p !== null })
                        // Grid: 20 °C columns and 25 % rows, like a terminal plot.
                        ctx.strokeStyle = "rgba(255,255,255,0.06)"
                        ctx.lineWidth = 1
                        for (let t = 20; t <= 100; t += 20) { const x = (t - 20) / 90 * width; ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke() }
                        for (let v = 0; v <= 100; v += 25) { const y = height - v / 100 * height; ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke() }
                        if (parsed.length < 2) return
                        const px = function(p) { return Math.max(0, Math.min(1, (p.t - 20) / 90)) * width }
                        const py = function(p) { return height - Math.max(0, Math.min(100, p.v)) / 100 * height }
                        // Soft fill under the curve, then the line and points.
                        ctx.beginPath()
                        ctx.moveTo(px(parsed[0]), height)
                        parsed.forEach(function(p) { ctx.lineTo(px(p), py(p)) })
                        ctx.lineTo(px(parsed[parsed.length - 1]), height)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.12)
                        ctx.fill()
                        ctx.beginPath()
                        parsed.forEach(function(p, i) { if (i === 0) ctx.moveTo(px(p), py(p)); else ctx.lineTo(px(p), py(p)) })
                        ctx.strokeStyle = tint
                        ctx.lineWidth = 2
                        ctx.lineJoin = "round"
                        ctx.stroke()
                        ctx.fillStyle = "#ffffff"
                        parsed.forEach(function(p) { ctx.beginPath(); ctx.arc(px(p), py(p), 2.5, 0, 2 * Math.PI); ctx.fill() })
                    }
                }
                Caption {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                    text: "20°"
                    font.pixelSize: 9
                }
                Caption {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                    text: "110°"
                    font.pixelSize: 9
                }
                Caption {
                    anchors { right: parent.right; top: parent.top; margins: 6 }
                    text: "100%"
                    font.pixelSize: 9
                }
            }

            // Number: a slider that applies when you let go (only if the value changed).
            Slider {
                id: slider
                objectName: "slider_" + row.control.id
                visible: row.kind === "number" && row.available && !row.isLevels
                Layout.fillWidth: true
                implicitHeight: 26
                from: Number(row.control.min || 0)
                to: Number(row.control.max === undefined ? 100 : row.control.max)
                stepSize: Number(row.control.step || 1)
                snapMode: Slider.SnapAlways
                value: Number(row.control.value || 0)
                enabled: row.available && !backend.busy
                onMoved: row.draft = Math.round(value)
                onPressedChanged: if (!pressed && row.dirty) window.apply(row.control, row.draft)
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 4
                    radius: 2
                    color: "#1fffffff"
                    Rectangle { width: slider.visualPosition * parent.width; height: parent.height; radius: 2; color: window.accent }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 20; height: 20; radius: 10
                    color: "#ffffff"
                    border.color: slider.activeFocus ? window.accent : "#33000000"
                    border.width: slider.activeFocus ? 2 : 1
                    scale: slider.pressed ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                }
            }

            // Colour: theme-aware swatches that apply instantly, plus a hex field.
            RowLayout {
                visible: row.control.id === "color" && row.available
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [String(window.accent).replace("#", "").slice(-6), "ffffff", "ff3b30", "ff9f0a", "30d158", "0a84ff", "bf5af2"]
                    delegate: AbstractButton {
                        id: swatch
                        required property string modelData
                        objectName: "swatch_" + modelData
                        implicitWidth: 24; implicitHeight: 24
                        enabled: !backend.busy
                        focusPolicy: Qt.StrongFocus
                        onClicked: window.apply(row.control, modelData)
                        background: Rectangle {
                            radius: 12
                            color: "#" + swatch.modelData
                            border.width: String(row.control.value).toLowerCase() === swatch.modelData.toLowerCase() || swatch.activeFocus ? 2 : 1
                            border.color: String(row.control.value).toLowerCase() === swatch.modelData.toLowerCase() ? window.ink : swatch.activeFocus ? window.accent : "#33ffffff"
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Text: fan curves and hex colours keep an explicit Apply, because typing is in-between work.
            RowLayout {
                visible: row.kind === "text"
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    objectName: "text_" + row.control.id
                    Layout.fillWidth: true
                    text: row.draft === undefined ? "" : String(row.draft)
                    enabled: row.available && !backend.busy
                    selectByMouse: true
                    font.family: window.mono
                    font.pixelSize: 11
                    color: window.ink
                    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 8
                    background: Rectangle { radius: window.rControl; color: "#0dffffff"; border.color: parent.activeFocus ? window.accent : window.hairline }
                    onTextEdited: row.draft = text
                    onAccepted: if (row.dirty) window.apply(row.control, row.draft)
                    // Long curves start at their beginning, not scrolled to the end.
                    Component.onCompleted: cursorPosition = 0
                    onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                }
                PillButton {
                    objectName: "apply_" + row.control.id
                    text: qsTr("Apply")
                    primary: true
                    visible: row.dirty
                    enabled: row.available && !backend.busy
                    onClicked: window.apply(row.control, row.draft)
                }
            }

            // Action: a full-width text button, red for the ones that end your session.
            AbstractButton {
                id: actionButton
                objectName: "action_" + row.control.id
                visible: row.kind === "action"
                Layout.fillWidth: true
                implicitHeight: 22
                enabled: row.available && !backend.busy
                focusPolicy: Qt.StrongFocus
                onClicked: window.apply(row.control, true)
                contentItem: Txt {
                    text: row.control.label || qsTr("Run")
                    font.weight: Font.Medium
                    color: window.destructive(row.control) ? window.hot : window.accent
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { color: "transparent"; border.color: actionButton.activeFocus ? window.accent : "transparent"; radius: 6 }
            }
            Txt {
                visible: row.kind === "action" && !!row.control.description
                text: row.control.description || ""
                color: window.tertiary
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
        }
        Rectangle {
            visible: !row.last
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14 }
            height: 1
            color: window.hairline
        }
    }

    // The panel ---------------------------------------------------------------------------------
    Rectangle {
        id: shell
        anchors.fill: parent
        radius: window.rWindow
        color: window.base
        border.color: window.edge
        border.width: 1
        clip: true
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        // A faint wash of the theme accent at the top, like light catching brushed metal.
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 140
            radius: window.rWindow
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.10) }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 18
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34
                    radius: 10
                    color: window.accent
                    Txt { anchors.centerIn: parent; text: "R"; color: window.accentInk; font.weight: Font.Black; font.pixelSize: 19; font.italic: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Txt { text: "ROG Companion"; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Caption { text: window.telemetry.model || qsTr("ASUS laptop"); color: window.secondary; Layout.fillWidth: true }
                }
                IconButton { objectName: "helpButton"; glyph: "?"; onClicked: help.open(); Accessible.name: qsTr("Keyboard shortcuts") }
                IconButton { objectName: "refreshButton"; glyph: "↻"; spinning: backend.busy; enabled: !backend.busy; onClicked: backend.refresh(); Accessible.name: qsTr("Refresh hardware status") }
            }

            // Battery: ring gauge plus the numbers that matter.
            Card {
                Layout.fillWidth: true
                implicitHeight: 136
                visible: !window.expanded
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 18
                    Item {
                        implicitWidth: 104; implicitHeight: 104
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            property real fraction: window.known(window.telemetry.battery) ? Math.min(100, window.telemetry.battery) / 100 : 0
                            property color tint: window.known(window.telemetry.battery) && window.telemetry.battery <= 15 ? window.hot : window.accent
                            onFractionChanged: requestPaint()
                            onTintChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const c = width / 2, r = c - 6, start = -Math.PI / 2
                                ctx.lineWidth = 8
                                ctx.lineCap = "round"
                                ctx.strokeStyle = "rgba(255,255,255,0.08)"
                                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                                if (fraction > 0) {
                                    ctx.strokeStyle = tint
                                    ctx.beginPath(); ctx.arc(c, c, r, start, start + 2 * Math.PI * fraction); ctx.stroke()
                                }
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: -2
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                Mono { id: batteryNumber; objectName: "batteryReading"; text: window.number(window.telemetry.battery, 0); font.pixelSize: 26; font.weight: Font.Medium }
                                Mono { text: "%"; visible: window.known(window.telemetry.battery); font.pixelSize: 13; color: window.secondary; anchors.baseline: batteryNumber.baseline }
                            }
                            Caption {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: window.telemetry.batteryStatus === "Charging" ? qsTr("charging") : window.telemetry.ac === true ? qsTr("plugged in") : window.telemetry.ac === false ? qsTr("battery") : ""
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            spacing: 0
                            Caption { text: qsTr("power draw") }
                            Mono { objectName: "wattsReading"; text: window.reading(window.telemetry.watts, " W", 1); font.pixelSize: 18 }
                        }
                        RowLayout {
                            spacing: 18
                            ColumnLayout {
                                spacing: 0
                                Caption { text: qsTr("health") }
                                Mono { text: window.reading(window.telemetry.batteryHealth, "%", 0); color: window.secondary }
                            }
                            ColumnLayout {
                                spacing: 0
                                Caption { text: qsTr("limit") }
                                Mono { text: window.reading(window.telemetry.chargeLimit, "%", 0); color: window.secondary }
                            }
                        }
                    }
                }
            }

            // Temperatures
            RowLayout {
                Layout.fillWidth: true
                visible: !window.expanded
                spacing: 10
                MetricTile {
                    objectName: "cpuCard"
                    Layout.fillWidth: true
                    caption: "cpu"
                    value: window.reading(window.telemetry.cpuTemp, "°", 0)
                    detail: qsTr("Processor")
                    celsius: window.known(window.telemetry.cpuTemp) ? window.telemetry.cpuTemp : -1
                }
                MetricTile {
                    objectName: "gpuCard"
                    Layout.fillWidth: true
                    caption: "gpu"
                    value: window.reading(window.telemetry.gpuTemp, "°", 0)
                    detail: window.titleCase(window.telemetry.gpuMode) + (window.known(window.telemetry.gpuPower) ? " · " + window.reading(window.telemetry.gpuPower, " W", 1) : "")
                    celsius: window.known(window.telemetry.gpuTemp) ? window.telemetry.gpuTemp : -1
                }
            }

            // Fans
            Card {
                Layout.fillWidth: true
                implicitHeight: 62
                visible: !window.expanded
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14
                    Repeater {
                        model: [
                            { key: "cpu", name: "cpuFanReading", value: window.telemetry.fanCpu, show: true },
                            { key: "gpu", name: "gpuFanReading", value: window.telemetry.fanGpu, show: true },
                            { key: "mid", name: "midFanReading", value: window.telemetry.fanMid, show: window.known(window.telemetry.fanMid) }
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            visible: modelData.show
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                spacing: 4
                                Caption { text: modelData.key }
                                Item { Layout.fillWidth: true }
                                Mono { objectName: modelData.name; visible: modelData.show; text: window.number(modelData.value, 0); font.pixelSize: 12 }
                                Caption { text: "rpm" }
                            }
                            Meter { Layout.fillWidth: true; fraction: window.known(modelData.value) ? modelData.value / 6500 : 0; tint: window.secondary }
                        }
                    }
                }
            }

            // Folded dashboard, shown while the controls are open.
            Card {
                objectName: "compactStats"
                visible: window.expanded
                Layout.fillWidth: true
                implicitHeight: 58
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8
                    Repeater {
                        model: [
                            { caption: qsTr("battery"), value: window.reading(window.telemetry.battery, "%", 0), tint: window.ink },
                            { caption: qsTr("power"), value: window.reading(window.telemetry.watts, " W", 1), tint: window.ink },
                            { caption: "cpu", value: window.reading(window.telemetry.cpuTemp, "°", 0), tint: window.heat(window.telemetry.cpuTemp) },
                            { caption: "gpu", value: window.reading(window.telemetry.gpuTemp, "°", 0), tint: window.heat(window.telemetry.gpuTemp) }
                        ]
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 1
                            Caption { text: modelData.caption }
                            Mono { text: modelData.value; font.pixelSize: 15; color: modelData.tint === window.ink ? window.ink : modelData.tint }
                        }
                    }
                }
            }

            // Performance mode: the one control worth keeping on the front.
            Segmented {
                Layout.fillWidth: true
                control: window.control("profile")
                visible: control !== null
            }

            Rectangle {
                objectName: "pendingGpuBanner"
                visible: !!window.telemetry.pendingGpu
                Layout.fillWidth: true
                implicitHeight: pendingText.implicitHeight + 20
                radius: window.rControl + 2
                color: window.accentSoft
                border.color: Qt.rgba(window.accent.r, window.accent.g, window.accent.b, 0.35)
                Txt {
                    id: pendingText
                    anchors.fill: parent
                    anchors.margins: 10
                    text: qsTr("%1 graphics queued · restart to switch").arg(window.titleCase(window.telemetry.pendingGpu))
                    color: window.accent
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }

            // Controls (expanded)
            ColumnLayout {
                visible: window.expanded
                opacity: window.expanded ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: window.motion } }
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Section tabs as a segmented control.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: height / 2
                    color: "#0dffffff"
                    border.color: window.hairline
                    Rectangle {
                        width: (parent.width - 6) / window.tabs.length
                        height: parent.height - 6
                        y: 3
                        x: 3 + window.selectedTab * width
                        radius: height / 2
                        color: window.raised
                        border.color: window.edge
                        Behavior on x { NumberAnimation { duration: window.motion; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 3
                        Repeater {
                            model: window.tabs
                            delegate: AbstractButton {
                                id: tabButton
                                required property int index
                                required property string modelData
                                objectName: "tab_" + index
                                width: (parent.width) / window.tabs.length
                                height: parent.height
                                focusPolicy: Qt.StrongFocus
                                onClicked: window.selectedTab = index
                                contentItem: Txt {
                                    text: tabButton.modelData
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                    font.weight: window.selectedTab === tabButton.index ? Font.DemiBold : Font.Normal
                                    color: window.selectedTab === tabButton.index ? window.ink : window.secondary
                                }
                                background: Rectangle { radius: height / 2; color: "transparent"; border.color: tabButton.activeFocus ? window.accent : "transparent" }
                            }
                        }
                    }
                }

                ScrollView {
                    id: controlScroll
                    objectName: "controlScroll"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        width: controlScroll.availableWidth
                        spacing: 6
                        Caption { text: window.tabPaths[window.selectedTab]; Layout.leftMargin: 4; Layout.topMargin: 2 }
                        Repeater {
                            model: window.sections(window.selectedTab)
                            delegate: ColumnLayout {
                                id: section
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.bottomMargin: 8
                                spacing: 6
                                Txt { text: section.modelData.title; color: window.secondary; font.pixelSize: 11; font.weight: Font.DemiBold; Layout.leftMargin: 4 }
                                Card {
                                    Layout.fillWidth: true
                                    implicitHeight: rows.implicitHeight
                                    Column {
                                        id: rows
                                        width: parent.width
                                        Repeater {
                                            model: section.modelData.controls
                                            delegate: ControlRow {
                                                required property var modelData
                                                required property int index
                                                control: modelData
                                                last: index === section.modelData.controls.length - 1
                                                width: rows.width
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Txt {
                            visible: window.sections(window.selectedTab).length === 0
                            text: qsTr("Nothing to adjust here on this laptop.")
                            color: window.tertiary
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                        }
                    }
                }
            }
            Item { visible: !window.expanded; Layout.fillHeight: true }

            // Status line: a prompt, in the terminal font. The cursor blinks while work is running.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Mono { text: "›"; color: window.telemetry.error ? window.hot : window.accent; font.pixelSize: 12 }
                Mono {
                    objectName: "statusMessage"
                    text: window.telemetry.error || backend.message || (window.telemetry.updated ? qsTr("in sync · %1").arg(window.telemetry.updated) : qsTr("ready"))
                    color: window.telemetry.error ? window.hot : window.secondary
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    maximumLineCount: 3
                    Layout.fillWidth: true
                }
                Rectangle {
                    visible: backend.busy
                    implicitWidth: 7; implicitHeight: 13
                    color: window.accent
                    SequentialAnimation on opacity {
                        running: backend.busy
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 450 }
                        NumberAnimation { to: 1; duration: 450 }
                    }
                }
            }

            PillButton {
                objectName: "expandButton"
                Layout.fillWidth: true
                implicitHeight: 38
                text: window.expanded ? qsTr("Done") : qsTr("Controls")
                primary: window.expanded
                onClicked: window.expanded = !window.expanded
            }
        }
    }

    // Dialogs ---------------------------------------------------------------------------------
    component SheetDialog: Dialog {
        anchors.centerIn: parent
        width: window.width - 48
        modal: true
        padding: 20
        topPadding: 22
        Overlay.modal: Rectangle { color: "#a6000000"; radius: window.rWindow }
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: window.motion }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: window.motion; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }
        background: Rectangle { radius: window.rCard + 2; color: window.raised; border.color: window.edge }
        header: Item {}
    }
    SheetDialog {
        id: confirmation
        objectName: "confirmationDialog"
        contentItem: ColumnLayout {
            spacing: 8
            Txt {
                text: window.pendingControl ? (window.pendingControl.label || window.pendingControl.id) : ""
                font.pixelSize: 16
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            Txt {
                text: window.pendingControl ? (window.pendingControl.description || qsTr("This change may interrupt your current session.")) : ""
                color: window.secondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                spacing: 10
                PillButton { objectName: "confirmCancel"; text: qsTr("Cancel"); Layout.fillWidth: true; onClicked: confirmation.close() }
                PillButton {
                    id: confirmApplyButton
                    objectName: "confirmApply"
                    text: qsTr("Apply")
                    primary: true
                    danger: window.destructive(window.pendingControl)
                    Layout.fillWidth: true
                    onClicked: {
                        if (window.pendingControl) backend.setControl(window.pendingControl.id, window.pendingValue)
                        confirmation.close()
                    }
                }
            }
        }
        onOpened: confirmApplyButton.forceActiveFocus()
        onClosed: { window.pendingControl = null; window.pendingValue = null }
    }
    SheetDialog {
        id: help
        objectName: "shortcutDialog"
        contentItem: ColumnLayout {
            spacing: 12
            Txt { text: qsTr("Keyboard shortcuts"); font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.bottomMargin: 4 }
            Repeater {
                model: [
                    { key: "C", label: qsTr("Open or close controls") },
                    { key: "1–4", label: qsTr("Switch section") },
                    { key: "Space", label: qsTr("Refresh hardware status") },
                    { key: "Esc", label: qsTr("Close controls") },
                    { key: "?", label: qsTr("Show shortcuts") },
                    { key: "Q", label: qsTr("Quit ROG Companion") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Txt { text: modelData.label; color: window.secondary; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideNone }
                    Rectangle {
                        implicitWidth: Math.max(28, keyText.implicitWidth + 14)
                        implicitHeight: 24
                        radius: 6
                        color: "#14ffffff"
                        border.color: window.edge
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 2
                            radius: 6
                            color: "#33000000"
                        }
                        Mono { id: keyText; anchors.centerIn: parent; text: modelData.key; font.pixelSize: 11 }
                    }
                }
            }
            PillButton { text: qsTr("Close"); Layout.fillWidth: true; Layout.topMargin: 8; onClicked: help.close() }
        }
    }
}
