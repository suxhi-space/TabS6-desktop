import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import "."

// S6 Looks: everything about how the tablet looks and feels, in one place (it used to be one long page in
// S6 Companion). Short pages: layout, style, keyboard, touch and size, start-up, files. The changes are made by
// /usr/local/bin/s6-look in your own session; the boot screen by S6's root helper (it asks for your password).
ApplicationWindow {
    id: win
    visible: true
    width: 1280; height: 800
    title: "S6 Looks"
    color: Theme.bg

    property var setup: JSON.parse(backend.setupState())
    property int page: 0
    property int pageCount: pages.length
    readonly property var pages: [
        { label: "Layout", icon: "screen" }, { label: "Style", icon: "look" }, { label: "Keyboard", icon: "tablet" },
        { label: "Touch & size", icon: "phone" }, { label: "Start-up", icon: "clock" }, { label: "Files", icon: "folder" }]
    readonly property var helper: backend.mock ? ["true"] : ["pkexec", backend.helper]
    function h(args) { return helper.concat(args) }

    Component.onCompleted: { Theme.dark = setup.theme === "dark" || (setup.theme === undefined && Qt.styleHints.colorScheme === Qt.Dark); load() }
    Connections { target: Qt.styleHints; function onColorSchemeChanged() { if (!backend.mock) Theme.dark = Qt.styleHints.colorScheme === Qt.Dark } }

    property var handlers: ({})
    function run(id, argv, onLine, onDone) { handlers[id] = { line: onLine, done: onDone }; backend.run(id, argv) }
    Connections {
        target: backend
        function onOutput(id, line) { var x = win.handlers[id]; try { if (x && x.line) x.line(line) } catch (e) { } }
        function onFinished(id, code) { var x = win.handlers[id]; delete win.handlers[id]; try { if (x && x.done) x.done(code) } catch (e) { } }
    }

    // what s6-look reports (LAYOUT, THEME, KBTHEME...), and applying a change
    property var cur: ({})
    property var extras: ({})
    property string out: ""
    function load() {
        var c = {}
        run("lookst", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "status"], function (l) { var f = l.split("|"); c[f[0]] = f[1] },
            function () { if (backend.mock) c = { LAYOUT: "touch", EFFECTS: "soft", SIZE: "larger", HASDARKLY: "yes", APPSTYLE: "darkly", PLASMASTYLE: "darkly" }; cur = c })
        var x = {}
        run("extras", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "extras"], function (l) { var f = l.split("|"); x[f[0]] = f.slice(1) },
            function () { if (backend.mock) x = { BBDX: ["installed", "loaded"], DARKLY: ["installed"] }; extras = x })
    }
    function apply(args) {
        out = "Applying..."; var last = ""
        run("look", backend.mock ? ["true"] : ["/usr/local/bin/s6-look"].concat(args), function (l) { win.out = l; last = l },
            function (c) { win.out = c === 0 ? "Done." : "That didn't work" + (last ? ": " + last : "."); load() })
    }
    Component.onDestruction: {}

    Frame {
        id: frame
        anchors.fill: parent
        navigable: true
        appName: "S6 Looks"
        appSub: "How your tablet looks and feels"
        steps: win.pages
        current: win.page
        sideFooter: "S6 Migrate " + backend.version
        note: win.out
        onStepClicked: (i) => { win.page = i; win.out = "" }
        Loader { width: parent.width; sourceComponent: [layoutPage, stylePage, keyboardPage, touchPage, startPage, filesPage][win.page] }
    }
    function head(title, sub) { frame.eyebrow = ""; frame.title = title; frame.subtitle = sub; frame.primary = ""; frame.secondary = "" }

    // ---------------------------------------------------------------- Layout
    Component {
        id: layoutPage
        Column {
            width: parent.width; spacing: 16
            Component.onCompleted: win.head("Layout", "Where the taskbar, the apps and the clock go. Your pinned apps come along when you switch. The layouts are also in System Settings as Global Themes.")
            LayoutPicker { width: parent.width; effects: win.cur.EFFECTS || win.setup.effects || "soft"; value: win.cur.LAYOUT || win.setup.layout || "touch"
                           onPicked: (id) => win.apply(["layout", id]) }
            Item {
                width: parent.width; height: 40
                Label2 { anchors.verticalCenter: parent.verticalCenter; text: "Taskbar gone after turning on auto-hide?"; color: Theme.sub; font.pixelSize: 14 }
                Btn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Show the taskbar again"; onClicked: win.apply(["show-panels"]) }
            }
        }
    }

    // ---------------------------------------------------------------- Style
    Component {
        id: stylePage
        Column {
            width: parent.width; spacing: 18
            Component.onCompleted: win.head("Style", "Light or dark, how apps and the taskbar are drawn, and how much see-through and blur.")
            Label2 { text: "Appearance"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: 2; columnSpacing: 14
                Choice { width: (parent.width - 14) / 2; title: "Light"; on: !Theme.dark; onPicked: { Theme.dark = false; win.apply(["theme", "light"]) } }
                Choice { width: (parent.width - 14) / 2; title: "Dark"; on: Theme.dark; onPicked: { Theme.dark = true; win.apply(["theme", "dark"]) } }
            }
            Segmented {
                width: parent.width; label: "Apps and window borders"; value: win.cur.APPSTYLE === "darkly" ? "darkly" : "breeze"
                options: [{ id: "darkly", label: "Darkly", sub: "Rounded, frosted and modern" + (win.cur.HASDARKLY === "yes" ? "" : " (not installed yet: add it below)") },
                          { id: "breeze", label: "Breeze", sub: "KDE's own style" }]
                onPicked: (id) => win.apply(["appstyle", id])
            }
            Segmented {
                width: parent.width; label: "Taskbar, menus and pop-ups"; value: win.cur.PLASMASTYLE === "darkly" ? "darkly" : "breeze"
                options: [{ id: "darkly", label: "Darkly (see-through)", sub: "Darkly's Plasma style, see-through with blur behind like Breeze" },
                          { id: "breeze", label: "Breeze", sub: "KDE's own Plasma style" }]
                onPicked: (id) => win.apply(["plasmastyle", id])
            }
            Label2 { text: "Effects"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 14; rowSpacing: 12
                property real cw: frame.roomy ? (width - 28) / 3 : width
                property string v: win.cur.EFFECTS || win.setup.effects || "soft"
                Choice { width: parent.cw; title: "Off"; sub: "Solid and simple; saves battery"; on: parent.v === "off"; onPicked: win.apply(["effects", "off"]) }
                Choice { width: parent.cw; title: "Soft"; sub: "Frosted panels and menus"; on: parent.v === "soft"; onPicked: win.apply(["effects", "soft"]) }
                Choice { width: parent.cw; title: "Glassy"; sub: "See-through panels, menus and background windows"; on: parent.v === "glassy"; onPicked: win.apply(["effects", "glassy"]) }
            }
            Card {
                id: exCard
                width: parent.width
                property bool bb: (win.extras.BBDX || [""])[0] === "installed"
                property bool dk: (win.extras.DARKLY || [""])[0] === "installed"
                property bool queued: backend.exists("/var/lib/s6migrate/maint/extras")
                Row { spacing: 10
                      Glyph { kind: exCard.bb && exCard.dk ? "ok" : "clock"; tint: exCard.bb && exCard.dk ? Theme.ok : Theme.muted; width: 22; height: 22 }
                      Label2 { text: "Better Blur DX and Darkly"; strong: true } }
                Label2 { width: parent.width; font.pixelSize: 14; color: Theme.muted
                         text: (exCard.bb ? ((win.extras.BBDX || [])[1] === "loaded" ? "Better Blur DX is on. " : "Better Blur DX is installed; Plasma's blur is used until it matches this Plasma version. ") : "Better Blur DX isn't installed (Plasma's own blur is used). ")
                               + (exCard.dk ? "Darkly is installed." : "Darkly isn't installed (Breeze is used).") }
                Flow {
                    width: parent.width; spacing: 10; visible: !(exCard.bb && exCard.dk)
                    Btn { text: exCard.queued ? "Added at the next restart" : "Add them at the next restart"; enabled: !exCard.queued
                          onClicked: win.run("extrasi", win.h(["look-extras"]), function (l) { win.out = l }, function () { exCard.queued = true }) }
                    Btn { visible: exCard.queued; text: "Restart now"; primary: true; onClicked: backend.detach("systemctl reboot") }
                }
            }
        }
    }

    // ---------------------------------------------------------------- Keyboard
    Component {
        id: keyboardPage
        Column {
            width: parent.width; spacing: 16
            Component.onCompleted: win.head("Keyboard", "S6 Keyboard: the on-screen keyboard, Gboard style. Changes show the next time it opens.")
            Toggle {
                width: parent.width; title: "S6 Keyboard extras"
                sub: "Emoji, clipboard and hide buttons, and the themes below. Off: Fedora's plain keyboard."
                checked: !backend.exists(backend.home + "/.config/s6migrate/stock-keyboard")
                onCheckedChanged: win.run("kbd", backend.mock ? ["true"] : ["/bin/sh", "-c", checked
                    ? "rm -f \"$HOME/.config/s6migrate/stock-keyboard\"; pkill -f maliit-keyboard"
                    : "mkdir -p \"$HOME/.config/s6migrate\" && touch \"$HOME/.config/s6migrate/stock-keyboard\"; pkill -f maliit-keyboard"], null, null)
            }
            Toggle {
                width: parent.width; title: "Keyboard over the taskbar"
                sub: "Like on a phone: the keyboard sits at the bottom of the screen, over the taskbar or dock, while it's open."
                checked: (win.cur.KBDOVER || "on") !== "off"
                onCheckedChanged: if (((win.cur.KBDOVER || "on") !== "off") !== checked) win.apply(["kbd-over", checked ? "on" : "off"])
            }
            KeyboardStyle {
                width: parent.width
                theme: win.cur.KBTHEME || "auto"; accent: win.cur.KBACCENT || "system"
                borders: win.cur.KBBORDERS !== "false"; hints: win.cur.KBHINTS !== "false"; kbheight: win.cur.KBHEIGHT || "normal"
                onChanged: win.apply(["kbd-style", "theme=" + theme, "accent=" + accent, "borders=" + borders, "hints=" + hints, "height=" + kbheight])
            }
        }
    }

    // ---------------------------------------------------------------- Touch & size
    Component {
        id: touchPage
        Column {
            width: parent.width; spacing: 18
            Component.onCompleted: win.head("Touch & size", "How big things are, and menus you can hit with a finger.")
            Label2 { text: "Size"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 14; rowSpacing: 12
                property real cw: frame.roomy ? (width - 28) / 3 : width
                property string v: win.cur.SIZE || win.setup.size || "larger"
                Choice { width: parent.cw; title: "Standard"; sub: "The tablet's original size"; on: parent.v === "standard"; onPicked: win.apply(["size", "standard"]) }
                Choice { width: parent.cw; title: "Larger"; sub: "Recommended for touch"; on: parent.v === "larger"; onPicked: win.apply(["size", "larger"]) }
                Choice { width: parent.cw; title: "Largest"; sub: "Easiest to tap and read"; on: parent.v === "largest"; onPicked: win.apply(["size", "largest"]) }
            }
            Segmented {
                width: parent.width; label: "Menus (also what holding something opens)"; value: win.cur.MENUS === "normal" ? "normal" : "touch"
                options: [{ id: "touch", label: "Touch size", sub: "Taller rows in apps' menus and Firefox's, easy to hit with a finger" },
                          { id: "normal", label: "Normal", sub: "Compact menus, for a mouse or a pen" }]
                onPicked: (id) => win.apply(["menus", id])
            }
        }
    }

    // ---------------------------------------------------------------- Start-up
    Component {
        id: startPage
        Column {
            width: parent.width; spacing: 18
            Component.onCompleted: win.head("Start-up", "What you see while the tablet starts and while the desktop loads.")
            Segmented {
                width: parent.width; label: "While the tablet starts"
                value: (backend.read("/var/lib/s6migrate/boot-screen") || "verbose").trim()
                options: [{ id: "quiet", label: "Logo and progress bar", sub: "The Fedora logo with a thin bar while the tablet starts" },
                          { id: "verbose", label: "Text", sub: "Every start-up message scrolling by (useful when something goes wrong)" }]
                onPicked: (id) => win.run("bootscreen", win.h(["boot-screen", id]), function (l) { win.out = l }, null)
            }
            Segmented {
                width: parent.width; label: "After logging in"; value: win.cur.SPLASH || "s6"
                options: [{ id: "s6", label: "Loading bar", sub: "Your wallpaper with a thin progress bar while the desktop starts" },
                          { id: "none", label: "None", sub: "Straight to the desktop, no loading screen" }]
                onPicked: (id) => win.apply(["splash", id])
            }
            Label2 { text: "Holding Volume Down while it starts still opens the boot menu."; font.pixelSize: 13; color: Theme.muted; width: parent.width }
        }
    }

    // ---------------------------------------------------------------- Files
    Component {
        id: filesPage
        Column {
            width: parent.width; spacing: 18
            Component.onCompleted: win.head("Files", "The file manager that opens your folders.")
            Segmented {
                width: parent.width; label: "File manager"; value: win.cur.FILES || "dolphin"
                options: [{ id: "dolphin", label: "Dolphin", sub: "KDE's file manager, as KDE made it" },
                          { id: "cosmic", label: "COSMIC Files", sub: "From the COSMIC desktop, written in Rust (installed at the next restart)" }]
                onPicked: (id) => { if (id === "cosmic") win.run("sched", win.h(["schedule", "cosmicfiles"]), null, null); win.apply(["files", id]) }
            }
            Item {
                width: parent.width; height: 40
                Label2 { anchors.verticalCenter: parent.verticalCenter; text: "Dolphin looking odd?"; color: Theme.sub; font.pixelSize: 14 }
                Btn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Back to Dolphin's own look"; onClicked: win.apply(["dolphin", "default"]) }
            }
        }
    }
}
