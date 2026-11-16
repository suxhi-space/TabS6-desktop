import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// S6 Quick Settings: status icons in the taskbar; tap them for an Android-style panel. The commands are in
// /usr/local/bin/s6-quick; the look follows the desktop's colours (light/dark, your accent).
PlasmoidItem {
    id: root
    property var st: ({})
    readonly property string cmd: "/usr/local/bin/s6-quick"
    readonly property color fg: Kirigami.Theme.textColor
    readonly property var pal: ({
        accent: Kirigami.Theme.highlightColor, accentFg: Kirigami.Theme.highlightedTextColor,
        fg: fg, sub: Qt.rgba(fg.r, fg.g, fg.b, 0.66),
        tile: Qt.rgba(fg.r, fg.g, fg.b, 0.08), tileIcon: Qt.rgba(fg.r, fg.g, fg.b, 0.12) })
    preferredRepresentation: compactRepresentation
    toolTipMainText: "Quick settings"
    toolTipSubText: (st.wifi === "on" ? (st.ssid || "Wi-Fi on") : "Wi-Fi off") + (parseInt(st.battery) >= 0 ? " · battery " + st.battery + "%" : "")

    function parse(out) {
        var s = {}
        String(out).split("\n").forEach(function (l) { var i = l.indexOf("="); if (i > 0) s[l.slice(0, i)] = l.slice(i + 1) })
        st = s
    }
    function run(args) { sh.connectSource(cmd + " " + args) }
    function refresh() { sh.connectSource(cmd + " status") }
    // what the panel calls
    function toggle(k) { var s = Object.assign({}, st); if (k !== "mute") s[k] = s[k] === "on" ? "off" : "on"; st = s; run("toggle " + k) }
    function open(a) { root.expanded = false; run("open " + a) }
    property double lastSlide: 0
    function slide(what, v, done) {
        var now = Date.now()
        if (!done && now - lastSlide < 120) return
        lastSlide = now; run(what + " " + v)
        if (done) { var s = Object.assign({}, st); s[what] = String(v); if (what === "volume") s.muted = "off"; st = s }
    }
    function brightness(v, done) { slide("brightness", v, done) }
    function volume(v, done) { slide("volume", v, done) }

    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            if (source.endsWith(" status")) root.parse(data["stdout"])
            else again.restart()
            disconnectSource(source)
        }
    }
    Timer { id: again; interval: 700; onTriggered: root.refresh() }
    Timer { interval: root.expanded ? 3000 : 15000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    onExpandedChanged: if (expanded) refresh()

    compactRepresentation: MouseArea {
        id: cr
        readonly property real ic: Math.min(height, width) * 0.5 > 0 ? Math.max(16, Math.min(24, parent ? parent.height * 0.42 : 20)) : 20
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Rectangle { anchors.fill: parent; anchors.margins: 2; radius: height / 2; color: root.fg; opacity: root.expanded ? 0.14 : (cr.containsMouse ? 0.08 : 0) }
        Row {
            id: row
            anchors.centerIn: parent; spacing: Kirigami.Units.smallSpacing * 1.5
            QsIcon { name: "wifi"; on: root.st.wifi === "on" && root.st.ssid !== ""; color: root.fg; width: cr.ic; height: cr.ic; anchors.verticalCenter: parent.verticalCenter }
            QsIcon { visible: root.st.bt === "on"; name: "bt"; color: root.fg; width: cr.ic; height: cr.ic; anchors.verticalCenter: parent.verticalCenter }
            QsIcon { name: "sound"; on: root.st.muted !== "on"; color: root.fg; width: cr.ic; height: cr.ic; anchors.verticalCenter: parent.verticalCenter }
            QsIcon { visible: parseInt(root.st.battery) >= 0; name: "battery"; level: parseInt(root.st.battery) / 100; color: root.fg; width: cr.ic; height: cr.ic; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: parseInt(root.st.battery) >= 0; text: root.st.battery + "%"; color: root.fg; font.pixelSize: cr.ic * 0.62; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    fullRepresentation: QuickPanel {
        backend: root; pal: root.pal
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: implicitWidth; Layout.minimumHeight: implicitHeight
    }
}
