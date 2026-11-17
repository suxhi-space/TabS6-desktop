import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager

// S6 Clock and Notifications: time over date in the taskbar (a dot when something new arrived); tap it for your
// notifications and a calendar that folds away, like Windows 11. The notifications are Plasma's own list (the same
// ones its notification pop-ups show); clearing them here clears them there.
PlasmoidItem {
    id: root
    readonly property color fg: Kirigami.Theme.textColor
    readonly property var pal: ({
        accent: Kirigami.Theme.highlightColor, accentFg: Kirigami.Theme.highlightedTextColor,
        fg: fg, sub: Qt.rgba(fg.r, fg.g, fg.b, 0.66),
        tile: Qt.rgba(fg.r, fg.g, fg.b, 0.08), tileIcon: Qt.rgba(fg.r, fg.g, fg.b, 0.14) })
    property date now: new Date()
    preferredRepresentation: compactRepresentation
    toolTipMainText: Qt.formatDate(now, "dddd, MMMM d, yyyy")
    toolTipSubText: notes.count === 0 ? "No new notifications" : notes.count === 1 ? "1 notification" : notes.count + " notifications"

    Timer { interval: 1000; repeat: true; running: true; triggeredOnStart: true
            onTriggered: { var d = new Date(); if (d.getMinutes() !== root.now.getMinutes() || d.getDate() !== root.now.getDate()) root.now = d } }

    NotificationManager.Notifications {
        id: notes
        showExpired: true
        showDismissed: true
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
        urgencies: NotificationManager.Notifications.LowUrgency | NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
    }
    // seen: opening the panel marks everything read (the dot goes away)
    onExpandedChanged: if (expanded) notes.lastRead = new Date()

    compactRepresentation: MouseArea {
        id: cr
        readonly property bool beside: Plasmoid.configuration.beside || (parent && parent.height < 34)
        Layout.minimumWidth: (beside ? besideText.implicitWidth : Math.max(t.implicitWidth, d.implicitWidth)) + Kirigami.Units.largeSpacing * 2 + (dot.visible ? 10 : 0)
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 8; color: root.fg; opacity: root.expanded ? 0.14 : (cr.containsMouse ? 0.08 : 0) }
        Column {
            visible: !cr.beside
            anchors.centerIn: parent; spacing: 0
            Text { id: t; anchors.right: parent.right; text: Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat))
                   color: root.fg; font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.0; font.weight: Font.DemiBold }
            Text { id: d; anchors.right: parent.right; text: Qt.formatDate(root.now, Qt.locale().dateFormat(Locale.ShortFormat))
                   color: root.fg; opacity: 0.85; font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 0.9 }
        }
        Text { id: besideText; visible: cr.beside; anchors.centerIn: parent; color: root.fg; font.weight: Font.DemiBold
               font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
               text: Qt.formatDate(root.now, "ddd MMM d") + "   " + Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat)) }
        Rectangle {   // something new arrived
            id: dot
            visible: notes.unreadNotificationsCount > 0
            anchors.right: parent.right; anchors.rightMargin: 4; anchors.top: parent.top; anchors.topMargin: 6
            width: 8; height: 8; radius: 4; color: Kirigami.Theme.highlightColor
        }
    }

    fullRepresentation: ClockPanel {
        pal: root.pal
        model: notes
        count: notes.count
        calendarShown: Plasmoid.configuration.calendarShown
        Layout.preferredWidth: implicitWidth; Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: implicitWidth; Layout.minimumHeight: implicitHeight
        iconComponent: Component { Kirigami.Icon { property string iconName: ""; source: iconName || "preferences-desktop-notification" } }
        onClearAll: { notes.clear(NotificationManager.Notifications.ClearExpired); for (var i = notes.count - 1; i >= 0; i--) notes.close(notes.index(i, 0)) }
        onCloseAt: (row) => notes.close(notes.index(row, 0))
        onActivate: (row) => notes.invokeDefaultAction(notes.index(row, 0))   // opens the app, if it offers that
        onToggleCalendar: Plasmoid.configuration.calendarShown = !Plasmoid.configuration.calendarShown
    }
}
