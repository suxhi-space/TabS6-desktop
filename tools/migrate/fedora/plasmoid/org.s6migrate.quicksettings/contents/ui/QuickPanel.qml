import QtQuick

// S6 Quick Settings: the panel that opens from the status icons, like Android's quick settings on a tablet:
// battery and shortcuts on top, brightness and sound sliders, then tiles. Colours come from the desktop theme
// (pal); the commands from the backend (state "st" and toggle/open/brightness/volume).
Item {
    id: qp
    property var backend
    property var pal
    readonly property var st: backend ? backend.st : ({})
    function on(k) { return st[k] === "on" }
    implicitWidth: 420
    implicitHeight: col.implicitHeight + 32
    Column {
        id: col
        x: 16; y: 16; width: parent.width - 32; spacing: 12
        // top: battery, then lock / settings / power
        Item {
            width: parent.width; height: 44
            Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: 8
                QsIcon { name: "battery"; level: parseInt(qp.st.battery) / 100; color: qp.pal.fg; width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parseInt(qp.st.battery) >= 0 ? qp.st.battery + "%" + (qp.on("charging") ? " · Charging" : "") : "Plugged in"
                    color: qp.pal.fg; font.pixelSize: 15; font.weight: Font.DemiBold
                }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Repeater {
                    model: [{ i: "lock", a: "lock" }, { i: "gear", a: "settings" }, { i: "power", a: "power" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 44; height: 44; radius: 22; color: bm.pressed ? qp.pal.tileIcon : qp.pal.tile
                        QsIcon { anchors.centerIn: parent; name: modelData.i; color: qp.pal.fg; width: 20; height: 20 }
                        MouseArea { id: bm; anchors.fill: parent; onClicked: qp.backend.open(modelData.a) }
                    }
                }
            }
        }
        QsSlider {
            width: parent.width; pal: qp.pal; icon: "sun"; minimum: 0.02
            value: (parseInt(qp.st.brightness) || 50) / 100
            onMoved: (v) => qp.backend.brightness(Math.round(v * 100), false)
            onReleased: (v) => qp.backend.brightness(Math.round(v * 100), true)
            onIconTapped: qp.backend.open("display")
        }
        QsSlider {
            width: parent.width; pal: qp.pal; icon: "sound"; iconOn: !qp.on("muted")
            value: qp.on("muted") ? 0 : (parseInt(qp.st.volume) || 0) / 100
            onMoved: (v) => qp.backend.volume(Math.round(v * 100), false)
            onReleased: (v) => qp.backend.volume(Math.round(v * 100), true)
            onIconTapped: qp.backend.toggle("mute")
        }
        Grid {
            id: tiles
            width: parent.width; columns: 2; columnSpacing: 10; rowSpacing: 10
            readonly property real cw: (width - columnSpacing) / 2
            QsTile { width: tiles.cw; pal: qp.pal; icon: "wifi"; label: "Wi-Fi"; more: true; on: qp.on("wifi")
                     sub: !qp.on("wifi") ? "Off" : (qp.st.ssid || "Not connected"); onToggled: qp.backend.toggle("wifi"); onOpened: qp.backend.open("wifi") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "bt"; label: "Bluetooth"; more: true; on: qp.on("bt")
                     sub: !qp.on("bt") ? "Off" : (qp.st.btdev || "On"); onToggled: qp.backend.toggle("bt"); onOpened: qp.backend.open("bt") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "dark"; label: "Dark mode"; on: qp.on("dark"); sub: qp.on("dark") ? "On" : "Off"; onToggled: qp.backend.toggle("dark") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "night"; label: "Night light"; on: qp.on("night"); sub: qp.on("night") ? "Warmer screen" : "Off"; onToggled: qp.backend.toggle("night") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "plane"; label: "Airplane mode"; on: qp.on("airplane"); sub: qp.on("airplane") ? "On" : "Off"; onToggled: qp.backend.toggle("airplane") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "saver"; label: "Battery saver"; on: qp.on("saver"); sub: qp.on("saver") ? "On" : "Off"; onToggled: qp.backend.toggle("saver") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "keyboard"; label: "Keyboard"; on: qp.on("keyboard"); sub: qp.on("keyboard") ? "When typing" : "Off"; onToggled: qp.backend.toggle("keyboard") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "shot"; label: "Screenshot"; sub: "Pick an area"; onToggled: qp.backend.open("screenshot") }
        }
    }
}
