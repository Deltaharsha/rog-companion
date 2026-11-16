import QtQuick
import QtTest
import QtQuick.Controls
import "../../src" as App
Item {
    QtObject {
        id: backend
        property var state: ({ model: "ROG Zephyrus G14 · GA403UV", cpuTemp: 47, gpuTemp: 39, battery: 78, batteryHealth: 97.2, watts: 12.4, fanCpu: 1800, fanGpu: 1600, profile: "balanced", gpuMode: "integrated", ac: true, updated: "16:52", error: "" })
        property var controls: [
            { id: "profile", label: "Performance mode", group: "Power", kind: "choice", value: "balanced", available: true, options: [{label:"Quiet", value:"quiet"}, {label:"Balanced",value:"balanced"},{label:"Performance",value:"performance"}] },
            { id: "gpu", label: "GPU mode", group: "Power", kind: "choice", value: "eco", available: true, confirm: true, options: [{label:"Eco · integrated",value:"eco"},{label:"Hybrid",value:"hybrid"}] },
            { id: "charge", label: "Charge limit", group:"Power", kind:"number", value:80, min:40,max:100,step:5,unit:"%", available:true, description:"Stop charging at this battery level." },
            { id: "curve", label: "CPU fan curve",group:"Fans",kind:"text",value:"30c:0%,50c:20%,70c:60%",available:true },
            { id: "boost", label: "CPU boost",group:"Power",kind:"toggle",value:true,available:true },
            { id: "reset", label: "Reset tuning",group:"System",kind:"action",available:true,confirm:true },
            { id: "led", label: "Anime Matrix",group:"Lighting",kind:"toggle",value:false,available:false, reason:"This model does not have an AniMe Matrix display." }
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
                if (item.objectName === name) return item
                const list=item.children || []
                for (let i=0; i<list.length; ++i) { const found=visual(list[i]); if(found)return found }
                return null
            }
            return findChild(panel,name) || visual(panel.contentItem)
        }
        function initTestCase() { tryVerify(function() { return locate("tab_1") !== null }) }
        function test_01_slider_requires_apply() {
            mouseClick(locate("tab_1"))
            const slider=locate("slider_charge")
            verify(slider !== null)
            mouseClick(slider, slider.width * 0.3, slider.height / 2)
            compare(backend.calls.length,0)
            const apply=locate("apply_charge")
            verify(apply.enabled)
            mouseClick(apply)
            compare(backend.calls.length,1)
            compare(backend.calls[0].id,"charge")
        }
        function test_02_confirmation() {
            mouseClick(locate("tab_4"))
            mouseClick(locate("action_reset"))
            const dialog=locate("confirmationDialog")
            tryCompare(dialog,"opened",true)
            compare(backend.calls.length,1)
            mouseClick(dialog.standardButton(Dialog.Cancel))
            tryCompare(dialog,"opened",false)
            tryCompare(dialog,"visible",false)
            compare(backend.calls.length,1)
            mouseClick(locate("action_reset"))
            tryCompare(dialog,"opened",true)
            mouseClick(dialog.standardButton(Dialog.Apply))
            compare(backend.calls.length,2)
            compare(backend.calls[1].id,"reset")
            tryCompare(dialog,"visible",false)
        }
        function test_03_unknown_is_not_zero() {
            backend.state={battery:null, watts:null, fanCpu:null, fanGpu:null, cpuTemp:null,gpuTemp:null}
            compare(locate("batteryReading").text,"—")
            compare(locate("wattsReading").text,"—")
            compare(locate("cpuFanReading").text,"—")
        }
        function test_04_overview_includes_graphics() {
            mouseClick(locate("tab_0"))
            verify(locate("choice_gpu") !== null)
        }
        function test_05_optional_gpu_and_middle_fan() {
            backend.state={gpuMode:"hybrid",gpuPower:8.5,fanMid:2100,pendingGpu:"integrated"}
            compare(locate("gpuCard").detail,"Hybrid · " + Number(8.5).toLocaleString(Qt.locale(),'f',1) + " W")
            compare(locate("midFanReading").visible,true)
            compare(locate("pendingGpuBanner").visible,true)
            backend.state={gpuMode:"hybrid",gpuPower:null,fanMid:null,pendingGpu:""}
            compare(locate("gpuCard").detail,"Hybrid")
            compare(locate("midFanReading").visible,false)
            compare(locate("pendingGpuBanner").visible,false)
        }
        function test_06_scroll() {
            mouseClick(locate("tab_1"))
            const scroll=locate("controlScroll")
            tryVerify(function() { return scroll.contentHeight > scroll.height })
        }
    }
}
