import QtQuick
import "."

// Small drawn icons (24-unit grid), so nothing depends on an icon theme being present.
Canvas {
    id: g
    property string kind: "ok"   // done current todo ok warn clock logo radio radioOn box phone screen folder wifi lock user spin fail
    property color tint: Theme.accent
    property real turn: 0
    property color fg: Theme.accentFg      // marks drawn on a filled shape
    property color hole: Theme.bg
    property color ringc: Theme.ring
    property color trackc: Theme.track
    onFgChanged: requestPaint()
    onHoleChanged: requestPaint()
    width: 22; height: 22
    onKindChanged: requestPaint()
    onTintChanged: requestPaint()
    onTurnChanged: requestPaint()
    Connections { target: Theme; function onDarkChanged() { g.requestPaint() } }
    RotationAnimation on turn { running: g.kind === "spin" && g.visible; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
    onPaint: {
        var c = getContext("2d"); var s = width / 24; c.reset();
        c.lineCap = "round"; c.lineJoin = "round"; c.strokeStyle = String(tint); c.fillStyle = String(tint);
        function line(pts) { c.beginPath(); c.moveTo(pts[0]*s, pts[1]*s); for (var i = 2; i < pts.length; i += 2) c.lineTo(pts[i]*s, pts[i+1]*s); c.stroke(); }
        function circle(x, y, r, fill) { c.beginPath(); c.arc(x*s, y*s, r*s, 0, Math.PI*2); fill ? c.fill() : c.stroke(); }
        function rrect(x, y, w, h, r) { c.beginPath(); c.roundedRect(x*s, y*s, w*s, h*s, r*s, r*s); c.stroke(); }
        switch (kind) {
        case "done": circle(12, 12, 12, true); c.strokeStyle = String(fg); c.lineWidth = 2.6*s; line([7,12.5, 10.5,16, 17,8.5]); break;
        case "current": circle(12, 12, 12, true); c.fillStyle = String(hole); circle(12, 12, 5.5, true); break;
        case "todo": c.strokeStyle = String(ringc); c.lineWidth = 2*s; circle(12, 12, 11); break;
        case "ok": c.lineWidth = 2.2*s; circle(12, 12, 10); line([7.5,12.5, 10.5,15.5, 16.5,9]); break;
        case "fail": c.lineWidth = 2.2*s; circle(12, 12, 10); line([8.5,8.5, 15.5,15.5]); line([15.5,8.5, 8.5,15.5]); break;
        case "warn": c.lineWidth = 2.2*s; c.beginPath(); c.moveTo(12*s,3*s); c.lineTo(21.5*s,20*s); c.lineTo(2.5*s,20*s); c.closePath(); c.stroke(); line([12,10, 12,14.5]); circle(12, 17.6, 1.3, true); break;
        case "clock": c.lineWidth = 2*s; circle(12, 12, 10); line([12,7, 12,12, 15,14]); break;
        case "radio": c.strokeStyle = String(ringc); c.lineWidth = 2*s; circle(12, 12, 11); break;
        case "radioOn": c.lineWidth = 2*s; circle(12, 12, 11); circle(12, 12, 5.7, true); break;
        case "box": c.lineWidth = 1.8*s; c.strokeRect(4*s, 7*s, 16*s, 13*s); line([9,7, 9,4, 15,4, 15,7]); break;
        case "phone": c.lineWidth = 1.8*s; rrect(7, 2, 10, 20, 2); line([11,18, 13,18]); break;
        case "screen": c.lineWidth = 1.8*s; rrect(3, 4, 18, 12, 2); line([8,20, 16,20]); line([12,16, 12,20]); break;
        case "folder": c.lineWidth = 1.8*s; c.beginPath(); c.moveTo(3*s,6*s); c.lineTo(9*s,6*s); c.lineTo(11*s,8*s); c.lineTo(21*s,8*s); c.lineTo(21*s,19*s); c.lineTo(3*s,19*s); c.closePath(); c.stroke(); break;
        case "wifi": c.lineWidth = 2*s; c.beginPath(); c.arc(12*s, 19*s, 14*s, -Math.PI*0.78, -Math.PI*0.22); c.stroke(); c.beginPath(); c.arc(12*s, 19*s, 9*s, -Math.PI*0.75, -Math.PI*0.25); c.stroke(); c.beginPath(); c.arc(12*s, 19*s, 4*s, -Math.PI*0.72, -Math.PI*0.28); c.stroke(); circle(12, 19, 1.4, true); break;
        case "lock": c.lineWidth = 1.8*s; rrect(5, 10, 14, 11, 2); c.beginPath(); c.arc(12*s, 10*s, 4.5*s, Math.PI, 0); c.stroke(); break;
        case "user": c.lineWidth = 1.8*s; circle(12, 8, 4); c.beginPath(); c.arc(12*s, 22*s, 8*s, Math.PI*1.1, Math.PI*1.9); c.stroke(); break;
        case "spin": c.lineWidth = 2.4*s; c.strokeStyle = String(trackc); circle(12, 12, 9.5); c.strokeStyle = String(tint); c.beginPath(); var a = turn * Math.PI / 180; c.arc(12*s, 12*s, 9.5*s, a, a + Math.PI*0.6); c.stroke(); break;
        case "logo":
            c.beginPath(); c.roundedRect(0, 0, width, height, width*0.27, width*0.27); c.fill();
            var o = width * 0.2, k = width * 0.6 / 24; c.strokeStyle = String(fg); c.lineWidth = 1.8*k;
            c.beginPath(); c.roundedRect(o+3*k, o+5*k, 13*k, 15*k, 2*k, 2*k); c.stroke();
            c.beginPath(); c.moveTo(o+14*k, o+9*k); c.lineTo(o+21*k, o+9*k); c.moveTo(o+18*k, o+6*k); c.lineTo(o+21*k, o+9*k); c.lineTo(o+18*k, o+12*k); c.stroke(); break;
        }
    }
}
