import QtQuick

// Icons drawn on a 24-unit grid, so the panel looks the same with any icon theme.
Canvas {
    id: g
    property string name: "wifi"
    property color color: "white"
    property bool on: true
    property real level: -1            // battery: 0..1 fills the icon
    width: 22; height: 22
    onNameChanged: requestPaint(); onColorChanged: requestPaint(); onOnChanged: requestPaint(); onLevelChanged: requestPaint()
    onPaint: {
        var c = getContext("2d"); var s = width / 24; c.reset()
        c.strokeStyle = String(color); c.fillStyle = String(color); c.lineCap = "round"; c.lineJoin = "round"; c.lineWidth = 2 * s
        function L(p) { c.beginPath(); c.moveTo(p[0]*s, p[1]*s); for (var i = 2; i < p.length; i += 2) c.lineTo(p[i]*s, p[i+1]*s); c.stroke() }
        function A(x, y, r, a0, a1, fill) { c.beginPath(); c.arc(x*s, y*s, r*s, a0, a1); fill ? c.fill() : c.stroke() }
        function R(x, y, w, h, r) { c.beginPath(); c.roundedRect(x*s, y*s, w*s, h*s, r*s, r*s); c.stroke() }
        switch (name) {
        case "wifi":   // level 0..1 (signal): the arcs it doesn't reach are faint
            c.globalAlpha = level >= 0 && level < 0.75 ? 0.3 : 1; A(12, 19, 15, -Math.PI*0.76, -Math.PI*0.24)
            c.globalAlpha = level >= 0 && level < 0.45 ? 0.3 : 1; A(12, 19, 10, -Math.PI*0.74, -Math.PI*0.26)
            c.globalAlpha = level >= 0 && level < 0.2 ? 0.3 : 1; A(12, 19, 5, -Math.PI*0.7, -Math.PI*0.3)
            c.globalAlpha = 1; A(12, 19, 1.5, 0, 7, true)
            if (!on) L([3, 3, 21, 21]); break
        case "back": L([15, 6, 9, 12, 15, 18]); break
        case "check": L([5, 12.5, 10, 17.5, 19, 7]); break
        case "refresh": A(12, 12, 7.5, -Math.PI*0.35, Math.PI*1.45); L([17.5, 3.5, 18.5, 7.5, 14.5, 8.5]); break
        case "plus": L([12, 5, 12, 19]); L([5, 12, 19, 12]); break
        case "headset": A(12, 13, 8, Math.PI, 0); R(3, 13, 4.5, 7, 2); R(16.5, 13, 4.5, 7, 2); break
        case "device": R(6, 2.5, 12, 19, 2.5); L([10.5, 18.5, 13.5, 18.5]); break
        case "bt": L([7, 7.5, 17, 16.5, 12, 21, 12, 3, 17, 7.5, 7, 16.5]); break
        case "plane": c.beginPath(); c.moveTo(12*s, 2*s); c.lineTo(13.5*s, 9*s); c.lineTo(22*s, 14*s); c.lineTo(22*s, 16*s); c.lineTo(13.5*s, 13.5*s)
            c.lineTo(13*s, 19*s); c.lineTo(15.5*s, 21*s); c.lineTo(15.5*s, 22.5*s); c.lineTo(12*s, 21.5*s); c.lineTo(8.5*s, 22.5*s); c.lineTo(8.5*s, 21*s)
            c.lineTo(11*s, 19*s); c.lineTo(10.5*s, 13.5*s); c.lineTo(2*s, 16*s); c.lineTo(2*s, 14*s); c.lineTo(10.5*s, 9*s); c.closePath(); c.fill(); break
        case "dark": c.beginPath(); c.arc(12*s, 12*s, 9*s, 0, Math.PI*2); c.fill(); c.globalCompositeOperation = "destination-out"
            c.beginPath(); c.arc(16.5*s, 8*s, 7.5*s, 0, Math.PI*2); c.fill(); break
        case "night": A(12, 12, 4, 0, 7, true); for (var i = 0; i < 8; i++) { var a = i * Math.PI / 4; L([12 + 7*Math.cos(a), 12 + 7*Math.sin(a), 12 + 9.5*Math.cos(a), 12 + 9.5*Math.sin(a)]) }
            c.fillStyle = "rgba(0,0,0,0)"; break
        case "saver": R(3, 7, 16, 10, 2.5); L([21.5, 10.5, 21.5, 13.5]); c.beginPath(); c.roundedRect(5.5*s, 9.5*s, 5*s, 5*s, 1*s, 1*s); c.fill(); break
        case "keyboard": R(2, 6, 20, 13, 3); for (var x = 0; x < 5; x++) { A(5.5 + x*3.25, 10, 0.9, 0, 7, true) } L([7.5, 15, 16.5, 15]); break
        case "shot": L([3, 8, 3, 3, 8, 3]); L([16, 3, 21, 3, 21, 8]); L([21, 16, 21, 21, 16, 21]); L([8, 21, 3, 21, 3, 16]); A(12, 12, 3.5, 0, 7); break
        case "sun": A(12, 12, 4.5, 0, 7); for (var j = 0; j < 8; j++) { var b = j * Math.PI / 4; L([12 + 7.5*Math.cos(b), 12 + 7.5*Math.sin(b), 12 + 9.5*Math.cos(b), 12 + 9.5*Math.sin(b)]) } break
        case "sound": c.beginPath(); c.moveTo(3*s, 9*s); c.lineTo(7*s, 9*s); c.lineTo(12*s, 4.5*s); c.lineTo(12*s, 19.5*s); c.lineTo(7*s, 15*s); c.lineTo(3*s, 15*s); c.closePath(); c.fill()
            if (on) { A(13, 12, 4, -0.9, 0.9); A(13, 12, 8, -0.8, 0.8) } else { L([16, 9, 22, 15]); L([22, 9, 16, 15]) } break
        case "gear": A(12, 12, 3.2, 0, 7); for (var k = 0; k < 8; k++) { var d = k * Math.PI / 4; L([12 + 6*Math.cos(d), 12 + 6*Math.sin(d), 12 + 9*Math.cos(d), 12 + 9*Math.sin(d)]) } A(12, 12, 6.5, 0, 7); break
        case "power": A(12, 13, 8, -Math.PI*0.32, Math.PI*1.32); L([12, 3, 12, 11]); break
        case "lock": R(5, 10.5, 14, 10.5, 2.5); A(12, 10.5, 4.5, Math.PI, 0); break
        case "battery": R(2, 7, 18, 10, 2.5); L([22, 10.5, 22, 13.5])
            if (level >= 0) { c.beginPath(); c.roundedRect(4.5*s, 9.5*s, Math.max(1.5, 13 * Math.min(1, level))*s, 5*s, 1*s, 1*s); c.fill() } break
        case "chev": L([9, 6, 15, 12, 9, 18]); break
        }
    }
}
