import QtQuick

// A rounded tile: icon, label and state; filled with the accent colour when on. Tap toggles; the arrow opens its page
// in the panel (Wi-Fi, Bluetooth); a long press opens its settings, like Android.
Rectangle {
    id: t
    property var pal
    property string icon
    property string label
    property string sub: ""
    property bool on: false
    property bool more: false
    signal toggled()
    signal opened()                    // the arrow: its page in the panel
    signal held()                      // long press: its System Settings page
    height: 64; radius: 22
    color: on ? pal.accent : pal.tile
    Behavior on color { ColorAnimation { duration: 140 } }
    scale: ma.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    Rectangle {
        id: dot
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: 42; height: 42; radius: 21
        color: t.on ? Qt.rgba(1, 1, 1, 0.22) : pal.tileIcon
        QsIcon { anchors.centerIn: parent; name: t.icon; on: t.on || t.icon !== "wifi"; color: t.on ? pal.accentFg : pal.fg; width: 20; height: 20 }
    }
    Column {
        anchors { left: dot.right; leftMargin: 10; right: chev.visible ? chev.left : parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        spacing: 1
        Text { width: parent.width; text: t.label; color: t.on ? pal.accentFg : pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
        Text { width: parent.width; visible: t.sub !== ""; text: t.sub; color: t.on ? Qt.rgba(pal.accentFg.r, pal.accentFg.g, pal.accentFg.b, 0.8) : pal.sub; font.pixelSize: 12; elide: Text.ElideRight }
    }
    MouseArea { id: ma; anchors.fill: parent; onClicked: t.toggled(); onPressAndHold: t.held() }
    Item {
        id: chev; visible: t.more
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 34
        QsIcon { anchors.centerIn: parent; name: "chev"; color: t.on ? pal.accentFg : pal.sub; width: 16; height: 16 }
        MouseArea { anchors.fill: parent; onClicked: t.opened(); onPressAndHold: t.held() }
    }
}
