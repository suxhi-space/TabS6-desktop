import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Effects
import "."

// "Getting your tablet ready": shown before the login screen while S6 Migrate updates Fedora (s6-maint), like a
// phone or a Mac installing an update. Works in either orientation. "Show details" slides up the live output.
Window {
    id: win
    visible: true
    width: 1280; height: 800
    visibility: mock ? Window.Windowed : Window.FullScreen
    color: "#05080D"
    title: "Getting your tablet ready"
    Component.onCompleted: Theme.dark = true
    property bool details: false
    property var log: []
    property string logText: ""
    readonly property bool portrait: height > width

    Connections {
        target: maint
        function onLine(l) { win.log.push(l); if (win.log.length > 500) win.log.splice(0, win.log.length - 500); win.logText = win.log.join("\n") }
    }

    // the wallpaper, blurred and dimmed (where effects can't run, the dark background alone)
    Image { id: wp; anchors.fill: parent; anchors.margins: -80; source: maint.wallpaper(); fillMode: Image.PreserveAspectCrop; sourceSize.width: 720; visible: false; asynchronous: true }
    MultiEffect { source: wp; anchors.fill: wp; blurEnabled: true; blur: 1.0; blurMax: 64; saturation: 0.1; opacity: wp.status === Image.Ready ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 800 } } }
    Rectangle { anchors.fill: parent; color: "#05080D"; opacity: 0.62 }

    // the middle: icon, title, step, progress bar, what's happening
    Column {
        id: mid
        width: Math.min(parent.width - 64, 520)
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.details ? Math.max(40, (term.y - height) / 2) : (parent.height - height) / 2 - 20
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        spacing: 14
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 84; height: 84; radius: 22
            gradient: Gradient {
                GradientStop { position: 0; color: "#5B8FD6" }
                GradientStop { position: 1; color: "#2C5A9C" }
            }
            Glyph { anchors.centerIn: parent; kind: "tablet"; tint: "#FFFFFF"; width: 52; height: 52 }
        }
        Item { width: 1; height: 6 }
        Label2 {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: maint.finishedText.indexOf("All done") === 0 ? "Your tablet is ready" : "Getting your tablet ready"
            display: true; font.pixelSize: 30; color: "#F2F5FA"
        }
        Label2 {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: maint.stepLabel || " "; font.pixelSize: 16; color: "#B9C4D3"
        }
        Item { width: 1; height: 4 }
        Rectangle {
            width: parent.width; height: 6; radius: 3
            color: Qt.rgba(1, 1, 1, 0.16)
            Rectangle {
                width: Math.max(6, parent.width * maint.progress); height: parent.height; radius: 3; color: "#FFFFFF"
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Item {
            width: parent.width; height: 20
            Label2 { anchors.left: parent.left; text: maint.jobLabel; font.pixelSize: 13; color: "#9AA8BA"; elide: Text.ElideRight; wrapMode: Text.NoWrap; width: parent.width - el.width - 12 }
            Label2 { id: el; anchors.right: parent.right; text: maint.elapsed; font.pixelSize: 13; color: "#9AA8BA"; wrapMode: Text.NoWrap }
        }
        Item { width: 1; height: 8 }
        Label2 {
            visible: !win.details
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: maint.finishedText !== "" && maint.finishedText.indexOf("All done") !== 0
                  ? "It carries on at the next start. Starting the login screen..."
                  : "Keep your tablet plugged in. It goes to the login screen by itself when it's done."
            font.pixelSize: 14; color: "#7E8CA0"
        }
    }

    // live output, sliding up from the bottom
    Rectangle {
        id: term
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 48
        height: win.portrait ? parent.height * 0.48 : parent.height * 0.44
        y: win.details ? parent.height - height - toggle.height - 20 : parent.height + 10
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        radius: 14; color: "#0B0F14"; border.width: 1; border.color: "#1E2733"
        Flickable {
            id: tf
            anchors.fill: parent; anchors.margins: 14
            contentHeight: tt.height; clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height
            Text {
                id: tt; width: tf.width
                text: win.logText || "Waiting for output..."
                color: "#C9D6E4"; font.family: "monospace"; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; lineHeight: 1.12
            }
        }
    }

    // bottom centre: show or hide the output
    Item {
        id: toggle
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        width: tl.implicitWidth + 40; height: 40
        Rectangle { anchors.fill: parent; radius: 20; color: Qt.rgba(1, 1, 1, tm.pressed ? 0.16 : 0.08) }
        Label2 { id: tl; anchors.centerIn: parent; text: win.details ? "Hide details  ▾" : "Show details  ▴"; font.pixelSize: 14; strong: true; color: "#DCE4EE"; wrapMode: Text.NoWrap }
        MouseArea { id: tm; anchors.fill: parent; anchors.margins: -10; onClicked: win.details = !win.details }
    }
}
