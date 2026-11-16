import QtQuick
import QtQuick.Controls.Basic
import "."

// A field you tap to choose from a long list (time zones, languages): opens a full-height list with search.
// options: [{id, label}] ; value: the chosen id ; picked(id) when the user chooses.
Column {
    id: p
    property alias label: lab.text
    property string value: ""
    property var options: []
    property string hint: ""
    property string emptyText: "Choose..."
    property string searchHint: "Search"
    signal picked(string id)
    spacing: 6

    function labelFor(id) {
        for (var i = 0; i < options.length; i++) if (options[i].id === id) return options[i].label
        return id
    }
    property var shown: {
        var q = search.text.trim().toLowerCase()
        if (!q) return options
        return options.filter(function (o) { return o.label.toLowerCase().indexOf(q) >= 0 || o.id.toLowerCase().indexOf(q) >= 0 })
    }

    Label2 { id: lab; font.pixelSize: 14; strong: true; color: Theme.sub; width: p.width }
    Rectangle {
        width: p.width; height: 56; radius: 10
        color: Theme.bg; border.width: pop.opened ? 2 : 1; border.color: pop.opened ? Theme.accent : Theme.border
        Label2 {
            x: 14; width: parent.width - 56; anchors.verticalCenter: parent.verticalCenter
            text: p.value ? p.labelFor(p.value) : p.emptyText
            color: p.value ? Theme.text : Theme.muted
            font.pixelSize: 18; elide: Text.ElideRight; wrapMode: Text.NoWrap
        }
        Label2 { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: "▾"; color: Theme.sub; font.pixelSize: 20 }
        MouseArea { anchors.fill: parent; onClicked: pop.open() }
    }
    Label2 { visible: p.hint !== ""; text: p.hint; font.pixelSize: 13; color: Theme.muted; width: p.width }

    Popup {
        id: pop
        parent: Overlay.overlay
        modal: true; focus: true
        width: Math.min(parent ? parent.width - 32 : 600, 760)
        height: parent ? parent.height - 48 : 600
        x: parent ? (parent.width - width) / 2 : 0
        y: 24
        padding: 18
        background: Rectangle { radius: 16; color: Theme.bg; border.width: 1; border.color: Theme.border }
        onOpened: {
            search.text = ""
            for (var i = 0; i < p.options.length; i++) if (p.options[i].id === p.value) { list.positionViewAtIndex(i, ListView.Center); break }
        }
        contentItem: Item {
            Row {
                id: head; width: parent.width; spacing: 12
                Label2 { text: p.label; display: true; font.pixelSize: 22; width: parent.width - done.width - 12; anchors.verticalCenter: parent.verticalCenter }
                Btn { id: done; text: "Close"; onClicked: pop.close() }
            }
            Field { id: search; anchors.top: head.bottom; anchors.topMargin: 12; width: parent.width; placeholder: p.searchHint }
            ListView {
                id: list
                anchors.top: search.bottom; anchors.topMargin: 10; anchors.bottom: parent.bottom
                width: parent.width; clip: true
                model: p.shown
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    required property var modelData
                    width: list.width; height: 56; radius: 8
                    color: modelData.id === p.value ? Theme.sel : (ma.pressed ? Theme.hair : "transparent")
                    Label2 {
                        x: 12; width: parent.width - 24; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label; font.pixelSize: 17; elide: Text.ElideRight; wrapMode: Text.NoWrap
                        font.weight: modelData.id === p.value ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { id: ma; anchors.fill: parent; onClicked: { p.value = modelData.id; p.picked(modelData.id); pop.close() } }
                }
                Label2 { visible: list.count === 0; text: "Nothing matches \"" + search.text + "\"."; color: Theme.muted; width: parent.width }
            }
        }
    }
}
