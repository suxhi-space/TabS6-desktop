import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

// S6 Setup's frame, in the spirit of macOS Setup Assistant and Android's setup: one floating, rounded window over a
// soft backdrop; a slim step indicator; a large icon, a centred title and text; the page below; Back on the left and a
// pill-shaped Continue on the right. Optional: a progress bar that stays put above the scrolling page, and a terminal
// view of what is running ("Show details"). Same interface as Frame.qml, so the pages don't change.
Item {
    id: f
    objectName: "setupFrame"
    property var steps: []
    property int current: 0
    property string icon: ""
    property string eyebrow: ""
    property string title: ""
    property string subtitle: ""
    property string note: ""
    property string primary: ""
    property string secondary: ""
    property bool primaryEnabled: true
    property real keyboardHeight: 0
    property real progress: -1            // 0..1 shows the fixed progress bar
    property string progressLabel: ""
    property bool detailsAvailable: false
    property bool detailsShown: false
    property string details: ""
    property bool wideContent: false
    property url wallpaper: ""            // shown blurred behind the window; cross-fades when it changes
    default property alias content: body.data
    signal primaryClicked()
    signal secondaryClicked()
    readonly property real contentWidth: Math.min(card.width - 96, wideContent ? 880 : 680)
    readonly property bool roomy: contentWidth >= 600
    readonly property bool wide: card.width >= 820
    readonly property int pad: 48
    readonly property real room: flick.height - 16      // height a page can use without scrolling

    // ---- backdrop: a soft gradient with three blurred colour fields (like a macOS wallpaper)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Theme.back1 }
            GradientStop { position: 1; color: Theme.back2 }
        }
    }
    Item {
        id: blobs
        anchors.fill: parent; anchors.margins: -80
        visible: false
        Rectangle { x: -parent.width * 0.10; y: -parent.height * 0.15; width: parent.width * 0.55; height: width; radius: width / 2; color: Theme.blob1 }
        Rectangle { x: parent.width * 0.55; y: parent.height * 0.05; width: parent.width * 0.50; height: width; radius: width / 2; color: Theme.blob2 }
        Rectangle { x: parent.width * 0.25; y: parent.height * 0.55; width: parent.width * 0.55; height: width; radius: width / 2; color: Theme.blob3 }
    }
    MultiEffect { source: blobs; anchors.fill: blobs; blurEnabled: true; blur: 1.0; blurMax: 64; opacity: Theme.dark ? 0.55 : 0.75 }

    // the wallpaper (Fedora's, then yours from Android once you choose to bring your stuff), blurred like a frosted desk
    property bool _onA: true
    function _show(u) {
        if (String(u) === "") return
        if (String(wpA.source) === "" ) { wpA.source = u; _onA = true; return }
        if (_onA) { if (String(wpA.source) === String(u)) return; wpB.source = u } else { if (String(wpB.source) === String(u)) return; wpA.source = u }
        _onA = !_onA
    }
    onWallpaperChanged: _show(wallpaper)
    Component.onCompleted: _show(wallpaper)
    Item {
        id: walls
        anchors.fill: parent; anchors.margins: -80
        visible: false
        Image { id: wpA; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; sourceSize.width: 720; asynchronous: true; cache: false
                opacity: f._onA && status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } } }
        Image { id: wpB; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; sourceSize.width: 720; asynchronous: true; cache: false
                opacity: !f._onA && status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } } }
    }
    MultiEffect { source: walls; anchors.fill: walls; blurEnabled: true; blur: 1.0; blurMax: 48; saturation: 0.15 }
    Rectangle { anchors.fill: parent; color: Theme.dark ? "#000000" : "#FFFFFF"; opacity: (wpA.status === Image.Ready || wpB.status === Image.Ready) ? (Theme.dark ? 0.35 : 0.18) : 0 }

    // ---- the window
    Item {
        id: holder
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(16, (parent.height - f.keyboardHeight - height) / 2)
        // a window floating on the desk: a margin of backdrop all round, as large as fits up to 1040 x 760
        width: Math.min(parent.width - 48, 1040)
        height: Math.min(parent.height - f.keyboardHeight - 32, 760)
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // the shadow is drawn separately, so the window itself shows even where effects can't run
        Rectangle { id: shade; anchors.fill: parent; radius: 26; color: "#000000"; visible: false }
        MultiEffect { source: shade; anchors.fill: shade; shadowEnabled: true; shadowBlur: 1.0; shadowVerticalOffset: 18; shadowOpacity: Theme.dark ? 0.55 : 0.20; shadowColor: "#000000"; paddingRect: Qt.rect(0, 0, 0, 0); autoPaddingEnabled: true }
        Rectangle {
            id: card
            anchors.fill: parent
            radius: 26
            color: Theme.card
            border.width: 1; border.color: Theme.cardBorder
        }

        // step indicator: capsules, the current one stretched (Android style)
        Row {
            id: dots
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20; spacing: 6
            Repeater {
                model: f.steps.length
                Rectangle {
                    width: index === f.current ? 26 : 8; height: 8; radius: 4
                    color: index <= f.current ? Theme.accent : Theme.track
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
        }

        // header: icon tile, eyebrow, title, subtitle, fixed progress
        Column {
            id: head
            anchors.horizontalCenter: parent.horizontalCenter
            y: 42; width: f.contentWidth; spacing: 6
            Rectangle {
                visible: f.icon !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 56; radius: 15
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.18) }
                    GradientStop { position: 1; color: Theme.dark ? Qt.darker(Theme.accent, 1.35) : Qt.darker(Theme.accent, 1.12) }
                }
                Glyph { anchors.centerIn: parent; kind: f.icon; tint: "#FFFFFF"; width: f.icon === "tablet" ? 36 : 28; height: width }
            }
            Item { width: 1; height: 2 }
            Label2 {
                visible: f.eyebrow !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: f.eyebrow.toUpperCase(); font.pixelSize: 12; strong: true; color: Theme.accentText; font.letterSpacing: 1.2
            }
            Label2 { text: f.title; display: true; font.pixelSize: 30; width: parent.width; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.05 }
            Label2 {
                visible: f.subtitle !== ""; text: f.subtitle; color: Theme.sub; font.pixelSize: 15
                width: Math.min(parent.width, 560); anchors.horizontalCenter: parent.horizontalCenter; horizontalAlignment: Text.AlignHCenter
            }
            Column {
                visible: f.progress >= 0; width: parent.width; spacing: 8; topPadding: 6
                Rectangle {
                    width: parent.width; height: 6; radius: 3; color: Theme.track
                    Rectangle { width: Math.max(6, parent.width * Math.min(1, f.progress)); height: parent.height; radius: 3; color: Theme.accent
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
                }
                Item {
                    width: parent.width; height: 22
                    Label2 { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: f.progressLabel; font.pixelSize: 13; color: Theme.muted; elide: Text.ElideRight; wrapMode: Text.NoWrap; width: parent.width - det.width - 12 }
                    Label2 {
                        id: det; visible: f.detailsAvailable
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: (f.detailsShown ? "Hide details" : "Show details") + (f.detailsShown ? "  ▾" : "  ▸"); font.pixelSize: 13; strong: true; color: Theme.accentText; wrapMode: Text.NoWrap
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: f.detailsShown = !f.detailsShown }
                    }
                }
            }
        }

        // the page (scrolls under the fixed header)
        Flickable {
            id: flick
            objectName: "flick"
            anchors { top: head.bottom; topMargin: 16; left: parent.left; right: parent.right; bottom: term.visible ? term.top : foot.top; bottomMargin: 10 }
            contentHeight: body.implicitHeight + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Column { id: body; x: (flick.width - width) / 2; width: f.contentWidth; spacing: 16 }
        }

        // terminal view of what is running
        Rectangle {
            id: term
            visible: f.detailsAvailable && f.detailsShown
            anchors { left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 32; rightMargin: 32; bottomMargin: 10 }
            height: Math.max(140, (foot.y - head.y - head.height) * 0.42)
            radius: 12; color: Theme.term
            Flickable {
                id: tflick
                anchors.fill: parent; anchors.margins: 12
                contentHeight: ttext.height; clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
                Text {
                    id: ttext; width: tflick.width
                    text: f.details || "Waiting for output..."
                    color: f.details ? Theme.termText : Theme.termDim
                    font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; lineHeight: 1.15
                }
            }
        }

        // footer: Back as a text button on the left, the main action as a pill on the right
        Item {
            id: foot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 76
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 32; rightMargin: 32 } height: 1; color: Theme.hair }
            Label2 {
                id: back
                visible: f.secondary !== ""
                anchors.left: parent.left; anchors.leftMargin: 36; anchors.verticalCenter: parent.verticalCenter
                text: "‹  " + f.secondary; font.pixelSize: 16; strong: true; color: Theme.accentText; wrapMode: Text.NoWrap
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: f.secondaryClicked() }
            }
            Label2 {
                visible: f.note !== ""
                anchors.verticalCenter: parent.verticalCenter
                x: back.visible ? back.x + back.width + 28 : 36
                width: pill.x - x - 24
                text: f.note; font.pixelSize: 13; color: Theme.muted; maximumLineCount: 2; elide: Text.ElideRight
            }
            Rectangle {
                id: pill
                visible: f.primary !== ""
                anchors.right: parent.right; anchors.rightMargin: 32; anchors.verticalCenter: parent.verticalCenter
                height: 46; radius: 23; width: Math.max(150, pl.implicitWidth + 52)
                color: f.primaryEnabled ? (pm.pressed ? Qt.darker(Theme.accent, 1.12) : Theme.accent) : Theme.track
                Label2 { id: pl; anchors.centerIn: parent; text: f.primary; font.pixelSize: 16; strong: true; wrapMode: Text.NoWrap
                         color: f.primaryEnabled ? Theme.accentFg : Theme.muted }
                MouseArea { id: pm; anchors.fill: parent; enabled: f.primaryEnabled; onClicked: f.primaryClicked() }
            }
        }
    }
}
