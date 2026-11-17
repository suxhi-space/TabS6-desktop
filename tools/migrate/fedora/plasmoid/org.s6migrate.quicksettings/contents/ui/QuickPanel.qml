import QtQuick

// S6 Quick Settings: the panel that opens from the status icons, like Android's quick settings on a tablet:
// battery and shortcuts on top, brightness and sound sliders, then tiles. A tile's arrow opens its page here
// (Wi-Fi networks, Bluetooth devices); holding a tile opens its System Settings page. Colours come from the
// desktop theme (pal); the commands from the backend.
Item {
    id: qp
    property var backend
    property var pal
    readonly property var st: backend ? backend.st : ({})
    property string page: "main"          // main | wifi | bt
    function on(k) { return st[k] === "on" }
    function show(p) { page = p; if (backend) backend.pageShown(p) }
    implicitWidth: 420
    implicitHeight: main.implicitHeight + 32
    clip: true

    // ---------------------------------------------------------------- the main page
    Column {
        id: main
        x: qp.page === "main" ? 16 : -qp.width; y: 16; width: qp.width - 32; spacing: 12
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        // top: battery, then lock / settings / power
        Item {
            width: parent.width; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter; spacing: 8
                QsIcon { name: "battery"; level: parseInt(qp.st.battery) / 100; color: qp.pal.fg; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parseInt(qp.st.battery) >= 0 ? qp.st.battery + "%" + (qp.on("charging") ? " · Charging" : "") : "Plugged in"
                    color: qp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold
                }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Repeater {
                    model: [{ i: "lock", a: "lock" }, { i: "gear", a: "settings" }, { i: "power", a: "power" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 40; height: 40; radius: 20; color: bm.pressed ? qp.pal.tileIcon : qp.pal.tile
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
                     sub: !qp.on("wifi") ? "Off" : (qp.st.ssid || "Not connected")
                     onToggled: qp.backend.toggle("wifi"); onOpened: qp.show("wifi"); onHeld: qp.backend.open("wifi") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "bt"; label: "Bluetooth"; more: true; on: qp.on("bt")
                     sub: !qp.on("bt") ? "Off" : (qp.st.btdev || "On")
                     onToggled: qp.backend.toggle("bt"); onOpened: qp.show("bt"); onHeld: qp.backend.open("bt") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "dark"; label: "Dark mode"; on: qp.on("dark"); sub: qp.on("dark") ? "On" : "Off"
                     onToggled: qp.backend.toggle("dark"); onHeld: qp.backend.open("colors") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "night"; label: "Night light"; on: qp.on("night"); sub: qp.on("night") ? "Warmer screen" : "Off"
                     onToggled: qp.backend.toggle("night"); onHeld: qp.backend.open("night") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "plane"; label: "Airplane mode"; on: qp.on("airplane"); sub: qp.on("airplane") ? "On" : "Off"
                     onToggled: qp.backend.toggle("airplane"); onHeld: qp.backend.open("wifi") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "saver"; label: "Battery saver"; on: qp.on("saver"); sub: qp.on("saver") ? "On" : "Off"
                     onToggled: qp.backend.toggle("saver"); onHeld: qp.backend.open("battery") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "keyboard"; label: "Keyboard"; on: qp.on("keyboard"); sub: qp.on("keyboard") ? "When typing" : "Off"
                     onToggled: qp.backend.toggle("keyboard"); onHeld: qp.backend.open("keyboard") }
            QsTile { width: tiles.cw; pal: qp.pal; icon: "shot"; label: "Screenshot"; sub: "Pick an area"
                     onToggled: qp.backend.open("screenshot"); onHeld: qp.backend.open("screenshot") }
        }
    }

    // ---------------------------------------------------------------- a tile's page: Wi-Fi networks or Bluetooth devices
    Item {
        id: detail
        x: qp.page === "main" ? qp.width : 0; y: 0; width: qp.width; height: qp.height
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        readonly property bool wifi: qp.page === "wifi" || (qp.page === "main" && lastWifi)
        property bool lastWifi: true
        Connections { target: qp; function onPageChanged() { if (qp.page !== "main") detail.lastWifi = qp.page === "wifi" } }
        readonly property bool radioOn: wifi ? qp.on("wifi") : qp.on("bt")

        // header: back, title, on/off
        Item {
            id: head
            x: 16; y: 16; width: parent.width - 32; height: 40
            Rectangle {
                id: back; width: 40; height: 40; radius: 20; color: backMa.pressed ? qp.pal.tileIcon : qp.pal.tile
                QsIcon { anchors.centerIn: parent; name: "back"; color: qp.pal.fg; width: 20; height: 20 }
                MouseArea { id: backMa; anchors.fill: parent; onClicked: qp.show("main") }
            }
            Text { anchors.left: back.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                   text: detail.wifi ? "Wi-Fi" : "Bluetooth"; color: qp.pal.fg; font.pixelSize: 17; font.weight: Font.DemiBold }
            Rectangle {   // refresh (Wi-Fi: look for networks again)
                visible: detail.wifi && detail.radioOn
                anchors.right: sw.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20; color: rfMa.pressed ? qp.pal.tileIcon : qp.pal.tile
                QsIcon { anchors.centerIn: parent; name: "refresh"; color: qp.pal.fg; width: 18; height: 18
                         RotationAnimation on rotation { running: qp.backend.scanning; from: 0; to: 360; duration: 900; loops: Animation.Infinite } }
                MouseArea { id: rfMa; anchors.fill: parent; onClicked: qp.backend.scanWifi() }
            }
            Rectangle {   // the switch
                id: sw
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 56; height: 32; radius: 16; color: detail.radioOn ? qp.pal.accent : qp.pal.tileIcon
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle { width: 24; height: 24; radius: 12; y: 4; x: detail.radioOn ? parent.width - 28 : 4
                            color: detail.radioOn ? qp.pal.accentFg : qp.pal.fg
                            Behavior on x { NumberAnimation { duration: 140 } } }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: qp.backend.toggle(detail.wifi ? "wifi" : "bt") }
            }
        }

        ListView {
            id: list
            anchors { top: head.bottom; topMargin: 12; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; bottom: foot.top; bottomMargin: 10 }
            clip: true; spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: !detail.radioOn ? [] : detail.wifi ? qp.backend.nets : qp.backend.devs
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: detail.wifi ? modelData.active : modelData.connected
                width: list.width; height: 56; radius: 18
                color: active ? qp.pal.accent : (rowMa.pressed ? qp.pal.tileIcon : qp.pal.tile)
                QsIcon {
                    x: 14; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
                    name: detail.wifi ? "wifi" : (/audio|head/.test(modelData.icon) ? "headset" : /input|keyboard|mouse/.test(modelData.icon) ? "keyboard" : /phone/.test(modelData.icon) ? "device" : "bt")
                    level: detail.wifi ? modelData.signal / 100 : -1
                    color: parent.active ? qp.pal.accentFg : qp.pal.fg
                }
                Column {
                    anchors { left: parent.left; leftMargin: 48; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Text { width: parent.width; text: detail.wifi ? modelData.ssid : modelData.name; elide: Text.ElideRight
                           color: active ? qp.pal.accentFg : qp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12
                           color: active ? Qt.rgba(qp.pal.accentFg.r, qp.pal.accentFg.g, qp.pal.accentFg.b, 0.8) : qp.pal.sub
                           text: detail.wifi ? (active ? "Connected" : modelData.saved ? "Saved" : modelData.secure ? "Secured" : "Open")
                                             : (active ? "Connected" : "Paired") }
                }
                Row {
                    id: tail
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    QsIcon { visible: detail.wifi && modelData.secure && !active; name: "lock"; width: 14; height: 14; color: qp.pal.sub; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: active; text: detail.wifi ? "Disconnect" : "Disconnect"; font.pixelSize: 12; font.weight: Font.DemiBold
                           color: qp.pal.accentFg; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: rowMa; anchors.fill: parent
                    onClicked: detail.wifi ? (parent.active ? qp.backend.disconnectWifi() : qp.backend.connectWifi(modelData.ssid))
                                           : qp.backend.btConnect(modelData.mac, !parent.active)
                    onPressAndHold: qp.backend.open(detail.wifi ? "wifi" : "bt")
                }
            }
            Text {
                visible: list.count === 0
                anchors.centerIn: parent; width: parent.width * 0.85; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                color: qp.pal.sub; font.pixelSize: 13
                text: !detail.radioOn ? (detail.wifi ? "Wi-Fi is off." : "Bluetooth is off.")
                      : detail.wifi ? (qp.backend.scanning ? "Looking for networks..." : "No networks found. Tap ⟳ to look again.")
                      : "No paired devices yet. Pair one in Bluetooth settings below."
            }
        }

        Rectangle {   // more: the System Settings page
            id: foot
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16; x: 16; width: parent.width - 32; height: 44; radius: 22
            color: ftMa.pressed ? qp.pal.tileIcon : qp.pal.tile
            Text { anchors.centerIn: parent; text: detail.wifi ? "Wi-Fi settings" : "Pair a new device"
                   color: qp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold }
            MouseArea { id: ftMa; anchors.fill: parent; onClicked: qp.backend.open(detail.wifi ? "wifi" : "bt") }
        }
    }
}
