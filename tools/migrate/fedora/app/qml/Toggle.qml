import QtQuick
import "."

// A row with a title, an optional note and a switch on the right (the whole row is tappable).
Item {
    id: t
    property string title
    property string sub: ""
    property bool checked: false
    implicitHeight: Math.max(58, col.implicitHeight + 18)
    Column {
        id: col
        anchors.left: parent.left; anchors.right: sw.left; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Label2 { text: t.title; width: parent.width }
        Label2 { visible: t.sub !== ""; text: t.sub; font.pixelSize: 13; color: Theme.muted; width: parent.width }
    }
    Rectangle {
        id: sw
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: 58; height: 34; radius: 17
        color: t.checked ? Theme.accent : Theme.track
        Rectangle { width: 28; height: 28; radius: 14; y: 3; x: t.checked ? 27 : 3; color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 120 } } }
    }
    MouseArea { anchors.fill: parent; onClicked: t.checked = !t.checked }
}
