// S6 Migrate: the on-screen keyboard over the taskbar, like on a phone.
// KWin puts the keyboard just above any panel that keeps its space free at the bottom of the screen. While the
// keyboard is open, the bottom panels here stop keeping that space ("windows go below"), so it sits at the very
// bottom over them; when it closes they keep their space again. The taskbar itself never disappears.
// It never moves the keyboard itself: KWin places it once the space is free. (Moving it froze the tablet: the app
// shrank around the keyboard, KWin put the keyboard back, the script moved it again, without end.)
var lowered = [];      // ids of the panels changed here, to put back exactly those
var busy = false;
var kbd = null;

function plasma(js, done) {
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", js,
             function (out) { if (done) done(String(out || "")); });
}

function opened() {
    if (lowered.length || busy) return;
    busy = true;
    plasma("var ids = []; panels().forEach(function (p) { if (p.location == 'bottom' && p.hiding == 'none') " +
           "{ p.hiding = 'windowsgobelow'; ids.push(p.id); } }); print(ids.join(','));",
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
