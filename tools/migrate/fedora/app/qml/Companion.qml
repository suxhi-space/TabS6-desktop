import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import "."

// S6 Companion: like a distribution's welcome app. Finishes the move at the first login,
// then keeps Android apps, updates, fixes and tablet tools one tap away.
ApplicationWindow {
    id: win
    visible: true
    width: 1280; height: 800
    title: "S6 Companion"
    color: Theme.bg

    property var setup: JSON.parse(backend.setupState())
    property string fullName: setup.fullName || backend.userName
    property int page: 0
    property int pageCount: pages.length
    readonly property var pages: [
        { label: "Home", icon: "box" }, { label: "Tablet", icon: "phone" }, { label: "Look", icon: "screen" }, { label: "Android apps", icon: "phone" },
        { label: "Updates", icon: "clock" }, { label: "Tune-ups", icon: "lock" }, { label: "Fixes", icon: "ok" },
        { label: "Your stuff", icon: "folder" }, { label: "About", icon: "user" }]
    // While the first run is going, setup's temporary rights apply (no password prompts); later, polkit asks once.
    readonly property var helper: backend.mock ? ["true"] : (backend.firstRun ? ["sudo", "-n", backend.helper] : ["pkexec", backend.helper])
    function h(args) { return helper.concat(args) }
    function sh(cmd) { return backend.mock ? ["true"] : ["/bin/sh", "-c", cmd] }

    Component.onCompleted: {
        Theme.dark = setup.theme === "dark" || (setup.theme === undefined && Qt.styleHints.colorScheme === Qt.Dark)
    }
    Connections {
        target: Qt.styleHints
        function onColorSchemeChanged() { if (!backend.mock) Theme.dark = Qt.styleHints.colorScheme === Qt.Dark }
    }

    property var handlers: ({})
    function run(id, argv, onLine, onDone) {
        handlers[id] = { line: onLine, done: onDone }
        backend.run(id, argv)
    }
    Connections {
        target: backend
        function onOutput(id, line) { var x = win.handlers[id]; try { if (x && x.line) x.line(line) } catch (e) { } }
        function onFinished(id, code) { var x = win.handlers[id]; delete win.handlers[id]; try { if (x && x.done) x.done(code) } catch (e) { } }
    }

    // ---------------------------------------------------------------- first run: finish the move
    property var firstTasks: []
    property bool firstRunning: false
    property bool firstDone: !backend.firstRun || backend.exists("/var/lib/s6migrate/firstrun-done")
    property var parts: []
    function setTask(i, props) { var t = firstTasks.slice(); for (var k in props) t[i][k] = props[k]; firstTasks = t }
    function startFirstRun() {
        firstRunning = true
        var found = []
        run("parts", h(["find-parts"]), function (l) { var f = l.split("|"); if (f[0] === "PART") found.push(f[1]) }, function () {
            parts = found
            var t = []
            var migrate = setup.migrate !== "no", android = setup.android !== "no"
            if (migrate) for (var i = 0; i < found.length; i++)
                t.push({ title: "Your wallpaper and settings from Android" + (found.length > 1 ? " (part " + (i + 1) + ")" : ""), argv: ["/usr/local/bin/s6-restore", "--settings-only", "--skip-verify", "--yes", found[i]] })
            var lay = setup.layout || "touch", size = setup.size || "larger", theme = setup.theme || "light", eff = setup.effects || "soft"
            // Queued for the next restart (added before the login screen), never installed under the running desktop.
            if (eff !== "off" && !backend.exists("/var/lib/s6migrate/last-update")) t.push({ title: "Better blur and the Darkly style: added at the next restart", argv: h(["look-extras"]), optional: true })
            // S6 Setup prepares the desktop before the first login; older setups get it applied here.
            if (backend.exists(backend.home + "/.config/s6migrate/prepared"))
                t.push({ title: "Your layout, look and effects (" + layoutName(lay) + ", " + eff + "): set up before you logged in", argv: ["true"] })
            else t.push({ title: "Your layout, size and effects (" + layoutName(lay) + ", " + size + ", " + eff + ")",
                     argv: sh("s6-look theme " + theme + "; s6-look effects " + eff + "; s6-look layout " + lay + "; s6-look size " + size + "; s6-look install-themes") })
            if (android) {
                t.push({ title: "Download Android for apps (about 1 GB)" + (setup.gapps === "1" ? ", with Google Play" : ""), argv: h(["waydroid-init", setup.gapps === "1" ? "1" : "0"]) })
                t.push({ title: "Start Android", argv: ["/usr/local/bin/s6-android", "start"] })
                if (migrate) for (var j = 0; j < found.length; j++)
                    t.push({ title: "Your Android apps and their data" + (found.length > 1 ? " (part " + (j + 1) + " of " + found.length + ")" : ""), argv: ["/usr/local/bin/s6-restore", "--apps-only", "--skip-verify", "--yes", found[j]] })
            }
            t.push({ title: "Finish up", argv: h(["end-firstrun", backend.userName]) })
            for (var k = 0; k < t.length; k++) { t[k].state = "wait"; t[k].detail = ""; t[k].progress = -1 }
            firstTasks = t
            firstStep(0)
        })
    }
    function firstStep(i) {
        if (i >= firstTasks.length) { firstRunning = false; firstDone = true; return }
        setTask(i, { state: "run" })
        var apps = 0, appN = 0
        run("first" + i, firstTasks[i].argv, function (l) {
            var m = /^\s*\[(\d+)\/(\d+)\]\s*(.*)$/.exec(l)
            if (m) setTask(i, { progress: parseInt(m[1]) / Math.max(1, parseInt(m[2])), detail: m[3] })
            else if (/^==/.test(l)) setTask(i, { detail: l.replace(/=/g, "").trim() })
            else if (/installed|Downloading|downloading|started|restored|set:|->/.test(l)) setTask(i, { detail: l.trim() })
        }, function (code) {
            var opt = firstTasks[i].optional === true
            setTask(i, { state: code === 0 ? "done" : (opt ? "skip" : "fail"), progress: -1,
                         detail: code === 0 ? "" : (opt ? "Not available right now: Plasma's own blur and style are used." : "Didn't finish. You can try again from the Android apps page.") })
            firstStep(i + 1)
        })
    }

    function layoutName(id) { return ({ touch: "Touch", centered: "Centered taskbar", traditional: "Traditional", topdock: "Top bar and dock", plasma: "Plasma default" })[id] || id }

    // ---------------------------------------------------------------- tablet system updates (t860-fedora)
    property var sys: ({ current: "", kernel: "", latest: "", date: "", channel: "", state: "", notes: [] })
    property bool sysChecking: false
    property string pending: backend.read("/var/lib/s6migrate/kernel-pending")
    function checkSystem() {
        sysChecking = true
        var x = { current: "", kernel: "", latest: "", date: "", channel: "", state: "", notes: [] }
        run("sys", backend.mock ? ["s6-update", "check"] : ["/usr/local/bin/s6-update", "check"], function (l) {
            var f = l.split("|")
            if (f[0] === "CURRENT") { x.current = f[1]; x.kernel = f[2] }
            else if (f[0] === "LATEST") { x.latest = f[1]; x.date = f[2]; x.channel = f[3]; x.state = f[4] }
            else if (f[0] === "OFFLINE") x.state = "offline"
            else if (f[0] === "NOTE") x.notes.push(l.substring(5))
        }, function () {
            if (backend.mock) x = { current: "2026-10-29", kernel: "6.18.59-t860-gpu18", latest: "v2026.12.03-gpu19", date: "2026-12-03", channel: "pre", state: "newer",
                                    notes: ["S Pen: pressure and hover work", "Headphone jack detection", "Faster wake from sleep"] }
            sys = x; sysChecking = false
        })
    }

    // ---------------------------------------------------------------- shared bits
    property string androidStatus: "Checking..."
    property bool androidRunning: false
    function refreshAndroid() {
        var out = []
        run("astat", backend.mock ? ["s6-android", "status"] : ["/usr/local/bin/s6-android", "status"], function (l) { out.push(l) }, function () {
            androidStatus = out.join("\n") || "Unknown"
            androidRunning = /running/.test(out[0] || "")
        })
    }
    property int updates: -1
    property var updateList: []
    property bool checkingUpdates: false
    function checkUpdates() {
        checkingUpdates = true; var list = []
        run("upd", backend.mock ? ["pkcon", "get-updates"] : ["/bin/sh", "-c", "pkcon -p refresh >/dev/null 2>&1; pkcon -p get-updates 2>/dev/null | sed -n 's/^\\(Security\\|Bug fix\\|Enhancement\\|Normal\\|Important\\)\\s*/\\1\\t/p'"],
            function (l) { if (l.indexOf("\t") > 0) list.push(l.split("\t")[1]) },
            function () { updateList = list; updates = list.length; checkingUpdates = false })
    }
    Component.onDestruction: {}

    Frame {
        id: frame
        anchors.fill: parent
        navigable: true
        appName: "S6 Companion"
        appSub: "Fedora on your Galaxy Tab S6"
        steps: win.pages
        current: win.page
        sideFooter: "Version " + backend.version
        onStepClicked: (i) => win.page = i
        Loader { width: parent.width; sourceComponent: [homePage, tabletPage, lookPage, androidPage, updatesPage, tunePage, fixesPage, stuffPage, aboutPage][win.page] }
    }

    // ================================================================ Home
    Component {
        id: homePage
        Column {
            width: parent.width; spacing: 16
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = (win.firstDone ? "Hi, " : "Welcome, ") + (win.fullName.split(" ")[0] || "there") + "!"
                frame.subtitle = win.firstDone ? "Your tablet at a glance. Everything here is one tap." : "Let's finish moving in: your Android apps come over now. Keep Wi-Fi on and the tablet plugged in."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
                if (!win.firstDone && !win.firstRunning && win.firstTasks.length === 0) win.startFirstRun()
                win.refreshAndroid()
            }
            Card {
                width: parent.width; warn: true; visible: win.pending !== ""
                property string newk: (win.pending.match(/kernel=(.*)/) || ["", ""])[1]
                Label2 { text: "You're trying a new tablet system"; strong: true; color: Theme.warn; width: parent.width }
                Label2 { text: "Is everything working (Wi-Fi, sound, touch, rotation)? Keep it, or go back to the last version that worked."; color: Theme.warnText; width: parent.width }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: "Everything works: keep it"; primary: true; onClicked: win.run("keep", win.h(["update-keep"]), null, function () { win.pending = backend.read("/var/lib/s6migrate/kernel-pending") }) }
                    Btn { text: "Go back"; onClicked: win.run("rb", win.h(["update-rollback"]), null, function () { win.pending = "" }) }
                }
            }
            Card {
                width: parent.width; visible: !win.firstDone || win.firstTasks.length > 0; spacing: 14
                Label2 { text: win.firstDone ? "Moving in: done" : "Finishing up"; display: true; font.pixelSize: 19; width: parent.width }
                Repeater {
                    model: win.firstTasks
                    delegate: TaskRow { width: parent.width; title: modelData.title; detail: modelData.detail; status: modelData.state; progress: modelData.progress }
                }
                Label2 { visible: win.firstTasks.length === 0; text: "Getting ready..."; color: Theme.muted; width: parent.width }
            }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 14; rowSpacing: 14
                property real cw: frame.roomy ? (width - 28) / 3 : width
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "phone"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Android apps"; strong: true } }
                    Label2 { text: win.androidRunning ? "Running" : "Stopped (no memory used)"; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                    Btn { text: "Manage"; onClicked: win.page = 3 }
                }
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "clock"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Updates"; strong: true } }
                    Label2 { text: win.updates < 0 ? "Not checked yet" : win.updates === 0 ? "Everything is up to date" : win.updates + " update(s) available"; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                    Btn { text: "Check"; onClicked: { win.page = 4 } }
                }
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "ok"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Something not working?"; strong: true } }
                    Label2 { text: "One-tap fixes for Wi-Fi, sound, rotation, the keyboard and Android apps."; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                    Btn { text: "Fixes"; onClicked: win.page = 6 }
                }
            }
            Card {
                width: parent.width
                Label2 { text: "Good to know"; display: true; font.pixelSize: 19; width: parent.width }
                TaskRow { width: parent.width; status: "done"; title: "Android apps are in your app menu and open in their own windows."; detail: "Android starts when you open one, and stops by itself a few minutes after you close the last one." }
                TaskRow { width: parent.width; status: "done"; title: "Your Android folders are in your home folder"; detail: "Photos in Pictures, downloads in Downloads; folders apps made are in Android. Android apps see the same files." }
                Toggle {
                    width: parent.width; title: "Open S6 Companion when I log in"; sub: "Like a welcome screen. It's always in your app menu too."
                    checked: backend.exists(backend.home + "/.config/autostart/s6-companion.desktop")
                    onCheckedChanged: win.run("auto", win.sh(checked ? "mkdir -p ~/.config/autostart && cp /usr/local/share/applications/s6-companion.desktop ~/.config/autostart/" : "rm -f ~/.config/autostart/s6-companion.desktop"), null, null)
                }
                TaskRow { width: parent.width; status: "done"; title: "The touch keyboard pops up when you tap a text field"; detail: "If it ever doesn't, Fixes has a one-tap repair. Screen rotation follows the tablet." }
            }
        }
    }

    // ================================================================ Tablet
    Component {
        id: tabletPage
        Column {
            id: tb
            width: parent.width; spacing: 16
            property var i: JSON.parse(backend.tabletInfo())
            property var bat: i.battery || { level: -1, status: "", health: -1 }
            property var sto: i.storage || { free: 0, total: 1 }
            property var mem: i.memory || {}
            Timer { interval: 5000; running: true; repeat: true; onTriggered: tb.i = JSON.parse(backend.tabletInfo()) }
            function gb(b) { return (b / 1073741824).toFixed(1) + " GB" }
            function dur(s) { var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return (h > 0 ? h + " h " : "") + m + " min" }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Your tablet"
                frame.subtitle = "Battery, storage and the tablet's own parts. Updates every few seconds."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
            }
            Grid {
                width: parent.width; columns: frame.roomy ? 2 : 1; columnSpacing: 14; rowSpacing: 14
                property real cw: frame.roomy ? (width - 14) / 2 : width
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "box"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Battery"; strong: true } }
                    Label2 { text: tb.bat.level >= 0 ? tb.bat.level + "%" : "Unknown"; display: true; font.pixelSize: 34 }
                    Rectangle { width: parent.width; height: 10; radius: 5; color: Theme.track
                        Rectangle { width: parent.width * Math.max(0, tb.bat.level) / 100; height: 10; radius: 5; color: tb.bat.level <= 15 ? Theme.warn : Theme.ok } }
                    Label2 { width: parent.width; font.pixelSize: 14; color: Theme.muted
                             text: (tb.bat.status || "") + (tb.bat.health > 0 ? " \u00b7 health " + tb.bat.health + "%" : "") + (tb.bat.temp ? " \u00b7 " + tb.bat.temp + " \u00b0C" : "") + (tb.bat.cycles ? " \u00b7 " + tb.bat.cycles + " charge cycles" : "") }
                }
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "folder"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Storage"; strong: true } }
                    Label2 { text: tb.gb(tb.sto.free) + " free"; display: true; font.pixelSize: 34 }
                    Rectangle { width: parent.width; height: 10; radius: 5; color: Theme.track
                        Rectangle { width: parent.width * (1 - tb.sto.free / Math.max(1, tb.sto.total)); height: 10; radius: 5; color: Theme.accent } }
                    Label2 { text: "of " + tb.gb(tb.sto.total); font.pixelSize: 14; color: Theme.muted; width: parent.width }
                }
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: "screen"; tint: Theme.accentText; width: 24; height: 24 } Label2 { text: "Memory"; strong: true } }
                    Label2 { text: tb.gb((tb.mem.MemTotal || 0) - (tb.mem.MemAvailable || 0)) + " in use"; display: true; font.pixelSize: 34 }
                    Label2 { width: parent.width; font.pixelSize: 14; color: Theme.muted
                             text: "of " + tb.gb(tb.mem.MemTotal || 0) + (tb.mem.SwapTotal ? " \u00b7 compressed memory " + tb.gb((tb.mem.SwapTotal || 0) - (tb.mem.SwapFree || 0)) + " used" : "") + (win.androidRunning ? " \u00b7 Android is running" : "") }
                }
                Card {
                    width: parent.cw
                    Row { spacing: 10; Glyph { kind: tb.i.pen ? "ok" : "clock"; tint: tb.i.pen ? Theme.ok : Theme.muted; width: 24; height: 24 } Label2 { text: "S Pen"; strong: true } }
                    Label2 { width: parent.width; text: tb.i.pen ? "Detected: you can write and draw." : "Not supported by this tablet system yet." }
                    Label2 { width: parent.width; font.pixelSize: 14; color: Theme.muted
                             text: tb.i.pen ? "The pen's battery level isn't available on Linux (Samsung reports it over its own Bluetooth protocol)." : "When a t860-fedora update adds it, Updates will offer it, and this card will show the pen." }
                }
            }
            Card {
                width: parent.width
                Label2 { text: "About this tablet"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { width: parent.width; font.pixelSize: 15; color: Theme.sub
                         text: "Galaxy Tab S6 Wi-Fi (SM-T860)\nSystem: " + tb.i.system + "\nKernel: " + tb.i.kernel + (tb.i.cpuTemp ? "\nProcessor temperature: " + tb.i.cpuTemp + " \u00b0C" : "") + "\nOn for " + tb.dur(tb.i.uptime || 0) }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: "Check for system updates"; onClicked: win.page = 4 }
                    Btn { text: "Power and battery settings"; onClicked: backend.detach("systemsettings kcm_powerdevilprofilesconfig") }
                }
            }
        }
    }

    // ================================================================ Look
    Component {
        id: lookPage
        Column {
            id: lk
            width: parent.width; spacing: 16
            property var cur: ({})
            property var extras: ({})
            function loadExtras() { var x = {}; win.run("extras", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "extras"], function (l) { var f = l.split("|"); x[f[0]] = f.slice(1) }, function () {
                if (backend.mock) x = { BBDX: ["installed", "loaded"], DARKLY: ["installed"] }; extras = x }) }
            property string out: ""
            function load() { var c = {}; win.run("lookst", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "status"], function (l) { var f = l.split("|"); c[f[0]] = f[1] }, function () { cur = c }) }
            function apply(args) { out = "Applying..."; win.run("look", backend.mock ? ["true"] : ["/usr/local/bin/s6-look"].concat(args), function (l) { lk.out = l }, function (c) { lk.out = c === 0 ? "Done." : "That didn't work."; load() }) }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Look"
                frame.subtitle = "Layout, size, effects and light or dark. Window buttons and the file manager follow the layout. The layouts are also in System Settings as Global Themes."
                frame.primary = ""; frame.secondary = ""; frame.note = lk.out
                load(); loadExtras()
            }
            onOutChanged: frame.note = out
            LayoutPicker { width: parent.width; effects: lk.cur.EFFECTS || win.setup.effects || "soft"; value: lk.cur.LAYOUT || win.setup.layout || "touch"; onPicked: (id) => lk.apply(["layout", id]) }
            Label2 { text: "Size"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 14; rowSpacing: 12
                property real cw: frame.roomy ? (width - 28) / 3 : width
                property string v: lk.cur.SIZE || win.setup.size || "larger"
                Choice { width: parent.cw; title: "Standard"; sub: "The tablet's original size"; on: parent.v === "standard"; onPicked: lk.apply(["size", "standard"]) }
                Choice { width: parent.cw; title: "Larger"; sub: "Recommended for touch"; on: parent.v === "larger"; onPicked: lk.apply(["size", "larger"]) }
                Choice { width: parent.cw; title: "Largest"; sub: "Easiest to tap and read"; on: parent.v === "largest"; onPicked: lk.apply(["size", "largest"]) }
            }
            Label2 { text: "Effects"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 14; rowSpacing: 12
                property real cw: frame.roomy ? (width - 28) / 3 : width
                property string v: lk.cur.EFFECTS || win.setup.effects || "soft"
                Choice { width: parent.cw; title: "Off"; sub: "Solid and simple; saves battery"; on: parent.v === "off"; onPicked: lk.apply(["effects", "off"]) }
                Choice { width: parent.cw; title: "Soft"; sub: "Frosted panels and menus"; on: parent.v === "soft"; onPicked: lk.apply(["effects", "soft"]) }
                Choice { width: parent.cw; title: "Glassy"; sub: "See-through panels, menus and background windows"; on: parent.v === "glassy"; onPicked: lk.apply(["effects", "glassy"]) }
            }
            Card {
                id: exCard
                width: parent.width
                property bool bb: (lk.extras.BBDX || [""])[0] === "installed"
                property bool dk: (lk.extras.DARKLY || [""])[0] === "installed"
                property bool queued: backend.exists("/var/lib/s6migrate/maint/extras")
                Row { spacing: 10
                      Glyph { kind: exCard.bb && exCard.dk ? "ok" : "clock"; tint: exCard.bb && exCard.dk ? Theme.ok : Theme.muted; width: 22; height: 22 }
                      Label2 { text: "Better Blur DX and Darkly"; strong: true } }
                Label2 { width: parent.width; font.pixelSize: 14; color: Theme.muted
                         text: (exCard.bb ? ((lk.extras.BBDX || [])[1] === "loaded" ? "Better Blur DX is on. " : "Better Blur DX is installed; Plasma's blur is used until it matches this Plasma version. ") : "Better Blur DX isn't installed (Plasma's own blur is used). ")
                               + (exCard.dk ? "Darkly gives apps rounded, frosted surfaces." : "Darkly isn't installed (Breeze is used).") }
                Flow {
                    width: parent.width; spacing: 10; visible: !(exCard.bb && exCard.dk)
                    Btn { text: exCard.queued ? "Added at the next restart" : "Add them at the next restart"; enabled: !exCard.queued
                          onClicked: win.run("extrasi", win.h(["look-extras"]), function (l) { lk.out = l }, function () { exCard.queued = true }) }
                    Btn { visible: exCard.queued; text: "Restart now"; primary: true; onClicked: backend.detach("systemctl reboot") }
                }
                Label2 { width: parent.width; font.pixelSize: 13; color: Theme.muted; visible: !(exCard.bb && exCard.dk)
                         text: "They're added while the tablet restarts, before the login screen, never while your desktop is running." }
            }
            Label2 { text: "Appearance"; strong: true; color: Theme.sub; font.pixelSize: 15 }
            Grid {
                width: parent.width; columns: 2; columnSpacing: 14
                Choice { width: (parent.width - 14) / 2; title: "Light"; on: !Theme.dark; onPicked: { Theme.dark = false; lk.apply(["theme", "light"]) } }
                Choice { width: (parent.width - 14) / 2; title: "Dark"; on: Theme.dark; onPicked: { Theme.dark = true; lk.apply(["theme", "dark"]) } }
            }
        }
    }

    // ================================================================ Tune-ups
    Component {
        id: tunePage
        Column {
            id: tn
            width: parent.width; spacing: 16
            property var st: ({})
            property bool busy: false
            property string out: ""
            readonly property var items: [
                { id: "memory", t: "Smoother memory use", d: "Uses compressed memory (zram) earlier, so apps stay open and the tablet doesn't stall." },
                { id: "background", t: "Fewer background jobs", d: "Stops crash reporting and the hourly package-list downloads. Saves battery." },
                { id: "logs", t: "Smaller system log", d: "Keeps the system log at 200 MB to spare the tablet's storage." },
                { id: "shutdown", t: "Faster shutdown", d: "Waits 15 seconds, not 90, for a stuck program when turning off." },
                { id: "downloads", t: "Faster update downloads", d: "Downloads up to 10 packages at once." },
                { id: "protect", t: "Protect the tablet's own parts", d: "Fedora updates never replace the login screen and sensor service that t860-fedora customised for this tablet." },
                { id: "codecs", t: "Media codecs", d: "Every common video and music format, from RPM Fusion. Needs Wi-Fi; stays installed when switched off." }]
            function load() { var x = {}; win.run("tst", win.h(["tune-status"]), function (l) { var f = l.split("|"); if (f[0] === "TUNE") x[f[1]] = f[2] === "on" }, function () { if (backend.mock) x = { memory: true, background: true, logs: true, shutdown: true, downloads: true, protect: true, codecs: false }; st = x }) }
            function set(id, on) {
                busy = true; out = ""
                // Codecs install graphics-related packages: never under the running desktop, at the next restart instead.
                if (id === "codecs" && on) { win.run("tune", win.h(["schedule", "codecs"]), null, function () { busy = false; tn.out = "Media codecs are added at the next restart, before the login screen."; load() }); return }
                win.run("tune", win.h(["tune", id, on ? "on" : "off"]), function (l) { tn.out = l }, function () { busy = false; load() })
            }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Tune-ups"
                frame.subtitle = "Small changes that make Fedora run better on this tablet. Each one can be switched off again."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
                load()
            }
            onOutChanged: frame.note = out
            Card {
                width: parent.width
                Repeater {
                    model: tn.items
                    delegate: Column {
                        width: parent.width; spacing: 6
                        Toggle { width: parent.width; title: modelData.t; sub: modelData.d; checked: tn.st[modelData.id] === true; enabled: !tn.busy
                                 onCheckedChanged: if (checked !== (tn.st[modelData.id] === true)) tn.set(modelData.id, checked) }
                        Rectangle { width: parent.width; height: 1; color: Theme.hair; visible: index < tn.items.length - 1 }
                    }
                }
            }
            Card {
                width: parent.width
                Toggle {
                    width: parent.width; title: "File search indexing"; sub: "Lets the app menu and file manager search inside files. Off by default: it slows the tablet while it indexes."
                    checked: !/Indexing-Enabled=false/.test(backend.read(backend.home + "/.config/baloofilerc"))
                    onCheckedChanged: win.run("baloo", win.sh(checked ? "balooctl6 enable" : "balooctl6 disable"), null, null)
                }
            }
        }
    }

    // ================================================================ Android apps
    Component {
        id: androidPage
        Column {
            id: ap
            width: parent.width; spacing: 16
            property string out: ""
            property bool busy: false
            function go(id, argv) { busy = true; out = ""; win.run(id, argv, function (l) { ap.out += l + "\n" }, function () { busy = false; win.refreshAndroid() }) }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Android apps"
                frame.subtitle = "Your Android apps run in Waydroid, a full Android inside Fedora that only runs while you use it."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
                win.refreshAndroid()
            }
            Card {
                width: parent.width
                Row { spacing: 12; Glyph { kind: win.androidRunning ? "ok" : "clock"; tint: win.androidRunning ? Theme.ok : Theme.muted; width: 24; height: 24 } Label2 { text: win.androidStatus.split("\n")[0]; strong: true } }
                Label2 { text: win.androidStatus.split("\n").slice(1).join("\n"); color: Theme.muted; font.pixelSize: 14; width: parent.width }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: win.androidRunning ? "Stop Android now" : "Start Android"; enabled: !ap.busy; onClicked: ap.go("act", backend.mock ? ["true"] : ["/usr/local/bin/s6-android", win.androidRunning ? "stop" : "start"]) }
                    Btn { text: "Check and fix"; enabled: !ap.busy; onClicked: ap.go("doc", backend.mock ? ["true"] : ["/usr/bin/env", "S6D_SUDO=pkexec", "/usr/local/bin/s6-doctor", "--fix"]) }
                    Btn { text: "Update Android"; enabled: !ap.busy; onClicked: ap.go("upd", backend.mock ? ["true"] : ["/usr/bin/env", "S6D_SUDO=pkexec", "/usr/local/bin/s6-doctor", "--update"]) }
                }
            }
            Card {
                width: parent.width
                Label2 { text: "Save memory"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { text: "Android stops by itself when no Android app has been open for a few minutes. It starts again when you open one."; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                Flow {
                    width: parent.width; spacing: 10
                    Repeater {
                        model: [2, 5, 15, 60]
                        delegate: Choice {
                            width: 150; title: modelData + " min"; on: autoMin === modelData
                            property int autoMin: parseInt((backend.read(backend.home + "/.config/s6migrate/android.conf").match(/IDLE_MIN=(\d+)/) || [0, 5])[1])
                            onPicked: win.run("idle", win.sh("mkdir -p ~/.config/s6migrate && echo 'IDLE_MIN=" + modelData + "' > ~/.config/s6migrate/android.conf && systemctl --user restart s6migrate-android-idle.service"), null, function () { ap.out = "Android now stops after " + modelData + " idle minutes." })
                        }
                    }
                }
            }
            Card {
                width: parent.width
                Label2 { text: "Bring Android apps over again"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { text: "Re-installs the apps from your package and their data, without touching anything else. Your package must be plugged in."; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                Btn { text: "Bring apps over"; enabled: !ap.busy; onClicked: win.page = 7 }
            }
            Card {
                width: parent.width; visible: ap.out !== "" || ap.busy
                Row { spacing: 10; Glyph { kind: ap.busy ? "spin" : "ok"; width: 22; height: 22 } Label2 { text: ap.busy ? "Working..." : "Done"; strong: true } }
                Label2 { text: ap.out; font.family: "monospace"; font.pixelSize: 13; color: Theme.sub; width: parent.width }
            }
        }
    }

    // ================================================================ Updates
    Component {
        id: updatesPage
        Column {
            width: parent.width; spacing: 16
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Updates"
                frame.subtitle = "Fedora, your Linux apps and Android for apps. Fedora updates install while the tablet restarts, before the login screen, so the desktop is never changed while it runs."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
                if (win.updates < 0 && !win.checkingUpdates) win.checkUpdates()
            }
            Card {
                id: updCard
                width: parent.width
                property bool queued: backend.exists("/var/lib/s6migrate/maint/update")
                Row { spacing: 12; Glyph { kind: win.checkingUpdates ? "spin" : (win.updates === 0 ? "ok" : "clock"); tint: win.updates === 0 ? Theme.ok : Theme.accent; width: 24; height: 24 }
                      Label2 { strong: true; text: win.checkingUpdates ? "Checking for updates..." : win.updates === 0 ? "Everything is up to date" : win.updates + " update(s) ready" } }
                Repeater { model: win.updateList.slice(0, 8); delegate: Label2 { text: "• " + modelData; font.pixelSize: 14; color: Theme.sub; width: parent.width } }
                Label2 { visible: win.updateList.length > 8; text: "and " + (win.updateList.length - 8) + " more"; font.pixelSize: 14; color: Theme.muted }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: updCard.queued ? "Updates at the next restart" : "Update at the next restart"; primary: !updCard.queued; enabled: win.updates > 0 && !updCard.queued
                          onClicked: win.run("updq", win.h(["schedule", "update"]), null, function () { updCard.queued = true }) }
                    Btn { visible: updCard.queued; text: "Restart now"; primary: true; onClicked: backend.detach("systemctl reboot") }
                    Btn { text: "Check again"; enabled: !win.checkingUpdates; onClicked: win.checkUpdates() }
                    Btn { text: "Linux apps from Flathub"; onClicked: win.run("flat", win.sh("flatpak update --user -y --noninteractive"), null, null) }
                }
            }
            Card {
                id: sysCard
                width: parent.width
                property bool confirm: false
                property bool busy: false
                property string out: ""
                Component.onCompleted: if (win.sys.latest === "" && !win.sysChecking) win.checkSystem()
                Label2 { text: "Tablet system (t860-fedora)"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 {
                    width: parent.width; font.pixelSize: 15; color: Theme.sub
                    text: win.sysChecking ? "Checking GitHub..." : win.sys.state === "offline" ? "Couldn't reach GitHub. Check Wi-Fi."
                        : "This tablet: build from " + (win.sys.current || "?") + ", kernel " + (win.sys.kernel || "?") + (win.sys.latest ? "\nNewest: " + win.sys.latest + (win.sys.channel === "pre" ? " (pre-release)" : "") : "")
                }
                Row { visible: win.sys.state === "same"; spacing: 10; Glyph { kind: "ok"; tint: Theme.ok; width: 22; height: 22 } Label2 { text: "Up to date"; strong: true } }
                Column {
                    visible: win.sys.state === "newer"; width: parent.width; spacing: 6
                    Label2 { text: "What's new in " + win.sys.latest; strong: true; width: parent.width }
                    Repeater { model: win.sys.notes.slice(0, 12); delegate: Label2 { text: modelData; font.pixelSize: 14; color: Theme.sub; width: parent.width } }
                }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { visible: win.sys.state === "newer" && !sysCard.confirm; text: "Update tablet system"; primary: true; enabled: !sysCard.busy; onClicked: sysCard.confirm = true }
                    Btn { text: "Check again"; enabled: !win.sysChecking && !sysCard.busy; onClicked: win.checkSystem() }
                    Btn { text: "Release page"; onClicked: Qt.openUrlExternally("https://github.com/starlight4you/t860-fedora/releases") }
                }
                Card {
                    width: parent.width; warn: true; visible: sysCard.confirm
                    Label2 { width: parent.width; color: Theme.warnText; text: "This downloads about 5 GB, needs about 25 GB free while it works, and takes 30 to 60 minutes. Your files, apps and settings stay. The current kernel is kept as LAST KNOWN GOOD: if the tablet doesn't start afterwards, hold Volume Down while it starts and choose it." }
                    Flow {
                        width: parent.width; spacing: 10
                        Btn { text: "Yes, update"; primary: true; onClicked: { sysCard.confirm = false; sysCard.busy = true; sysCard.out = ""
                            win.run("sysupd", win.h(["update-system", win.sys.latest]), function (l) { sysCard.out += l + "\n" }, function (c) { sysCard.busy = false; sysCard.out += c === 0 ? "Restart the tablet to finish." : "Stopped. Nothing was switched over; run it again to resume."; win.pending = backend.read("/var/lib/s6migrate/kernel-pending") }) } }
                        Btn { text: "Not now"; onClicked: sysCard.confirm = false }
                    }
                }
                Label2 { visible: sysCard.out !== ""; text: sysCard.out; font.family: "monospace"; font.pixelSize: 13; color: Theme.sub; width: parent.width }
            }
            Card {
                width: parent.width
                property string out: ""
                id: selfCard
                Label2 { text: "S6 Migrate"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { text: "Version " + backend.version + ". Updates S6 Setup, S6 Companion and the restore tools from S6 Migrate's GitHub page."; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                Btn { text: "Update S6 Migrate"; onClicked: { selfCard.out = "Checking..."; win.run("self", win.h(["update-self"]), function (l) { selfCard.out = l }, null) } }
                Label2 { visible: selfCard.out !== ""; text: selfCard.out; font.pixelSize: 14; color: Theme.sub; width: parent.width }
            }
            Card {
                width: parent.width
                Label2 { text: "Android for apps"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { text: "LineageOS updates for Waydroid. Android restarts afterwards."; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                Btn { text: "Update Android"; onClicked: win.page = 3 }
            }
            Card {
                width: parent.width; warn: true
                Label2 { text: "Two kinds of updates"; strong: true; color: Theme.warn; width: parent.width }
                Label2 { text: "Fedora and your apps update at restart, without Fedora's own kernel packages: this tablet runs its own kernel and drivers from the t860-fedora project, which S6 Companion checks above."; color: Theme.warnText; width: parent.width }
            }
        }
    }

    // ================================================================ Fixes
    Component {
        id: fixesPage
        Column {
            id: fx
            width: parent.width; spacing: 16
            property string out: ""
            property string running: ""
            function go(name, argv) { running = name; out = ""; win.run("fix", argv, function (l) { fx.out += l + "\n" }, function (c) { fx.out += (c === 0 ? "Done." : "That didn't work (code " + c + ").") + "\n"; running = "" }) }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Fixes"
                frame.subtitle = "Something not right? Each fix restarts just the part that's stuck. Nothing is deleted."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
            }
            Grid {
                width: parent.width; columns: frame.roomy ? 2 : 1; columnSpacing: 14; rowSpacing: 14
                property real cw: frame.roomy ? (width - 14) / 2 : width
                Repeater {
                    model: [
                        { t: "Wi-Fi isn't connecting", d: "Restarts Wi-Fi and the tablet's Wi-Fi driver helper.", a: win.h(["fix", "wifi"]) },
                        { t: "Bluetooth won't connect", d: "Restarts Bluetooth.", a: win.h(["fix", "bluetooth"]) },
                        { t: "Screen doesn't rotate", d: "Restarts the rotation sensors and auto-rotate.", a: win.h(["fix", "sensors"]) },
                        { t: "No sound", d: "Restarts the sound system for your account.", a: win.sh("systemctl --user restart wireplumber pipewire pipewire-pulse") },
                        { t: "Touch keyboard doesn't appear", d: "Turns the on-screen keyboard back on.", a: win.sh("kwriteconfig6 --file kwinrc --group Wayland --key InputMethod /usr/share/applications/com.github.maliit.keyboard.desktop && kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true && qdbus6 org.kde.KWin /KWin reconfigure") },
                        { t: "Android apps misbehave", d: "Checks Android for apps and repairs what it can.", a: backend.mock ? ["true"] : ["/usr/bin/env", "S6D_SUDO=pkexec", "/usr/local/bin/s6-doctor", "--fix"] }
                    ]
                    delegate: Card {
                        width: parent.cw
                        Label2 { text: modelData.t; strong: true; width: parent.width }
                        Label2 { text: modelData.d; color: Theme.muted; font.pixelSize: 14; width: parent.width }
                        Btn { text: fx.running === modelData.t ? "Fixing..." : "Fix it"; enabled: fx.running === ""; onClicked: fx.go(modelData.t, modelData.a) }
                    }
                }
            }
            Card {
                width: parent.width; visible: fx.out !== ""
                Label2 { text: fx.out; font.family: "monospace"; font.pixelSize: 13; color: Theme.sub; width: parent.width }
            }
        }
    }

    // ================================================================ Your stuff
    Component {
        id: stuffPage
        Column {
            id: sp
            width: parent.width; spacing: 16
            property var found: []
            property string out: ""
            property bool busy: false
            function look() { var f = []; win.run("parts", win.h(["find-parts"]), function (l) { var x = l.split("|"); if (x[0] === "PART") f.push(x[1]) }, function () { sp.found = f }) }
            function bring(mode) {
                busy = true; out = ""
                var queue = found.slice()
                function next() {
                    if (queue.length === 0) { busy = false; out += "Done.\n"; return }
                    var p = queue.shift()
                    win.run("bring", backend.mock ? ["true"] : ["/usr/bin/env", "S6R_SUDO=pkexec", "/usr/local/bin/s6-restore", mode, "--yes", p],
                            function (l) { if (/^==|->|installed|restored|set/.test(l)) sp.out += l + "\n" }, next)
                }
                next()
            }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Your stuff from Android"
                frame.subtitle = "Your package stays on the drive until you delete it. Bring things over again any time; nothing is overwritten."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
                look()
            }
            Card {
                width: parent.width
                Label2 { text: sp.found.length > 0 ? "Your package (" + sp.found.length + (sp.found.length === 1 ? " part)" : " parts)") : "No package found"; display: true; font.pixelSize: 19; width: parent.width }
                Repeater {
                    model: sp.found
                    delegate: TaskRow {
                        width: parent.width; status: "done"
                        title: (sp.found.length > 1 ? "Part " + (index + 1) + ": " : "") + (modelData.indexOf("/var/lib/") === 0 ? "copied into Fedora from your microSD card" : "on your USB drive")
                        detail: modelData
                    }
                }
                Label2 { visible: sp.found.length === 0; text: "Plug in the USB drive with your S6Migrate folder, then tap Look again."; color: Theme.muted; width: parent.width }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: "Look again"; onClicked: sp.look() }
                    Btn { text: "Files and folders"; enabled: sp.found.length > 0 && !sp.busy; onClicked: sp.bring("--files-only") }
                    Btn { text: "Android apps"; enabled: sp.found.length > 0 && !sp.busy; onClicked: sp.bring("--apps-only") }
                    Btn { text: "Settings and wallpaper"; enabled: sp.found.length > 0 && !sp.busy; onClicked: sp.bring("--settings-only") }
                }
            }
            Card {
                width: parent.width
                Label2 { text: "Open your folders"; display: true; font.pixelSize: 19; width: parent.width }
                Flow {
                    width: parent.width; spacing: 10
                    Btn { text: "Pictures"; onClicked: backend.detach("xdg-open \"$(xdg-user-dir PICTURES)\"") }
                    Btn { text: "Downloads"; onClicked: backend.detach("xdg-open \"$(xdg-user-dir DOWNLOAD)\"") }
                    Btn { text: "Android folders"; onClicked: backend.detach("xdg-open \"$HOME/Android\"") }
                    Btn { text: "Restore logs"; onClicked: backend.detach("xdg-open \"$HOME\"") }
                }
            }
            Card {
                width: parent.width; visible: sp.out !== "" || sp.busy
                Row { spacing: 10; Glyph { kind: sp.busy ? "spin" : "ok"; width: 22; height: 22 } Label2 { text: sp.busy ? "Working..." : "Finished"; strong: true } }
                Label2 { text: sp.out; font.family: "monospace"; font.pixelSize: 13; color: Theme.sub; width: parent.width }
            }
        }
    }

    // ================================================================ About
    Component {
        id: aboutPage
        Column {
            width: parent.width; spacing: 16
            Component.onCompleted: {
                frame.eyebrow = "S6 Migrate " + backend.version; frame.title = "About"
                frame.subtitle = "Fedora on the Galaxy Tab S6 exists thanks to these projects. S6 Migrate moves you in and keeps things running."
                frame.primary = ""; frame.secondary = ""; frame.note = ""
            }
            Card {
                width: parent.width
                Label2 {
                    width: parent.width; textFormat: Text.StyledText; font.pixelSize: 15
                    text: "<b>Bentlybro</b>: <a href=\"https://github.com/Bentlybro/gts6l-mainline-linux\">gts6l-mainline-linux</a>, the mainline Linux port for this tablet<br><br>" +
                          "<b>starlight4you</b>: <a href=\"https://github.com/starlight4you/t860-fedora\">t860-fedora</a>, the Fedora 44 KDE build and installer you are running<br><br>" +
                          "<b>Project Aloha</b>: SM8150 UEFI and DualBootKernelPatcher<br><br>" +
                          "Fedora, KDE Plasma, Mesa (freedreno), linux-msm, Waydroid and LineageOS, Magisk, TWRP<br><br>" +
                          "Linux apps suggested for your Android apps, such as <a href=\"https://github.com/pear-devs/pear-desktop\">Pear Desktop</a>, and Flathub<br><br>" +
                          "Red Hat Display and Red Hat Text fonts by Red Hat (SIL Open Font License)"
                }
            }
            Card {
                width: parent.width
                Label2 { text: "S6 Migrate"; display: true; font.pixelSize: 19; width: parent.width }
                Label2 { textFormat: Text.StyledText; width: parent.width; font.pixelSize: 15; color: Theme.sub
                         text: "Source, help and the full list of credits: <a href=\"https://github.com/suxhi-space/TabS6-desktop\">github.com/suxhi-space/TabS6-desktop</a>. Restore logs are in your home folder (S6Migrate-restore-*.log)." }
            }
        }
    }
}
