import QtQuick
import QtQuick.Controls.Basic
import "."

// The wizard layout from the concept design: steps in a sidebar (a step bar when narrow),
// a title, scrolling content, and a footer with an optional note and up to two buttons.
Rectangle {
    id: f
    property var steps: []
    property int current: 0
    property string appName: "S6 Migrate"
    property string appSub: "Android to Fedora"
    property string eyebrow: ""
    property string title: ""
    property string subtitle: ""
    property string note: ""
    property string primary: ""
    property string secondary: ""
    property bool primaryEnabled: true
    property bool navigable: false     // sidebar entries can be tapped (companion)
    property var sideFooter: null      // optional extra text at the bottom of the sidebar
    property real keyboardHeight: 0
    default property alias content: body.data
    signal primaryClicked()
    signal secondaryClicked()
    signal stepClicked(int index)
    readonly property bool wide: width >= 900
    readonly property bool roomy: (wide ? width - 280 : width) - 2 * pad >= 720
    readonly property int pad: wide ? 56 : 22
    color: Theme.bg

    // ---- sidebar
    Rectangle {
        id: side
        visible: f.wide
        width: f.wide ? 280 : 0
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        color: Theme.side
        Column {
            x: 28; y: 40; width: side.width - 56; spacing: 34
            Row {
                spacing: 12
                Glyph { kind: "logo"; tint: Theme.accent; width: 44; height: 44 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label2 { text: f.appName; display: true; font.pixelSize: 19; wrapMode: Text.NoWrap }
                    Label2 { text: f.appSub; font.pixelSize: 13; color: Theme.muted; wrapMode: Text.NoWrap }
                }
            }
            Column {
                spacing: 4; width: parent.width
                Repeater {
                    model: f.steps
                    delegate: Rectangle {
                        width: parent.width; height: 50; radius: 10
                        color: f.navigable && index === f.current ? Theme.sel : "transparent"
                        Row {
                            x: f.navigable ? 10 : 0; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                            Glyph {
                                width: 22; height: 22
                                kind: f.navigable ? (modelData.icon || "box") : (index < f.current ? "done" : index === f.current ? "current" : "todo")
                                tint: f.navigable ? (index === f.current ? Theme.accent : Theme.muted) : Theme.accent
                            }
                            Label2 {
                                text: f.navigable ? modelData.label : modelData
                                anchors.verticalCenter: parent.verticalCenter
                                font.weight: index === f.current ? Font.DemiBold : Font.Normal
                                color: index === f.current ? Theme.text : (index < f.current && !f.navigable ? Theme.sub : Theme.muted)
                                wrapMode: Text.NoWrap
                            }
                        }
                        MouseArea { anchors.fill: parent; enabled: f.navigable; onClicked: f.stepClicked(index) }
                    }
                }
            }
        }
        Label2 {
            visible: f.sideFooter !== null && f.sideFooter !== ""
            text: f.sideFooter || ""
            x: 28; width: side.width - 56
            anchors.bottom: parent.bottom; anchors.bottomMargin: 24
            font.pixelSize: 13; color: Theme.muted
        }
    }

    // ---- main column
    Item {
        id: main
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: side.right }
        anchors.bottomMargin: f.keyboardHeight

        Column {
            id: head
            x: f.pad; y: f.wide ? 44 : 16
            width: main.width - 2 * f.pad
            spacing: 8
            // narrow: app name, step and a segmented bar
            Column {
                visible: !f.wide; width: parent.width; spacing: 10
                Row {
                    spacing: 10
                    Glyph { kind: "logo"; width: 30; height: 30 }
                    Label2 {
                        anchors.verticalCenter: parent.verticalCenter
                        text: f.navigable ? f.appName : f.appName + "  ·  Step " + (f.current + 1) + " of " + f.steps.length
                        font.pixelSize: 14; strong: true; color: Theme.sub; wrapMode: Text.NoWrap
                    }
                }
                Row {
                    visible: !f.navigable
                    width: parent.width; spacing: 4
                    Repeater {
                        model: f.steps.length
                        Rectangle { width: (head.width - 4 * (f.steps.length - 1)) / f.steps.length; height: 4; radius: 2; color: index <= f.current ? Theme.accent : Theme.track }
                    }
                }
                Flow {
                    visible: f.navigable; width: parent.width; spacing: 8
                    Repeater {
                        model: f.steps
                        Rectangle {
                            height: 36; width: tl.implicitWidth + 24; radius: 18
                            color: index === f.current ? Theme.accent : Theme.side
                            Label2 { id: tl; anchors.centerIn: parent; text: modelData.label || modelData; font.pixelSize: 14; wrapMode: Text.NoWrap; color: index === f.current ? Theme.accentFg : Theme.text }
                            MouseArea { anchors.fill: parent; onClicked: f.stepClicked(index) }
                        }
                    }
                }
                Item { width: 1; height: 4 }
            }
            Label2 {
                visible: f.eyebrow !== ""
                text: f.eyebrow.toUpperCase(); font.pixelSize: 14; strong: true; color: Theme.accentText
                font.letterSpacing: 0.8; width: parent.width
            }
            Label2 { text: f.title; display: true; font.pixelSize: f.wide ? 38 : 30; width: parent.width; lineHeight: 1.08 }
            Label2 { visible: f.subtitle !== ""; text: f.subtitle; color: Theme.sub; width: parent.width; font.pixelSize: 17 }
        }

        Flickable {
            id: flick
            objectName: "flick"
            anchors { top: head.bottom; topMargin: 20; left: parent.left; right: parent.right; bottom: foot.top; bottomMargin: 8 }
            contentHeight: body.implicitHeight + 24
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
            Column {
                id: body
                x: f.pad
                width: flick.width - 2 * f.pad
                spacing: 16
            }
        }

        Item {
            id: foot
            visible: f.primary !== "" || f.secondary !== "" || f.note !== ""
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: visible ? (f.wide || f.note === "" ? 84 : 120) : 0
            Rectangle { x: f.pad; width: parent.width - 2 * f.pad; height: 1; color: Theme.hair }
            Label2 {
                id: noteText
                text: f.note; visible: f.note !== ""
                x: f.pad; y: f.wide ? 32 : 14
                width: f.wide ? parent.width - 2 * f.pad - buttons.width - 20 : parent.width - 2 * f.pad
                font.pixelSize: 14; color: Theme.muted; maximumLineCount: 2; elide: Text.ElideRight
            }
            Row {
                id: buttons
                anchors.right: parent.right; anchors.rightMargin: f.pad
                anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                spacing: 12
                Btn { visible: f.secondary !== ""; text: f.secondary; onClicked: f.secondaryClicked() }
                Btn { visible: f.primary !== ""; text: f.primary; primary: true; enabled: f.primaryEnabled; onClicked: f.primaryClicked() }
            }
        }
    }
}
