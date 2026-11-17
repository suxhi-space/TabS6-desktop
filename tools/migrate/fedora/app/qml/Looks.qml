import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

// S6 Looks: how the tablet looks and feels, as a KDE app (Kirigami, like System Settings): categories on the left,
// a form on the right, and on each page the matching System Settings pages one tap away. S6's own choices are
// made by /usr/local/bin/s6-look in your session; the boot screen by S6's root helper (it asks for your password).
Kirigami.ApplicationWindow {
    id: win
    width: 1280; height: 800
    minimumWidth: Kirigami.Units.gridUnit * 22
    title: "S6 Looks"
    pageStack.defaultColumnWidth: Kirigami.Units.gridUnit * 15
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.ToolBar
    pageStack.initialPage: categories

    readonly property var setup: { try { return JSON.parse(backend.setupState()) } catch (e) { return {} } }
    readonly property var helper: backend.mock ? ["true"] : ["pkexec", backend.helper]
    function h(args) { return helper.concat(args) }
    function kcm(name) { backend.detach("systemsettings " + name) }   // a System Settings page
    property int pageCount: sections.length          // for the screenshot tool
    property int page: 0
    onPageChanged: show(page)

    // S6's previews follow KDE's colours
    function lum(c) { return c.r * 0.299 + c.g * 0.587 + c.b * 0.114 }
    Component.onCompleted: { Theme.dark = lum(Kirigami.Theme.backgroundColor) < 0.5; load(); show(0) }

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
    property bool failed: false
    function load() {
        var c = {}
        run("lookst", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "status"], function (l) { var f = l.split("|"); c[f[0]] = f[1] },
            function () { if (backend.mock) c = { LAYOUT: "touch", EFFECTS: "soft", SIZE: "larger", HASDARKLY: "yes", APPSTYLE: "darkly", PLASMASTYLE: "darkly" }; cur = c })
        var x = {}
        run("extras", backend.mock ? ["true"] : ["/usr/local/bin/s6-look", "extras"], function (l) { var f = l.split("|"); x[f[0]] = f.slice(1) },
            function () { if (backend.mock) x = { BBDX: ["installed", "loaded"], DARKLY: ["installed"] }; extras = x })
    }
    function apply(args) {
        out = "Applying..."; failed = false; var last = ""
        run("look", backend.mock ? ["true"] : ["/usr/local/bin/s6-look"].concat(args), function (l) { win.out = l; last = l },
            function (c) { win.failed = c !== 0; win.out = c === 0 ? (last || "Done.") : "That didn't work" + (last ? ": " + last : "."); load() })
    }

    readonly property var sections: [
        { name: "Layout", icon: "preferences-desktop-theme-global", page: layoutPage },
        { name: "Colours & style", icon: "preferences-desktop-color", page: stylePage },
        { name: "Wallpaper", icon: "preferences-desktop-wallpaper", page: wallPage },
        { name: "Windows", icon: "preferences-system-windows", page: windowsPage },
        { name: "Keyboard", icon: "input-keyboard-virtual", page: keyboardPage },
        { name: "Touch & size", icon: "preferences-desktop-touchscreen", page: touchPage },
        { name: "Start-up", icon: "preferences-system-startup", page: startPage },
        { name: "Files", icon: "system-file-manager", page: filesPage }]
    property int current: -1
    function show(i) {
        if (i === current && pageStack.depth > 1) return
        current = i; out = ""
        while (pageStack.depth > 1) pageStack.pop()
        pageStack.push(sections[i].page)
    }

    // ---------------------------------------------------------------- the category list
    Kirigami.ScrollablePage {
        id: categories
        title: "S6 Looks"
        ListView {
            model: win.sections
            delegate: QQC2.ItemDelegate {
                required property var modelData
                required property int index
                width: ListView.view.width
                text: modelData.name
                icon.name: modelData.icon
                highlighted: win.current === index
                onClicked: win.show(index)
            }
        }
    }

    // a row of buttons that open System Settings pages: [[label, kcm], ...]
    component SettingsLinks: Flow {
        property var links: []
        Kirigami.FormData.label: "In System Settings:"
        Layout.fillWidth: true
        Layout.preferredWidth: Kirigami.Units.gridUnit * 30
        spacing: Kirigami.Units.smallSpacing
        Repeater {
            model: parent.links
            QQC2.Button { required property var modelData; text: modelData[0]; icon.name: "configure"; onClicked: win.kcm(modelData[1]) }
        }
    }
    // the result of the last change
    component Result: Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: win.out !== ""
        text: win.out
        type: win.failed ? Kirigami.MessageType.Error : Kirigami.MessageType.Information
    }

    // ---------------------------------------------------------------- Layout
    Component {
        id: layoutPage
        Kirigami.ScrollablePage {
            title: "Layout"
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap
                             text: "Where the taskbar, the apps and the clock go. Your pinned apps come along when you switch." }
                GridLayout {
                    id: grid
                    Layout.fillWidth: true
                    columns: width > Kirigami.Units.gridUnit * 36 ? 3 : 2
                    columnSpacing: Kirigami.Units.largeSpacing; rowSpacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: [{ id: "touch", name: "Touch", sub: "One bar with big icons, made for fingers" },
                                { id: "centered", name: "Centred", sub: "App icons in the middle of the bar" },
                                { id: "traditional", name: "Traditional", sub: "Menu on the left, window names" },
                                { id: "topdock", name: "Top bar & dock", sub: "Menu and clock on top, a dock below" },
                                { id: "plasma", name: "Plasma", sub: "KDE's standard desktop" }]
                        delegate: QQC2.ItemDelegate {
                            id: lay
                            required property var modelData
                            readonly property bool on: (win.cur.LAYOUT || win.setup.layout || "touch") === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
                            highlighted: on
                            onClicked: win.apply(["layout", modelData.id])
                            contentItem: ColumnLayout {
                                spacing: Kirigami.Units.smallSpacing
                                LayoutPreview { Layout.fillWidth: true; Layout.preferredHeight: width * 0.55; layout: lay.modelData.id
                                                effects: win.cur.EFFECTS || "soft" }
                                QQC2.RadioButton { text: lay.modelData.name; checked: lay.on; font.bold: true
                                                   onClicked: win.apply(["layout", lay.modelData.id]) }
                                QQC2.Label { Layout.fillWidth: true; text: lay.modelData.sub; wrapMode: Text.Wrap; opacity: 0.7 }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Label { text: "Taskbar gone after turning on auto-hide?"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    QQC2.Button { text: "Show the taskbar again"; icon.name: "view-visible"; onClicked: win.apply(["show-panels"]) }
                }
                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    SettingsLinks { links: [["Global theme", "kcm_lookandfeel"], ["Notifications", "kcm_notifications"]] }
                }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Colours & style
    Component {
        id: stylePage
        Kirigami.ScrollablePage {
            title: "Colours & style"
            Kirigami.FormLayout {
                QQC2.ButtonGroup { id: modeGroup }
                QQC2.RadioButton { Kirigami.FormData.label: "Appearance:"; text: "Light"; QQC2.ButtonGroup.group: modeGroup
                                   checked: win.lum(Kirigami.Theme.backgroundColor) >= 0.5; onClicked: win.apply(["theme", "light"]) }
                QQC2.RadioButton { text: "Dark"; QQC2.ButtonGroup.group: modeGroup
                                   checked: win.lum(Kirigami.Theme.backgroundColor) < 0.5; onClicked: win.apply(["theme", "dark"]) }
                QQC2.ComboBox {
                    Kirigami.FormData.label: "Apps and window borders:"
                    model: ["Darkly: rounded, frosted, modern", "Breeze: KDE's own"]
                    currentIndex: win.cur.APPSTYLE === "darkly" ? 0 : 1
                    onActivated: (i) => win.apply(["appstyle", i === 0 ? "darkly" : "breeze"])
                }
                QQC2.ComboBox {
                    Kirigami.FormData.label: "Taskbar, menus and pop-ups:"
                    model: ["Darkly (see-through)", "Breeze"]
                    currentIndex: win.cur.PLASMASTYLE === "darkly" ? 0 : 1
                    onActivated: (i) => win.apply(["plasmastyle", i === 0 ? "darkly" : "breeze"])
                }
                QQC2.ButtonGroup { id: fxGroup }
                QQC2.RadioButton { Kirigami.FormData.label: "Effects:"; text: "Off: solid, saves battery"; QQC2.ButtonGroup.group: fxGroup
                                   checked: win.cur.EFFECTS === "off"; onClicked: win.apply(["effects", "off"]) }
                QQC2.RadioButton { text: "Soft: frosted panels and menus"; QQC2.ButtonGroup.group: fxGroup
                                   checked: (win.cur.EFFECTS || "soft") === "soft"; onClicked: win.apply(["effects", "soft"]) }
                QQC2.RadioButton { text: "Glassy: see-through panels, menus and background windows"; QQC2.ButtonGroup.group: fxGroup
                                   checked: win.cur.EFFECTS === "glassy"; onClicked: win.apply(["effects", "glassy"]) }
                QQC2.Label {
                    Kirigami.FormData.label: "Better Blur and Darkly:"
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    readonly property bool bb: (win.extras.BBDX || [""])[0] === "installed"
                    readonly property bool dk: (win.extras.DARKLY || [""])[0] === "installed"
                    text: (bb ? ((win.extras.BBDX || [])[1] === "loaded" ? "Better Blur is on. " : "Better Blur is installed but doesn't match this KWin; Plasma's blur is used. ") : "Better Blur isn't installed. ")
                          + (dk ? "Darkly is installed." : "Darkly isn't installed.")
                }
                QQC2.Button {
                    visible: (win.extras.DARKLY || [""])[0] !== "installed"
                    text: "Add Darkly at the next restart"; icon.name: "list-add"
                    onClicked: win.run("extrasi", win.h(["look-extras"]), function (l) { win.out = l }, null)
                }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Colours", "kcm_colors"], ["Global theme", "kcm_lookandfeel"], ["Plasma style", "kcm_desktoptheme"],
                                        ["Application style", "kcm_style"], ["Icons", "kcm_icons"], ["Fonts", "kcm_fonts"], ["Cursors", "kcm_cursortheme"]] }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Wallpaper
    Component {
        id: wallPage
        Kirigami.ScrollablePage {
            title: "Wallpaper"
            Kirigami.FormLayout {
                Image {
                    Kirigami.FormData.label: "From your Android tablet:"
                    visible: (win.cur.WALLANDROID || "") !== ""
                    source: win.cur.WALLANDROID ? "file://" + win.cur.WALLANDROID : ""
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 16; Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                    fillMode: Image.PreserveAspectCrop; sourceSize.width: 512; asynchronous: true
                }
                QQC2.Button { visible: (win.cur.WALLANDROID || "") !== ""; text: "Use my Android wallpaper"; icon.name: "smartphone"
                              onClicked: win.apply(["wallpaper", "android"]) }
                QQC2.Label { visible: (win.cur.WALLANDROID || "") === ""; Kirigami.FormData.label: "From your Android tablet:"
                             text: "No Android wallpaper was brought over."; opacity: 0.7 }
                QQC2.Button { Kirigami.FormData.label: "Fedora's:"; text: "Use Fedora's wallpaper"; icon.name: "fedora-logo-icon"
                              onClicked: win.apply(["wallpaper", "default"]) }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Wallpaper: pictures, slideshows, colours", "kcm_wallpaper"], ["Lock screen", "kcm_screenlocker"]] }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Windows
    Component {
        id: windowsPage
        Kirigami.ScrollablePage {
            title: "Windows"
            Kirigami.FormLayout {
                QQC2.Label {
                    Kirigami.FormData.label: "Window buttons:"
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "They follow the layout: on the left like a Mac for \"Top bar & dock\", on the right for the others. Apps stay on screen when the tablet turns."
                }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Window decorations", "kcm_kwindecoration"], ["Window behaviour", "kcm_kwinoptions"], ["Desktop effects", "kcm_kwin_effects"],
                                        ["Window rules", "kcm_kwinrules"], ["Task switcher", "kcm_kwintabbox"], ["Virtual desktops", "kcm_kwin_virtualdesktops"],
                                        ["Screen edges", "kcm_kwinscreenedges"], ["Touch screen gestures", "kcm_kwintouchscreen"]] }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Keyboard
    Component {
        id: keyboardPage
        Kirigami.ScrollablePage {
            id: kp
            title: "Keyboard"
            property string kbTheme: win.cur.KBTHEME || "auto"
            property string kbAccent: win.cur.KBACCENT || "system"
            property bool kbBorders: win.cur.KBBORDERS !== "false"
            property bool kbHints: win.cur.KBHINTS !== "false"
            property bool kbNumrow: win.cur.KBNUMROW !== "false"
            property string kbHeight: win.cur.KBHEIGHT || "normal"
            property string kbMode: win.cur.KBMODE || "docked"
            function save() {
                win.apply(["kbd-style", "theme=" + kbTheme, "accent=" + kbAccent, "borders=" + kbBorders, "hints=" + kbHints,
                           "height=" + kbHeight, "mode=" + kbMode, "numrow=" + kbNumrow])
            }
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                KeyboardPreview {
                    Layout.fillWidth: true; Layout.maximumWidth: Kirigami.Units.gridUnit * 34; Layout.alignment: Qt.AlignHCenter
                    theme: kp.kbTheme; accent: kp.kbAccent; borders: kp.kbBorders; hints: kp.kbHints; kbheight: kp.kbHeight; mode: kp.kbMode; numrow: kp.kbNumrow
                }
                Kirigami.FormLayout {
                    Layout.fillWidth: true
                    QQC2.Switch {
                        Kirigami.FormData.label: "S6 Keyboard:"
                        text: "Gboard layout, emoji, clipboard, hide button and these themes"
                        checked: !backend.exists(backend.home + "/.config/s6migrate/stock-keyboard")
                        onToggled: win.run("kbd", backend.mock ? ["true"] : ["/bin/sh", "-c", checked
                            ? "rm -f \"$HOME/.config/s6migrate/stock-keyboard\"; pkill -f maliit-keyboard"
                            : "mkdir -p \"$HOME/.config/s6migrate\" && touch \"$HOME/.config/s6migrate/stock-keyboard\"; pkill -f maliit-keyboard"], null, null)
                    }
                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Theme:"
                        readonly property var ids: ["auto", "light", "dark", "black", "tinted"]
                        model: ["Auto (light or dark mode)", "Light", "Dark", "Black (AMOLED)", "Tinted in your colour"]
                        currentIndex: Math.max(0, ids.indexOf(kp.kbTheme))
                        onActivated: (i) => { kp.kbTheme = ids[i]; kp.save() }
                    }
                    Flow {
                        Kirigami.FormData.label: "Enter key colour:"
                        Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: ["system", "#4285F4", "#34A853", "#EA4335", "#FBBC04", "#A142F4", "#F06292", "#00ACC1"]
                            delegate: QQC2.AbstractButton {
                                id: sw
                                required property string modelData
                                width: Kirigami.Units.gridUnit * 2; height: width
                                checkable: true; checked: kp.kbAccent === modelData
                                QQC2.ToolTip.text: modelData === "system" ? "Your accent colour" : modelData; QQC2.ToolTip.visible: hovered
                                background: Rectangle { radius: width / 2; color: sw.modelData === "system" ? Kirigami.Theme.highlightColor : sw.modelData
                                                        border.width: sw.checked ? 3 : 0; border.color: Kirigami.Theme.textColor }
                                onClicked: { kp.kbAccent = modelData; kp.save() }
                            }
                        }
                    }
                    QQC2.Switch { Kirigami.FormData.label: "Number row:"; text: "1 to 0 above the letters, like Gboard"; checked: kp.kbNumrow
                                  onToggled: { kp.kbNumrow = checked; kp.save() } }
                    QQC2.Switch { Kirigami.FormData.label: "Key borders:"; text: "Keys drawn as keys (off: only the letters)"; checked: kp.kbBorders
                                  onToggled: { kp.kbBorders = checked; kp.save() } }
                    QQC2.Switch { Kirigami.FormData.label: "Hints:"; text: "Symbols on the keys (hold a key to type them)"; checked: kp.kbHints
                                  onToggled: { kp.kbHints = checked; kp.save() } }
                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Height:"
                        readonly property var ids: ["short", "normal", "tall"]
                        model: ["Short", "Normal", "Tall"]
                        currentIndex: Math.max(0, ids.indexOf(kp.kbHeight))
                        onActivated: (i) => { kp.kbHeight = ids[i]; kp.save() }
                    }
                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Position:"
                        readonly property var ids: ["docked", "floating"]
                        model: ["Docked: full width along the bottom", "Floating: smaller and rounded, bottom centre"]
                        currentIndex: Math.max(0, ids.indexOf(kp.kbMode))
                        onActivated: (i) => { kp.kbMode = ids[i]; kp.save() }
                    }
                    QQC2.Switch {
                        Kirigami.FormData.label: "Taskbar:"
                        text: "Hide it while the full keyboard is open"
                        checked: win.cur.KBDOVER === "on"
                        onToggled: win.apply(["kbd-over", checked ? "on" : "off"])
                    }
                    Kirigami.Separator { Kirigami.FormData.isSection: true }
                    SettingsLinks { links: [["Virtual keyboard", "kcm_virtualkeyboard"], ["Keyboard layouts", "kcm_keyboard"]] }
                    Result {}
                }
            }
        }
    }

    // ---------------------------------------------------------------- Touch & size
    Component {
        id: touchPage
        Kirigami.ScrollablePage {
            title: "Touch & size"
            Kirigami.FormLayout {
                QQC2.ButtonGroup { id: sizeGroup }
                QQC2.RadioButton { Kirigami.FormData.label: "Size:"; text: "Standard: the tablet's original size"; QQC2.ButtonGroup.group: sizeGroup
                                   checked: win.cur.SIZE === "standard"; onClicked: win.apply(["size", "standard"]) }
                QQC2.RadioButton { text: "Larger: recommended for touch"; QQC2.ButtonGroup.group: sizeGroup
                                   checked: (win.cur.SIZE || win.setup.size || "larger") === "larger"; onClicked: win.apply(["size", "larger"]) }
                QQC2.RadioButton { text: "Largest: easiest to tap and read"; QQC2.ButtonGroup.group: sizeGroup
                                   checked: win.cur.SIZE === "largest"; onClicked: win.apply(["size", "largest"]) }
                QQC2.Switch { Kirigami.FormData.label: "Menus:"; text: "Touch size (taller rows, also what holding something opens)"
                              checked: win.cur.MENUS !== "normal"; onToggled: win.apply(["menus", checked ? "touch" : "normal"]) }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Display and scale", "kcm_kscreen"], ["Touchscreen", "kcm_touchscreen"], ["Touch gestures", "kcm_kwintouchscreen"],
                                        ["Pen", "kcm_tablet"]] }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Start-up
    Component {
        id: startPage
        Kirigami.ScrollablePage {
            id: sp
            title: "Start-up"
            readonly property string boot: (backend.read("/var/lib/s6migrate/boot-screen") || "verbose").trim()
            Kirigami.FormLayout {
                QQC2.ButtonGroup { id: bootGroup }
                QQC2.RadioButton { Kirigami.FormData.label: "While the tablet starts:"; text: "Fedora logo and a progress bar"; QQC2.ButtonGroup.group: bootGroup
                                   checked: sp.boot === "quiet"; onClicked: win.run("boot", win.h(["boot-screen", "quiet"]), function (l) { win.out = l }, null) }
                QQC2.RadioButton { text: "Text (every start-up message, useful when something goes wrong)"; QQC2.ButtonGroup.group: bootGroup
                                   checked: sp.boot !== "quiet"; onClicked: win.run("boot", win.h(["boot-screen", "verbose"]), function (l) { win.out = l }, null) }
                QQC2.ButtonGroup { id: splashGroup }
                QQC2.RadioButton { Kirigami.FormData.label: "After logging in:"; text: "Your wallpaper with a thin loading bar"; QQC2.ButtonGroup.group: splashGroup
                                   checked: (win.cur.SPLASH || "s6") === "s6"; onClicked: win.apply(["splash", "s6"]) }
                QQC2.RadioButton { text: "None: straight to the desktop"; QQC2.ButtonGroup.group: splashGroup
                                   checked: win.cur.SPLASH === "none"; onClicked: win.apply(["splash", "none"]) }
                QQC2.Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7
                             text: "Holding Volume Down while it starts still opens the boot menu." }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Login screen", "kcm_sddm"], ["Splash screen", "kcm_splashscreen"], ["Autostart", "kcm_autostart"]] }
                Result {}
            }
        }
    }

    // ---------------------------------------------------------------- Files
    Component {
        id: filesPage
        Kirigami.ScrollablePage {
            title: "Files"
            Kirigami.FormLayout {
                QQC2.ComboBox {
                    Kirigami.FormData.label: "File manager:"
                    model: ["Dolphin (KDE's)", "COSMIC Files (written in Rust; installed at the next restart)"]
                    currentIndex: win.cur.FILES === "cosmic" ? 1 : 0
                    onActivated: (i) => { if (i === 1) win.run("sched", win.h(["schedule", "cosmicfiles"]), null, null); win.apply(["files", i === 1 ? "cosmic" : "dolphin"]) }
                }
                QQC2.Button { Kirigami.FormData.label: "Dolphin looking odd?"; text: "Back to Dolphin's own look"; icon.name: "edit-undo"
                              onClicked: win.apply(["dolphin", "default"]) }
                Kirigami.Separator { Kirigami.FormData.isSection: true }
                SettingsLinks { links: [["Default apps", "kcm_componentchooser"], ["File associations", "kcm_filetypes"], ["File search", "kcm_baloofile"]] }
                Result {}
            }
        }
    }
}
