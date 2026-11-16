import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: window
    objectName: "rogCompanionWindow"
    visible: false
    width: 360
    height: expanded ? Math.min(760, Screen.height - 48) : 560
    minimumWidth: 360
    maximumWidth: 360
    minimumHeight: 500
    title: "ROG Companion"
    color: "#121416"
    font.family: "sans-serif"
    Material.theme: Material.Dark
    Material.accent: accentColor
    Material.foreground: ink
    Material.roundedScale: cornerRadius

    property bool expanded: false
    property int selectedTab: 0
    readonly property color accentColor: typeof theme !== "undefined" ? theme.accent : "#d4b75c"
    readonly property color accentInk: typeof theme !== "undefined" ? theme.accentForeground : "#171713"
    readonly property real cornerRadius: typeof theme !== "undefined" ? theme.radius : 0
    readonly property color ink: "#e5e7e7"
    readonly property color muted: "#899096"
    readonly property color panel: "#1b1e21"
    readonly property color line: "#30353a"
    readonly property var telemetry: backend.state
    readonly property string languageRevision: typeof translator !== "undefined" ? translator.language : "en"
    readonly property var tabs: [qsTr("Overview"), qsTr("Power"), qsTr("Fans"), qsTr("Lighting"), qsTr("System")]
    property var pendingControl: null
    property var pendingValue: null

    onExpandedChanged: backend.raisePanel(expanded)

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
    function filteredControls() {
        const list = backend.controls || []
        return list.filter(function(c) {
            const group = String(c.group || "system").toLowerCase()
            if (selectedTab === 0) return group === "overview" || String(c.id).toLowerCase() === "gpu" || /profile|gpu.?mode/.test(String(c.id).toLowerCase())
            if (selectedTab === 1) return /power|battery|performance/.test(group)
            if (selectedTab === 2) return /fan|thermal/.test(group)
            if (selectedTab === 3) return /light|keyboard|display/.test(group)
            return !/overview|power|battery|performance|fan|thermal|light|keyboard|display/.test(group)
        })
    }
    function requestApply(control, value) {
        if (control.confirm) {
            pendingControl = control
            pendingValue = value
            confirmation.open()
        } else {
            backend.setControl(control.id, value)
        }
    }

    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !confirmation.opened && !help.opened && !window.activeFocusItemIsEditor(); onActivated: backend.quit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !window.activeFocusItemIsEditor(); onActivated: backend.refresh() }
    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; enabled: !window.activeFocusItemIsEditor(); onActivated: help.open() }
    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: expanded && !confirmation.opened && !help.opened; onActivated: expanded = false }
    function activeFocusItemIsEditor() {
        const item = activeFocusItem
        return item && (item instanceof TextInput || item instanceof TextEdit)
    }

    component PlainLabel: Label {
        color: window.ink
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.pixelSize: 12
    }
    component MicroLabel: PlainLabel {
        color: window.muted
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
    }
    component SmallButton: Button {
        id: small
        implicitHeight: 34
        font.pixelSize: 11
        font.weight: Font.DemiBold
        leftPadding: 11
        rightPadding: 11
        contentItem: Text {
            text: small.text
            textFormat: Text.PlainText
            color: small.enabled ? (small.highlighted ? window.accentInk : window.ink) : window.muted
            font: small.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: small.highlighted ? window.accentColor : (small.down ? "#363b3f" : small.hovered ? "#2c3136" : "#24282c")
            radius: Math.min(4, window.cornerRadius)
            border.color: small.activeFocus ? window.accentColor : "#383e43"
            Behavior on color { ColorAnimation { duration: 100 } }
            opacity: small.enabled ? 1 : 0.45
        }
    }
    component MetricCard: Rectangle {
        property string caption
        property string value
        property string detail
        property color valueColor: window.ink
        implicitHeight: 105
        color: window.panel
        radius: window.cornerRadius
        border.color: "#292e32"
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 4
            MicroLabel { text: caption; Layout.fillWidth: true }
            PlainLabel { text: value; font.pixelSize: 27; font.weight: Font.Medium; color: valueColor; Layout.fillWidth: true }
            PlainLabel { text: detail; color: window.muted; font.pixelSize: 10; Layout.fillWidth: true }
        }
    }
    component CapabilityRow: Rectangle {
        id: row
        required property var control
        property var draft: control.value
        readonly property bool available: control.available !== false
        readonly property bool dirty: String(draft) !== String(control.value)
        implicitHeight: rowContents.implicitHeight + 26
        color: window.panel
        radius: window.cornerRadius
        border.color: "#2b3035"
        onControlChanged: draft = control.value
        ColumnLayout {
            id: rowContents
            anchors.fill: parent
            anchors.margins: 13
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                PlainLabel { text: row.control.label || row.control.id; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Rectangle { visible: row.dirty; implicitWidth: 5; implicitHeight: 5; radius: 2.5; color: window.accentColor }
                MicroLabel { text: row.available ? "" : qsTr("UNAVAILABLE"); font.pixelSize: 8; font.letterSpacing: 0.5 }
            }
            PlainLabel {
                text: !row.available ? (row.control.reason || qsTr("This device does not expose this control.")) : (row.control.description || "")
                visible: text.length > 0
                color: window.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            RowLayout {
                Layout.fillWidth: true
                visible: row.control.kind === "choice"
                ComboBox {
                    id: choice
                    objectName: "choice_" + row.control.id
                    Layout.fillWidth: true
                    implicitHeight: 38
                    enabled: row.available && !backend.busy
                    model: row.control.options || []
                    textRole: "label"
                    valueRole: "value"
                    contentItem: PlainLabel {
                        text: choice.displayText
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 4
                        rightPadding: choice.indicator.width + choice.spacing
                        color: choice.enabled ? window.ink : window.muted
                    }
                    delegate: ItemDelegate {
                        id: optionDelegate
                        required property var modelData
                        required property int index
                        width: choice.width
                        text: modelData.label
                        highlighted: choice.highlightedIndex === index
                        contentItem: PlainLabel { text: optionDelegate.text; verticalAlignment: Text.AlignVCenter }
                    }
                    currentIndex: {
                        const options = row.control.options || []
                        for (let i = 0; i < options.length; i++) if (String(options[i].value) === String(row.draft)) return i
                        return -1
                    }
                    onActivated: row.draft = currentValue
                }
                SmallButton { objectName: "apply_" + row.control.id; text: qsTr("Apply"); highlighted: row.dirty; enabled: row.available && row.dirty && !backend.busy; onClicked: window.requestApply(row.control, row.draft) }
            }
            ColumnLayout {
                visible: row.control.kind === "number"
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    PlainLabel { text: window.reading(row.draft, row.control.unit ? " " + row.control.unit : "", 0); font.pixelSize: 20; color: window.accentColor; Layout.fillWidth: true }
                    SmallButton { objectName: "apply_" + row.control.id; text: qsTr("Apply"); highlighted: row.dirty; enabled: row.available && row.dirty && !backend.busy; onClicked: window.requestApply(row.control, row.draft) }
                }
                Slider {
                    objectName: "slider_" + row.control.id
                    Layout.fillWidth: true
                    implicitHeight: 32
                    from: Number(row.control.min || 0)
                    to: Number(row.control.max === undefined ? 100 : row.control.max)
                    stepSize: Number(row.control.step || 1)
                    value: Number(row.draft || 0)
                    enabled: row.available && !backend.busy
                    onMoved: row.draft = value
                }
                RowLayout {
                    Layout.fillWidth: true
                    PlainLabel { text: window.number(row.control.min, 0); font.pixelSize: 10; color: window.muted }
                    Item { Layout.fillWidth: true }
                    PlainLabel { text: window.number(row.control.max, 0); font.pixelSize: 10; color: window.muted }
                }
            }
            RowLayout {
                visible: row.control.kind === "toggle"
                Layout.fillWidth: true
                Switch {
                    objectName: "toggle_" + row.control.id
                    text: checked ? qsTr("On") : qsTr("Off")
                    checked: !!row.draft
                    enabled: row.available && !backend.busy
                    Layout.fillWidth: true
                    onToggled: row.draft = checked
                }
                SmallButton { objectName: "apply_" + row.control.id; text: qsTr("Apply"); highlighted: row.dirty; enabled: row.available && row.dirty && !backend.busy; onClicked: window.requestApply(row.control, row.draft) }
            }
            ColumnLayout {
                visible: row.control.kind === "text"
                Layout.fillWidth: true
                TextField {
                    objectName: "text_" + row.control.id
                    Layout.fillWidth: true
                    text: row.draft === undefined ? "" : String(row.draft)
                    enabled: row.available && !backend.busy
                    selectByMouse: true
                    font.family: "monospace"
                    font.pixelSize: 11
                    onTextEdited: row.draft = text
                }
                SmallButton { objectName: "apply_" + row.control.id; Layout.alignment: Qt.AlignRight; text: qsTr("Apply"); highlighted: row.dirty; enabled: row.available && row.dirty && !backend.busy; onClicked: window.requestApply(row.control, row.draft) }
            }
            SmallButton {
                objectName: "action_" + row.control.id
                visible: row.control.kind === "action"
                text: row.control.label || qsTr("Run")
                Layout.fillWidth: true
                enabled: row.available && !backend.busy
                onClicked: window.requestApply(row.control, true)
            }
        }
    }

    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true
        Rectangle { anchors.top: parent.top; width: parent.width; height: 2; color: window.accentColor }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            anchors.topMargin: 20
            anchors.bottomMargin: 12
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    implicitWidth: 29; implicitHeight: 29
                    color: window.accentColor
                    radius: Math.min(4, window.cornerRadius)
                    PlainLabel { anchors.centerIn: parent; text: "R"; color: window.accentInk; font.weight: Font.Black; font.pixelSize: 19; font.italic: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    PlainLabel { text: "ROG COMPANION"; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: 3 }
                    PlainLabel { text: window.telemetry.model || qsTr("ASUS laptop"); color: window.muted; font.pixelSize: 10; Layout.fillWidth: true }
                }
                SmallButton { objectName: "helpButton"; text: "?"; implicitWidth: 30; leftPadding: 0; rightPadding: 0; onClicked: help.open(); Accessible.name: qsTr("Keyboard shortcuts") }
                SmallButton { objectName: "refreshButton"; text: "↻"; implicitWidth: 30; leftPadding: 0; rightPadding: 0; enabled: !backend.busy; onClicked: backend.refresh(); Accessible.name: qsTr("Refresh hardware status") }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: window.line }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 2.5; color: backend.busy ? window.accentColor : window.telemetry.error ? "#d99679" : "#88aa91" }
                MicroLabel { text: backend.busy ? qsTr("UPDATING") : window.telemetry.ac === true ? qsTr("AC CONNECTED") : window.telemetry.ac === false ? qsTr("ON BATTERY") : qsTr("POWER UNKNOWN"); font.pixelSize: 9; Layout.fillWidth: true }
                MicroLabel { text: window.titleCase(window.telemetry.profile); color: window.accentColor; font.pixelSize: 9; font.letterSpacing: 0.7 }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 105
                color: window.panel
                radius: window.cornerRadius
                border.color: "#292e32"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        MicroLabel { text: qsTr("BATTERY") }
                        RowLayout {
                            spacing: 3
                            PlainLabel { objectName: "batteryReading"; text: window.number(window.telemetry.battery, 0); font.pixelSize: 35; font.weight: Font.Medium }
                            PlainLabel { text: "%"; visible: window.known(window.telemetry.battery); font.pixelSize: 15; color: window.muted; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 5 }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 3
                            color: "#3b4044"
                            Rectangle { width: parent.width * (window.known(window.telemetry.battery) ? Math.max(0, Math.min(100, window.telemetry.battery)) / 100 : 0); height: 3; color: window.accentColor }
                        }
                    }
                    Rectangle { implicitWidth: 1; Layout.fillHeight: true; color: window.line }
                    ColumnLayout {
                        implicitWidth: 105
                        spacing: 7
                        MicroLabel { text: qsTr("BATTERY POWER"); font.pixelSize: 8; font.letterSpacing: 0.8 }
                        PlainLabel { objectName: "wattsReading"; text: window.reading(window.telemetry.watts, " W", 1); font.pixelSize: 21 }
                        PlainLabel { text: qsTr("Health %1").arg(window.reading(window.telemetry.batteryHealth, "%", 0)); font.pixelSize: 10; color: window.muted; Layout.fillWidth: true }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                MetricCard { objectName: "cpuCard"; caption: qsTr("CPU"); value: window.reading(window.telemetry.cpuTemp, "°", 0); detail: qsTr("Processor temperature"); Layout.fillWidth: true; valueColor: window.known(window.telemetry.cpuTemp) && window.telemetry.cpuTemp > 90 ? "#e3a383" : window.ink }
                MetricCard { objectName: "gpuCard"; caption: qsTr("GPU"); value: window.reading(window.telemetry.gpuTemp, "°", 0); detail: window.titleCase(window.telemetry.gpuMode) + (window.known(window.telemetry.gpuPower) ? " · " + window.reading(window.telemetry.gpuPower, " W", 1) : ""); Layout.fillWidth: true }
            }
            Rectangle {
                implicitHeight: 54
                Layout.fillWidth: true
                color: window.panel
                radius: window.cornerRadius
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: window.known(window.telemetry.fanMid) ? 6 : 9
                    MicroLabel { visible: !window.known(window.telemetry.fanMid); text: qsTr("FANS"); font.pixelSize: 9 }
                    Item { Layout.fillWidth: true }
                    PlainLabel { text: "CPU"; color: window.muted; font.pixelSize: 10 }
                    PlainLabel { objectName: "cpuFanReading"; text: window.number(window.telemetry.fanCpu, 0); font.family: "monospace" }
                    Rectangle { implicitWidth: 1; implicitHeight: 15; color: window.line }
                    PlainLabel { text: "GPU"; color: window.muted; font.pixelSize: 10 }
                    PlainLabel { objectName: "gpuFanReading"; text: window.number(window.telemetry.fanGpu, 0); font.family: "monospace" }
                    Rectangle { visible: window.known(window.telemetry.fanMid); implicitWidth: 1; implicitHeight: 15; color: window.line }
                    PlainLabel { visible: window.known(window.telemetry.fanMid); text: "MID"; color: window.muted; font.pixelSize: 10 }
                    PlainLabel { objectName: "midFanReading"; visible: window.known(window.telemetry.fanMid); text: window.number(window.telemetry.fanMid, 0); font.family: "monospace" }
                    PlainLabel { text: "RPM"; color: window.muted; font.pixelSize: 8 }
                }
            }
            Rectangle {
                objectName: "pendingGpuBanner"
                visible: !!window.telemetry.pendingGpu
                Layout.fillWidth: true
                implicitHeight: pendingGpuText.implicitHeight + 18
                color: "#29271e"
                radius: window.cornerRadius
                border.color: "#4d4631"
                PlainLabel {
                    id: pendingGpuText
                    anchors.fill: parent
                    anchors.margins: 9
                    text: qsTr("%1 graphics queued · reboot required").arg(window.titleCase(window.telemetry.pendingGpu))
                    color: window.accentColor
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
            ColumnLayout {
                visible: window.expanded
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Repeater {
                        model: window.tabs
                        delegate: SmallButton {
                            required property int index
                            required property string modelData
                            objectName: "tab_" + index
                            text: modelData
                            Layout.fillWidth: true
                            implicitWidth: 0
                            implicitHeight: 32
                            leftPadding: 2
                            rightPadding: 2
                            font.pixelSize: 10
                            highlighted: window.selectedTab === index
                            onClicked: window.selectedTab = index
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
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ColumnLayout {
                        width: controlScroll.availableWidth
                        spacing: 8
                        Repeater {
                            model: window.filteredControls()
                            delegate: CapabilityRow { required property var modelData; control: modelData; Layout.fillWidth: true }
                        }
                        PlainLabel {
                            visible: window.filteredControls().length === 0
                            text: qsTr("No controls are exposed for this section.")
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                            color: window.muted
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                        }
                    }
                }
            }
            Item { visible: !window.expanded; Layout.fillHeight: true }
            PlainLabel {
                objectName: "statusMessage"
                text: window.telemetry.error || backend.message || qsTr("Changes are applied only when you choose Apply.")
                color: window.telemetry.error ? "#e3a383" : window.muted
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                maximumLineCount: 3
                Layout.fillWidth: true
            }
            SmallButton {
                objectName: "expandButton"
                Layout.fillWidth: true
                implicitHeight: 37
                text: window.expanded ? qsTr("Close controls  ↑") : qsTr("Open controls  ↓")
                onClicked: window.expanded = !window.expanded
            }
        }
    }
    Dialog {
        id: confirmation
        objectName: "confirmationDialog"
        anchors.centerIn: parent
        width: window.width - 36
        modal: true
        title: qsTr("Confirm change")
        standardButtons: Dialog.Apply | Dialog.Cancel
        padding: 18
        background: Rectangle { color: window.panel; radius: window.cornerRadius; border.color: window.line }
        contentItem: PlainLabel {
            text: window.pendingControl ? qsTr("Apply %1?").arg(window.pendingControl.label || window.pendingControl.id) + "\n\n" + (window.pendingControl.description || qsTr("This change may interrupt your current session.")) : ""
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
        }
        onApplied: {
            if (window.pendingControl) backend.setControl(window.pendingControl.id, window.pendingValue)
            close()
        }
        onClosed: { window.pendingControl = null; window.pendingValue = null }
    }
    Dialog {
        id: help
        objectName: "shortcutDialog"
        anchors.centerIn: parent
        width: window.width - 36
        modal: true
        title: qsTr("Keyboard shortcuts")
        standardButtons: Dialog.Close
        padding: 18
        background: Rectangle { color: window.panel; radius: window.cornerRadius; border.color: window.line }
        contentItem: ColumnLayout {
            spacing: 16
            Repeater {
                model: [{ key: "Space", label: qsTr("Refresh hardware status") }, { key: "Esc", label: qsTr("Close controls") }, { key: "?", label: qsTr("Show shortcuts") }, { key: "Q", label: qsTr("Quit ROG Companion") }]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    PlainLabel { text: modelData.label; Layout.fillWidth: true }
                    PlainLabel { text: modelData.key; color: window.accentColor; font.family: "monospace" }
                }
            }
        }
    }
}
