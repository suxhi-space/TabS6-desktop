import QtQuick
import "."

// Text in the theme's body font; wraps by default.
Text {
    property bool strong: false
    property bool display: false
    color: Theme.text
    font.family: display ? Theme.display : Theme.body
    font.pixelSize: 17
    font.weight: display ? Font.Bold : (strong ? Font.DemiBold : Font.Normal)
    wrapMode: Text.WordWrap
    lineHeight: 1.18
    linkColor: Theme.link
    onLinkActivated: (l) => Qt.openUrlExternally(l)
}
