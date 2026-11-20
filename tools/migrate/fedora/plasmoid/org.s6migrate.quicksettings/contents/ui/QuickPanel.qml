import QtQuick

// S6 Quick Settings: the control centre that opens from the status icons, like Googlebook's and macOS's: customise,
// settings, battery and power on top; brightness (dark theme beside it) and sound (mute beside it); then your tiles,
// which you choose and order in edit mode. A tile's arrow opens its page here
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

    // ---------------------------------------------------------------- the tiles you can have (edit mode adds and removes them)
    readonly property var defaults: ["wifi", "bt", "dark", "night", "airplane", "saver", "keyboard", "shot"]
    readonly property var all: ["wifi", "bt", "dark", "night", "airplane", "saver", "keyboard", "shot", "usb", "mic"]
    readonly property var order: { var t = (st.tiles || "").split(",").filter(function (x) { return qp.all.indexOf(x) >= 0 }); return t.length ? t : defaults }
    property bool editing: false
    function setOrder(list) { if (backend) backend.saveTiles(list) }
    function def(id) {
        switch (id) {
        case "wifi": return { icon: "wifi", label: "Wi-Fi", more: true, on: on("wifi"), sub: !on("wifi") ? "Off" : (st.ssid || "Not connected"), page: "wifi", kcm: "wifi" }
        case "bt": return { icon: "bt", label: "Bluetooth", more: true, on: on("bt"), sub: !on("bt") ? "Off" : (st.btdev || "On"), page: "bt", kcm: "bt" }
        case "dark": return { icon: "dark", label: "Dark theme", on: on("dark"), sub: on("dark") ? "On" : "Off", kcm: "colors" }
        case "night": return { icon: "night", label: "Night light", on: on("night"), sub: on("night") ? "Warmer screen" : "Off", kcm: "night" }
        case "airplane": return { icon: "plane", label: "Airplane mode", on: on("airplane"), sub: on("airplane") ? "On" : "Off", kcm: "wifi" }
        case "saver": return { icon: "saver", label: "Battery saver", on: on("saver"), sub: on("saver") ? "On" : "Off", kcm: "battery" }
        case "keyboard": return { icon: "keyboard", label: "Keyboard", on: on("keyboard"), sub: on("keyboard") ? "When typing" : "Off", kcm: "keyboard" }
        case "shot": return { icon: "shot", label: "Screen capture", on: false, sub: "Pick an area", kcm: "screenshot", action: "screenshot" }
        case "usb": return { icon: "usb", label: "USB devices", on: on("usb"), sub: on("usb") ? "Drives, hubs, keyboards" : "Off", kcm: "settings" }
        case "mic": return { icon: "mic", label: "Microphone", on: on("mic"), sub: on("mic") ? "Available" : "Muted", kcm: "sound" }
        }
        return { icon: "gear", label: id, on: false, sub: "" }
    }

    // ---------------------------------------------------------------- the main page
    Column {
        id: main
        x: qp.page === "main" ? 16 : -qp.width; y: 16; width: qp.width - 32; spacing: 12
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        // top: customise and settings on the left, battery and power on the right
        Item {
            width: parent.width; height: 40
            Row {
                spacing: 8; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ i: "edit", a: "edit" }, { i: "gear", a: "settings" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 40; height: 40; radius: 20
                        color: (modelData.a === "edit" && qp.editing) ? qp.pal.onTile : (hm.pressed ? qp.pal.tileIcon : "transparent")
                        QsIcon { anchors.centerIn: parent; name: modelData.i; width: 20; height: 20
                                 color: (modelData.a === "edit" && qp.editing) ? qp.pal.onInk : qp.pal.fg }
                        MouseArea { id: hm; anchors.fill: parent; onClicked: modelData.a === "edit" ? (qp.editing = !qp.editing) : qp.backend.open(modelData.a) }
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                Rectangle {
                    height: 32; width: bt.implicitWidth + 40; radius: 16; color: qp.pal.tile; anchors.verticalCenter: parent.verticalCenter
                    Row { anchors.centerIn: parent; spacing: 6
                          QsIcon { name: "battery"; level: parseInt(qp.st.battery) / 100; color: qp.pal.fg; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                          Text { id: bt; anchors.verticalCenter: parent.verticalCenter; color: qp.pal.fg; font.pixelSize: 13; font.weight: Font.DemiBold
                                 text: parseInt(qp.st.battery) >= 0 ? qp.st.battery + "%" + (qp.on("charging") ? " · charging" : "") : "Plugged in" } }
                }
                Repeater {
                    model: [{ i: "lock", a: "lock" }, { i: "power", a: "power" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 40; height: 40; radius: 20; color: pm.pressed ? qp.pal.tileIcon : qp.pal.tile
                        QsIcon { anchors.centerIn: parent; name: modelData.i; color: qp.pal.fg; width: 18; height: 18 }
                        MouseArea { id: pm; anchors.fill: parent; onClicked: qp.backend.open(modelData.a) }
                    }
                }
            }
        }
        // brightness (dark theme beside it) and sound (mute beside it), like Googlebook
        Repeater {
            model: ["brightness", "volume"]
            delegate: Item {
                required property string modelData
                readonly property bool isB: modelData === "brightness"
                width: main.width; height: 48
                QsSlider {
                    width: parent.width - 58; pal: qp.pal; icon: parent.isB ? "sun" : "sound"; minimum: parent.isB ? 0.02 : 0
                    iconOn: parent.isB || !qp.on("muted")
                    value: parent.isB ? (parseInt(qp.st.brightness) || 50) / 100 : (qp.on("muted") ? 0 : (parseInt(qp.st.volume) || 0) / 100)
                    onMoved: (v) => parent.isB ? qp.backend.brightness(Math.round(v * 100), false) : qp.backend.volume(Math.round(v * 100), false)
                    onReleased: (v) => parent.isB ? qp.backend.brightness(Math.round(v * 100), true) : qp.backend.volume(Math.round(v * 100), true)
                    onIconTapped: qp.backend.open(parent.isB ? "display" : "sound")
                }
                Rectangle {
                    readonly property bool lit: parent.isB ? qp.on("dark") : qp.on("muted")
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: 48; height: 48; radius: 24; color: lit ? qp.pal.onTile : qp.pal.tile
                    QsIcon { anchors.centerIn: parent; width: 20; height: 20; name: parent.parent.isB ? "dark" : "sound"
                             on: parent.parent.isB || !qp.on("muted"); color: parent.lit ? qp.pal.onInk : qp.pal.fg }
                    MouseArea { anchors.fill: parent; onClicked: qp.backend.toggle(parent.parent.isB ? "dark" : "mute")
                                onPressAndHold: qp.backend.open(parent.parent.isB ? "colors" : "sound") }
                }
            }
        }
        Grid {
            id: tiles
            width: parent.width; columns: 2; columnSpacing: 10; rowSpacing: 10
            readonly property real cw: (width - columnSpacing) / 2
            Repeater {
                model: qp.order
                delegate: QsTile {
                    required property string modelData
                    readonly property var d: qp.def(modelData)
                    width: tiles.cw; pal: qp.pal; editing: qp.editing
                    icon: d.icon; label: d.label; sub: d.sub; on: d.on; more: !!d.more
                    onToggled: d.action ? qp.backend.open(d.action) : qp.backend.toggle(modelData)
                    onOpened: qp.show(d.page)
                    onHeld: qp.backend.open(d.kcm)
                    onRemoved: qp.setOrder(qp.order.filter(function (x) { return x !== modelData }))
                }
            }
        }
        // edit mode: the tiles you could add, and done
        Column {
            visible: qp.editing
            width: parent.width; spacing: 8
            Text { text: "Add tiles"; color: qp.pal.sub; font.pixelSize: 13; font.weight: Font.DemiBold }
            Flow {
                width: parent.width; spacing: 8
                Repeater {
                    model: qp.all.filter(function (x) { return qp.order.indexOf(x) < 0 })
                    delegate: Rectangle {
                        required property string modelData
                        height: 36; width: ar.implicitWidth + 24; radius: 18; color: am.pressed ? qp.pal.tileIcon : qp.pal.tile
                        Row { id: ar; anchors.centerIn: parent; spacing: 6
                              QsIcon { name: "plus"; color: qp.pal.fg; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter }
                              Text { text: qp.def(modelData).label; color: qp.pal.fg; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { id: am; anchors.fill: parent; onClicked: qp.setOrder(qp.order.concat([modelData])) }
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.Wrap; color: qp.pal.sub; font.pixelSize: 12
                   text: "Tap a tile to remove it; added tiles go to the end. Your tiles stay when you change the layout." }
            Rectangle {
                width: parent.width; height: 40; radius: 20; color: qp.pal.onTile
                Text { anchors.centerIn: parent; text: "Done"; color: qp.pal.onInk; font.pixelSize: 14; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; onClicked: qp.editing = false }
            }
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
                width: 56; height: 32; radius: 16; color: detail.radioOn ? qp.pal.onTile : qp.pal.tileIcon
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle { width: 24; height: 24; radius: 12; y: 4; x: detail.radioOn ? parent.width - 28 : 4
                            color: detail.radioOn ? qp.pal.onInk : qp.pal.fg
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
                color: active ? qp.pal.onTile : (rowMa.pressed ? qp.pal.tileIcon : qp.pal.tile)
                QsIcon {
                    x: 14; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
                    name: detail.wifi ? "wifi" : (/audio|head/.test(modelData.icon) ? "headset" : /input|keyboard|mouse/.test(modelData.icon) ? "keyboard" : /phone/.test(modelData.icon) ? "device" : "bt")
                    level: detail.wifi ? modelData.signal / 100 : -1
                    color: parent.active ? qp.pal.onInk : qp.pal.fg
                }
                Column {
                    anchors { left: parent.left; leftMargin: 48; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Text { width: parent.width; text: detail.wifi ? modelData.ssid : modelData.name; elide: Text.ElideRight
                           color: active ? qp.pal.onInk : qp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12
                           color: active ? Qt.rgba(qp.pal.onInk.r, qp.pal.onInk.g, qp.pal.onInk.b, 0.75) : qp.pal.sub
                           text: detail.wifi ? (active ? "Connected" : modelData.saved ? "Saved" : modelData.secure ? "Secured" : "Open")
                                             : (active ? "Connected" : "Paired") }
                }
                Row {
                    id: tail
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    QsIcon { visible: detail.wifi && modelData.secure && !active; name: "lock"; width: 14; height: 14; color: qp.pal.sub; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: active; text: detail.wifi ? "Disconnect" : "Disconnect"; font.pixelSize: 12; font.weight: Font.DemiBold
                           color: qp.pal.onInk; anchors.verticalCenter: parent.verticalCenter }
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
