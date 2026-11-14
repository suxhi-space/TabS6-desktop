import QtQuick
import QtQuick.Controls.Basic
import "."

// Primary (filled Fedora blue) or secondary (outlined) button, 48 px tall for touch.
Button {
    id: b
    property bool primary: false
    font.family: Theme.body
    font.pixelSize: 17
    font.weight: Font.DemiBold
    implicitHeight: 54
    leftPadding: 26; rightPadding: 26
    opacity: enabled ? 1 : 0.45
    contentItem: Text {
        text: b.text; font: b.font; color: b.primary ? Theme.accentFg : Theme.text
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 12
        color: b.primary ? (b.down ? Qt.darker(Theme.accent, 1.15) : Theme.accent) : (b.down ? Theme.sel : Theme.btn2Bg)
        border.width: b.primary ? 0 : 1
        border.color: Theme.btn2Border
    }
}
