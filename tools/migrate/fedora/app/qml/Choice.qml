import QtQuick
import "."

// A selectable card with a radio mark, a title and a line under it.
Rectangle {
    id: c
    property string title
    property string sub: ""
    property bool on: false
    signal picked()
    radius: 14
    color: on ? Theme.sel : Theme.bg
    border.width: on ? 2 : 1
    border.color: on ? Theme.accent : Theme.border
    implicitHeight: Math.max(62, row.implicitHeight + 32)
    opacity: enabled ? 1 : 0.5
    Row {
        id: row
        x: 18; y: 16; spacing: 12
        width: c.width - 32
        Glyph { kind: c.on ? "radioOn" : "radio"; width: 20; height: 20; y: 1 }
        Column {
            width: row.width - 32; spacing: 2
            Label2 { text: c.title; strong: true; width: parent.width }
            Label2 { visible: c.sub !== ""; text: c.sub; font.pixelSize: 14; color: Theme.muted; width: parent.width }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: c.picked() }
}
