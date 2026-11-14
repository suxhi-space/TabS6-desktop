import QtQuick
import "."

// A small drawing of a desktop layout: screen, windows, and where the bars and icons go.
Rectangle {
    id: pv
    property string layout: "touch"
    radius: 8
    color: Theme.dark ? "#1E3550" : "#BFD6EE"
    clip: true
    readonly property color bar: Theme.dark ? "#0E141D" : "#F7FAFD"
    readonly property color icon: Theme.accent
    // a window
    Rectangle { x: parent.width * 0.16; y: parent.height * (pv.layout === "topdock" ? 0.2 : 0.12); width: parent.width * 0.5; height: parent.height * 0.5; radius: 4; color: Theme.dark ? "#2B3748" : "#FFFFFF"; opacity: 0.9 }
    // top bar (top bar and dock)
    Rectangle { visible: pv.layout === "topdock"; width: parent.width; height: parent.height * 0.09; color: pv.bar
        Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 2; color: pv.icon }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 4; radius: 2; color: Theme.muted } }
    // bottom bar
    Rectangle {
        id: b
        readonly property bool dock: pv.layout === "topdock"
        readonly property bool floaty: pv.layout === "touch" || dock
        height: pv.height * (pv.layout === "touch" ? 0.16 : dock ? 0.15 : pv.layout === "traditional" ? 0.1 : 0.12)
        width: dock ? pv.width * 0.42 : (floaty ? pv.width - 12 : pv.width)
        x: (pv.width - width) / 2
        y: pv.height - height - (floaty ? 6 : 0)
        radius: floaty ? 6 : 0
        color: pv.bar
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
