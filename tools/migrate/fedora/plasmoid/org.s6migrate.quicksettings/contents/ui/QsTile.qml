import QtQuick

// A pill tile, like Googlebook and macOS: an icon in a circle, label and state; light when on. Tap toggles; the
// arrow opens its page in the panel (Wi-Fi, Bluetooth); a long press opens its settings, like Android.
// In edit mode (customising the panel) a tap removes it instead.
Rectangle {
    id: t
    property var pal
    property string icon
    property string label
    property string sub: ""
    property bool on: false
    property bool more: false
    property bool editing: false
    signal toggled()
    signal opened()                    // the arrow: its page in the panel
    signal held()                      // long press: its System Settings page
    signal removed()                   // edit mode
    height: 60; radius: 30
    color: on ? pal.onTile : pal.tile
    Behavior on color { ColorAnimation { duration: 140 } }
    scale: ma.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    readonly property color ink: on ? pal.onInk : pal.fg
    Rectangle {
        id: dot
        x: 8; anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 44; radius: 22
        color: t.on ? Qt.rgba(t.ink.r, t.ink.g, t.ink.b, 0.10) : pal.tileIcon
        QsIcon { anchors.centerIn: parent; name: t.icon; on: t.on || (t.icon !== "wifi" && t.icon !== "mic"); color: t.ink; width: 20; height: 20 }
    }
    Column {
        anchors { left: dot.right; leftMargin: 10; right: chev.visible ? chev.left : parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 1
        Text { width: parent.width; text: t.label; color: t.ink; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
        Text { width: parent.width; visible: t.sub !== ""; text: t.sub; color: Qt.rgba(t.ink.r, t.ink.g, t.ink.b, 0.72); font.pixelSize: 12; elide: Text.ElideRight }
    }
    MouseArea { id: ma; anchors.fill: parent; onClicked: t.editing ? t.removed() : t.toggled(); onPressAndHold: if (!t.editing) t.held() }
    Item {
        id: chev; visible: t.more && !t.editing
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 36
        QsIcon { anchors.centerIn: parent; name: "chev"; color: Qt.rgba(t.ink.r, t.ink.g, t.ink.b, 0.7); width: 16; height: 16 }
        MouseArea { anchors.fill: parent; onClicked: t.opened(); onPressAndHold: t.held() }
    }
    Rectangle {   // edit mode: remove
        visible: t.editing
        anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 26; radius: 13; color: Qt.rgba(t.ink.r, t.ink.g, t.ink.b, 0.14)
        QsIcon { anchors.centerIn: parent; name: "close"; color: t.ink; width: 12; height: 12 }
    }
}
