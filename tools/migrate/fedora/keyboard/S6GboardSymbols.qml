import QtQuick 2.4
import MaliitKeyboard 2.0
import "keys"

// S6 Keyboard: Gboard's symbol pages. "?123" shows the first page; the =\\< key flips to the second (each key's
// second character), "?123" there flips back; ABC returns to the letters.
KeyPad {
    anchors.fill: parent
    content: c1

    Column {
        id: c1
        anchors.fill: parent
        spacing: 0

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            CharKey { label: "1"; shifted: "~"; leftSide: true }
            CharKey { label: "2"; shifted: "`" }
            CharKey { label: "3"; shifted: "|" }
            CharKey { label: "4"; shifted: "•" }
            CharKey { label: "5"; shifted: "√" }
            CharKey { label: "6"; shifted: "π" }
            CharKey { label: "7"; shifted: "÷" }
            CharKey { label: "8"; shifted: "×" }
            CharKey { label: "9"; shifted: "§" }
            CharKey { label: "0"; shifted: "Δ"; rightSide: true }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            CharKey { label: "@"; shifted: "£"; leftSide: true }
            CharKey { label: "#"; shifted: "¢" }
            CharKey { label: "$"; shifted: "€" }
            CharKey { label: "_"; shifted: "¥" }
            CharKey { label: "&"; shifted: "^" }
            CharKey { label: "-"; shifted: "°" }
            CharKey { label: "+"; shifted: "=" }
            CharKey { label: "("; shifted: "{" }
            CharKey { label: ")"; shifted: "}" }
            CharKey { label: "/"; shifted: "\\"; rightSide: true }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            OneTwoKey { label: "=\\<"; shifted: "?123"; fontSize: Device.fontSize }
            CharKey { label: "*"; shifted: "%" }
            CharKey { label: "\""; shifted: "©" }
            CharKey { label: "'"; shifted: "®" }
            CharKey { label: ":"; shifted: "™" }
            CharKey { label: ";"; shifted: "✓" }
            CharKey { label: "!"; shifted: "[" }
            CharKey { label: "?"; shifted: "]" }
            BackspaceKey {}
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            height: panel.keyHeight + Device.row_margin

            SymbolShiftKey { id: symShiftKey; label: "ABC"; shifted: "ABC"; anchors.left: parent.left; height: parent.height }
            CharKey        { id: commaKey; label: ","; shifted: "<"; anchors.left: symShiftKey.right; height: parent.height }
            LanguageKey    { id: emojiKey; anchors.left: commaKey.right; height: parent.height }
            SpaceKey       { id: spaceKey; anchors.left: emojiKey.right; anchors.right: dotKey.left; noMagnifier: true; height: parent.height }
            CharKey        { id: dotKey; label: "."; shifted: ">"; anchors.right: enterKey.left; height: parent.height }
            ReturnKey      { id: enterKey; anchors.right: parent.right; height: parent.height }
        }
    }
}
