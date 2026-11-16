import QtQuick
import "."

// A label, a row of pill segments (one is picked) and a line about the picked one, like Android/KDE settings.
Column {
    id: sg
    property string label: ""
    property var options: []          // [{ id, label, sub }]
    property string value: ""
    signal picked(string id)
    spacing: 8
    function current() { for (var i = 0; i < options.length; i++) if (options[i].id === value) return options[i]; return null }
    Label2 { visible: sg.label !== ""; text: sg.label; strong: true; color: Theme.sub; font.pixelSize: 14; width: sg.width }
    Rectangle {
        width: sg.width; height: 44; radius: 22
        color: Theme.track
        Row {
            anchors.fill: parent; anchors.margins: 4
            Repeater {
                model: sg.options
                delegate: Rectangle {
                    required property var modelData
                    width: (sg.width - 8) / sg.options.length; height: 36; radius: 18
                    color: sg.value === modelData.id ? Theme.card : "transparent"
                    border.width: sg.value === modelData.id ? 1 : 0; border.color: Theme.cardBorder
                    Label2 {
                        anchors.centerIn: parent; text: modelData.label; font.pixelSize: 15; wrapMode: Text.NoWrap
                        strong: sg.value === modelData.id; color: sg.value === modelData.id ? Theme.accentText : Theme.sub
                    }
                    MouseArea { anchors.fill: parent; onClicked: { sg.value = modelData.id; sg.picked(modelData.id) } }
                }
            }
        }
    }
    Label2 {
        property var c: sg.current()
        visible: !!(c && c.sub); text: c && c.sub ? c.sub : ""
        font.pixelSize: 13; color: Theme.muted; width: sg.width; elide: Text.ElideRight; wrapMode: Text.NoWrap
    }
}
