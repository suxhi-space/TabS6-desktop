import QtQuick

// A small S6 Keyboard in the chosen look, for S6 Looks: the same colour rules as the keyboard (S6Style.qml there).
Item {
    id: ks
    property string theme: "auto"
    property string accent: "system"
    property bool borders: true
    property bool hints: true
    property string kbheight: "normal"
    property string mode: "docked"
    implicitWidth: 640
    implicitHeight: pv.height

    SystemPalette { id: sys }
    function lum(c) { return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 }
    function shade(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    readonly property bool dark: theme === "dark" || theme === "black" || (theme !== "light" && lum(sys.window) < 0.5)
    readonly property color acc: accent !== "system" ? accent : sys.highlight
    readonly property color accText: lum(acc) > 0.62 ? "#1B1B1F" : "#FFFFFF"
    readonly property color base: theme === "black" ? "#000000" : dark ? "#1B1B1F" : "#E8EAED"
    readonly property color bg: theme === "tinted" ? Qt.tint(base, shade(acc, dark ? 0.16 : 0.20)) : base
    readonly property color key: theme === "black" ? "#1C1C1E"
                               : theme === "tinted" ? Qt.tint(dark ? "#36363B" : "#FFFFFF", shade(acc, dark ? 0.12 : 0.05))
                               : dark ? "#36363B" : "#FFFFFF"
    readonly property color fn: theme === "black" ? "#2C2C2E"
                              : theme === "tinted" ? Qt.tint(dark ? "#4A4A52" : "#C9CDD4", shade(acc, dark ? 0.28 : 0.30))
                              : dark ? "#4A4A52" : "#C9CDD4"
    readonly property color txt: dark ? "#E6E5EA" : "#1B1B1F"

    // the preview: a small S6 Keyboard in the chosen look
    Rectangle {
        id: pv
        width: ks.mode === "floating" ? parent.width * 0.62 : parent.width; anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        readonly property real kh: (ks.kbheight === "short" ? 30 : ks.kbheight === "tall" ? 40 : 35)
        height: 34 + 4 * (kh + 8) + 10; radius: 18; color: ks.bg
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {   // the top bar
            x: 14; y: 8; spacing: 18; height: 22
            Repeater { model: ["☻", "⎘", "↶", "↷"]
                Text { text: modelData; color: ks.txt; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter; opacity: 0.85 } }
        }
        Text { x: pv.width - 30; y: 8; height: 22; text: "⌄"; color: ks.txt; font.pixelSize: 18; verticalAlignment: Text.AlignVCenter }
        Column {
            x: 8; y: 34; width: pv.width - 16; spacing: 8
            Repeater {
                model: [
                    [["q", "1"], ["w", "2"], ["e", "3"], ["r", "4"], ["t", "5"], ["y", "6"], ["u", "7"], ["i", "8"], ["o", "9"], ["p", "0"]],
                    [["a", "@"], ["s", "#"], ["d", "$"], ["f", "%"], ["g", "&"], ["h", "-"], ["j", "+"], ["k", "("], ["l", ")"]],
                    [["⇧", "", "fn", 1.5], ["z", ""], ["x", ""], ["c", ""], ["v", ""], ["b", ""], ["n", ""], ["m", ""], ["⌫", "", "fn", 1.5]],
                    [["?123", "", "fn", 1.5], ["☻", "", "fn"], [",", ""], ["", "", "space", 4], [".", ""], ["⏎", "", "enter", 1.5]]
                ]
                delegate: Row {
                    required property var modelData
                    spacing: 6; anchors.horizontalCenter: parent.horizontalCenter
                    readonly property real unit: (pv.width - 16 - 9 * 6) / 10
                    Repeater {
                        model: parent.modelData
                        delegate: Rectangle {
                            required property var modelData
                            readonly property string kind: modelData[2] || "char"
                            width: parent.unit * (modelData[3] || 1) + 6 * ((modelData[3] || 1) - 1); height: pv.kh
                            radius: Math.min(width, height) * 0.2
                            color: kind === "enter" ? ks.acc : !ks.borders ? "transparent" : kind === "fn" ? ks.fn : ks.key
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text { anchors.centerIn: parent; text: modelData[0]; color: kind === "enter" ? ks.accText : ks.txt; font.pixelSize: pv.kh * 0.45 }
                            Text { visible: ks.hints && modelData[1] !== ""; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                                   text: modelData[1]; color: ks.txt; opacity: 0.6; font.pixelSize: pv.kh * 0.26 }
                        }
                    }
                }
            }
        }
    }

}
