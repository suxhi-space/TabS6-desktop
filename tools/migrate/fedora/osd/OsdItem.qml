import QtQuick
import org.kde.kirigami as Kirigami

// A pill: the filled part carries the icon, the percentage on the right (or the message, when it isn't a level).
Item {
    id: it
    property QtObject rootItem
    readonly property bool level: rootItem && rootItem.showingProgress
    readonly property real frac: level && rootItem.osdMaxValue > 0 ? Math.max(0, Math.min(1, Number(rootItem.osdValue) / rootItem.osdMaxValue)) : 0
    readonly property color fg: Kirigami.Theme.textColor
    implicitWidth: Kirigami.Units.gridUnit * 18
    implicitHeight: Kirigami.Units.gridUnit * 2.75
    width: implicitWidth; height: implicitHeight
    Rectangle {
        anchors.fill: parent; radius: height / 2
        color: Qt.rgba(it.fg.r, it.fg.g, it.fg.b, 0.10)
        Rectangle {
            visible: it.level
            width: Math.max(parent.height, parent.width * it.frac); height: parent.height; radius: parent.radius
            color: Kirigami.Theme.highlightColor
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    Kirigami.Icon {
        id: ic
        x: parent.height * 0.28; anchors.verticalCenter: parent.verticalCenter
        width: parent.height * 0.48; height: width
        source: it.rootItem ? it.rootItem.icon : ""
        isMask: true
        color: it.level && it.frac * it.width > ic.x + ic.width ? Kirigami.Theme.highlightedTextColor : it.fg
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: parent.height * 0.4; anchors.verticalCenter: parent.verticalCenter
        anchors.left: it.level ? undefined : ic.right; anchors.leftMargin: parent.height * 0.25
        horizontalAlignment: it.level ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        text: !it.rootItem ? "" : it.level ? (it.rootItem.osdAdditionalText ? String(it.rootItem.osdAdditionalText) : Math.round(it.frac * 100) + "%")
                                           : String(it.rootItem.osdValue === undefined ? "" : it.rootItem.osdValue)
        color: it.level && it.frac > 0.86 ? Kirigami.Theme.highlightedTextColor : it.fg
        font.pixelSize: parent.height * 0.32; font.weight: Font.DemiBold
    }
}
