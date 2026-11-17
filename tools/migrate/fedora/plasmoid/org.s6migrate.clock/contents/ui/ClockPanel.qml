import QtQuick

// The panel that opens from the clock, like Windows 11's: your notifications on top (newest first, "Clear all"),
// then the calendar, which folds away to leave just the notifications. Plain QtQuick: the notifications and the
// app icons come from main.qml (Plasma's own notification list), so this can also be shown with sample data.
Item {
    id: cp
    property var pal
    property var model                       // notifications: summary, body, applicationName, applicationIconName, created
    property int count: 0
    property bool calendarShown: true
    property Component iconComponent         // draws an app icon; gets "iconName"
    signal clearAll()
    signal closeAt(int row)
    signal activate(int row)
    signal toggleCalendar()
    implicitWidth: 400
    implicitHeight: 560

    function ago(d) {
        if (!d) return ""
        var s = (Date.now() - new Date(d).getTime()) / 1000
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + " min ago"
        if (s < 86400) return Qt.formatTime(new Date(d), Qt.locale().timeFormat(Locale.ShortFormat))
        return Qt.formatDate(new Date(d), Qt.locale().dateFormat(Locale.ShortFormat))
    }

    // ---------------------------------------------------------------- notifications
    Item {
        id: nhead
        x: 16; y: 14; width: parent.width - 32; height: 36
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; color: cp.pal.fg; font.pixelSize: 16; font.weight: Font.DemiBold }
        Rectangle {
            visible: cp.count > 0
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: clr.implicitWidth + 28; height: 32; radius: 16; color: clrMa.pressed ? cp.pal.tileIcon : cp.pal.tile
            Text { id: clr; anchors.centerIn: parent; text: "Clear all"; color: cp.pal.fg; font.pixelSize: 13; font.weight: Font.DemiBold }
            MouseArea { id: clrMa; anchors.fill: parent; onClicked: cp.clearAll() }
        }
    }
    ListView {
        id: list
        anchors { top: nhead.bottom; topMargin: 8; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16
                  bottom: cal.top; bottomMargin: 12 }
        clip: true; spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: cp.model
        delegate: Rectangle {
            id: card
            required property int index
            required property string summary
            required property string body
            required property string applicationName
            required property string applicationIconName
            required property var created
            width: list.width; height: cardCol.implicitHeight + 24; radius: 16
            color: cardMa.pressed ? cp.pal.tileIcon : cp.pal.tile
            // swipe sideways to dismiss, like a phone
            x: 0
            Behavior on x { NumberAnimation { duration: 160 } }
            MouseArea {
                id: cardMa; anchors.fill: parent
                drag.target: card; drag.axis: Drag.XAxis; drag.minimumX: -list.width; drag.maximumX: list.width
                onReleased: { if (Math.abs(card.x) > list.width * 0.35) cp.closeAt(card.index); else card.x = 0 }
                onClicked: cp.activate(card.index)
            }
            Loader {
                id: ic; x: 12; y: 12; width: 18; height: 18
                sourceComponent: cp.iconComponent
                onLoaded: item.iconName = Qt.binding(function () { return card.applicationIconName })
            }
            Column {
                id: cardCol
                x: 12; y: 12; width: parent.width - 24; spacing: 4
                Item {
                    width: parent.width; height: 18
                    Text { x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 26 - when.width - 36; elide: Text.ElideRight
                           text: card.applicationName; color: cp.pal.sub; font.pixelSize: 12 }
                    Text { id: when; anchors.right: parent.right; anchors.rightMargin: 30; anchors.verticalCenter: parent.verticalCenter
                           text: cp.ago(card.created); color: cp.pal.sub; font.pixelSize: 12 }
                    Rectangle {   // dismiss
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 12; color: xMa.pressed ? cp.pal.tileIcon : "transparent"
                        Text { anchors.centerIn: parent; text: "✕"; color: cp.pal.sub; font.pixelSize: 12 }
                        MouseArea { id: xMa; anchors.fill: parent; anchors.margins: -8; onClicked: cp.closeAt(card.index) }
                    }
                }
                Text { width: parent.width; text: card.summary; color: cp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold
                       wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                Text { visible: card.body !== ""; width: parent.width; text: card.body; color: cp.pal.sub; font.pixelSize: 13
                       wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; textFormat: Text.StyledText }
            }
        }
        Text {
            visible: cp.count === 0
            anchors.centerIn: parent; text: "No new notifications"; color: cp.pal.sub; font.pixelSize: 14
        }
    }

    // ---------------------------------------------------------------- calendar (folds away)
    Rectangle {
        id: cal
        anchors.bottom: parent.bottom; anchors.bottomMargin: 12; x: 12; width: parent.width - 24
        height: calHead.height + (cp.calendarShown ? grid.height + 14 : 0) + 8; radius: 18
        color: cp.pal.tile; clip: true
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        property date shown: new Date()
        readonly property date today: new Date()
        Item {
            id: calHead
            x: 14; y: 4; width: parent.width - 28; height: 44
            Text { anchors.verticalCenter: parent.verticalCenter; color: cp.pal.fg; font.pixelSize: 14; font.weight: Font.DemiBold
                   text: cp.calendarShown ? Qt.formatDate(cal.shown, "MMMM yyyy") : Qt.formatDate(cal.today, "dddd, MMMM d") }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Repeater {
                    model: cp.calendarShown ? ["‹", "›", "⌄"] : ["⌃"]
                    delegate: Rectangle {
                        required property string modelData
                        width: 34; height: 34; radius: 17; color: nb.pressed ? cp.pal.tileIcon : "transparent"
                        Text { anchors.centerIn: parent; text: modelData; color: cp.pal.fg; font.pixelSize: 18 }
                        MouseArea {
                            id: nb; anchors.fill: parent
                            onClicked: {
                                if (modelData === "‹") cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() - 1, 1)
                                else if (modelData === "›") cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() + 1, 1)
                                else { cal.shown = new Date(); cp.toggleCalendar() }
                            }
                        }
                    }
                }
            }
        }
        Grid {
            id: grid
            x: 10; anchors.top: calHead.bottom; anchors.topMargin: 4; width: parent.width - 20
            columns: 7; opacity: cp.calendarShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            readonly property real cw: width / 7
            // the first day of the week follows your region
            readonly property int first: Qt.locale().firstDayOfWeek % 7
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    width: grid.cw; height: 26; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().dayName((index + grid.first) % 7, Locale.ShortFormat).slice(0, 2); color: cp.pal.sub; font.pixelSize: 12
                }
            }
            Repeater {
                model: 42
                delegate: Item {
                    required property int index
                    readonly property date start: new Date(cal.shown.getFullYear(), cal.shown.getMonth(), 1)
                    readonly property int lead: (start.getDay() - grid.first + 7) % 7
                    readonly property date day: new Date(cal.shown.getFullYear(), cal.shown.getMonth(), index - lead + 1)
                    readonly property bool inMonth: day.getMonth() === cal.shown.getMonth()
                    readonly property bool isToday: day.toDateString() === cal.today.toDateString()
                    width: grid.cw; height: 34
                    Rectangle { anchors.centerIn: parent; width: 32; height: 32; radius: 16; color: cp.pal.accent; visible: parent.isToday }
                    Text { anchors.centerIn: parent; text: parent.day.getDate(); font.pixelSize: 13
                           color: parent.isToday ? cp.pal.accentFg : cp.pal.fg; opacity: parent.inMonth ? 1 : 0.35 }
                }
            }
        }
    }
}
