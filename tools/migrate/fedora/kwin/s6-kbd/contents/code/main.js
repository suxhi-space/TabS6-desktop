// S6 Migrate: the taskbar steps aside while the full on-screen keyboard is open, like on a phone.
// KWin puts the keyboard just above a taskbar that keeps its space, so while the full-width keyboard is open the
// bottom panels hide (auto-hide), and the keyboard gets the bottom of the screen; when it closes they come back.
// A floating (narrower) keyboard leaves the taskbar alone.
// It never moves the keyboard itself: KWin places it. (An earlier version moved it and froze the tablet: the app
// shrank around the keyboard, KWin put the keyboard back, the script moved it again, without end.)
var lowered = [];      // ids of the panels changed here, to put back exactly those
var busy = false;
var kbd = null;

function plasma(js, done) {
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", js,
             function (out) { if (done) done(String(out || "")); });
}

function fullWidth() {   // the docked keyboard, not the floating one
    try {
        var area = workspace.clientArea(KWin.FullScreenArea, kbd);
        return kbd.frameGeometry.width >= area.width * 0.95;
    } catch (e) { return true; }
}

function opened() {
    if (lowered.length || busy || !fullWidth()) return;
    busy = true;
    plasma("var ids = []; panels().forEach(function (p) { if (p.location == 'bottom' && p.hiding == 'none') " +
           "{ p.hiding = 'autohide'; ids.push(p.id); } }); print(ids.join(','));",
           function (out) {
               busy = false;
               lowered = out.trim() ? out.trim().split(",") : [];
               if (kbd && kbd.hidden) closed();    // closed again meanwhile
           });
}

function closed() {
    if (!lowered.length || busy) return;
    var ids = lowered; lowered = [];
    plasma("[" + ids.join(",") + "].forEach(function (i) { var p = panelById(i); if (p) p.hiding = 'none'; });");
}

// Closing and opening again (moving between text fields) shouldn't make the taskbar jump: wait a moment
var later = null;
function closedSoon() {
    if (typeof QTimer === "undefined") { closed(); return; }
    if (!later) { later = new QTimer(); later.singleShot = true; later.timeout.connect(function () { if (!kbd || kbd.hidden) closed(); }); }
    later.start(400);
}

function watch(w) {
    if (!w || !w.inputMethod) return;
    kbd = w;
    w.hiddenChanged.connect(function () { if (w.hidden) closedSoon(); else opened(); });
    if (!w.hidden) opened();
}
workspace.windowAdded.connect(watch);
workspace.windowRemoved.connect(function (w) { if (w === kbd) { kbd = null; closed(); } });
(workspace.windowList ? workspace.windowList() : workspace.clientList()).forEach(watch);
