import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.VirtualKeyboard
import "."

// S6 Setup: first start of Fedora, before any desktop. Like setting up a new computer:
// Wi-Fi, your account, your tablet's settings (filled in from Android), moving your stuff in, done.
ApplicationWindow {
    id: win
    visible: true
    width: 1280; height: 800
    visibility: backend.mock ? Window.Windowed : Window.FullScreen
    title: "Set up your tablet"
    color: Theme.bg

    property var info: JSON.parse(backend.packageInfo())
    property var set: info.settings || {}
    property var parts: info.parts || []
    property int want: info.want || 1
    property int page: 0
    readonly property var steps: ["Welcome", "Wi-Fi", "Your account", "Your tablet", "Look and feel", "Moving in", "All set"]
    readonly property var icons: ["tablet", "wifi", "user", "globe", "look", "move", "check"]
    property var walls: JSON.parse(backend.wallpapers())
    readonly property url backdrop: personal && walls.android ? walls.android : walls["default"]
    readonly property var helper: backend.mock ? ["true"] : ["pkexec", backend.helper]

    // choices
    property string fullName: ""
    property string userName: ""
    property bool userEdited: false
    property string password: ""
    property bool autoLogin: true
    property bool removeFedora: true
    property string deviceName: set.device_name && set.device_name !== "null" ? set.device_name : "Galaxy Tab S6"
    property string timeZone: set.timezone || "UTC"
    property string loc: set.locale || "en-US"
    property bool dark: set.night_mode === "2"
    property bool gapps: true
    property bool migrate: true            // bring stuff from Android, or start fresh
    property bool android: true            // set up Android app support (Waydroid) after login
    property string layout: "touch"
    property string size: "larger"
    property string effects: "on"
    property bool tune: true
    property bool codecs: true
    property bool online: false
    property string connectedTo: ""
    property bool useAccent: true          // your Android (Material You) colour for Setup and KDE
    readonly property bool personal: page >= 1 && migrate && parts.length > 0
    Binding { target: Theme; property: "tint"; value: win.personal && win.useAccent && win.info.tint ? win.info.tint : null }

    Component.onCompleted: { Theme.dark = dark; findParts() }
    onDarkChanged: Theme.dark = dark

    function h(args) { return helper.concat(args) }
    function firstName() { return (fullName.trim().split(" ")[0]) || "there" }

    // ---- commands with callbacks
    property var handlers: ({})
    function run(id, argv, onLine, onDone, input) {
        handlers[id] = { line: onLine, done: onDone }
        if (input !== undefined) backend.runInput(id, argv, input); else backend.run(id, argv)
    }
    Connections {
        target: backend
        function onOutput(id, line) { var x = win.handlers[id]; try { if (x && x.line) x.line(line) } catch (e) { } }
        function onFinished(id, code) { var x = win.handlers[id]; delete win.handlers[id]; try { if (x && x.done) x.done(code) } catch (e) { } }
    }

    // ---- package parts (the helper also mounts USB drives so the package can be read)
    property bool lookingForParts: false
    function findParts() {
        lookingForParts = true
        var found = []
        run("parts", h(["find-parts"]), function (l) {
            var f = l.split("|"); if (f[0] === "PART") found.push(f[1])
        }, function () {
            lookingForParts = false
            if (found.length > 0) {
                parts = found
                info = JSON.parse(backend.packageInfo()); set = info.settings || set
                if (info.parts.length > parts.length) parts = info.parts
                want = Math.max(info.want || 1, want)
                walls = JSON.parse(backend.wallpapers())
            }
        })
    }

    // pages that don't show progress or a terminal
    function plainFrame() { frame.wideContent = false; frame.progress = -1; frame.detailsAvailable = false; frame.detailsShown = false; frame.details = "" }

    SetupFrame {
        id: frame
        anchors.fill: parent
        steps: win.steps
        current: win.page
        icon: win.icons[win.page]
        wallpaper: win.backdrop
        keyboardHeight: kb.active ? kb.height : 0
        Loader {
            id: pageLoader
            width: parent.width
            sourceComponent: [welcomePage, wifiPage, accountPage, tabletPage, lookPage, movingPage, donePage][win.page]
        }
        onPrimaryClicked: if (pageLoader.item && pageLoader.item.next) pageLoader.item.next()
        onSecondaryClicked: if (win.page > 0 && win.page < 5) win.page--
    }

    InputPanel {
        id: kb
        z: 99
        y: active ? win.height - height : win.height
        width: Math.min(win.width, 1100)
        anchors.horizontalCenter: parent.horizontalCenter
        Behavior on y { NumberAnimation { duration: 150 } }
    }

    // ================================================================ 1. Welcome
    Component {
        id: welcomePage
        Column {
            width: parent.width; spacing: 18
            Component.onCompleted: {
                win.plainFrame(); frame.eyebrow = "Fedora 44 · Galaxy Tab S6"
                frame.title = "Welcome to your new Fedora"
                frame.subtitle = "Let's set up your tablet. It takes a few minutes, and your apps, files and settings from Android move in along the way."
                frame.note = ""; frame.primary = "Let's go"; frame.secondary = ""; frame.primaryEnabled = true
            }
            function next() { if (win.parts.length === 0) win.migrate = false; win.android = win.migrate && win.info.apps > 0; win.page = 1 }
            Grid {
                width: parent.width; columns: frame.roomy ? 2 : 1; columnSpacing: 14; rowSpacing: 12
                property real cw: frame.roomy ? (width - 14) / 2 : width
                Choice {
                    width: parent.cw; enabled: win.parts.length > 0
                    title: "Bring my stuff from Android"; sub: win.parts.length > 0 ? "Apps, files and settings from your package" : "No package found yet (see below)"
                    on: win.migrate && win.parts.length > 0; onPicked: win.migrate = true
                }
                Choice { width: parent.cw; title: "Start fresh"; sub: "A clean Fedora. You can still bring things over later in S6 Companion."; on: !win.migrate || win.parts.length === 0; onPicked: win.migrate = false }
            }
            Card {
                width: parent.width; visible: win.migrate && win.parts.length > 0
                Label2 { text: "What's coming over from Android"; display: true; font.pixelSize: 19; width: parent.width }
                TaskRow { title: win.info.apps + " Android apps and their data" + (win.info.linux > 0 ? ", plus " + win.info.linux + " that switch to Linux versions" : ""); status: win.info.apps + win.info.linux > 0 ? "done" : "skip" }
                TaskRow { title: win.info.folders + " folders" + (win.info.folderNames && win.info.folderNames.length ? ": " + win.info.folderNames.slice(0, 6).join(", ") : ""); status: win.info.folders > 0 ? "done" : "skip" }
                TaskRow { title: "Wallpaper, dark mode, time zone, language and device name"; status: win.set.timezone ? "done" : "skip" }
                TaskRow { title: win.info.wifi + " saved Wi-Fi networks"; status: win.info.wifi > 0 ? "done" : "skip" }
            }
            Card {
                width: parent.width; warn: true
                visible: win.parts.length < win.want || (win.parts.length === 0 && !win.lookingForParts)
                Label2 { text: win.parts.length === 0 ? "Your package wasn't found yet" : "Part of your package is missing"; strong: true; color: Theme.warn; width: parent.width }
                Label2 { text: "Connect the USB drive that holds your S6Migrate folder through a powered USB-C hub (this tablet's port can't power a USB stick by itself), then tap Check again. You can also continue and bring your stuff over later from S6 Companion."; color: Theme.warnText; width: parent.width }
                Btn { text: win.lookingForParts ? "Looking..." : "Check again"; enabled: !win.lookingForParts; onClicked: win.findParts() }
            }
        }
    }

    // ================================================================ 2. Wi-Fi
    Component {
        id: wifiPage
        Column {
            id: wp
            objectName: "wifiPage"
            width: parent.width; spacing: 16
            property var nets: []
            property bool scanning: false
            property string picked: ""
            property string status: ""
            function next() { win.page = 2 }
            Component.onCompleted: {
                win.plainFrame(); frame.eyebrow = ""; frame.title = "Connect to Wi-Fi"
                frame.subtitle = win.info.wifi > 0 ? "Your Wi-Fi networks from Android are added for you. Wi-Fi is needed for your Linux apps and Android app support." : "Wi-Fi is needed for your Linux apps and Android app support."
                frame.primary = "Continue"; frame.secondary = "Back"; frame.note = "You can skip this and connect later."
                importAndScan()
            }
            function importAndScan() {
                scanning = true
                var queue = win.parts.slice()
                function nextImport() {
                    if (queue.length === 0) { wp.status = ""; scan(); return }
                    win.run("wifi-import", win.h(["wifi-import", queue.shift()]), function (l) { wp.status = l }, nextImport)
                }
                nextImport()
            }
            function scan() {
                scanning = true; var list = []
                win.run("wifi-list", win.h(["wifi-list"]), function (l) {
                    var f = l.split("|")
                    if (f[0] === "NET") list.push({ ssid: f[1], signal: parseInt(f[2]) || 0, sec: f[3], on: f[4] === "yes" })
                }, function () {
                    nets = list; scanning = false
                    win.connectedTo = ""; for (var i = 0; i < list.length; i++) if (list[i].on) win.connectedTo = list[i].ssid
                    win.online = win.connectedTo !== ""
                })
            }
            // every network, strongest first; the list scrolls inside its panel so the page itself stays put
            readonly property var shown: nets.slice().sort(function (x, y) { return (y.on - x.on) || (y.signal - x.signal) })
            Card {
                id: netCard
                width: parent.width; spacing: 0; pad: 14
                Item {
                    width: parent.width; height: 44
                    Glyph { id: wg; anchors.verticalCenter: parent.verticalCenter; kind: win.online ? "ok" : (wp.scanning ? "spin" : "wifi"); tint: win.online ? Theme.ok : Theme.accent; width: 24; height: 24 }
                    Label2 {
                        anchors { left: wg.right; leftMargin: 12; right: rb.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        strong: true; text: win.online ? "Connected to " + win.connectedTo : (wp.scanning ? "Looking for networks..." : "Not connected")
                    }
                    Label2 {
                        id: rb; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: wp.scanning ? "" : "Refresh"; strong: true; color: Theme.accentText; font.pixelSize: 15; wrapMode: Text.NoWrap
                        MouseArea { anchors.fill: parent; anchors.margins: -12; enabled: !wp.scanning; onClicked: wp.scan() }
                    }
                }
                ListView {
                    id: netList
                    width: parent.width
                    model: wp.shown
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property real fits: frame.room - 44 - 2 * netCard.pad - (pwRow.visible ? pwRow.height + wp.spacing : 0)
                    height: Math.max(53 * 2, Math.min(contentHeight, fits))
                    ScrollBar.vertical: ScrollBar { policy: netList.contentHeight > netList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                    delegate: Column {
                        required property var modelData
                        width: netList.width
                        Rectangle { width: parent.width; height: 1; color: Theme.hair }
                        Item {
                            width: parent.width; height: 52
                            Glyph { id: ng; anchors.verticalCenter: parent.verticalCenter; kind: modelData.on || wp.picked === modelData.ssid ? "radioOn" : "radio"; width: 20; height: 20 }
                            Label2 { anchors { left: ng.right; leftMargin: 12; verticalCenter: parent.verticalCenter; right: meta.left; rightMargin: 12 }
                                     text: modelData.ssid; strong: modelData.on; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                            Label2 { id: meta; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; wrapMode: Text.NoWrap
                                     text: (modelData.on ? "Connected · " : (modelData.sec ? "Secured · " : "Open · ")) + modelData.signal + "%"; font.pixelSize: 13; color: Theme.muted }
                            MouseArea { anchors.fill: parent; onClicked: { wp.picked = modelData.ssid; pw.text = "" } }
                        }
                    }
                }
            }
            Row {
                id: pwRow
                width: parent.width; spacing: 12
                visible: wp.picked !== "" && !(win.online && win.connectedTo === wp.picked)
                Field { id: pw; width: parent.width - cb.width - 12; label: "Password for " + wp.picked; echoMode: TextInput.Password; hint: wp.status }
                Btn {
                    id: cb; y: 26
                    text: "Connect"; primary: true
                    onClicked: {
                        wp.status = "Connecting..."
                        win.run("wifi-connect", win.h(["wifi-connect", wp.picked]), function (l) { wp.status = l }, function (code) {
                            wp.status = code === 0 ? "" : "Couldn't connect. Check the password and try again."
                            wp.scan()
                        }, pw.text + "\n")
                    }
                }
            }
        }
    }

    // ================================================================ 3. Account
    Component {
        id: accountPage
        Column {
            id: ap
            width: parent.width; spacing: 18
            property string error: ""
            function valid() {
                if (win.fullName.trim() === "") return "Enter your name."
                if (!/^[a-z_][a-z0-9_-]{0,30}$/.test(win.userName)) return "The user name can use lower-case letters, numbers, - and _, and starts with a letter."
                if (["root", "fedora", "s6setup", "admin", "bin", "daemon", "nobody"].indexOf(win.userName) >= 0) return "That user name is taken. Pick another."
                if (pass1.text.length < 4) return "Choose a password of at least 4 characters."
                if (pass1.text !== pass2.text) return "The passwords don't match."
                return ""
            }
            function next() {
                error = valid(); if (error !== "") return
                win.password = pass1.text
                win.page = 3
            }
            Component.onCompleted: {
                win.plainFrame(); frame.eyebrow = ""; frame.title = "Create your account"
                frame.subtitle = "This is you on Fedora. Your password unlocks the tablet and approves system changes."
                frame.primary = "Continue"; frame.secondary = "Back"; frame.note = ""
            }
            Grid {
                width: parent.width; columns: frame.roomy ? 2 : 1; columnSpacing: 20; rowSpacing: 16
                property real cw: frame.roomy ? (width - 20) / 2 : width
                Field {
                    width: parent.cw; label: "Your name"; placeholder: "e.g. Alex Doe"; text: win.fullName
                    input.onTextChanged: { win.fullName = input.text; if (!win.userEdited) win.userName = backend.suggestUser(input.text) }
                }
                Field {
                    width: parent.cw; label: "User name"; lower: true; text: win.userName; hint: "Used for your home folder: /home/" + (win.userName || "...")
                    input.onTextEdited: { win.userEdited = true; win.userName = input.text.toLowerCase() }
                }
                Field { id: pass1; width: parent.cw; label: "Password"; echoMode: TextInput.Password; hint: text.length > 0 && text.length < 8 ? "Tip: 8 or more characters is safer." : "" }
                Field { id: pass2; width: parent.cw; label: "Password again"; echoMode: TextInput.Password; bad: text.length > 0 && text !== pass1.text; hint: bad ? "Doesn't match yet." : "" }
            }
            Card {
                width: parent.width
                Toggle { width: parent.width; title: "Log in automatically"; sub: "Start straight to your desktop. The lock screen still uses your password."; checked: win.autoLogin; onCheckedChanged: win.autoLogin = checked }
                Rectangle { width: parent.width; height: 1; color: Theme.hair }
                Toggle { width: parent.width; title: "Remove the default \"fedora\" account"; sub: "Recommended: its password is public. Your own account becomes the only one."; checked: win.removeFedora; onCheckedChanged: win.removeFedora = checked }
            }
            Label2 { visible: ap.error !== ""; text: ap.error; color: Theme.warn; strong: true; width: parent.width }
        }
    }

    // ================================================================ 4. Your tablet
    Component {
        id: tabletPage
        Column {
            id: tp
            width: parent.width; spacing: 18
            function next() {
                win.deviceName = dn.text.trim() || "Galaxy Tab S6"
                win.timeZone = tz.value || "UTC"
                win.loc = lang.value || win.loc
                win.page = 4
            }
            Component.onCompleted: {
                win.plainFrame(); frame.wideContent = true
                frame.eyebrow = ""; frame.title = "Your tablet"
                frame.subtitle = "Filled in from your Android settings. Change anything you like."
                frame.primary = "Continue"; frame.secondary = "Back"; frame.note = ""
            }
            Grid {
                width: parent.width; columns: frame.roomy ? 3 : 1; columnSpacing: 16; rowSpacing: 16
                property real cw: frame.roomy ? (width - 32) / 3 : width
                Field { id: dn; width: parent.cw; label: "Device name"; text: win.deviceName; hint: "Shown on Bluetooth and Wi-Fi" }
                Picker {
                    id: tz; width: parent.cw; label: "Time zone"; value: win.timeZone
                    options: backend.timeZones(); searchHint: "Search by city or country"
                    hint: "Search by city or country"
                }
                Picker {
                    id: lang; width: parent.cw; label: "Language and region"; value: win.loc; searchHint: "Search by language or country"
                    hint: "Menus, dates and numbers"
                    Component.onCompleted: {
                        var o = [], codes = backend.languages()
                        for (var i = 0; i < codes.length; i++) {
                            var l = Qt.locale(codes[i].replace("-", "_"))
                            var name = l.nativeLanguageName ? l.nativeLanguageName + (l.nativeTerritoryName ? " (" + l.nativeTerritoryName + ")" : "") : codes[i]
                            o.push({ id: codes[i], label: name.charAt(0).toUpperCase() + name.slice(1) + "  ·  " + codes[i] })
                        }
                        o.sort(function (a, b) { return a.label.localeCompare(b.label) })
                        options = o
                    }
                }
            }
            Card {
                width: parent.width; spacing: 0; pad: 14
                Toggle {
                    width: parent.width; title: "Android app support"
                    sub: win.migrate && win.info.apps > 0 ? "Needed for the " + win.info.apps + " Android apps you're bringing. About 1 GB, after you log in." : "Run Android apps in their own windows (Waydroid). About 1 GB, after you log in."
                    checked: win.android; onCheckedChanged: win.android = checked
                }
                Rectangle { visible: win.android; width: parent.width; height: 1; color: Theme.hair }
                Toggle {
                    visible: win.android
                    width: parent.width; title: "Google Play for Android apps"
                    sub: "Most Play Store apps need it for sign-in and notifications."
                    checked: win.gapps; onCheckedChanged: win.gapps = checked
                }
                Rectangle { width: parent.width; height: 1; color: Theme.hair }
                Toggle { width: parent.width; title: "Tune Fedora for this tablet"; sub: "Recommended. Smoother memory, faster shutdown and updates, fewer background jobs."; checked: win.tune; onCheckedChanged: win.tune = checked }
                Rectangle { width: parent.width; height: 1; color: Theme.hair }
                Toggle { width: parent.width; title: "Media codecs"; sub: "Plays every common video and music format (RPM Fusion, needs Wi-Fi)."; checked: win.codecs; onCheckedChanged: win.codecs = checked }
            }
        }
    }

    // ================================================================ 5. Look and feel
    Component {
        id: lookPage
        Column {
            width: parent.width; spacing: 20
            function next() { win.page = 5 }
            Component.onCompleted: {
                win.plainFrame(); frame.wideContent = true
                frame.eyebrow = ""; frame.title = "Look and feel"
                frame.subtitle = "Pick a layout and how it looks. You can change all of it later in S6 Companion."
                frame.primary = win.migrate ? "Move my stuff in" : "Set it up"; frame.secondary = "Back"; frame.note = "Nothing on your drives is changed or erased."
            }
            LayoutPicker { width: parent.width; value: win.layout; effects: win.effects; onPicked: (id) => win.layout = id }
            Grid {
                width: parent.width; columns: frame.roomy ? 2 : 1; columnSpacing: 28; rowSpacing: 18
                property real cw: frame.roomy ? (width - 28) / 2 : width
                Segmented {
                    width: parent.cw; label: "Size"; value: win.size; onPicked: (id) => win.size = id
                    options: [{ id: "standard", label: "Standard", sub: "The tablet's original size" },
                              { id: "larger", label: "Larger", sub: "Recommended for touch" },
                              { id: "largest", label: "Largest", sub: "Easiest to tap and read" }]
                }
                Segmented {
                    width: parent.cw; label: "Effects"; value: win.effects; onPicked: (id) => win.effects = id
                    options: [{ id: "on", label: "On", sub: "Frosted taskbar and menus (recommended)" },
                              { id: "off", label: "Off", sub: "Solid and simple; saves battery" }]
                }
                Segmented {
                    width: parent.cw; label: "Appearance"; value: win.dark ? "dark" : "light"; onPicked: (id) => win.dark = id === "dark"
                    options: [{ id: "light", label: "Light", sub: win.set.night_mode === "2" ? "Bright Fedora look" : "Bright Fedora look, like your Android" },
                              { id: "dark", label: "Dark", sub: win.set.night_mode === "2" ? "Like your Android" : "Easy on the eyes" }]
                }
                Column {
                    width: parent.cw; spacing: 8
                    visible: !!win.info.tint && win.migrate && win.parts.length > 0
                    Label2 { text: "Accent colour"; strong: true; color: Theme.sub; font.pixelSize: 14; width: parent.width }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [{ on: true, c: win.info.tint ? win.info.tint[win.dark ? "dark" : "light"].accent : "#3C6EB4", name: "From Android" },
                                    { on: false, c: win.dark ? "#51A2DA" : "#3C6EB4", name: "Fedora blue" }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 150; height: 44; radius: 22
                                color: win.useAccent === modelData.on ? Theme.sel : Theme.track
                                border.width: win.useAccent === modelData.on ? 2 : 0; border.color: Theme.accent
                                Row {
                                    anchors.centerIn: parent; spacing: 8
                                    Rectangle { width: 20; height: 20; radius: 10; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                                    Label2 { text: modelData.name; font.pixelSize: 14; strong: win.useAccent === modelData.on; wrapMode: Text.NoWrap; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { anchors.fill: parent; onClicked: win.useAccent = modelData.on }
                            }
                        }
                    }
                    Label2 { text: "Your Material You colour, for Setup and the whole KDE desktop"; font.pixelSize: 13; color: Theme.muted; width: parent.width; elide: Text.ElideRight; wrapMode: Text.NoWrap }
                }
            }
        }
    }

    // ================================================================ 6. Moving in
    Component {
        id: movingPage
        Column {
            id: mp
            width: parent.width; spacing: 14
            property var tasks: []
            property int at: -1
            property bool finished: false
            property int failures: 0
            function next() { if (finished) win.page = 6 }
            Component.onCompleted: {
                frame.eyebrow = ""; frame.title = "Moving in"
                frame.detailsAvailable = true; frame.detailsShown = false; frame.details = ""; frame.progress = 0
                frame.subtitle = "Keep the tablet plugged in. This can take a while for lots of photos."
                frame.primary = "Continue"; frame.secondary = ""; frame.primaryEnabled = false
                frame.note = "Nothing is deleted from your package or drives."
                var t = []
                t.push({ title: "Create your account (" + win.userName + ")", argv: win.h(["create-user", win.userName, win.fullName]), input: win.password + "\n" })
                t.push({ title: "Apply your tablet's settings", argv: win.h(["settings", win.timeZone, win.loc, win.deviceName, win.userName, win.dark ? "dark" : "light"]) })
                t.push({ title: "Remember your layout and choices", argv: win.h(["save-prefs", win.userName, "layout=" + win.layout, "size=" + win.size, "effects=" + win.effects, "migrate=" + (win.migrate ? "yes" : "no"), "android=" + (win.android ? "yes" : "no"), "tune=" + (win.tune ? "yes" : "no")]) })
                t.push({ title: "Set up your desktop: " + win.layout + " layout, " + (win.dark ? "dark" : "light") + " look, " + win.effects + " effects",
                         argv: win.h(["prepare-look", win.userName, win.layout, win.size, win.dark ? "dark" : "light", win.effects,
                                       win.personal && win.useAccent && win.info.tint ? win.info.tint[win.dark ? "dark" : "light"].accent : ""]) })
                t.push({ title: "Your screen size (" + win.size + "): set the moment you log in", skip: true, after: true })
                if (win.tune) {
                    var tunes = ["memory", "logs", "shutdown", "downloads", "background", "protect"]
                    for (var u = 0; u < tunes.length; u++) t.push({ title: "Tune-up: " + ["smoother memory use", "smaller system log", "faster shutdown", "faster update downloads", "fewer background jobs", "protect the tablet's own parts from updates"][u], argv: win.h(["tune", tunes[u], "on"]) })
                }
                // Codec drivers can need matching graphics libraries: installed at the restart, before the first login.
                if (win.codecs) t.push({ title: "Media codecs (RPM Fusion): added during the restart", argv: win.h(["schedule", "codecs"]) })
                for (var i = 0; i < (win.migrate ? win.parts.length : 0); i++)
                    t.push({ title: "Your files and settings" + (win.parts.length > 1 ? " (part " + (i + 1) + " of " + win.parts.length + ")" : ""), argv: win.h(["restore-files", win.userName, win.parts[i]]), files: true, part: "move" })
                for (var j = 0; j < (win.migrate ? win.parts.length : 0); j++)
                    // Installed during the restart after setup (after Fedora's update), never under a running desktop.
                    t.push({ title: "Your Linux apps" + (win.parts.length > 1 ? " (part " + (j + 1) + ")" : "") + ": installed during the restart", argv: win.h(["schedule-linux-apps", win.userName, win.parts[j]]), needsNet: true, part: "move" })
                if (win.migrate && win.parts.length === 0) t.push({ title: "Your files: no package found (bring it over later in S6 Companion)", skip: true, part: "move" })
                if (win.android) t.push({ title: win.migrate && win.info.apps > 0 ? "Android apps: they finish installing after you log in" : "Android app support: set up after you log in", skip: true, after: true, part: "move" })
                for (var k = 0; k < t.length; k++) { t[k].state = "wait"; t[k].detail = ""; t[k].progress = -1 }
                tasks = t
                step()
            }
            // the terminal view keeps the last 400 lines
            property var log: []
            function say(line) { log.push(line); if (log.length > 400) log.splice(0, log.length - 400); frame.details = log.join("\n") }
            function overall() {
                var n = 0, d = 0
                for (var i = 0; i < tasks.length; i++) { if (tasks[i].skip && tasks[i].after) continue; n++; if (i < at || tasks[i].state === "done" || tasks[i].state === "fail" || tasks[i].state === "skip") d += 1; else if (i === at && tasks[i].progress > 0) d += tasks[i].progress }
                frame.progress = n ? Math.min(1, d / n) : 1
            }
            function setTask(i, props) { var t = tasks.slice(); for (var k in props) t[i][k] = props[k]; tasks = t }
            function step() {
                at++
                overall()
                if (at >= tasks.length) {
                    finished = true; frame.primaryEnabled = true; frame.progress = 1
                    frame.progressLabel = failures > 0 ? "Finished with " + failures + " problem(s)" : "All done"
                    say("")
                    say(failures > 0 ? "== finished, " + failures + " problem(s)" : "== all done")
                    frame.subtitle = failures > 0 ? "Done, with " + failures + " problem(s). Details are in the log; S6 Companion can try again." : "Everything's in place."
                    return
                }
                var t = tasks[at]
                if (t.skip) { setTask(at, { state: t.after ? "wait" : "skip" }); step(); return }
                if (t.needsNet && !win.online) { setTask(at, { state: "skip", detail: "No Wi-Fi: S6 Companion installs them later." }); step(); return }
                setTask(at, { state: "run" })
                var idx = at
                frame.progressLabel = t.title
                say((at > 0 ? "\n" : "") + "== " + t.title)
                say("$ " + (t.argv[0] === win.helper[0] ? ["s6-helper"].concat(t.argv.slice(win.helper.length)) : t.argv).map(function (a) { return /[\s'"]/.test(a) ? "'" + a + "'" : a }).join(" "))
                win.run("task" + idx, t.argv, function (l) {
                    mp.say(l)
                    var m = /checking (\d+) of (\d+)/.exec(l)
                    if (m) { setTask(idx, { progress: parseInt(m[1]) / Math.max(1, parseInt(m[2])), detail: "Checking your package: " + m[1] + " of " + m[2] }); mp.overall() }
                    else if (/^==/.test(l)) setTask(idx, { detail: l.replace(/=/g, "").trim() })
                    else if (/->|installed|Installing|added|set:/.test(l)) setTask(idx, { detail: l.trim() })
                }, function (code) {
                    mp.say(code === 0 ? "-- ok" : "-- exit code " + code)
                    if (code !== 0) failures++
                    setTask(idx, { state: code === 0 ? "done" : "fail", progress: -1, detail: code === 0 ? (tasks[idx].detail.indexOf("Checking") === 0 ? "" : tasks[idx].detail) : "Didn't finish (code " + code + "). The setup continues." })
                    if (idx === 0 && code !== 0) { // no account: nothing else can go on
                        frame.subtitle = "Your account couldn't be created. Go back and try another user name."
                        frame.secondary = "Back"; win.page = 2; return
                    }
                    step()
                }, t.input)
            }
            Card {
                width: parent.width; spacing: 16
                Repeater {
                    model: mp.tasks
                    // Two parts: setting up the tablet, then moving your things in (files, apps, Android).
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: mp.width - 36; spacing: 6
                        Label2 {
                            visible: index === 0 || (mp.tasks[index - 1].part || "setup") !== (modelData.part || "setup")
                            text: (modelData.part || "setup") === "move" ? "Moving your things in" : "Setting up your tablet"
                            strong: true; color: Theme.sub; font.pixelSize: 15; topPadding: index === 0 ? 0 : 12; width: parent.width
                        }
                        TaskRow { width: parent.width; title: modelData.title; detail: modelData.detail; status: modelData.state; progress: modelData.progress }
                    }
                }
            }
        }
    }

    // ================================================================ 7. All set
    Component {
        id: donePage
        Column {
            id: dp
            width: parent.width; spacing: 18
            property bool leaving: false
            function next() {
                if (leaving) return
                leaving = true; frame.primaryEnabled = false; frame.primary = "Restarting..."
                // With Wi-Fi, the restart brings Fedora up to date (and adds the blur/Darkly extras) before the first login,
                // so the first desktop is complete; offline, S6 Companion offers it later.
                var jobs = win.online ? ("update" + (win.effects !== "off" ? ",extras" : "")) : ""
                win.run("finish", win.h(["finish", win.userName, win.autoLogin ? "1" : "0", win.removeFedora ? "1" : "0", win.gapps ? "1" : "0", win.dark ? "dark" : "light", jobs]),
                        null, function (code) {
                    if (code !== 0) { leaving = false; frame.primaryEnabled = true; frame.primary = "Try again"; frame.subtitle = "Something went wrong handing over to your account. Tap Try again." }
                })
            }
            Component.onCompleted: {
                win.plainFrame(); frame.eyebrow = ""; frame.title = "All set, " + win.firstName() + "!"
                frame.subtitle = win.online ? "Your tablet is ready. While it restarts it brings Fedora up to date (this can take a while; the progress is shown), then opens your own account, all set up."
                                            : "Your tablet is ready. It restarts once (about a minute) into your own account, then S6 Companion finishes your Android apps and shows you around."
                frame.primary = "Restart into my account"; frame.secondary = ""; frame.primaryEnabled = true; frame.note = ""
            }
            Card {
                width: parent.width
                TaskRow { title: "Your account: " + win.fullName + " (" + win.userName + ")" + (win.autoLogin ? ", logs in automatically" : ""); status: "done" }
                TaskRow { title: "Device name " + win.deviceName + ", time zone " + win.timeZone + ", " + (win.dark ? "dark" : "light") + " look"; status: "done" }
                TaskRow { title: !win.migrate ? "A fresh start: bring things over later in S6 Companion if you like" : (win.parts.length > 0 ? "Your files are in your home folder" : "Your files: bring them over later in S6 Companion"); status: win.migrate && win.parts.length > 0 ? "done" : "skip" }
                TaskRow { title: "Your desktop is set up; the screen size is set the moment you log in"; status: "done" }
                TaskRow { visible: win.android; title: "Android apps finish after you log in" + (win.gapps ? ", with Google Play" : ""); status: "wait" }
            }
            Card {
                width: parent.width; warn: true
                visible: win.want > 1 || win.parts.some(function (p) { return p.indexOf("/run/") === 0 })
                Label2 { text: "Keep your USB drive connected (through the powered hub) until S6 Companion says your Android apps are done."; color: Theme.warnText; width: parent.width }
            }
        }
    }
}
