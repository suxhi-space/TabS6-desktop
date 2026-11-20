import QtQuick

// A pill slider (Googlebook / Android style): the filled part carries the icon; drag or tap anywhere on it.
Rectangle {
    id: s
    property var pal
    property string icon
    property bool iconOn: true
    property real value: 0.5           // 0..1
    property real minimum: 0
    signal moved(real v)               // while dragging (throttled by the caller)
    signal released(real v)
    signal iconTapped()
    height: 48; radius: 24
    color: pal.tile
    readonly property real shown: drag.pressed ? drag.live : value
    Rectangle {
        width: Math.max(height, s.width * s.shown); height: parent.height; radius: parent.radius
        color: pal.onTile
        Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    QsIcon {
        x: 16; anchors.verticalCenter: parent.verticalCenter; width: 20; height: 20
        name: s.icon; on: s.iconOn; color: s.shown * s.width > 40 ? pal.onInk : pal.fg
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: s.iconTapped(); z: 2 }
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
        text: Math.round(s.shown * 100) + "%"; font.pixelSize: 13; font.weight: Font.DemiBold
        color: s.shown > 0.88 ? pal.onInk : pal.sub
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        property real live: s.value
        function at(x) { return Math.max(s.minimum, Math.min(1, x / s.width)) }
        onPressed: (m) => { live = at(m.x); s.moved(live) }
        onPositionChanged: (m) => { live = at(m.x); s.moved(live) }
        onReleased: s.released(live)
    }
}
