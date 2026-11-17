import QtQuick 2.4
import MaliitKeyboard 2.0
import "keys"

// S6 Keyboard: Gboard's English layout. The small character on a key is its first long-press character, like
// Gboard's hints; accents follow it. ?123 opens Gboard's symbol pages (S6GboardSymbols.qml).
KeyPad {
    anchors.fill: parent
    content: c1
    symbols: "S6GboardSymbols.qml"

    Column {
        id: c1
        anchors.fill: parent
        spacing: 0

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            CharKey { label: "q"; shifted: "Q"; extended: ["%"]; extendedShifted: ["%"]; leftSide: true }
            CharKey { label: "w"; shifted: "W"; extended: ["\\"]; extendedShifted: ["\\"] }
            CharKey { label: "e"; shifted: "E"; extended: ["|", "è", "é", "ê", "ë", "€"]; extendedShifted: ["|", "È", "É", "Ê", "Ë", "€"] }
            CharKey { label: "r"; shifted: "R"; extended: ["="]; extendedShifted: ["="] }
            CharKey { label: "t"; shifted: "T"; extended: ["[", "þ"]; extendedShifted: ["[", "Þ"] }
            CharKey { label: "y"; shifted: "Y"; extended: ["]", "ý", "¥"]; extendedShifted: ["]", "Ý", "¥"] }
            CharKey { label: "u"; shifted: "U"; extended: ["<", "û", "ù", "ú", "ü"]; extendedShifted: ["<", "Û", "Ù", "Ú", "Ü"] }
            CharKey { label: "i"; shifted: "I"; extended: [">", "î", "ï", "ì", "í"]; extendedShifted: [">", "Î", "Ï", "Ì", "Í"] }
            CharKey { label: "o"; shifted: "O"; extended: ["{", "ö", "ô", "ò", "ó", "œ"]; extendedShifted: ["{", "Ö", "Ô", "Ò", "Ó", "Œ"] }
            CharKey { label: "p"; shifted: "P"; extended: ["}"]; extendedShifted: ["}"]; rightSide: true }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            CharKey { label: "a"; shifted: "A"; extended: ["@", "ä", "à", "â", "á", "å", "æ", "ª"]; extendedShifted: ["@", "Ä", "À", "Â", "Á", "Å", "Æ", "ª"]; leftSide: true }
            CharKey { label: "s"; shifted: "S"; extended: ["#", "ß", "$"]; extendedShifted: ["#", "SS", "$"] }
            CharKey { label: "d"; shifted: "D"; extended: ["$", "ð"]; extendedShifted: ["$", "Ð"] }
            CharKey { label: "f"; shifted: "F"; extended: ["_"]; extendedShifted: ["_"] }
            CharKey { label: "g"; shifted: "G"; extended: ["&"]; extendedShifted: ["&"] }
            CharKey { label: "h"; shifted: "H"; extended: ["-"]; extendedShifted: ["-"] }
            CharKey { label: "j"; shifted: "J"; extended: ["+"]; extendedShifted: ["+"] }
            CharKey { label: "k"; shifted: "K"; extended: ["("]; extendedShifted: ["("] }
            CharKey { label: "l"; shifted: "L"; extended: [")"]; extendedShifted: [")"]; rightSide: true }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            ShiftKey {}
            CharKey { label: "z"; shifted: "Z"; extended: ["*"]; extendedShifted: ["*"] }
            CharKey { label: "x"; shifted: "X"; extended: ["\""]; extendedShifted: ["\""] }
            CharKey { label: "c"; shifted: "C"; extended: ["'", "ç"]; extendedShifted: ["'", "Ç"] }
            CharKey { label: "v"; shifted: "V"; extended: [":"]; extendedShifted: [":"] }
            CharKey { label: "b"; shifted: "B"; extended: [";"]; extendedShifted: [";"] }
            CharKey { label: "n"; shifted: "N"; extended: ["!", "ñ"]; extendedShifted: ["!", "Ñ"] }
            CharKey { label: "m"; shifted: "M"; extended: ["?"]; extendedShifted: ["?"] }
            BackspaceKey {}
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            height: panel.keyHeight + Device.row_margin

            SymbolShiftKey { id: symShiftKey; anchors.left: parent.left; height: parent.height }
            CharKey        { id: commaKey; label: ","; shifted: ","; extended: ["'", "\"", ";", ":", "@", "&", "(", ")"]; extendedShifted: ["'", "\"", ";", ":", "@", "&", "(", ")"]; anchors.left: symShiftKey.right; height: parent.height }
            LanguageKey    { id: emojiKey; anchors.left: commaKey.right; height: parent.height }
            SpaceKey       { id: spaceKey; anchors.left: emojiKey.right; anchors.right: dotKey.left; noMagnifier: true; height: parent.height }
            CharKey        { id: dotKey; label: "."; shifted: "."; extended: ["?", "!", ",", "-", "_", "/", "#", "%"]; extendedShifted: ["?", "!", ",", "-", "_", "/", "#", "%"]; anchors.right: enterKey.left; height: parent.height }
            ReturnKey      { id: enterKey; anchors.right: parent.right; height: parent.height }
        }
    }
}
