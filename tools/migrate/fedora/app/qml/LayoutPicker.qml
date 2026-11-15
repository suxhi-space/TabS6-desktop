import QtQuick
import "."

// Pick a desktop layout: drawings with plain names (no brand look-alikes).
Grid {
    id: lp
    property string value: "touch"
    property string effects: "soft"
    signal picked(string id)
    readonly property var options: [
        { id: "touch", name: "Touch", sub: "One big floating bar, made for fingers" },
        { id: "centered", name: "Centered taskbar", sub: "App icons in the middle of the bottom bar" },
        { id: "traditional", name: "Traditional", sub: "Menu on the left, window names in the bar" },
        { id: "topdock", name: "Top bar and dock", sub: "Menu and clock on top, a dock below" },
        { id: "plasma", name: "Plasma default", sub: "KDE's standard desktop" }]
    columns: width >= 640 ? 3 : 2
    columnSpacing: 14; rowSpacing: 14
    readonly property real cw: (width - columnSpacing * (columns - 1)) / columns
    Repeater {
        model: lp.options
        delegate: Rectangle {
            width: lp.cw; height: col.implicitHeight + 24
            radius: 14
            color: lp.value === modelData.id ? Theme.sel : Theme.bg
            border.width: lp.value === modelData.id ? 2 : 1
            border.color: lp.value === modelData.id ? Theme.accent : Theme.border
            Column {
                id: col
                x: 12; y: 12; width: parent.width - 24; spacing: 10
                LayoutPreview { layout: modelData.id; effects: lp.effects; width: parent.width; height: width * 0.5 }
                Row {
                    spacing: 10; width: parent.width
                    Glyph { kind: lp.value === modelData.id ? "radioOn" : "radio"; width: 20; height: 20; y: 2 }
                    Column {
                        width: parent.width - 30
                        Label2 { text: modelData.name; strong: true; width: parent.width }
                        Label2 { text: modelData.sub; font.pixelSize: 14; color: Theme.muted; width: parent.width }
                    }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: { lp.value = modelData.id; lp.picked(modelData.id) } }
        }
    }
}
