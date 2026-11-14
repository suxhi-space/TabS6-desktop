pragma Singleton
import QtQuick

// Fedora palette, Red Hat type; the same tokens as the Android app (light and dark).
QtObject {
    property bool dark: false
    readonly property color bg: dark ? "#0E141D" : "#FFFFFF"
    readonly property color side: dark ? "#151D29" : "#EEF3F9"
    readonly property color text: dark ? "#EEF2F8" : "#10131A"
    readonly property color sub: dark ? "#C5CDD9" : "#3E4756"
    readonly property color muted: dark ? "#9BA7B8" : "#56606F"
    readonly property color border: dark ? "#2B3748" : "#D6DEE8"
    readonly property color hair: dark ? "#222D3B" : "#E4EAF1"
    readonly property color sel: dark ? "#13304A" : "#EBF4FB"
    readonly property color track: dark ? "#253244" : "#E1E8F0"
    readonly property color accent: dark ? "#51A2DA" : "#3C6EB4"
    readonly property color accentText: dark ? "#7DBCE8" : "#2F5F9E"
    readonly property color accentFg: dark ? "#0B1220" : "#FFFFFF"
    readonly property color accent2: dark ? "#2C5F8F" : "#8DBEE6"
    readonly property color ok: dark ? "#5ED18B" : "#1C7A43"
    readonly property color warn: dark ? "#F2A65A" : "#A04E06"
    readonly property color warnBg: dark ? "#2A2014" : "#FFF5E9"
    readonly property color warnBorder: dark ? "#5A4325" : "#F0D0A8"
    readonly property color warnText: dark ? "#F0DEC6" : "#3D2A14"
    readonly property color ring: dark ? "#5B6778" : "#A3AEBD"
    readonly property color link: dark ? "#8CC4F0" : "#2A62A8"
    readonly property color btn2Bg: dark ? "#151D29" : "#FFFFFF"
    readonly property color btn2Border: dark ? "#3A4759" : "#C3CCD8"
    readonly property color okBg: dark ? "#5ED18B" : "#1C7A43"
    readonly property color okFg: dark ? "#0B1220" : "#FFFFFF"
    readonly property string display: hasRedHat ? "Red Hat Display" : "Noto Sans"
    readonly property string body: hasRedHat ? "Red Hat Text" : "Noto Sans"
}
