import QtQuick 2.9
import QtQuick.Controls 2.9
import MaliitKeyboard 2.0
import QtQuick.Layouts 1.3

// S6 Migrate: Gboard's top bar. Shown in the suggestion strip while there is nothing to suggest:
// emoji, clipboard, undo, redo; hide on the right.
Item {
    id: bar
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Device.gu(1); anchors.rightMargin: Device.gu(1)
        spacing: Device.gu(1)
        ToolButton { Layout.fillHeight: true; Layout.preferredWidth: height * 1.6; icon.name: "face-smile"; display: AbstractButton.IconOnly
                     onClicked: { Feedback.keyPressed(); keypad.state = "EMOJI" } }
        ToolButton { Layout.fillHeight: true; Layout.preferredWidth: height * 1.6; icon.name: "edit-paste"; display: AbstractButton.IconOnly
                     onClicked: { Feedback.keyPressed(); fullScreenItem.s6clips = !fullScreenItem.s6clips } }
        ToolButton { Layout.fillHeight: true; Layout.preferredWidth: height * 1.6; icon.name: "edit-undo"; display: AbstractButton.IconOnly
                     onClicked: { Feedback.keyPressed(); fullScreenItem.undo() } }
        ToolButton { Layout.fillHeight: true; Layout.preferredWidth: height * 1.6; icon.name: "edit-redo"; display: AbstractButton.IconOnly
                     onClicked: { Feedback.keyPressed(); fullScreenItem.redo() } }
        Item { Layout.fillWidth: true }
        ToolButton { Layout.fillHeight: true; Layout.preferredWidth: height * 1.6; icon.name: "go-down"; display: AbstractButton.IconOnly
                     onClicked: { Feedback.keyPressed(); fullScreenItem.s6clips = false; MaliitGeometry.shown = false } }
    }
}
