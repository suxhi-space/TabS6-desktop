import QtQuick
import "."

// A small drawing of a desktop layout: screen, windows, and where the bars and icons go.
Rectangle {
    id: pv
    property string layout: "touch"
    property string effects: "on"       // on | off: how see-through the bars are
    readonly property real barOpacity: effects === "off" ? 1.0 : 0.85
    readonly property bool buttonsLeft: layout === "topdock"
    readonly property real winRadius: layout === "traditional" ? 2 : layout === "plasma" ? 3 : 6
    radius: 8
    color: Theme.dark ? "#1E3550" : "#BFD6EE"
    clip: true
    readonly property color bar: Theme.dark ? "#0E141D" : "#F7FAFD"
    readonly property color icon: Theme.accent
    // a window
    Rectangle {
        id: winr
        x: parent.width * 0.16; y: parent.height * (pv.layout === "topdock" ? 0.2 : 0.12); width: parent.width * 0.5; height: parent.height * 0.5
        radius: pv.winRadius; color: Theme.dark ? "#2B3748" : "#FFFFFF"; opacity: 0.95
        // title bar buttons, on the side this layout uses
        Row {
            spacing: 3; y: 4
            x: pv.buttonsLeft ? 5 : winr.width - width - 5
            Repeater {
                model: 3
                Rectangle { width: pv.layout === "touch" ? 7 : 5; height: width; radius: width / 2
                    color: pv.buttonsLeft ? ["#E5534B", "#D9A33E", "#57A55A"][index] : (index === 2 ? "#E5534B" : Theme.muted) }
            }
        }
        // a frosted sidebar when effects are glassy
        Rectangle { visible: false; y: 14; width: winr.width * 0.28; height: winr.height - 14; radius: pv.winRadius; color: Theme.accent; opacity: 0.18 }
    }
    // top bar (top bar and dock)
    Rectangle { visible: pv.layout === "topdock"; width: parent.width; height: parent.height * 0.09; color: Qt.rgba(pv.bar.r, pv.bar.g, pv.bar.b, pv.barOpacity)
        Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 2; color: pv.icon }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 4; radius: 2; color: Theme.muted } }
    // bottom bar
    Rectangle {
        id: b
        readonly property bool dock: pv.layout === "topdock"
        readonly property bool floaty: dock          // only the dock floats (a little)
        height: pv.height * (pv.layout === "touch" ? 0.16 : dock ? 0.15 : pv.layout === "traditional" ? 0.1 : 0.12)
        width: dock ? pv.width * 0.42 : (floaty ? pv.width - 12 : pv.width)
        x: (pv.width - width) / 2
        y: pv.height - height - (floaty ? 6 : 0)
        radius: floaty ? 6 : 0
        color: Qt.rgba(pv.bar.r, pv.bar.g, pv.bar.b, pv.barOpacity)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: pv.layout === "centered" || b.dock ? (b.width - width) / 2 : 6
            spacing: pv.layout === "touch" ? 6 : 4
            Repeater {
                model: pv.layout === "traditional" ? 3 : 5
                Rectangle {
                    width: pv.layout === "traditional" ? (index === 0 ? 10 : 26) : b.height * 0.55
                    height: pv.layout === "traditional" ? 8 : b.height * 0.55
                    radius: 2; color: index === 0 && !b.dock ? pv.icon : (Theme.dark ? "#51A2DA" : "#8DBEE6")
                    opacity: index === 0 ? 1 : 0.8
                }
            }
        }
        Rectangle { visible: !b.dock; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 4; radius: 2; color: Theme.muted }
    }
}
