import QtQuick 2.9
import QtQuick.Controls 2.9

// S6 Migrate: a slim strip under the keys, like Android's navigation bar while typing: hide the keyboard on the
// left, the clipboard on the right.
Item {
    ToolButton {
        anchors.left: parent.left; anchors.leftMargin: Device.gu(2)
        anchors.top: parent.top; anchors.bottom: parent.bottom
        width: height * 2
        icon.name: "go-down"; display: AbstractButton.IconOnly
        onClicked: { Feedback.keyPressed(); fullScreenItem.s6clips = false; MaliitGeometry.shown = false }
    }
    ToolButton {
        anchors.right: parent.right; anchors.rightMargin: Device.gu(2)
        anchors.top: parent.top; anchors.bottom: parent.bottom
        width: height * 2
        icon.name: "edit-paste"; display: AbstractButton.IconOnly
        onClicked: { Feedback.keyPressed(); fullScreenItem.s6clips = !fullScreenItem.s6clips }
    }
}
