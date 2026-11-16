import QtQuick
import org.kde.plasma.core as PlasmaCore

// S6 Migrate's on-screen display (volume, brightness, keyboard light...): a thick rounded slider like Android's
// instead of Breeze's box. Part of the S6 Global Themes; Plasma falls back to Breeze's when another theme is used.
// The shell sets these properties (same names as Breeze's OSD).
PlasmaCore.Dialog {
    id: root
    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.OnScreenDisplay
    outputOnly: true
    property int timeout: 1800
    property var osdValue
    property int osdMaxValue: 100
    property var osdAdditionalText
    property string icon
    property bool showingProgress: false
    mainItem: OsdItem { rootItem: root }
}
