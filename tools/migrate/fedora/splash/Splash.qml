import QtQuick
import QtQuick.Effects

// S6 Migrate's login splash, like a Mac starting your session: your wallpaper, softly blurred and dimmed, with a
// thin progress bar. KSplash sets "stage" as Plasma starts (up to 6). Part of the S6 Global Themes; the wallpaper
// is copied in by "s6-look install-themes".
Rectangle {
    id: root
    color: "#0B0F16"
    property int stage
    Image {
        id: wall
        anchors.fill: parent; anchors.margins: -60
        source: "images/wallpaper"
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 960
        asynchronous: false
        visible: false
    }
    MultiEffect { source: wall; anchors.fill: wall; blurEnabled: true; blur: 0.7; blurMax: 48; visible: wall.status === Image.Ready }
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: wall.status === Image.Ready ? 0.25 : 0 }
    Rectangle {
        id: track
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: parent.height * 0.18
        width: Math.min(parent.width * 0.22, 260); height: 6; radius: 3
        color: Qt.rgba(1, 1, 1, 0.28)
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 500 } }
        Rectangle {
            width: Math.max(6, parent.width * Math.min(1, root.stage / 6)); height: parent.height; radius: 3
            color: "#FFFFFF"
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }
    }
    // fade out at the end, into the desktop
    OpacityAnimator { id: out; target: root; from: 1; to: 0; duration: 400 }
    onStageChanged: if (stage >= 6) out.start()
}
