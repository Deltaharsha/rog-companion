import QtQuick
import QtTest
import QtQuick.Controls
import "../../src" as App
Item {
    QtObject {
        id: backend
        property var state: ({ model: "ROG Zephyrus G14 · GA403UV", cpuTemp: 47, gpuTemp: 39, battery: 78, batteryHealth: 97.2, watts: 12.4, fanCpu: 1800, fanGpu: 1600, profile: "balanced", gpuMode: "integrated", ac: true, updated: "16:52", error: "" })
        property var controls: [
            { id: "profile", label: "Performance mode", group: "Power", kind: "choice", value: "Balanced", available: true, options: [{label:"Silent", value:"Quiet"}, {label:"Balanced",value:"Balanced"},{label:"Turbo",value:"Performance"}] },
            { id: "gpu", label: "Graphics mode", group: "Power", kind: "choice", value: "hybrid", available: true, confirm: true, options: [{label:"Hybrid",value:"hybrid"},{label:"Integrated / Eco",value:"integrated"},{label:"NVIDIA / Ultimate",value:"ultimate"}] },
            { id: "charge", label: "Charge ceiling", group:"Power", kind:"number", value:80, min:20,max:100,step:1,unit:"%", available:true },
            { id: "boost", label: "CPU turbo boost",group:"Power",kind:"toggle",value:true,available:true },
            { id: "fan_cpu", label: "CPU fan curve",group:"Fans",kind:"text",value:"30c:10%,40c:20%,50c:30%,60c:40%,70c:55%,80c:70%,90c:90%,100c:100%",available:true,confirm:true },
            { id: "keyboard", label: "Keyboard brightness",group:"Lighting",kind:"number",value:1,min:0,max:3,available:true },
            { id: "slash", label: "Slash lighting",group:"Lighting",kind:"toggle",value:false,available:false, reason:"This model has no Slash bar." },
            { id: "reboot", label: "Restart computer",group:"System",kind:"action",available:true,confirm:true, description: "Save all work first." }
        ]
        property bool busy: false
        property string message: ""
        function refresh() {}
        function raisePanel(value) {}
        function quit() { Qt.quit() }
        function setControl(id, value) { calls.push({id:id, value:value}) }
        property var calls: []
    }
    property var panel: App.Main { visible: true }
    Component.onCompleted: panel.expanded = true
    TestCase {
        name: "RogCompanionPanel"
        when: windowShown
        function locate(name) {
            function visual(item) {
                if (!item) return null
                if (item.objectName === name) return item
                // Popups (menus) keep their items under contentItem, outside the children list.
                const list=(item.children || []).concat(item.contentItem && item.contentItem !== item ? [item.contentItem] : [])
                for (let i=0; i<list.length; ++i) { const found=visual(list[i]); if(found)return found }
                return null
            }
            return findChild(panel,name) || visual(panel.contentItem) || visual(panel.overlay)
        }
        // Rows for a newly selected tab get their real geometry on the next polish,
        // so wait until the target is laid out before clicking it.
        function tap(name) {
            let item = null
            tryVerify(function() { item = locate(name); return item !== null && item.visible && item.width > 20 && item.height > 10 }, 3000, "waiting for " + name)
            waitForRendering(item)
            mouseClick(item)
            return item
        }
        function init() { backend.calls = []; panel.expanded = true }
        function initTestCase() { tryVerify(function() { return locate("tab_1") !== null }) }

        function test_01_slider_applies_on_release() {
            tap("tab_0")
            let slider = null
            tryVerify(function() { slider = locate("slider_charge"); return slider !== null && slider.width > 100 })
            waitForRendering(slider)
            mouseClick(slider, slider.width * 0.3, slider.height / 2)
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"charge")
            verify(backend.calls[0].value < 80)
        }
        function test_02_risky_action_asks_first() {
            tap("tab_3")
            tap("action_reboot")
            const dialog=locate("confirmationDialog")
            tryCompare(dialog,"opened",true)
            compare(backend.calls.length,0)
            tap("confirmCancel")
            tryCompare(dialog,"visible",false)
            compare(backend.calls.length,0)
            tap("action_reboot")
            tryCompare(dialog,"opened",true)
            tap("confirmApply")
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"reboot")
            tryCompare(dialog,"visible",false)
        }
        function test_03_unknown_is_not_zero() {
            const saved = backend.state
            backend.state={battery:null, watts:null, fanCpu:null, fanGpu:null, cpuTemp:null,gpuTemp:null}
            compare(locate("batteryReading").text,"—")
            compare(locate("wattsReading").text,"—")
            compare(locate("cpuFanReading").text,"—")
            backend.state = saved
        }
        function test_04_profile_on_front_applies_instantly() {
            const profile=locate("choice_profile")
            verify(profile !== null && profile.visible)
            tap("segment_profile_2")
            compare(backend.calls.length,1)
            compare(backend.calls[0].value,"Performance")
        }
        function test_05_optional_gpu_and_middle_fan() {
            panel.expanded = false
            const saved = backend.state
            backend.state={gpuMode:"hybrid",gpuPower:8.5,fanMid:2100,pendingGpu:"integrated"}
            compare(locate("gpuCard").detail,"Hybrid · " + Number(8.5).toLocaleString(Qt.locale(),'f',1) + " W")
            tryCompare(locate("midFanReading"),"visible",true)
            compare(locate("pendingGpuBanner").visible,true)
            backend.state={gpuMode:"hybrid",gpuPower:null,fanMid:null,pendingGpu:""}
            compare(locate("gpuCard").detail,"Hybrid")
            compare(locate("midFanReading").visible,false)
            compare(locate("pendingGpuBanner").visible,false)
            backend.state = saved
        }
        function test_06_scroll() {
            tap("tab_0")
            const height = panel.height
            panel.height = 480
            const scroll=locate("controlScroll")
            tryVerify(function() { return scroll.contentHeight > scroll.height })
            panel.height = height
        }
        function test_07_toggle_applies_instantly() {
            tap("tab_0")
            tap("toggle_boost")
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"boost")
            compare(backend.calls[0].value,false)
        }
        function test_08_long_choice_menu_confirms_gpu() {
            tap("tab_0")
            const btn = tap("choice_gpu")
            const menu = btn.menu
            tryVerify(function() { return menu.opened })
            let option = null
            for (let i = 0; i < menu.count; i++) if (menu.itemAt(i).objectName === "option_gpu_integrated") option = menu.itemAt(i)
            verify(option !== null)
            waitForRendering(option)
            mouseClick(option)
            tryCompare(locate("confirmationDialog"),"opened",true)
            compare(backend.calls.length,0)
            tap("confirmApply")
            compare(backend.calls.length,1)
            compare(backend.calls[0].value,"integrated")
            tryCompare(locate("confirmationDialog"),"visible",false)
        }
        function test_09_typed_curve_needs_apply() {
            tap("tab_1")
            let field = null
            tryVerify(function() { field = locate("text_fan_cpu"); return field !== null && field.width > 100 })
            const apply=locate("apply_fan_cpu")
            compare(apply.visible,false)
            field.forceActiveFocus()
            field.selectAll()
            keyClick(Qt.Key_Backspace)
            field.insert(0, "30c:0%,40c:10%,50c:20%,60c:35%,70c:50%,80c:70%,90c:90%,100c:100%")
            field.textEdited()
            tryCompare(apply,"visible",true)
            compare(backend.calls.length,0)
            tap("apply_fan_cpu")
            tryCompare(locate("confirmationDialog"),"opened",true)
            tap("confirmApply")
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"fan_cpu")
            tryCompare(locate("confirmationDialog"),"visible",false)
        }
        function test_10_keyboard_levels_and_unavailable() {
            tap("tab_2")
            tap("segment_keyboard_3")
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"keyboard")
            compare(Number(backend.calls[0].value),3)
            compare(locate("toggle_slash").enabled,false)
        }
    }
}
