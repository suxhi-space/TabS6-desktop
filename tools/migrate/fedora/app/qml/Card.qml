import QtQuick
import "."

// Rounded panel; "warn" gives the amber notice style. Content goes in a column.
Rectangle {
    id: card
    property bool warn: false
    property bool selected: false
    property int pad: 18
    default property alias content: col.data
    property alias spacing: col.spacing
    radius: 14
    color: warn ? Theme.warnBg : (selected ? Theme.sel : Theme.bg)
    border.width: selected ? 2 : 1
    border.color: warn ? Theme.warnBorder : (selected ? Theme.accent : Theme.border)
    implicitHeight: col.implicitHeight + 2 * pad
    Column {
        id: col
        x: card.pad; y: card.pad
        width: card.width - 2 * card.pad
        spacing: 8
    }
}
