import QtQuick
import QtQuick.Controls.Basic
import "."

// Labelled text field.
Column {
    id: f
    property alias label: lab.text
    property alias text: input.text
    property alias placeholder: input.placeholderText
    property alias echoMode: input.echoMode
    property alias input: input
    property string hint: ""
    property bool bad: false
    spacing: 6
    Label2 { id: lab; font.pixelSize: 14; strong: true; color: Theme.sub; width: f.width }
    TextField {
        id: input
        width: f.width
        height: 56
        font.family: Theme.body
        font.pixelSize: 18
        color: Theme.text
        placeholderTextColor: Theme.muted
        leftPadding: 14
        background: Rectangle {
            radius: 10; color: Theme.bg
            border.width: input.activeFocus ? 2 : 1
            border.color: f.bad ? Theme.warn : (input.activeFocus ? Theme.accent : Theme.border)
        }
    }
    Label2 { visible: f.hint !== ""; text: f.hint; font.pixelSize: 13; color: f.bad ? Theme.warn : Theme.muted; width: f.width }
}
