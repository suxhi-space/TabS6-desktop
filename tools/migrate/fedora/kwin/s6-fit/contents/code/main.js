// S6 Migrate: keep windows on screen when the tablet turns. Full-screen and maximised windows are set again so they
// take the new shape; any other window is shrunk and moved back inside the screen if the turn left it outside.
function fit(w) {
    try {
        if (!w || !w.normalWindow || w.minimized) return;
        if (w.fullScreen) { w.fullScreen = false; w.fullScreen = true; return; }
        var area = workspace.clientArea(KWin.MaximizeArea, w);
        var g = w.frameGeometry;
        var maxed = (typeof w.maximizeMode !== "undefined" && w.maximizeMode === 3) ||
                    (Math.abs(g.width - area.width) < 4 && Math.abs(g.height - area.height) < 4);
        if (maxed) { w.setMaximize(false, false); w.setMaximize(true, true); return; }
        var nw = Math.min(g.width, area.width), nh = Math.min(g.height, area.height);
        var nx = Math.min(Math.max(g.x, area.x), area.x + area.width - nw);
        var ny = Math.min(Math.max(g.y, area.y), area.y + area.height - nh);
        if (nx !== g.x || ny !== g.y || nw !== g.width || nh !== g.height)
            w.frameGeometry = { x: nx, y: ny, width: nw, height: nh };
    } catch (e) {
        print("s6-fit: " + e);
    }
}
function fitAll() {
    var list = workspace.windowList ? workspace.windowList() : workspace.clientList();
    for (var i = 0; i < list.length; i++) fit(list[i]);
}
if (workspace.screensChanged) workspace.screensChanged.connect(fitAll);
if (workspace.virtualScreenGeometryChanged) workspace.virtualScreenGeometryChanged.connect(fitAll);
