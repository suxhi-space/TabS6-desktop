import QtQuick 2.9
import QtQuick.Controls 2.9

// S6 Migrate: clipboard history in the keyboard, like Gboard's. The list comes from KDE's clipboard history
// (Klipper), kept in a private file by the s6-clips service; tap a clip to type it into the app.
Pane {
    id: clips
    property var items: []
    readonly property string source: "file://@CLIPS@"
    padding: Device.gu(1)
    function load() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            try { clips.items = JSON.parse(x.responseText) || [] } catch (e) { clips.items = [] }
        }
        x.open("GET", source + "?" + Date.now()); x.send()
    }
    function insert(t) {
        Feedback.keyPressed()
        event_handler.onKeyReleased("", "commit")
        event_handler.onKeyReleased(t, "")
        event_handler.onKeyReleased("", "commit")
        // a clip never leaves the keyboard stuck on capitals (caps lock stays as it was)
        if (keypad.activeKeypadState === "SHIFTED") keypad.activeKeypadState = "NORMAL"
        keypad.autoCapsTriggered = false
        fullScreenItem.s6clips = false
    }
    onVisibleChanged: if (visible) load()
    Item {
        id: head
        width: parent.width; height: Device.gu(5)
        Label { anchors.left: parent.left; anchors.leftMargin: Device.gu(1); anchors.verticalCenter: parent.verticalCenter
                text: "Clipboard"; font.pixelSize: parent.height * 0.42; font.bold: true }
        ToolButton { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: height * 1.6
                     icon.name: "input-keyboard"; display: AbstractButton.IconOnly; onClicked: fullScreenItem.s6clips = false }
    }
    Label {
        visible: clips.items.length === 0
        anchors.centerIn: parent
        width: parent.width * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: "Text you copy shows up here. Tap it to type it in."
        opacity: 0.7
    }
    GridView {
        id: grid
        anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: Device.gu(0.5) }
        clip: true
        model: clips.items
        cellWidth: width / (width > Device.gu(90) ? 3 : 2)
        cellHeight: Device.gu(9)
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            width: grid.cellWidth; height: grid.cellHeight
            Button {
                anchors.fill: parent; anchors.margins: Device.gu(0.6)
                onClicked: clips.insert(modelData.t)
                contentItem: Label {
                    text: modelData.t; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter; font.pixelSize: Device.gu(1.9)
                }
            }
        }
    }
}
