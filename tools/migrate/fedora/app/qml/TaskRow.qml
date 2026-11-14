import QtQuick
import "."

// One line of a progress list: waiting / working / done / failed / skipped.
Row {
    id: r
    property string title
    property string detail: ""
    property string status: "wait"   // wait run done fail skip
    property real progress: -1      // 0..1 shows a bar while running
    spacing: 14
    width: parent ? parent.width : 400
    Glyph {
        width: 24; height: 24; y: 1
        kind: r.status === "run" ? "spin" : r.status === "done" ? "ok" : r.status === "fail" ? "warn" : "todo"
        tint: r.status === "done" ? Theme.ok : r.status === "fail" ? Theme.warn : Theme.accent
    }
    Column {
        width: r.width - 38; spacing: 4
        Label2 { text: r.title; strong: r.status === "run"; color: r.status === "wait" || r.status === "skip" ? Theme.muted : Theme.text; width: parent.width }
        Rectangle {
            visible: r.status === "run" && r.progress >= 0
            width: parent.width; height: 8; radius: 4; color: Theme.track
            Rectangle { width: parent.width * Math.max(0, Math.min(1, r.progress)); height: 8; radius: 4; color: Theme.accent }
        }
        Label2 { visible: r.detail !== ""; text: r.detail; font.pixelSize: 13; color: r.status === "fail" ? Theme.warn : Theme.muted; width: parent.width; maximumLineCount: 2; elide: Text.ElideRight }
    }
}
