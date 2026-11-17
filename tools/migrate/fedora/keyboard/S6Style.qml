import QtQuick 2.9

// S6 Migrate: the keyboard's colours and options, Gboard style. Chosen in S6 Companion > Look > Keyboard, which
// writes a small settings file; it is read again every couple of seconds, so a change shows without a restart.
//   theme   auto (your colour scheme) | light | dark | black (AMOLED) | tinted (shaded in your accent colour)
//   accent  system (the one carried over from Android) or #RRGGBB: the Enter key and highlights
//   borders keys drawn as keys (true) or only their letters (false), like Gboard's "Key borders"
//   hints   the small numbers and symbols on the keys (long-press them)
//   height  short | normal | tall
Item {
    id: st
    readonly property string source: "file://@KBSTYLE@"
    property var cfg: ({})
    property string _last: ""
    SystemPalette { id: sys }

    function lum(c) { return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 }
    function shade(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property string theme: cfg.theme || "auto"
    readonly property bool dark: theme === "dark" || theme === "black" || (theme !== "light" && lum(sys.window) < 0.5)
    readonly property color accent: (cfg.accent && cfg.accent !== "system") ? cfg.accent : sys.highlight
    readonly property color accentText: lum(accent) > 0.62 ? "#1B1B1F" : "#FFFFFF"
    readonly property bool borders: cfg.borders !== false
    readonly property bool hints: cfg.hints !== false
    readonly property real scale: cfg.height === "short" ? 0.88 : cfg.height === "tall" ? 1.12 : 1.0

    readonly property color base: theme === "black" ? "#000000" : dark ? "#1B1B1F" : "#E8EAED"
    readonly property color bg: theme === "tinted" ? Qt.tint(base, shade(accent, dark ? 0.16 : 0.20)) : base
    readonly property color key: theme === "black" ? "#1C1C1E"
                               : theme === "tinted" ? Qt.tint(dark ? "#36363B" : "#FFFFFF", shade(accent, dark ? 0.12 : 0.05))
                               : dark ? "#36363B" : "#FFFFFF"
    readonly property color fn: theme === "black" ? "#2C2C2E"
                              : theme === "tinted" ? Qt.tint(dark ? "#4A4A52" : "#C9CDD4", shade(accent, dark ? 0.28 : 0.30))
                              : dark ? "#4A4A52" : "#C9CDD4"
    readonly property color down: dark ? Qt.lighter(fn, 1.4) : Qt.darker(fn, 1.18)
    readonly property color text: dark ? "#E6E5EA" : "#1B1B1F"

    function load() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.responseText === st._last) return       // unchanged: don't redraw the keys
            st._last = x.responseText
            try { var c = JSON.parse(x.responseText); st.cfg = (c && typeof c === "object") ? c : {} } catch (e) { st.cfg = {} }
        }
        x.open("GET", source + "?" + Date.now()); x.send()
    }
    Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true; onTriggered: st.load() }
}
