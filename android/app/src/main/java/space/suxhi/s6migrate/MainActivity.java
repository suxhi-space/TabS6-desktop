package space.suxhi.s6migrate;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * S6 Migrate: the Android to Fedora upgrade wizard for the Galaxy Tab S6 (SM-T860).
 *
 * Six steps (Introduction, What to keep, Apps on Fedora, Space check, Summary, Upgrade) in a Fedora-themed
 * frame that follows the tablet's light/dark setting. Packs the chosen apps, data, folders and settings with
 * root using the shared scripts in assets (tools/migrate/lib), looks up Linux versions of the chosen apps,
 * downloads the t860-fedora release to a card or USB drive and hands the upgrade to TWRP.
 * Nothing on Android is changed until the final, typed confirmation.
 */
public class MainActivity extends Activity {

    // Sizes from the t860-fedora v2026.10.29 release manifest.
    static final long FEDORA_IMAGE_KB = 18874368L;    // installed root, 18 GiB
    static final long FEDORA_DOWNLOAD_KB = 5254172L;  // compressed download incl. installer
    static final long FEDORA_HEADROOM_KB = 4194304L;  // working room for Linux, 4 GiB
    static final String PART_SIZE = "1000m";          // archive part size (FAT32-safe)

    static final Pattern SKIP = Pattern.compile(
            "^(com\\.termux.*|com\\.topjohnwu\\.magisk|io\\.github\\.huskydg\\.magisk|me\\.phh\\..*|"
                    + "com\\.android\\..*|com\\.google\\.android\\.gms|com\\.samsung\\..*|com\\.sec\\..*|"
                    + "space\\.suxhi\\.s6migrate)$");

    static class AppItem {
        String pkg, uid, label;
        long kb;
        boolean keystore, selected;
        Drawable icon;
        String choice = "keep"; // keep = Android only, both = Android + Linux, linux = Linux only (nothing packed)
        boolean choiceSet;      // default applied or picked by the user
        boolean installLinux;   // not brought along, but its Linux version is installed on Fedora
    }

    static class DirItem {
        String name;
        long kb;
        boolean selected;
        boolean top;   // "files directly in internal storage" (not a folder)
        long count;
        String kind = "DIR"; // DIR, TOP (loose files), SET (settings), WIFI (Wi-Fi networks)
        String sub;          // optional description shown under the name
        String dest;         // chosen place on Fedora (relative to ~), null = suggested
    }

    static final String TOP_LABEL = "Files directly in internal storage";

    static String dirLine(DirItem d) {
        switch (d.kind) {
            case "TOP": return "TOP|loose files";
            case "SET": return "SET|settings";
            case "WIFI": return "WIFI|wifi";
            default: return "DIR|" + d.name;
        }
    }

    static class Vol {
        String path, fs, kind;
        long freeKb;
    }

    final List<AppItem> apps = new ArrayList<>();
    final List<DirItem> dirs = new ArrayList<>();
    final List<Vol> vols = new ArrayList<>();
    final List<String[]> packages = new ArrayList<>(); // PKG|path|items|kb|status
    long internalFreeKb;
    String cryptoMode = "", probeHash = "";
    boolean metadataEncryption, keystoreChecked;
    int chosenDest = -1;

    final Handler ui = new Handler(Looper.getMainLooper());
    volatile boolean busy;
    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        initLook();
        scan();
    }

    // ------------------------------------------------------------------ helpers

    int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    static String human(long kb) {
        if (kb >= 1048576) return String.format(Locale.US, "%.1f GB", kb / 1048576.0);
        if (kb >= 1024) return String.format(Locale.US, "%d MB", kb / 1024);
        return kb + " KB";
    }

    // ------------------------------------------------------------------ root

    interface LineSink {
        void line(String s);
    }

    static int runRoot(String cmd, LineSink sink) throws IOException, InterruptedException {
        Process p = new ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
            String l;
            while ((l = r.readLine()) != null) sink.line(l);
        }
        return p.waitFor();
    }

    /** One long-lived root shell, so repeated small commands do not each make Magisk show a toast. */
    static class RootShell {
        final Process p;
        final java.io.Writer w;
        final BufferedReader r;

        RootShell() throws IOException {
            p = new ProcessBuilder("su").redirectErrorStream(true).start();
            w = new java.io.OutputStreamWriter(p.getOutputStream());
            r = new BufferedReader(new InputStreamReader(p.getInputStream()));
        }

        synchronized String run(String cmd) throws IOException {
            final String end = "__S6M_END__";
            w.write(cmd + "; echo " + end + "\n");
            w.flush();
            StringBuilder sb = new StringBuilder();
            String l;
            while ((l = r.readLine()) != null && !l.equals(end)) sb.append(l).append('\n');
            return sb.toString();
        }

        void close() {
            try {
                w.write("exit\n");
                w.flush();
            } catch (IOException ignored) {
            }
            p.destroy();
        }
    }

    static long duKb(RootShell rs, String path) {
        try {
            return parse(rs.run("du -sk " + q(path) + " 2>/dev/null").trim().split("\\s+")[0]);
        } catch (Exception e) {
            return 0;
        }
    }

    static int rootToFile(String cmd, File out) throws IOException, InterruptedException {
        Process p = new ProcessBuilder("su", "-c", cmd).start();
        long n = 0;
        try (InputStream in = p.getInputStream(); OutputStream os = new FileOutputStream(out)) {
            byte[] buf = new byte[65536];
            int k;
            while ((k = in.read(buf)) > 0) {
                os.write(buf, 0, k);
                n += k;
            }
        }
        int rc = p.waitFor();
        return (rc == 0 && n > 0) ? 0 : 1;
    }

    File asset(String name) throws IOException {
        File f = new File(getCacheDir(), name);
        try (InputStream in = getAssets().open(name); OutputStream os = new FileOutputStream(f)) {
            byte[] buf = new byte[16384];
            int k;
            while ((k = in.read(buf)) > 0) os.write(buf, 0, k);
        }
        return f;
    }

    static String q(String s) { // single-quote for sh
        return "'" + s.replace("'", "'\\''") + "'";
    }

    // ------------------------------------------------------------------ scan

    void scan() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        TextView m = text("Looking at your apps and folders (read-only).\n\nIf Magisk asks, tap Grant. This can take a minute.", 16, false);
        m.setGravity(Gravity.CENTER);
        body.addView(m);
        curStep = 0;
        frame("Move this tablet to Fedora", null, body, null, null, null, null, null);

        new Thread(() -> {
            try {
                File scanSh = asset("scan.sh");
                asset("pack.sh");
                asset("compare.sh");
                List<String> lines = new ArrayList<>();
                int rc = runRoot("sh " + q(scanSh.getAbsolutePath()) + " ''", lines::add);
                Set<String> keyUids = readKeystoreUids();
                ui.post(() -> parseScan(lines, keyUids, rc));
            } catch (Exception e) {
                ui.post(() -> message("Root needed",
                        "Could not run the scan as root (" + e.getMessage() + ").\n\n"
                                + "Open Magisk > Superuser, allow S6 Migrate, then start the app again."));
            }
        }).start();
    }

    Set<String> readKeystoreUids() {
        Set<String> uids = new HashSet<>();
        try {
            File db = new File(getCacheDir(), "ks.sqlite");
            File wal = new File(getCacheDir(), "ks.sqlite-wal");
            wal.delete();
            if (rootToFile("cat /data/misc/keystore/persistent.sqlite", db) != 0) return uids;
            if (rootToFile("cat /data/misc/keystore/persistent.sqlite-wal", wal) != 0) wal.delete();
            SQLiteDatabase d = SQLiteDatabase.openDatabase(db.getAbsolutePath(), null, SQLiteDatabase.OPEN_READWRITE);
            try (Cursor c = d.rawQuery("select distinct namespace from keyentry where domain=0", null)) {
                while (c.moveToNext()) uids.add(c.getString(0));
            }
            d.close();
            keystoreChecked = true;
        } catch (Exception ignored) {
            // Keystore check is optional: without it no warnings are shown.
        }
        return uids;
    }

    void parseScan(List<String> lines, Set<String> keyUids, int rc) {
        PackageManager pm = getPackageManager();
        for (String l : lines) {
            String[] f = l.split("\\|", -1);
            switch (f[0]) {
                case "APP": {
                    if (f.length < 5 || SKIP.matcher(f[1]).matches()) break;
                    AppItem a = new AppItem();
                    a.pkg = f[1];
                    a.uid = f[2];
                    a.kb = parse(f[3]) + parse(f[4]);
                    a.keystore = keyUids.contains(a.uid);
                    a.label = a.pkg;
                    try {
                        ApplicationInfo ai = pm.getApplicationInfo(a.pkg, 0);
                        a.label = String.valueOf(ai.loadLabel(pm));
                        a.icon = ai.loadIcon(pm);
                    } catch (Exception ignored) {
                    }
                    apps.add(a);
                    break;
                }
                case "DIR": {
                    if (f.length < 3) break;
                    DirItem d = new DirItem();
                    d.name = f[1];
                    d.kb = parse(f[2]);
                    dirs.add(d);
                    break;
                }
                case "VOL": {
                    if (f.length < 5) break;
                    Vol v = new Vol();
                    v.path = f[1];
                    v.freeKb = parse(f[2]);
                    v.fs = f[3];
                    v.kind = f[4];
                    vols.add(v);
                    break;
                }
                case "INTFREE":
                    internalFreeKb = parse(f[1]);
                    break;
                case "CRYPTO":
                    if (f.length >= 4) {
                        cryptoMode = f[2];
                        metadataEncryption = "yes".equals(f[3]);
                    }
                    break;
                case "PROBE":
                    probeHash = f[1];
                    break;
                case "TOPFILES": {
                    if (f.length < 3) break;
                    DirItem d = new DirItem();
                    d.name = TOP_LABEL;
                    d.top = true;
                    d.kind = "TOP";
                    d.count = parse(f[1]);
                    d.kb = parse(f[2]);
                    dirs.add(0, d);
                    break;
                }
                case "SETTINGS": { // SETTINGS|wallpapers|bluetooth devices|wifi networks[-encrypted]
                    if (f.length < 4) break;
                    DirItem st = new DirItem();
                    st.kind = "SET";
                    st.name = "Settings";
                    st.kb = 4096;
                    st.selected = true;
                    long bt = parse(f[2]);
                    st.sub = "Wallpaper" + (parse(f[1]) > 1 ? "s" : "") + ", dark mode, time zone, language, device name"
                            + (bt > 0 ? ", " + bt + " Bluetooth pairing" + (bt == 1 ? "" : "s") + " (experimental)" : "");
                    dirs.add(0, st);
                    boolean enc = f[3].endsWith("encrypted");
                    long nets = parse(f[3].replace("-encrypted", ""));
                    if (nets > 0) {
                        DirItem wf = new DirItem();
                        wf.kind = "WIFI";
                        wf.name = "Wi-Fi networks and passwords";
                        wf.kb = 64;
                        wf.selected = !enc;
                        wf.sub = enc ? nets + " saved networks, but this tablet encrypts their passwords: add them again on Fedora"
                                : nets + " saved network" + (nets == 1 ? "" : "s") + ". Passwords are stored in your package on the drive: keep it private";
                        dirs.add(1, wf);
                    }
                    break;
                }
                case "PKG":
                    if (f.length >= 5) packages.add(f);
                    break;
                default:
                    break;
            }
        }
        if (apps.isEmpty() && dirs.isEmpty()) {
            message("Scan failed", "Root did not return any apps (exit code " + rc + ").\n\n"
                    + "Open Magisk > Superuser, allow S6 Migrate, then start the app again.");
            return;
        }
        Collections.sort(apps, (x, y) -> x.label.compareToIgnoreCase(y.label));
        loadAlternatives();
        new Thread(this::loadLiveAlternatives).start();
        home();
    }

    static long parse(String s) {
        try {
            return Long.parseLong(s.trim());
        } catch (Exception e) {
            return 0;
        }
    }

    // ------------------------------------------------------------------ space check

    static long margin(long kb) {
        return kb / 20 + 102400;
    }

    static String fit(long free, long need) {
        return free >= need ? "fits ✓" : "short by " + human(need - free);
    }

    String vName(Vol v) {
        String k = "microSD".equals(v.kind) ? "microSD card" : "USB".equals(v.kind) ? "USB drive" : "External drive";
        return k + " (" + v.path.substring(v.path.lastIndexOf('/') + 1) + ")";
    }

    // ------------------------------------------------------------------ pickers

    static class Change {
        String kind, name, label, sub, line;
        long kb;
        boolean selected;
        Drawable icon;
    }

    Change makeChange(String kind, String name, String existingLine) {
        Change c = new Change();
        c.kind = kind;
        c.name = name;
        c.label = name;
        if ("APP".equals(kind)) {
            AppItem found = null;
            for (AppItem a : apps) if (a.pkg.equals(name)) found = a;
            if (found != null) {
                c.label = found.label;
                c.icon = found.icon;
                c.kb = found.kb;
                c.line = planLine(found);
            } else {
                c.line = existingLine != null ? existingLine : "APP|" + name + "||";
            }
        } else if ("SET".equals(kind) || "WIFI".equals(kind)) {
            for (DirItem d : dirs)
                if (kind.equals(d.kind)) {
                    c.label = d.name;
                    c.kb = d.kb;
                }
            c.line = "SET".equals(kind) ? "SET|settings" : "WIFI|wifi";
        } else if ("TOP".equals(kind)) {
            c.label = TOP_LABEL;
            for (DirItem d : dirs) if ("TOP".equals(d.kind)) c.kb = d.kb;
            c.line = "TOP|loose files";
        } else {
            for (DirItem d : dirs) if ("DIR".equals(d.kind) && d.name.equals(name)) c.kb = d.kb;
            c.line = "DIR|" + name;
        }
        return c;
    }

    long freeFor(String path) {
        for (Vol v : vols) if (path.startsWith(v.path + "/")) return v.freeKb;
        return internalFreeKb;
    }

    void openPackage(String[] p, String when, String where) {
        curStep = 0;
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        body.addView(text("Comparing your package with what is on the tablet now (read-only)...", 16, false));
        screen("Your package from " + when, null, body, false, null, null, "Back", this::home);
        new Thread(() -> {
            List<String> plan = new ArrayList<>();
            List<String> cmp = new ArrayList<>();
            try {
                partOwner = new HashMap<>();
                for (String[] pp : partsOf(p)) { // a split package: every part, on every drive
                    List<String> pl = new ArrayList<>();
                    runRoot("cat " + q(pp[1] + "/plan.txt"), pl::add);
                    for (String l : pl) {
                        String[] f = l.split("\\|", -1);
                        if (f.length >= 2) {
                            partOwner.put(f[0] + "|" + f[1], pp[1]);
                            if ("LINUX".equals(f[0])) partOwner.put("APP|" + f[1], pp[1]);
                        }
                    }
                    plan.addAll(pl);
                    runRoot("sh " + q(new File(getCacheDir(), "compare.sh").getAbsolutePath()) + " '' " + q(pp[1]), cmp::add);
                }
            } catch (Exception e) {
                ui.post(() -> message("Could not compare", String.valueOf(e.getMessage())));
                return;
            }
            ui.post(() -> showPackage(p, when, where, plan, cmp));
        }).start();
    }

    void showPackage(String[] p, String when, String where, List<String> plan, List<String> cmp) {
        Set<String> inPlan = new HashSet<>();
        Map<String, String> planLines = new HashMap<>();
        for (String l : plan) {
            String[] f = l.split("\\|", -1);
            if (f.length >= 2) {
                inPlan.add(f[0] + "|" + f[1]);
                if ("LINUX".equals(f[0])) inPlan.add("APP|" + f[1]);
                planLines.put(f[0] + "|" + f[1], l);
            }
        }
        List<Change> changed = new ArrayList<>();
        List<Change> fresh = new ArrayList<>();
        List<String> gone = new ArrayList<>();
        int same = 0;
        for (String l : cmp) {
            String[] f = l.split("\\|", -1);
            if (f.length < 5 || !"CMP".equals(f[0])) continue;
            if ("same".equals(f[3])) {
                same++;
            } else if ("gone".equals(f[3])) {
                gone.add(makeChange(f[1], f[2], planLines.get(f[1] + "|" + f[2])).label);
            } else {
                Change c = makeChange(f[1], f[2], planLines.get(f[1] + "|" + f[2]));
                long n = parse(f[4]);
                c.sub = "changed".equals(f[3])
                        ? (n >= 1000 ? "1000+ files changed" : n + (n == 1 ? " file changed" : " files changed")) + " \u00b7 " + human(c.kb)
                        : "Could not compare; re-packing is the safe choice";
                c.selected = true;
                changed.add(c);
            }
        }
        for (AppItem a : apps)
            if (!inPlan.contains("APP|" + a.pkg)) {
                Change c = makeChange("APP", a.pkg, null);
                c.sub = "Not in the package \u00b7 " + human(c.kb);
                fresh.add(c);
            }
        for (DirItem d : dirs)
            if (!inPlan.contains(dirLine(d))) {
                Change c = makeChange(d.kind, d.name, null);
                c.sub = "Not in the package \u00b7 " + human(c.kb);
                fresh.add(c);
            }
        final List<Change> all = new ArrayList<>(changed);
        all.addAll(fresh);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(text(parse(p[2]) + " items, " + human(parse(p[3])) + " on the " + where + ".\nSince then: "
                + changed.size() + " changed, " + fresh.size() + " new, " + gone.size() + " no longer on the tablet, "
                + same + " unchanged.", 15, false));
        TextView need = tv("", 15, fSemi, t.accentText);
        need.setPadding(0, dp(8), 0, dp(8));
        Runnable refresh = () -> {
            long kb = 0;
            int n = 0;
            for (Change c : all) if (c.selected) { kb += c.kb; n++; }
            long free = freeFor(p[1]), req = kb + margin(kb);
            need.setText(n == 0 ? "Nothing selected to update."
                    : "Update " + n + (n == 1 ? " item" : " items") + ", about " + human(kb) + ": "
                    + (free >= req ? "fits (" + human(free) + " free)." : "not enough space (needs " + human(req) + ", " + human(free) + " free)."));
        };
        body.addView(need);
        if (changed.isEmpty() && fresh.isEmpty()) {
            body.addView(text("\nYour package is up to date: nothing has changed since you made it.", 16, true));
        }
        if (!changed.isEmpty()) {
            body.addView(gap(14));
            body.addView(h2("Changed since then (ticked: re-pack recommended)"));
            for (Change c : changed)
                body.addView(row(c.icon, c.label, c.sub, null, c.selected, on -> { c.selected = on; refresh.run(); }));
        }
        if (!fresh.isEmpty()) {
            body.addView(gap(14));
            body.addView(h2("On the tablet but not in the package"));
            for (Change c : fresh)
                body.addView(row(c.icon, c.label, c.sub, null, c.selected, on -> { c.selected = on; refresh.run(); }));
        }
        if (!gone.isEmpty()) {
            body.addView(gap(14));
            body.addView(h2("No longer on the tablet"));
            body.addView(text(String.join(", ", gone) + "\nTheir copies stay in the package.", 14, false));
        }
        refresh.run();
        screen("Your package from " + when, null, body, false,
                "Update package", () -> confirmUpdate(p, all), "Back", this::home);
    }

    void confirmUpdate(String[] p, List<Change> all) {
        // Each changed item is re-packed into the part that holds it; new items go to the part with the most room.
        List<String[]> parts = partsOf(p);
        String roomiest = parts.get(0)[1];
        for (String[] pp : parts) if (freeFor(pp[1]) > freeFor(roomiest)) roomiest = pp[1];
        Map<String, StringBuilder> plans = new java.util.LinkedHashMap<>();
        Map<String, long[]> sizes = new HashMap<>(); // path -> {items, kb}
        int n = 0;
        long kb = 0;
        for (Change c : all)
            if (c.selected) {
                String[] cf = c.line.split("\\|", -1);
                String key = cf[0] + "|" + (cf.length > 1 ? cf[1] : "");
                String dest = partOwner.getOrDefault(key, roomiest);
                plans.computeIfAbsent(dest, k -> new StringBuilder()).append(c.line).append('\n');
                long[] sz = sizes.computeIfAbsent(dest, k -> new long[2]);
                sz[0]++;
                sz[1] += c.kb;
                n++;
                kb += c.kb;
            }
        if (n == 0) {
            Toast.makeText(this, "Nothing selected to update.", Toast.LENGTH_SHORT).show();
            return;
        }
        for (Map.Entry<String, long[]> e : sizes.entrySet())
            if (freeFor(e.getKey()) < e.getValue()[1] + margin(e.getValue()[1])) {
                Toast.makeText(this, "Not enough free space on the " + whereOf(e.getKey()) + " for this update.", Toast.LENGTH_LONG).show();
                return;
            }
        List<String> dests = new ArrayList<>(plans.keySet());
        StringBuilder where = new StringBuilder();
        for (String d : dests) where.append("\n").append(d);
        new AlertDialog.Builder(this).setTitle("Update this package?")
                .setMessage(n + (n == 1 ? " item" : " items") + " (about " + human(kb) + ") will be re-packed into" + where
                        + "\n\nEach item replaces its old copy only after the new one is verified. Nothing on Android is changed.")
                .setPositiveButton("Update", (d, w) -> updatePart(dests, 0, plans, sizes))
                .setNegativeButton("Cancel", null).show();
    }

    void updatePart(List<String> dests, int i, Map<String, StringBuilder> plans, Map<String, long[]> sizes) {
        String d = dests.get(i);
        if (dests.size() > 1) packPart = "Part " + (i + 1) + " of " + dests.size() + ": " + whereOf(d);
        if (i + 1 < dests.size()) afterPack = () -> updatePart(dests, i + 1, plans, sizes);
        long[] sz = sizes.get(d);
        runPack(d, plans.get(d).toString(), (int) sz[0], sz[1], true);
    }

    /** All parts of the package p (same name on several drives), p first. */
    List<String[]> partsOf(String[] p) {
        List<String[]> l = new ArrayList<>();
        l.add(p);
        for (String[] q : packages) if (q != p && !q[1].equals(p[1]) && folderOf(q[1]).equals(folderOf(p[1]))) l.add(q);
        return l;
    }

    // ------------------------------------------------------------------ split packages

    static final int SPLIT = -2;
    boolean deleteOld = true;            // delete older packages once the new one is verified

    /** Deletes package folders (every part); only dated S6Migrate package folders, never the Fedora download. */
    long deletePackages(List<String[]> pkgs) {
        long freed = 0;
        for (String[] p : pkgs) {
            if (!p[1].matches(".*/S6Migrate/\\d{8}-\\d{6}$")) continue;
            try {
                runRoot("rm -rf " + q(p[1]), l -> { });
                freed += parse(p[3]);
            } catch (Exception ignored) {
            }
        }
        return freed;
    }
    String packPart, packPartsInfo;      // label and parts.txt for the next runPack
    Runnable afterPack;                  // what runs after the next runPack succeeds
    volatile int packGen;
    Map<String, String> partOwner = new HashMap<>(); // "KIND|name" -> part folder holding it

    static class Part {
        Vol vol;
        final List<String> lines = new ArrayList<>();
        long kb;
    }

    /** Spreads the selection over all cards and drives (biggest items first, each to the drive with the most room left). */
    List<Part> splitPlan() {
        if (vols.size() < 2) return null;
        List<Part> parts = new ArrayList<>();
        for (Vol v : vols) { Part pt = new Part(); pt.vol = v; parts.add(pt); }
        List<Object[]> items = new ArrayList<>(); // {line, kb}
        for (AppItem a : apps) {
            String l = appLine(a);
            if (l == null) continue;
            items.add(new Object[]{l, l.startsWith("LINUX|") ? 0L : a.kb});
        }
        for (DirItem d : dirs) if (dirSel(d)) items.add(new Object[]{dirLine(d), d.kb});
        if (items.isEmpty()) return null;
        Collections.sort(items, (x, y) -> Long.compare((Long) y[1], (Long) x[1]));
        for (Object[] it : items) {
            Part best = null;
            long kb = (Long) it[1];
            for (Part pt : parts) {
                long left = pt.vol.freeKb - (pt.kb + kb) - margin(pt.kb + kb);
                if (left >= 0 && (best == null || pt.vol.freeKb - pt.kb > best.vol.freeKb - best.kb)) best = pt;
            }
            if (best == null) return null; // does not fit anywhere
            best.lines.add((String) it[0]);
            best.kb += kb;
        }
        parts.removeIf(pt -> pt.lines.isEmpty());
        return parts.size() >= 2 ? parts : null;
    }

    void packSplit(String stamp) {
        List<Part> parts = splitPlan();
        if (parts == null) { spaceStep(); return; }
        packSplitPart(parts, 0, stamp);
    }

    void packSplitPart(List<Part> parts, int i, String stamp) {
        Part pt = parts.get(i);
        packPart = "Part " + (i + 1) + " of " + parts.size() + ": " + vName(pt.vol);
        packPartsInfo = "id=" + stamp + "\nparts=" + parts.size() + "\npart=" + (i + 1) + "\n";
        if (i + 1 < parts.size()) afterPack = () -> packSplitPart(parts, i + 1, stamp);
        runPack(pt.vol.path + "/S6Migrate/" + stamp, String.join("\n", pt.lines) + "\n", pt.lines.size(), pt.kb, false);
    }


    // ------------------------------------------------------------------ switch to Fedora

    // The Fedora build for the SM-T860 (starlight4you/t860-fedora), pinned with its published checksums.
    static final String FEDORA_TAG = "v2026.10.29-gpu18";
    static final String FEDORA_BASE = "https://github.com/starlight4you/t860-fedora/releases/download/" + FEDORA_TAG + "/";
    static final String[][] FEDORA_FILES = {
            {"T860-Fedora44-GPU18-installer.tar.gz", "18342567", "9d071f316071acf38de679b41dbfe6fcd79717e4158eead372910bda04a3bd0b"},
            {"T860-Fedora44-GPU18-rootfs.img.gz.part000", "1800000000", "7d2050feef3bdab73c14698ad1477b4bc76f9cef0fe724bacc6c92b576ac247d"},
            {"T860-Fedora44-GPU18-rootfs.img.gz.part001", "1800000000", "db41d80c3f1aca17bf6a0891e455dde72241359f31d400c3c504a4e4a5263e8b"},
            {"T860-Fedora44-GPU18-rootfs.img.gz.part002", "1761929796", "50ca7a017fe9ba6d9995f7e438ecc681efafd4fa8d40543b626dac589385dd78"},
    };
    String[] switchPkg;
    String fedoraDrive; // drive the user picked for the Fedora download (external only)
    volatile boolean cancelDownload;

    static String folderOf(String path) { return path.substring(path.lastIndexOf('/') + 1); }
    static String driveOf(String pkgPath) { return pkgPath.substring(0, pkgPath.indexOf("/S6Migrate/")); }

    String[] newestExternalPackage() {
        String[] best = null;
        for (String[] p : packages) {
            if (p[1].startsWith("/data/media") || !p[1].contains("/S6Migrate/")) continue;
            if (best == null || folderOf(p[1]).compareTo(folderOf(best[1])) > 0) best = p;
        }
        return best;
    }

    void switchStart() {
        curStep = 5;
        boolean fresh = "fresh".equals(keepMode);
        switchPkg = fresh ? null : newestExternalPackage();
        if (switchPkg == null && !fresh) {
            LinearLayout b = vbox();
            b.addView(text("The upgrade needs your package on a USB drive or microSD card (internal storage is erased). "
                    + "Make a package on a drive first, then come back here.", 16, false));
            frame("Upgrade", null, b, null, "Make a package", this::keep, "Back", this::home);
            return;
        }
        if (vols.isEmpty()) {
            LinearLayout b = vbox();
            b.addView(text("Plug in a USB drive or microSD card: Fedora is downloaded to it (it is not erased).", 16, false));
            frame("Upgrade", null, b, null, null, null, "Back", this::home);
            return;
        }
        LinearLayout body = vbox();
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        body.addView(text("Checking your tablet (read-only)...", 16, false));
        frame("Upgrade to Fedora", null, body, null, null, null, "Back", this::home);
        final String pkgDrive = switchPkg != null ? driveOf(switchPkg[1]) : null;
        final List<String> drives = new ArrayList<>();
        for (Vol vo : vols) drives.add(vo.path);
        if (pkgDrive != null && !drives.contains(pkgDrive)) drives.add(0, pkgDrive);
        new Thread(() -> {
            StringBuilder names = new StringBuilder();
            for (String[] f : FEDORA_FILES) names.append(' ').append(f[0]);
            StringBuilder sh = new StringBuilder("echo MODEL=$(getprop ro.product.vendor.model);"
                    + "echo BAT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null);"
                    + "echo CHG=$(cat /sys/class/power_supply/battery/status 2>/dev/null);"
                    + "echo UP=$(cut -d. -f1 /proc/uptime);"
                    + "O=/cache/recovery/openrecoveryscript; [ -f $O ] && echo ORSAGE=$(( $(date +%s) - $(stat -c %Y $O) ));");
            for (int i = 0; i < drives.size(); i++) {
                String dr = drives.get(i), fd = dr + "/S6Migrate/fedora";
                sh.append("for f in").append(names).append("; do [ -f ").append(q(fd)).append("/$f.verified ] && echo D").append(i).append("VERIFIED=$f;")
                        .append(" [ -f ").append(q(fd)).append("/$f.partial ] && echo D").append(i).append("PARTIAL=$f=$(stat -c %s ").append(q(fd)).append("/$f.partial); done;")
                        .append("echo D").append(i).append("FREE=$(df -k ").append(q(dr)).append(" | tail -1 | tr -s ' ' | cut -d' ' -f4);")
                        .append("L=").append(q(dr + "/S6Migrate/switch-log.txt")).append("; [ -f \"$L\" ] && { grep -q S6MIGRATE-REHEARSAL-PASSED \"$L\" && echo D").append(i).append("LAST=passed")
                        .append(" || echo D").append(i).append("LAST=$(grep -m1 STOPPED \"$L\" | cut -c1-200); };");
            }
            final Map<String, String> v = new HashMap<>();
            final List<DriveState> states = new ArrayList<>();
            for (String dr : drives) { DriveState ds = new DriveState(); ds.path = dr; states.add(ds); }
            try {
                runRoot(sh.toString(), l -> {
                    int i = l.indexOf('=');
                    if (i < 0) return;
                    String k = l.substring(0, i), val = l.substring(i + 1);
                    java.util.regex.Matcher mt = Pattern.compile("^D(\\d+)(\\w+)$").matcher(k);
                    if (!mt.matches()) { v.put(k, val); return; }
                    int di = Integer.parseInt(mt.group(1));
                    if (di >= states.size()) return;
                    DriveState ds = states.get(di);
                    switch (mt.group(2)) {
                        case "VERIFIED": ds.verified.add(val); break;
                        case "PARTIAL": ds.partial += parse(val.substring(val.lastIndexOf('=') + 1)); break;
                        case "FREE": ds.freeKb = parse(val); break;
                        case "LAST": ds.last = val; break;
                    }
                });
            } catch (Exception e) {
                ui.post(() -> message("Could not check", String.valueOf(e.getMessage())));
                return;
            }
            ui.post(() -> showSwitchChecks(v, states));
        }).start();
    }

    static class DriveState {
        String path, last;
        long freeKb, partial;
        final Set<String> verified = new HashSet<>();

        long missingBytes() {
            long need = 0;
            for (String[] f : FEDORA_FILES) if (!verified.contains(f[0])) need += Long.parseLong(f[1]);
            return Math.max(0, need - partial);
        }

        long neededKb() { return missingBytes() / 1024 + 204800; }

        boolean done() { return verified.size() == FEDORA_FILES.length; }
    }

    String driveName(String path) {
        for (Vol vo : vols) if (vo.path.equals(path)) return vName(vo);
        return "Drive (" + path.substring(path.lastIndexOf('/') + 1) + ")";
    }

    /** Where the Fedora download goes: the user's pick, else a drive that has it (or part of it), else the package's drive if it fits, else the roomiest. */
    DriveState pickDrive(List<DriveState> st) {
        for (DriveState d : st) if (d.path.equals(fedoraDrive)) return d;
        for (DriveState d : st) if (d.done()) return d;
        for (DriveState d : st) if (d.partial > 0 || !d.verified.isEmpty()) return d;
        DriveState best = st.get(0);
        if (best.freeKb >= best.neededKb()) return best;
        for (DriveState d : st) if (d.freeKb > best.freeKb) best = d;
        return best;
    }

    void showSwitchChecks(Map<String, String> v, List<DriveState> states) {
        final DriveState sel = pickDrive(states);
        fedoraDrive = sel.path;
        final String drive = sel.path, fdir = drive + "/S6Migrate/fedora";
        final Set<String> verified = sel.verified;
        final long partialBytes = sel.partial;
        curStep = 5;
        String pkgLast = null;
        for (DriveState d : states) if (switchPkg != null && d.path.equals(driveOf(switchPkg[1]))) pkgLast = d.last;
        if (sel.last != null) pkgLast = sel.last;
        v.put("LAST", pkgLast);
        if (pkgLast == null) v.remove("LAST");
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        String model = v.getOrDefault("MODEL", "");
        boolean modelOk = model.startsWith("SM-T860");
        long bat = parse(v.getOrDefault("BAT", "0"));
        String chg = v.getOrDefault("CHG", "");
        boolean charging = chg.equalsIgnoreCase("Charging") || chg.equalsIgnoreCase("Full");
        boolean batOk = bat >= 60;
        boolean allParts = true;
        if (switchPkg != null) for (String[] x : partsOf(switchPkg)) allParts &= "complete".equals(x[4]);
        final boolean pkgOk = allParts;
        long need = 0, total = 0;
        for (String[] f : FEDORA_FILES) {
            total += Long.parseLong(f[1]);
            if (!verified.contains(f[0])) need += Long.parseLong(f[1]);
        }
        boolean fedoraOk = need == 0;
        long freeKb = sel.freeKb;
        long needKb = sel.neededKb();

        long orsAge = parse(v.getOrDefault("ORSAGE", "-1")), up = parse(v.getOrDefault("UP", "0"));
        if (v.containsKey("ORSAGE") && orsAge > up) { // queued before the last restart and still there: TWRP didn't run it
            body.addView(checkRow(false, "Last time, TWRP opened its menu instead of starting by itself",
                    "Nothing was changed. Use the manual way on the next screen (Install, then the ZIP on your card)."));
            new Thread(() -> { try { runRoot("rm -f /cache/recovery/openrecoveryscript", l -> { }); } catch (Exception ignored) { } }).start();
        }
        String last = v.get("LAST");
        if (last != null) body.addView(checkRow("passed".equals(last), "passed".equals(last)
                ? "Last rehearsal in TWRP passed" : "Last TWRP run stopped", "passed".equals(last) ? null : last));
        body.addView(checkRow(modelOk, "Galaxy Tab S6 Wi-Fi (SM-T860)", modelOk ? null : "This tablet reports '" + model + "'. The switch only supports the SM-T860."));
        body.addView(checkRow(batOk, "Battery " + bat + "%" + (charging ? ", charging" : ""), batOk ? (charging ? null : "Plug in the charger during the switch.") : "Charge to at least 60% and keep the charger plugged in."));
        if (switchPkg == null) {
            body.addView(checkRow(true, "Start fresh: nothing is restored", null));
        } else {
            List<String[]> pp = partsOf(switchPkg);
            long items = 0, kbs = 0;
            StringBuilder on = new StringBuilder();
            for (String[] x : pp) {
                items += parse(x[2]);
                kbs += parse(x[3]);
                on.append(on.length() > 0 ? " and the " : "On the ").append(whereOf(x[1]));
            }
            body.addView(checkRow(pkgOk, "Your package from " + when(switchPkg[1]) + " (" + items + " items, " + human(kbs) + ")",
                    pkgOk ? on + (pp.size() > 1 ? ": keep both in during the upgrade" : "") : "Some items didn't pack correctly. Fixing it packs only those items again."));
            if (!pkgOk) body.addView(button("Fix the package (packs only what's missing)", true, () -> repairPackage(switchPkg)), lpm(WRAP, WRAP, 0, 4, 0, 8));
            body.addView(link("Check the package for changes", () -> openPackage(switchPkg, when(switchPkg[1]), whereOf(switchPkg[1]))));
        }
        body.addView(checkRow(fedoraOk, "Fedora downloaded and verified (" + human(total / 1024) + ")",
                fedoraOk ? "On the " + driveName(drive) + ", in S6Migrate/fedora." :
                        "Needs " + human(Math.max(0, need - partialBytes) / 1024) + " more" + (partialBytes > 0 ? " (resumes where it stopped)" : "")
                                + ". Free on the " + driveName(drive) + ": " + human(freeKb) + "."));
        if (!fedoraOk) {
            body.addView(gap(6));
            body.addView(h2("Download Fedora to"));
            RadioGroup g = new RadioGroup(this);
            for (DriveState d : states) {
                RadioButton rb = new RadioButton(this);
                tint(rb);
                rb.setTextSize(15);
                rb.setPadding(dp(8), dp(8), 0, dp(8));
                boolean fits = d.done() || d.freeKb >= d.neededKb();
                rb.setText(driveName(d.path) + ": " + human(d.freeKb) + " free on this drive"
                        + (d.done() ? ", Fedora already here" : d.partial > 0 ? ", download started here" : "")
                        + (fits ? "" : " (short by " + human(d.neededKb() - d.freeKb) + ")")
                        + (switchPkg != null && d.path.equals(driveOf(switchPkg[1])) ? "\nYour package is on this drive" : ""));
                rb.setEnabled(fits);
                rb.setChecked(d == sel);
                rb.setOnClickListener(x -> { fedoraDrive = d.path; switchStart(); });
                g.addView(rb);
            }
            body.addView(g);
            body.addView(text("Internal storage (" + human(internalFreeKb) + " free) can't hold the download: "
                    + "the upgrade erases it, and TWRP reads the download while Fedora is written there. "
                    + (freeKb >= needKb ? "" : "A USB stick of 8 GB or more works, or free about " + human(needKb - freeKb) + " on the " + driveName(drive) + "."), 13, false));
            body.addView(gap(4));
            TextView dl = button(freeKb >= needKb ? "Download Fedora (" + human(Math.max(0, need - partialBytes) / 1024) + ")" : "Not enough space on the drive",
                    true, () -> downloadFedora(fdir));
            enable(dl, freeKb >= needKb);
            body.addView(dl, lpm(WRAP, WRAP, 0, 8, 0, 8));
        }
        body.addView(gap(14));
        body.addView(h2("Before you continue, confirm"));
        CheckBox twrp = new CheckBox(this);
        tint(twrp);
        twrp.setTextSize(15);
        twrp.setText("TWRP (the official one for gts6lwifi) is installed as my recovery");
        CheckBox auth = new CheckBox(this);
        tint(auth);
        auth.setTextSize(15);
        auth.setText("I exported my authenticator codes and saved anything else I need");
        body.addView(twrp);
        body.addView(auth);
        frame("Upgrade to Fedora", "Nothing is changed on this screen.", body, null, "Continue", () -> {
            if (!modelOk || !batOk || !pkgOk || !fedoraOk) {
                Toast.makeText(this, "Fix the items marked ✗ first.", Toast.LENGTH_LONG).show();
            } else if (!twrp.isChecked() || !auth.isChecked()) {
                Toast.makeText(this, "Please confirm both points.", Toast.LENGTH_LONG).show();
            } else {
                finalConfirm(drive);
            }
        }, "Back", this::home);
    }

    static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    void downloadFedora(String fdir) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView status = text("Starting...", 16, true);
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(1000);
        bar.setProgressTintList(ColorStateList.valueOf(t.accent));
        TextView detail = tv("", 14, fText, t.muted);
        curStep = 5;
        body.addView(status);
        body.addView(bar);
        body.addView(detail);
        body.addView(text("\nKeep this screen open and Wi-Fi on. If it stops, start again: it resumes where it left off.", 13, false));
        cancelDownload = false;
        busy = true;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        frame("Downloading Fedora", null, body, null, null, null, "Pause", () -> cancelDownload = true);
        long total = 0;
        for (String[] f : FEDORA_FILES) total += Long.parseLong(f[1]);
        final long fTotal = total;
        new Thread(() -> {
            String err = null;
            long doneAll = 0;
            try {
                // Which files are already verified?
                Set<String> verified = new HashSet<>();
                runRoot("for f in " + q(fdir) + "/*.verified; do [ -f \"$f\" ] && basename \"$f\" .verified; done", verified::add);
                for (String[] f : FEDORA_FILES) {
                    String name = f[0];
                    long size = Long.parseLong(f[1]);
                    if (verified.contains(name)) { doneAll += size; continue; }
                    String target = fdir + "/" + name, part = target + ".partial";
                    final long[] have = {0};
                    runRoot("stat -c %s " + q(part) + " 2>/dev/null || echo 0", l -> have[0] = parse(l));
                    if (have[0] > size) { runRoot("rm -f " + q(part), l -> { }); have[0] = 0; }
                    MessageDigest md = MessageDigest.getInstance("SHA-256");
                    if (have[0] > 0) { // re-read what is already there so the checksum covers the whole file
                        final long base0 = doneAll;
                        ui.post(() -> status.setText("Checking what was already downloaded of " + name + "..."));
                        Process rp = new ProcessBuilder("su", "-c", "cat " + q(part)).start();
                        try (InputStream in = rp.getInputStream()) {
                            byte[] buf = new byte[1 << 20];
                            int k;
                            while ((k = in.read(buf)) > 0) md.update(buf, 0, k);
                        }
                        rp.waitFor();
                    }
                    HttpURLConnection c = (HttpURLConnection) new URL(FEDORA_BASE + name).openConnection();
                    c.setRequestProperty("User-Agent", "S6Migrate");
                    c.setConnectTimeout(30000);
                    c.setReadTimeout(60000);
                    if (have[0] > 0) c.setRequestProperty("Range", "bytes=" + have[0] + "-");
                    int code = c.getResponseCode();
                    if (have[0] > 0 && code == 200) { // server ignored the range: start this file again
                        runRoot("rm -f " + q(part), l -> { });
                        have[0] = 0;
                        md.reset();
                    } else if (code != 200 && code != 206) {
                        throw new IOException("server answered " + code + " for " + name);
                    }
                    Process w = new ProcessBuilder("su", "-c", "mkdir -p " + q(fdir) + " && cat >> " + q(part)).start();
                    long got = have[0];
                    long lastUi = 0, t0 = System.currentTimeMillis(), startGot = got;
                    try (InputStream in = c.getInputStream(); OutputStream os = w.getOutputStream()) {
                        byte[] buf = new byte[1 << 20];
                        int k;
                        while (!cancelDownload && (k = in.read(buf)) > 0) {
                            os.write(buf, 0, k);
                            md.update(buf, 0, k);
                            got += k;
                            long now = System.currentTimeMillis();
                            if (now - lastUi > 500) {
                                lastUi = now;
                                long all = doneAll + got;
                                long rate = (got - startGot) / Math.max(1, (now - t0) / 1000); // bytes/s
                                String eta = rate > 0 ? ", about " + Math.max(1, (fTotal - all) / rate / 60) + " min left" : "";
                                String st = "Downloading " + name.replace("T860-Fedora44-GPU18-", "");
                                String dt = human(all / 1024) + " of " + human(fTotal / 1024) + " (" + human(rate / 1024) + "/s" + eta + ")";
                                int prog = (int) (all * 1000 / fTotal);
                                ui.post(() -> { status.setText(st); detail.setText(dt); bar.setProgress(prog); });
                            }
                        }
                    }
                    w.waitFor();
                    if (cancelDownload) { err = "paused"; break; }
                    if (got != size) throw new IOException(name + " is incomplete (" + got + " of " + size + " bytes); start again to resume");
                    String sum = hex(md.digest());
                    if (!sum.equals(f[2])) {
                        runRoot("rm -f " + q(part), l -> { });
                        throw new IOException(name + " failed its checksum and was removed; start again");
                    }
                    runRoot("mv " + q(part) + " " + q(target) + " && echo " + sum + " > " + q(target + ".verified"), l -> { });
                    doneAll += size;
                }
                if (err == null) { // description and checksums for the TWRP switch script
                    StringBuilder env = new StringBuilder("INSTALLER_BUNDLE=\"" + FEDORA_FILES[0][0] + "\"\nROOTFS_PARTS=\"");
                    StringBuilder sums = new StringBuilder();
                    for (int i = 0; i < FEDORA_FILES.length; i++) {
                        if (i > 0) env.append(i > 1 ? " " : "").append(FEDORA_FILES[i][0]);
                        sums.append(FEDORA_FILES[i][2]).append("  ").append(FEDORA_FILES[i][0]).append('\n');
                    }
                    env.append("\"\n");
                    File e1 = new File(getCacheDir(), "s6-download.env"), e2 = new File(getCacheDir(), "SHA256SUMS");
                    try (FileOutputStream o = new FileOutputStream(e1)) { o.write(env.toString().getBytes("UTF-8")); }
                    try (FileOutputStream o = new FileOutputStream(e2)) { o.write(sums.toString().getBytes("UTF-8")); }
                    runRoot("cp " + q(e1.getAbsolutePath()) + " " + q(e2.getAbsolutePath()) + " " + q(fdir) + "/", l -> { });
                }
            } catch (Exception e) {
                err = String.valueOf(e.getMessage());
            }
            final String fe = err;
            ui.post(() -> {
                busy = false;
                getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                if (fe == null) {
                    Toast.makeText(this, "Fedora downloaded and verified.", Toast.LENGTH_LONG).show();
                    switchStart();
                } else if (fe.equals("paused")) {
                    Toast.makeText(this, "Paused. Start the download again to resume.", Toast.LENGTH_LONG).show();
                    switchStart();
                } else {
                    LinearLayout b = new LinearLayout(this);
                    b.setOrientation(LinearLayout.VERTICAL);
                    b.addView(text("The download stopped: " + fe + "\n\nNothing on the tablet was changed. Try again; it resumes.", 15, false));
                    frame("Download stopped", null, b, null, "Try again", () -> downloadFedora(fdir), "Back", this::switchStart);
                }
            });
        }).start();
    }

    void finalConfirm(String drive) {
        curStep = 5;
        LinearLayout body = vbox();
        body.addView(h2("What happens now"));
        body.addView(text("1. The tablet restarts into TWRP. If TWRP asks for a password, tap Cancel.\n"
                + "2. TWRP checks the Fedora download and saves your Android boot backup to the drive.\n"
                + "3. Fedora is installed. Android and everything not in your package is erased.\n"
                + "4. The tablet restarts into Fedora (log in as fedora / fedora), and S6 Migrate brings your files, "
                + "settings and apps back.\n\nIt takes about 30-40 minutes. Keep the charger plugged in and the drive connected. "
                + "Don't press any buttons in TWRP.", 15, false));
        body.addView(gap(10));
        body.addView(muted("If anything fails before step 3, TWRP says \"Nothing was erased\" and you can go back to Android."));
        body.addView(gap(16));
        LinearLayout rc = card();
        rc.addView(tv("Recommended first: a rehearsal", 17, fSemi, t.text));
        rc.addView(tv("TWRP runs every check and returns to Android without erasing anything.", 15, fText, t.sub));
        rc.addView(button("Rehearse first (nothing is erased)", false, () -> prepareSwitch(true)), lpm(WRAP, WRAP, 0, 12, 0, 0));
        body.addView(rc);
        frame("Ready to upgrade", null, body, null, "Upgrade now", () -> {
            EditText et = new EditText(this);
            et.setHint("Type SWITCH");
            new AlertDialog.Builder(this).setTitle("Erase Android and install Fedora?")
                    .setMessage("Type SWITCH to confirm. This is the point of no return.")
                    .setView(et)
                    .setPositiveButton("Switch", (d, w) -> {
                        if ("SWITCH".equals(et.getText().toString().trim())) prepareSwitch();
                        else Toast.makeText(this, "Not confirmed. Nothing was changed.", Toast.LENGTH_LONG).show();
                    })
                    .setNegativeButton("Cancel", null).show();
        }, "Back", this::switchStart);
    }

    void zipAsset(ZipOutputStream z, String entry, String asset) throws IOException {
        z.putNextEntry(new ZipEntry(entry));
        try (InputStream in = getAssets().open(asset)) {
            byte[] buf = new byte[16384];
            int k;
            while ((k = in.read(buf)) > 0) z.write(buf, 0, k);
        }
        z.closeEntry();
    }

    void prepareSwitch() { prepareSwitch(false); }

    String readAsset(String name) throws IOException {
        try (InputStream in = getAssets().open(name)) {
            java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int k;
            while ((k = in.read(buf)) > 0) b.write(buf, 0, k);
            return b.toString("UTF-8");
        }
    }

    byte[] readAssetBytes(String name) throws IOException {
        try (InputStream in = getAssets().open(name)) {
            java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int k;
            while ((k = in.read(buf)) > 0) b.write(buf, 0, k);
            return b.toByteArray();
        }
    }

    /**
     * The TWRP script with S6 Migrate's Fedora files embedded as here-documents (TWRP needs no unzip), following
     * fedora/install.list. Same output as tools/migrate/switch/build-payload.py.
     */
    String embeddedUpdateBinary(boolean rehearsal) throws IOException {
        String script = readAsset("switch/update-binary");
        if (!script.contains("# @S6_EMBED@")) throw new IOException("switch script has no embed marker");
        String tag = "S6_EOF_" + Long.toHexString(System.nanoTime());
        StringBuilder e = new StringBuilder("S6_EMBEDDED=1\nS6_MODE=" + (rehearsal ? "rehearsal" : "switch")
                + "\nmkdir -p \"$W/zip/s6migrate\"\n");
        StringBuilder list = new StringBuilder();
        String[] lines = readAsset("fedora/install.list").split("\n");
        for (int i = 0; i < lines.length; i++) {
            String l = lines[i];
            if (l.trim().isEmpty() || l.startsWith("#")) continue;
            String[] f = (l + "|||").split("\\|", -1);
            byte[] data = readAssetBytes(f[0]);
            String c = (f[0].endsWith(".ttf") || f[0].endsWith(".png"))
                    ? java.util.Base64.getMimeEncoder(76, new byte[]{(byte) 10}).encodeToString(data)
                    : new String(data, "UTF-8").replace("\r\n", "\n");
            if (c.contains(tag)) throw new IOException("embed marker clash in " + f[0]);
            if (!c.endsWith("\n")) c += "\n";
            String name = "f" + i;
            e.append("cat > \"$W/zip/s6migrate/").append(name).append("\" <<'").append(tag).append("'\n").append(c).append(tag).append('\n');
            list.append(name).append('|').append(f[1]).append('|').append(f[2]).append('|').append(f[3]).append('\n');
        }
        e.append("cat > \"$W/zip/s6migrate/install.list\" <<'").append(tag).append("'\n").append(list).append(tag).append('\n');
        if (rehearsal) e.append("echo 'checks only, nothing is erased' > \"$W/zip/s6migrate/REHEARSAL\"\n");
        return script.replace("# @S6_EMBED@", e.toString());
    }

    String manualZip;

    String manualSteps() {
        String drive = manualZip == null ? "your card or drive" : "the " + driveName(manualZip.substring(0, manualZip.indexOf("/S6Migrate/")));
        String zip = manualZip == null ? "the S6Migrate ZIP" : manualZip.substring(manualZip.lastIndexOf('/') + 1);
        return "If TWRP opens its main menu instead of starting by itself:\n"
                + "1. Tap Install.\n2. Tap Select Storage and choose " + drive + ".\n"
                + "3. Open the S6Migrate folder and tap " + zip + ".\n4. Swipe to confirm.";
    }

    void prepareSwitch(boolean rehearsal) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        curStep = 5;
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        body.addView(text("Preparing the upgrade for TWRP...", 16, false));
        frame("Upgrade to Fedora", null, body, null, null, null, null, null);
        new Thread(() -> {
            String err = null;
            try {
                File zip = new File(getCacheDir(), "s6migrate-switch.zip");
                try (ZipOutputStream z = new ZipOutputStream(new FileOutputStream(zip))) {
                    z.putNextEntry(new ZipEntry("META-INF/com/google/android/update-binary"));
                    z.write(embeddedUpdateBinary(rehearsal).getBytes("UTF-8"));
                    z.closeEntry();
                    z.putNextEntry(new ZipEntry("META-INF/com/google/android/updater-script"));
                    z.write("# S6 Migrate: the work is done by update-binary\n".getBytes("UTF-8"));
                    z.closeEntry();
                    if (rehearsal) {
                        z.putNextEntry(new ZipEntry("s6migrate/REHEARSAL"));
                        z.write("checks only, nothing is erased\n".getBytes("UTF-8"));
                        z.closeEntry();
                    }
                }
                // A copy on the card or drive, so the switch can always be started by hand from TWRP's Install menu.
                String dir = (fedoraDrive != null ? fedoraDrive : switchPkg != null ? driveOf(switchPkg[1]) : vols.get(0).path) + "/S6Migrate";
                String name = rehearsal ? "S6Migrate-rehearsal.zip" : "S6Migrate-UPGRADE.zip";
                manualZip = dir + "/" + name;
                runRoot("mkdir -p " + q(dir) + " && rm -f " + q(dir) + "/S6Migrate-rehearsal.zip " + q(dir) + "/S6Migrate-UPGRADE.zip"
                        + " && cp " + q(zip.getAbsolutePath()) + " " + q(manualZip), l -> { });
                final List<String> out = new ArrayList<>();
                runRoot("{ mountpoint -q /cache || mount /cache || mount -t ext4 $(readlink -f /dev/block/by-name/cache) /cache; } 2>/dev/null;"
                        + " mkdir -p /cache/recovery && cp " + q(zip.getAbsolutePath()) + " /cache/recovery/s6migrate-switch.zip"
                        + " && echo 'install /cache/recovery/s6migrate-switch.zip' > /cache/recovery/openrecoveryscript"
                        + " && sync && echo READY", out::add);
                if (!out.contains("READY")) err = "could not queue the switch for TWRP (" + String.join(" ", out) + ")";
            } catch (Exception e) {
                err = String.valueOf(e.getMessage());
            }
            final String fe = err;
            ui.post(() -> {
                LinearLayout b = new LinearLayout(this);
                b.setOrientation(LinearLayout.VERTICAL);
                if (fe != null) {
                    b.addView(text("Could not prepare the switch: " + fe + "\n\nNothing was changed.", 15, false));
                    frame("Upgrade not started", null, b, null, null, null, "Back", this::switchStart);
                    return;
                }
                b.addView(text(rehearsal
                        ? "When you tap Restart, TWRP runs every check (about 5 minutes), erases nothing, and restarts into Android. "
                        + "Open S6 Migrate afterwards to see the result.\n\nIf TWRP asks for a password: tap Cancel."
                        : "When you tap Restart, the tablet starts TWRP and the upgrade runs by itself.\n\n"
                        + "If TWRP asks for a password: tap Cancel. Don't touch anything else until Fedora starts.", 16, false));
                b.addView(gap(16));
                LinearLayout mc = card();
                mc.addView(tv(manualSteps(), 15, fText, t.text));
                mc.addView(gap(6));
                mc.addView(muted(rehearsal ? "The rehearsal ZIP never erases anything." : "Only use this ZIP when you mean to upgrade: it erases Android."));
                b.addView(mc);
                frame(rehearsal ? "Rehearsal ready" : "Ready", null, b, null, "Restart into TWRP", () -> {
                    try { runRoot("reboot recovery", l -> { }); } catch (Exception ignored) { }
                }, "Cancel switch", () -> {
                    try {
                        runRoot("rm -f /cache/recovery/openrecoveryscript /cache/recovery/s6migrate-switch.zip"
                                + (manualZip != null ? " " + q(manualZip) : ""), l -> { });
                    } catch (Exception ignored) { }
                    Toast.makeText(this, "Switch cancelled. Nothing was changed.", Toast.LENGTH_LONG).show();
                    home();
                });
            });
        }).start();
    }

    // ------------------------------------------------------------------ pack

;

    // ------------------------------------------------------------------ Flathub lookups

    /** A Linux version found on Flathub for an app that has no hand-picked alternative. */
    static class Found {
        String name = "", appId = "", conf = "none", note = "";
    }

    static final Set<String> GENERIC = new HashSet<>(Arrays.asList("notes", "calculator", "camera", "gallery", "files",
            "music", "clock", "weather", "calendar", "contacts", "messages", "email", "mail", "browser", "phone", "settings",
            "photos", "video", "videos", "radio", "recorder", "voice recorder", "translate", "maps", "news", "podcasts"));

    static String norm(String s) {
        return s == null ? "" : s.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]+", " ").trim();
    }

    static Found flathubLookup(String label) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL("https://flathub.org/api/v2/search").openConnection();
        c.setRequestMethod("POST");
        c.setDoOutput(true);
        c.setConnectTimeout(8000);
        c.setReadTimeout(15000);
        c.setRequestProperty("Content-Type", "application/json");
        c.setRequestProperty("User-Agent", "S6Migrate");
        try (OutputStream os = c.getOutputStream()) {
            os.write(new JSONObject().put("query", label).toString().getBytes("UTF-8"));
        }
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), "UTF-8"))) {
            String l;
            while ((l = r.readLine()) != null) sb.append(l);
        }
        JSONArray hits = new JSONObject(sb.toString()).optJSONArray("hits");
        String L = norm(label);
        JSONObject official = null, best = null;
        double bestScore = -1;
        List<JSONObject> arm = new ArrayList<>();
        for (int i = 0; hits != null && i < hits.length(); i++) {
            JSONObject h = hits.getJSONObject(i);
            if (!"desktop-application".equals(h.optString("type"))) continue;
            if (official == null && norm(h.optString("name")).equals(L)) official = h;
            JSONArray ar = h.optJSONArray("arches");
            if (ar != null && ar.toString().contains("aarch64")) arm.add(h);
        }
        for (JSONObject h : arm) {
            String n = norm(h.optString("name"));
            // tools for an x86-only official app ("Steam ROM Manager") are not replacements
            if (official != null && n.startsWith(L + " ") && !n.equals(L + " desktop")) continue;
            double sc = 0;
            if (n.equals(L)) sc += 100;
            else if (!L.isEmpty() && (n.contains(L) || L.contains(n))) sc += 40;
            else if (!Collections.disjoint(Arrays.asList(L.split(" ")), Arrays.asList(n.split(" ")))) sc += 15;
            if (!L.isEmpty() && norm(h.optString("summary")).contains(L)) sc += 30;
            if (h.optBoolean("verification_verified")) sc += 15;
            sc += Math.min(20, h.optLong("installs_last_month") / 2000.0);
            if (sc > bestScore) { bestScore = sc; best = h; }
        }
        Found f = new Found();
        JSONArray oa = official == null ? null : official.optJSONArray("arches");
        if (oa != null && !oa.toString().contains("aarch64"))
            f.note = "the official " + official.optString("name") + " app does not run on this tablet's ARM processor";
        if (best != null) {
            String n = norm(best.optString("name"));
            boolean exact = n.equals(L) || n.equals(L + " desktop");
            f.conf = exact && !GENERIC.contains(L) ? "high" : (exact || bestScore >= 35) ? "maybe" : "none";
            if (!"none".equals(f.conf)) { f.name = best.optString("name"); f.appId = best.optString("app_id"); }
        }
        return f;
    }

    static String planLine(AppItem a) {
        return "APP|" + a.pkg + "|" + a.uid + "|" + (a.keystore ? "keystore" : "");
    }

    /** Runs pack.sh with the given plan into OUT. update = adding to an existing package. */
    void runPack(String out, String planText, int total, long expectedKb, boolean update) {
        File plan = new File(getCacheDir(), "plan.txt");
        try (FileOutputStream os = new FileOutputStream(plan)) {
            os.write(planText.getBytes("UTF-8"));
        } catch (IOException e) {
            message("Error", "Could not write the plan: " + e.getMessage());
            return;
        }

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView status = text("Starting...", 16, true);
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(Math.max(1, total));
        bar.setProgressTintList(ColorStateList.valueOf(t.accent));
        TextView written = tv("", 14, fText, t.muted);
        TextView log = tv("", 12, Typeface.MONOSPACE, t.muted);
        body.addView(status);
        body.addView(bar);
        body.addView(written);
        body.addView(log);
        final String partLabel = packPart, partsInfo = packPartsInfo;
        final Runnable next = afterPack;
        packPart = null; packPartsInfo = null; afterPack = null;
        frame(update ? "Updating your package" : "Packing your stuff",
                (partLabel != null ? partLabel + ". " : "") + "Keep this screen open. It stays on until packing finishes.",
                body, null, null, null, null, null);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        busy = true; // set before the counter thread starts, or it would exit at once
        final int gen = ++packGen;

        final long startMs = System.currentTimeMillis();
        // Live "written so far" counter, so a big item does not look frozen.
        new Thread(() -> {
            RootShell rs;
            try {
                rs = new RootShell();
            } catch (IOException e) {
                return; // no counter, packing itself still runs
            }
            long base = update ? duKb(rs, out) : 0; // an update starts from the existing package size
            while (busy && gen == packGen) {
                try {
                    Thread.sleep(4000);
                } catch (InterruptedException e) {
                    break;
                }
                long done = Math.max(0, duKb(rs, out) - base);
                long secs = Math.max(1, (System.currentTimeMillis() - startMs) / 1000);
                long rate = done / secs; // KB/s
                String eta = rate > 0 && expectedKb > done
                        ? ", about " + Math.max(1, (expectedKb - done) / rate / 60) + " min left" : "";
                String s = done >= expectedKb && expectedKb > 0
                        ? "Written: " + human(done) + ". Finishing: checking and recording checksums..."
                        : "Written so far: " + human(done) + " of about " + human(expectedKb)
                        + (rate > 0 ? " (" + human(rate) + "/s" + eta + ")" : "");
                ui.post(() -> { if (busy) written.setText(s); });
            }
            rs.close();
        }).start();

        String cmd = "sh " + q(new File(getCacheDir(), "pack.sh").getAbsolutePath()) + " '' "
                + q(plan.getAbsolutePath()) + " " + q(out) + " " + PART_SIZE;
        new Thread(() -> {
            final StringBuilder all = new StringBuilder();
            final String[] last = {""};
            int rc;
            try {
                rc = runRoot(cmd, l -> {
                    all.append(l).append('\n');
                    last[0] = l;
                    ui.post(() -> {
                        log.append(l + "\n");
                        if (l.startsWith("Updating checksums")) {
                            status.setText("Finishing: recording checksums (only new or changed files are read)");
                        }
                        if (l.startsWith("[")) {
                            int end = l.indexOf(']');
                            int n = (int) parse(end > 1 ? l.substring(1, end) : "0");
                            bar.setProgress(n);
                            status.setText("Item " + n + " of " + total + ": " + l.substring(end + 1).trim());
                        }
                    });
                });
            } catch (Exception e) {
                rc = -1;
                last[0] = "ERROR: " + e.getMessage();
            }
            final boolean ok = rc == 0 && "PACK-OK".equals(last[0].trim());
            final long[] freed = {0};
            if (ok && !update && next == null && deleteOld) {
                List<String[]> old = new ArrayList<>();
                for (String[] p : packages) if (!folderOf(p[1]).equals(folderOf(out))) old.add(p);
                freed[0] = deletePackages(old);
                if (!old.isEmpty()) ui.post(() -> { packages.removeAll(old); oldFreedKb = freed[0]; });
            }
            if (ok && !update) { // an update keeps the choices made when the package was created
                try {
                    File dt = new File(getCacheDir(), "destinations.txt");
                    try (FileOutputStream o = new FileOutputStream(dt)) { o.write(destinationsTxt().getBytes("UTF-8")); }
                    runRoot("cp " + q(dt.getAbsolutePath()) + " " + q(out + "/destinations.txt"), l -> { });
                    File ft = new File(getCacheDir(), "alternatives-found.tsv");
                    try (FileOutputStream o = new FileOutputStream(ft)) { o.write(foundTsv().getBytes("UTF-8")); }
                    runRoot("cp " + q(ft.getAbsolutePath()) + " " + q(out + "/alternatives-found.tsv"), l -> { });
                    File ch = new File(getCacheDir(), "choices.txt");
                    try (FileOutputStream o = new FileOutputStream(ch)) { o.write(choicesTxt().getBytes("UTF-8")); }
                    runRoot("cp " + q(ch.getAbsolutePath()) + " " + q(out + "/choices.txt"), l -> { });
                    if (partsInfo != null) { // one part of a package split across drives
                        File pt = new File(getCacheDir(), "parts.txt");
                        try (FileOutputStream o = new FileOutputStream(pt)) { o.write(partsInfo.getBytes("UTF-8")); }
                        runRoot("cp " + q(pt.getAbsolutePath()) + " " + q(out + "/parts.txt"), l -> { });
                    }
                } catch (Exception ignored) {
                }
            }
            ui.post(() -> {
                if (ok && !update) packages.add(new String[]{"PKG", out, String.valueOf(total), String.valueOf(expectedKb), "complete"});
                if (ok && update) for (String[] p : packages) if (p[1].equals(out)) p[4] = "complete";
                if (!ok) for (String[] p : packages) if (p[1].equals(out)) p[4] = "errors";
                if (!ok && !update) { // keep it listed, so "Fix it" can pack just the items that didn't make it
                    boolean known = false;
                    for (String[] p : packages) known |= p[1].equals(out);
                    if (!known) packages.add(new String[]{"PKG", out, String.valueOf(total), String.valueOf(expectedKb), "errors"});
                }
                if (ok && next != null) next.run();   // the next part of a split package
                else done(ok, out, all.toString(), update);
            });
        }).start();
    }

    // ------------------------------------------------------------------ look: Fedora theme, follows light/dark

    static final class Pal {
        int bg, side, text, sub, muted, border, hair, sel, track, accent, accentText, onAccent, accent2,
                ok, warn, warnBg, warnBorder, warnText, ring, link, btn2Bg, btn2Border, okBg, onOk;
    }

    static Pal palette(boolean dark) {
        Pal p = new Pal();
        if (!dark) {
            p.bg = 0xFFFFFFFF; p.side = 0xFFEEF3F9; p.text = 0xFF10131A; p.sub = 0xFF3E4756; p.muted = 0xFF56606F;
            p.border = 0xFFD6DEE8; p.hair = 0xFFE4EAF1; p.sel = 0xFFEBF4FB; p.track = 0xFFE1E8F0; p.accent = 0xFF3C6EB4;
            p.accentText = 0xFF2F5F9E; p.onAccent = 0xFFFFFFFF; p.accent2 = 0xFF8DBEE6; p.ok = 0xFF1C7A43; p.warn = 0xFFA04E06;
            p.warnBg = 0xFFFFF5E9; p.warnBorder = 0xFFF0D0A8; p.warnText = 0xFF3D2A14; p.ring = 0xFFA3AEBD; p.link = 0xFF2A62A8;
            p.btn2Bg = 0xFFFFFFFF; p.btn2Border = 0xFFC3CCD8; p.okBg = 0xFF1C7A43; p.onOk = 0xFFFFFFFF;
        } else {
            p.bg = 0xFF0E141D; p.side = 0xFF151D29; p.text = 0xFFEEF2F8; p.sub = 0xFFC5CDD9; p.muted = 0xFF9BA7B8;
            p.border = 0xFF2B3748; p.hair = 0xFF222D3B; p.sel = 0xFF13304A; p.track = 0xFF253244; p.accent = 0xFF51A2DA;
            p.accentText = 0xFF7DBCE8; p.onAccent = 0xFF0B1220; p.accent2 = 0xFF2C5F8F; p.ok = 0xFF5ED18B; p.warn = 0xFFF2A65A;
            p.warnBg = 0xFF2A2014; p.warnBorder = 0xFF5A4325; p.warnText = 0xFFF0DEC6; p.ring = 0xFF5B6778; p.link = 0xFF8CC4F0;
            p.btn2Bg = 0xFF151D29; p.btn2Border = 0xFF3A4759; p.okBg = 0xFF5ED18B; p.onOk = 0xFF0B1220;
        }
        return p;
    }

    Pal t = palette(false);
    Typeface fText = Typeface.DEFAULT, fSemi = Typeface.DEFAULT_BOLD, fDisplay = Typeface.DEFAULT_BOLD;
    boolean isDark;

    boolean nightNow() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    }

    void initLook() {
        isDark = nightNow();
        t = palette(isDark);
        try {
            fText = Typeface.createFromAsset(getAssets(), "fonts/RedHatText-Regular.ttf");
            fSemi = Typeface.createFromAsset(getAssets(), "fonts/RedHatText-SemiBold.ttf");
            fDisplay = Typeface.createFromAsset(getAssets(), "fonts/RedHatDisplay-Bold.ttf");
        } catch (Exception ignored) { // fonts missing: system fonts still work
        }
        if (getActionBar() != null) getActionBar().hide(); // the wizard draws its own header
        Window w = getWindow();
        w.setStatusBarColor(t.bg);
        w.setNavigationBarColor(t.bg);
        w.getDecorView().setBackgroundColor(t.bg);
        try {
            WindowInsetsController c = w.getInsetsController();
            int m = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            if (c != null) c.setSystemBarsAppearance(isDark ? 0 : m, m);
        } catch (Exception ignored) {
        }
    }

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        if (nightNow() != isDark) initLook();
        if (rerender != null) rerender.run(); // static screens are rebuilt for the new size or theme
    }

    static final int MATCH = LinearLayout.LayoutParams.MATCH_PARENT, WRAP = LinearLayout.LayoutParams.WRAP_CONTENT;

    LinearLayout.LayoutParams lp(int w, int h, float weight) {
        return new LinearLayout.LayoutParams(w, h, weight);
    }

    LinearLayout.LayoutParams lpm(int w, int h, int left, int top, int right, int bottom) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(w, h);
        p.setMargins(dp(left), dp(top), dp(right), dp(bottom));
        return p;
    }

    LinearLayout vbox() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    LinearLayout hbox() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    GradientDrawable box(int fill, int stroke, int strokeDp, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        if (strokeDp > 0) g.setStroke(dp(strokeDp), stroke);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    TextView tv(String s, float sp, Typeface f, int color) {
        TextView v = new TextView(this);
        v.setText(s);
        v.setTextSize(sp);
        v.setTypeface(f);
        v.setTextColor(color);
        v.setLineSpacing(0, 1.18f);
        return v;
    }

    TextView text(String s, float sp, boolean bold) {
        return tv(s, sp, bold ? fSemi : fText, t.text);
    }

    TextView h2(String s) {
        TextView v = tv(s, 15, fSemi, t.sub);
        v.setPadding(0, 0, 0, dp(10));
        return v;
    }

    TextView muted(String s) {
        return tv(s, 13, fText, t.muted);
    }

    LinearLayout card() {
        LinearLayout c = vbox();
        c.setBackground(box(t.bg, t.border, 1, 14));
        c.setPadding(dp(18), dp(14), dp(18), dp(14));
        return c;
    }

    LinearLayout warnCard(String title) {
        LinearLayout c = vbox();
        c.setBackground(box(t.warnBg, t.warnBorder, 1, 14));
        c.setPadding(dp(18), dp(14), dp(18), dp(14));
        if (title != null) {
            TextView h = tv(title, 16, fSemi, t.warn);
            h.setPadding(0, 0, 0, dp(6));
            c.addView(h);
        }
        return c;
    }

    void bullet(LinearLayout c, String s, int color) {
        TextView v = tv("•  " + s, 15, fText, color);
        v.setPadding(0, dp(3), 0, dp(3));
        c.addView(v);
    }

    View gap(int dpH) {
        View v = new View(this);
        v.setLayoutParams(new LinearLayout.LayoutParams(1, dp(dpH)));
        return v;
    }

    View hair() {
        View v = new View(this);
        v.setBackgroundColor(t.hair);
        v.setLayoutParams(new LinearLayout.LayoutParams(MATCH, dp(1)));
        return v;
    }

    TextView button(String label, boolean primary, Runnable r) {
        TextView b = tv(label, 16, fSemi, primary ? t.onAccent : t.text);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(dp(48));
        b.setMinimumHeight(dp(48));
        b.setPadding(dp(24), dp(10), dp(24), dp(10));
        GradientDrawable bg = primary ? box(t.accent, 0, 0, 12) : box(t.btn2Bg, t.btn2Border, 1, 12);
        b.setBackground(new RippleDrawable(ColorStateList.valueOf(primary ? 0x40FFFFFF : 0x22808080), bg, null));
        b.setClickable(true);
        b.setFocusable(true);
        b.setOnClickListener(v -> r.run());
        return b;
    }

    void enable(View b, boolean on) {
        b.setEnabled(on);
        b.setAlpha(on ? 1f : 0.45f);
    }

    TextView link(String s, Runnable r) {
        TextView v = tv(s, 15, fSemi, t.link);
        v.setPadding(0, dp(10), 0, dp(10));
        v.setClickable(true);
        v.setFocusable(true);
        v.setOnClickListener(x -> r.run());
        return v;
    }

    TextView pill(String s, int fg, int bg) {
        TextView v = tv(s, 13, fSemi, fg);
        v.setBackground(box(bg, 0, 0, 999));
        v.setPadding(dp(10), dp(3), dp(10), dp(4));
        return v;
    }

    void tint(CompoundButton b) {
        b.setButtonTintList(ColorStateList.valueOf(t.accent));
        b.setTypeface(fText);
        b.setTextColor(t.text);
    }

    // Drawn icons (24-unit grid), so the look does not depend on Android's icon set.
    static final int I_DONE = 0, I_CURRENT = 1, I_TODO = 2, I_OK = 3, I_WARN = 4, I_CLOCK = 5, I_LOGO = 6,
            I_RADIO = 7, I_RADIO_ON = 8, I_BOX = 9, I_PHONE = 10, I_SCREEN = 11, I_FOLDER = 12, I_DRIVE = 13;

    View icon(int kind, int sizeDp, int color) {
        View v = new View(this) {
            final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
            final Path path = new Path();

            void stroke(float w) {
                p.setStyle(Paint.Style.STROKE);
                p.setStrokeWidth(w);
                p.setStrokeCap(Paint.Cap.ROUND);
                p.setStrokeJoin(Paint.Join.ROUND);
            }

            @Override
            protected void onDraw(Canvas c) {
                float w = getWidth(), s = w / 24f;
                p.setColor(color);
                path.reset();
                switch (kind) {
                    case I_DONE:
                        p.setStyle(Paint.Style.FILL);
                        c.drawCircle(w / 2, w / 2, w / 2, p);
                        p.setColor(t.onAccent);
                        stroke(2.6f * s);
                        path.moveTo(7 * s, 12.5f * s); path.lineTo(10.5f * s, 16 * s); path.lineTo(17 * s, 8.5f * s);
                        c.drawPath(path, p);
                        break;
                    case I_CURRENT:
                        p.setStyle(Paint.Style.FILL);
                        c.drawCircle(w / 2, w / 2, w / 2, p);
                        p.setColor(t.bg);
                        c.drawCircle(w / 2, w / 2, w / 2 - 6.5f * s, p);
                        break;
                    case I_TODO:
                        stroke(2 * s);
                        c.drawCircle(w / 2, w / 2, w / 2 - s, p);
                        break;
                    case I_OK:
                        stroke(2.2f * s);
                        c.drawCircle(12 * s, 12 * s, 10 * s, p);
                        path.moveTo(7.5f * s, 12.5f * s); path.lineTo(10.5f * s, 15.5f * s); path.lineTo(16.5f * s, 9 * s);
                        c.drawPath(path, p);
                        break;
                    case I_WARN:
                        stroke(2.2f * s);
                        path.moveTo(12 * s, 3 * s); path.lineTo(21.5f * s, 20 * s); path.lineTo(2.5f * s, 20 * s); path.close();
                        path.moveTo(12 * s, 10 * s); path.lineTo(12 * s, 14.5f * s);
                        c.drawPath(path, p);
                        p.setStyle(Paint.Style.FILL);
                        c.drawCircle(12 * s, 17.6f * s, 1.3f * s, p);
                        break;
                    case I_CLOCK:
                        stroke(2 * s);
                        c.drawCircle(12 * s, 12 * s, 10 * s, p);
                        path.moveTo(12 * s, 7 * s); path.lineTo(12 * s, 12 * s); path.lineTo(15 * s, 14 * s);
                        c.drawPath(path, p);
                        break;
                    case I_LOGO:
                        p.setStyle(Paint.Style.FILL);
                        c.drawRoundRect(new RectF(0, 0, w, w), 12 * s * 24 / 44f, 12 * s * 24 / 44f, p);
                        p.setColor(t.onAccent);
                        float o = w * 0.2f, k = w * 0.6f / 24f; // glyph in the middle 60%
                        stroke(1.8f * k);
                        c.drawRoundRect(new RectF(o + 3 * k, o + 5 * k, o + 16 * k, o + 20 * k), 2 * k, 2 * k, p);
                        path.moveTo(o + 14 * k, o + 9 * k); path.lineTo(o + 21 * k, o + 9 * k);
                        path.moveTo(o + 18 * k, o + 6 * k); path.lineTo(o + 21 * k, o + 9 * k); path.lineTo(o + 18 * k, o + 12 * k);
                        c.drawPath(path, p);
                        break;
                    case I_RADIO:
                        p.setColor(t.ring);
                        stroke(2 * s);
                        c.drawCircle(w / 2, w / 2, w / 2 - s, p);
                        break;
                    case I_RADIO_ON:
                        stroke(2 * s);
                        c.drawCircle(w / 2, w / 2, w / 2 - s, p);
                        p.setStyle(Paint.Style.FILL);
                        c.drawCircle(w / 2, w / 2, w / 4.2f, p);
                        break;
                    case I_BOX:
                        stroke(1.8f * s);
                        c.drawRect(4 * s, 7 * s, 20 * s, 20 * s, p);
                        path.moveTo(9 * s, 7 * s); path.lineTo(9 * s, 4 * s); path.lineTo(15 * s, 4 * s); path.lineTo(15 * s, 7 * s);
                        c.drawPath(path, p);
                        break;
                    case I_PHONE:
                        stroke(1.8f * s);
                        c.drawRoundRect(new RectF(7 * s, 2 * s, 17 * s, 22 * s), 2 * s, 2 * s, p);
                        c.drawLine(11 * s, 18 * s, 13 * s, 18 * s, p);
                        break;
                    case I_SCREEN:
                        stroke(1.8f * s);
                        c.drawRoundRect(new RectF(3 * s, 4 * s, 21 * s, 16 * s), 2 * s, 2 * s, p);
                        c.drawLine(8 * s, 20 * s, 16 * s, 20 * s, p);
                        c.drawLine(12 * s, 16 * s, 12 * s, 20 * s, p);
                        break;
                    case I_FOLDER:
                        stroke(1.8f * s);
                        path.moveTo(3 * s, 6 * s); path.lineTo(9 * s, 6 * s); path.lineTo(11 * s, 8 * s); path.lineTo(21 * s, 8 * s);
                        path.lineTo(21 * s, 19 * s); path.lineTo(3 * s, 19 * s); path.close();
                        c.drawPath(path, p);
                        break;
                    case I_DRIVE:
                        stroke(1.8f * s);
                        c.drawRoundRect(new RectF(3 * s, 8 * s, 21 * s, 17 * s), 2 * s, 2 * s, p);
                        p.setStyle(Paint.Style.FILL);
                        c.drawCircle(17 * s, 12.5f * s, 1.2f * s, p);
                        break;
                }
            }
        };
        v.setLayoutParams(new LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp)));
        return v;
    }

    /** Horizontal bar: coloured parts of a total, on a track. */
    class SegBar extends View {
        long[] parts = {};
        int[] colors = {};
        long total = 1;
        final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        final Path clip = new Path();

        SegBar() { super(MainActivity.this); }

        void set(long[] parts, int[] colors, long total) {
            this.parts = parts;
            this.colors = colors;
            this.total = Math.max(1, total);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight();
            clip.reset();
            clip.addRoundRect(new RectF(0, 0, w, h), h / 2, h / 2, Path.Direction.CW);
            c.save();
            c.clipPath(clip);
            p.setColor(t.track);
            c.drawRect(0, 0, w, h, p);
            float x = 0;
            for (int i = 0; i < parts.length; i++) {
                float pw = Math.min(w - x, w * parts[i] / (float) total);
                p.setColor(colors[i]);
                c.drawRect(x, 0, x + pw, h, p);
                x += pw;
            }
            c.restore();
        }
    }

    SegBar segBar(long[] parts, int[] colors, long total) {
        SegBar b = new SegBar();
        b.set(parts, colors, total);
        b.setLayoutParams(lpm(MATCH, dp(10), 0, 8, 0, 4));
        return b;
    }

    /** Selectable card with a radio mark. */
    View choiceCard(String title, String sub, boolean on, boolean enabled, Runnable pick) {
        LinearLayout c = hbox();
        c.setGravity(Gravity.TOP);
        c.setBackground(on ? box(t.sel, t.accent, 2, 14) : box(t.bg, t.border, 1, 14));
        c.setPadding(dp(16), dp(14), dp(16), dp(14));
        c.setMinimumHeight(dp(48));
        View r = icon(on ? I_RADIO_ON : I_RADIO, 20, t.accent);
        ((LinearLayout.LayoutParams) r.getLayoutParams()).topMargin = dp(1);
        c.addView(r);
        LinearLayout tx = vbox();
        tx.setPadding(dp(12), 0, 0, 0);
        tx.addView(tv(title, 16, fSemi, t.text));
        if (sub != null) tx.addView(tv(sub, 14, fText, t.muted));
        c.addView(tx, lp(0, WRAP, 1f));
        if (enabled) {
            c.setClickable(true);
            c.setOnClickListener(v -> pick.run());
        } else {
            c.setAlpha(0.5f);
        }
        return c;
    }

    /** A row of choice cards (side by side when there is room, stacked otherwise). */
    LinearLayout choiceRow(boolean sideBySide) {
        LinearLayout l = sideBySide ? hbox() : vbox();
        if (sideBySide) l.setGravity(Gravity.TOP);
        return l;
    }

    void addChoice(LinearLayout row, View card, boolean sideBySide, boolean first) {
        LinearLayout.LayoutParams p = sideBySide ? lp(0, MATCH, 1f) : lp(MATCH, WRAP, 0);
        if (!first) { if (sideBySide) p.leftMargin = dp(12); else p.topMargin = dp(10); }
        row.addView(card, p);
    }

    // ------------------------------------------------------------------ wizard frame

    static final String[] STEPS = {"Introduction", "What to keep", "Apps on Fedora", "Space check", "Summary", "Upgrade"};
    int curStep = 0;
    String eyebrow;                 // small line above the next title
    Runnable rerender, pendingRerender, backAction;
    TextView spaceLabel, spaceRight;
    SegBar spaceBar;

    int widthDp() { return getResources().getConfiguration().screenWidthDp; }

    boolean wide() { return widthDp() >= 720; }

    /** Room for two columns in the content area. */
    boolean twoCols() { return widthDp() - (wide() ? 260 : 0) - 96 >= 700; }

    void screen(String title, String subtitle, View body, boolean withSpace,
                String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        frame(title, subtitle, body, withSpace ? spaceFooter() : null, primary, onPrimary, secondary, onSecondary);
    }

    void frame(String title, String subtitle, View body, View footLeft,
               String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        rerender = pendingRerender;
        pendingRerender = null;
        if (footLeft == null) { spaceLabel = null; spaceRight = null; spaceBar = null; }
        boolean wide = wide();
        LinearLayout root = hbox();
        root.setGravity(Gravity.NO_GRAVITY);
        root.setBackgroundColor(t.bg);
        if (wide) root.addView(sidebar(), lp(dp(260), MATCH, 0));

        LinearLayout main = vbox();
        int ph = wide ? 48 : 20;
        main.setPadding(dp(ph), dp(wide ? 40 : 14), dp(ph), dp(wide ? 24 : 12));
        if (!wide) main.addView(topSteps());
        if (eyebrow != null) {
            TextView e = tv(eyebrow.toUpperCase(Locale.getDefault()), 14, fSemi, t.accentText);
            e.setLetterSpacing(0.06f);
            e.setPadding(0, 0, 0, dp(10));
            main.addView(e);
            eyebrow = null;
        }
        main.addView(tv(title, wide ? 34 : 26, fDisplay, t.text));
        if (subtitle != null) {
            TextView s = tv(subtitle, 16, fText, t.sub);
            s.setPadding(0, dp(8), 0, 0);
            main.addView(s);
        }
        ScrollView sv = new ScrollView(this);
        sv.setFillViewport(true);
        LinearLayout wrap = vbox();
        wrap.setPadding(0, dp(20), 0, dp(16));
        wrap.addView(body, lp(MATCH, WRAP, 0));
        sv.addView(wrap);
        main.addView(sv, lp(MATCH, 0, 1f));

        main.addView(hair());
        if (!wide && footLeft != null) {
            footLeft.setPadding(0, dp(12), 0, 0);
            main.addView(footLeft, lp(MATCH, WRAP, 0));
        }
        LinearLayout foot = hbox();
        foot.setPadding(0, dp(14), 0, 0);
        if (wide && footLeft != null) foot.addView(footLeft, lp(0, WRAP, 1f));
        else foot.addView(new View(this), lp(0, 1, 1f));
        if (secondary != null) foot.addView(button(secondary, false, onSecondary), lpm(WRAP, WRAP, 16, 0, 0, 0));
        if (primary != null) foot.addView(button(primary, true, onPrimary), lpm(WRAP, WRAP, 12, 0, 0, 0));
        main.addView(foot);
        root.addView(main, lp(0, MATCH, 1f));
        backAction = secondary != null && (secondary.equals("Back") || secondary.startsWith("Cancel")) ? onSecondary : null;
        setContentView(root);
    }

    View sidebar() {
        LinearLayout s = vbox();
        s.setBackgroundColor(t.side);
        s.setPadding(dp(24), dp(40), dp(24), dp(20));
        LinearLayout brand = hbox();
        brand.addView(icon(I_LOGO, 44, t.accent));
        LinearLayout names = vbox();
        names.setPadding(dp(12), 0, 0, 0);
        names.addView(tv("S6 Migrate", 19, fDisplay, t.text));
        names.addView(tv("Android to Fedora", 13, fText, t.muted));
        brand.addView(names);
        s.addView(brand);
        LinearLayout list = vbox();
        list.setPadding(0, dp(32), 0, 0);
        for (int i = 0; i < STEPS.length; i++) {
            LinearLayout r = hbox();
            r.setPadding(0, dp(10), 0, dp(10));
            r.addView(icon(i < curStep ? I_DONE : i == curStep ? I_CURRENT : I_TODO, 22, i <= curStep ? t.accent : t.ring));
            TextView l = tv(STEPS[i], 16, i == curStep ? fSemi : fText, i == curStep ? t.text : i < curStep ? t.sub : t.muted);
            l.setPadding(dp(12), 0, 0, 0);
            r.addView(l);
            list.addView(r);
        }
        s.addView(list);
        s.addView(new View(this), lp(MATCH, 0, 1f));
        TextView about = tv("About and credits", 14, fSemi, t.link);
        about.setPadding(0, dp(12), 0, dp(12));
        about.setOnClickListener(v -> { if (!busy) credits(); });
        s.addView(about);
        return s;
    }

    View topSteps() {
        LinearLayout v = vbox();
        v.setPadding(0, 0, 0, dp(14));
        LinearLayout r = hbox();
        r.addView(icon(I_LOGO, 30, t.accent));
        TextView l = tv("S6 Migrate  ·  Step " + (curStep + 1) + " of " + STEPS.length + ": " + STEPS[curStep], 14, fSemi, t.sub);
        l.setPadding(dp(10), 0, 0, 0);
        r.addView(l, lp(0, WRAP, 1f));
        TextView about = tv("About", 14, fSemi, t.link);
        about.setPadding(dp(10), dp(8), 0, dp(8));
        about.setOnClickListener(x -> { if (!busy) credits(); });
        r.addView(about);
        v.addView(r);
        LinearLayout segs = hbox();
        segs.setPadding(0, dp(10), 0, 0);
        for (int i = 0; i < STEPS.length; i++) {
            View seg = new View(this);
            seg.setBackground(box(i <= curStep ? t.accent : t.track, 0, 0, 2));
            LinearLayout.LayoutParams p = lp(0, dp(4), 1f);
            if (i > 0) p.leftMargin = dp(4);
            segs.addView(seg, p);
        }
        v.addView(segs);
        return v;
    }

    View spaceFooter() {
        LinearLayout v = vbox();
        LinearLayout r = hbox();
        spaceLabel = tv("", 14, fSemi, t.text);
        spaceRight = tv("", 14, fText, t.muted);
        r.addView(spaceLabel, lp(0, WRAP, 1f));
        r.addView(spaceRight);
        v.addView(r);
        spaceBar = segBar(new long[]{0}, new int[]{t.accent}, 1);
        v.addView(spaceBar);
        updateSpace();
        return v;
    }

    void updateSpace() {
        if (spaceLabel == null) return;
        long sel = selectedKb(), need = sel + margin(sel);
        Vol d = targetVol();
        spaceLabel.setText(human(sel) + " selected");
        if (chosenDest == SPLIT && vols.size() >= 2) {
            long free = 0;
            for (Vol v : vols) free += v.freeKb;
            spaceRight.setText("Split across " + vols.size() + " drives: " + human(free) + " free");
            spaceBar.set(new long[]{need}, new int[]{need > free ? t.warn : t.accent}, free);
        } else if (d == null) {
            spaceRight.setText("No card or USB drive found");
            spaceBar.set(new long[]{need}, new int[]{t.warn}, need);
        } else {
            spaceRight.setText(vName(d) + ": " + human(d.freeKb) + " free");
            spaceBar.set(new long[]{need}, new int[]{need > d.freeKb ? t.warn : t.accent}, d.freeKb);
        }
    }

    /** The drive the package goes to: the chosen one, else the one with most room. */
    Vol targetVol() {
        if (chosenDest >= 1 && chosenDest <= vols.size()) return vols.get(chosenDest - 1);
        Vol best = null;
        for (Vol v : vols) if (best == null || v.freeKb > best.freeKb) best = v;
        return best;
    }

    void message(String title, String msg) {
        LinearLayout body = vbox();
        body.addView(tv(msg, 16, fText, t.text));
        screen(title, null, body, false, "Close", this::finish, null, null);
    }

    void info(String title, String msg) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(msg).setPositiveButton("OK", null).show();
    }

    @Override
    public void onBackPressed() {
        if (busy) {
            Toast.makeText(this, "Please wait until this finishes.", Toast.LENGTH_SHORT).show();
        } else if (backAction != null) {
            backAction.run();
        } else {
            super.onBackPressed();
        }
    }

    // ------------------------------------------------------------------ rows

    View row(Drawable icon, String title, String sub, String warn, boolean checked, CheckBoxToggle onToggle) {
        return row(icon, title, sub, warn, null, checked, onToggle);
    }

    View row(Drawable icon, String title, String sub, String warn, String right, boolean checked, CheckBoxToggle onToggle) {
        LinearLayout r = hbox();
        r.setMinimumHeight(dp(52));
        r.setPadding(0, dp(6), 0, dp(6));
        CheckBox cb = new CheckBox(this);
        tint(cb);
        cb.setChecked(checked);
        cb.setOnCheckedChangeListener((v, c) -> onToggle.set(c));
        r.addView(cb);
        if (icon != null) {
            ImageView iv = new ImageView(this);
            iv.setImageDrawable(icon);
            r.addView(iv, lpm(dp(34), dp(34), 6, 0, 10, 0));
        }
        LinearLayout tx = vbox();
        tx.addView(tv(title, 15, fText, t.text));
        if (sub != null && !sub.isEmpty()) tx.addView(tv(sub, 13, fText, t.muted));
        if (warn != null) tx.addView(tv(warn, 13, fText, t.warn));
        r.addView(tx, lp(0, WRAP, 1f));
        if (right != null) {
            TextView rt = tv(right, 14, fText, t.muted);
            rt.setPadding(dp(10), 0, 0, 0);
            r.addView(rt);
        }
        r.setOnClickListener(v -> cb.toggle());
        return r;
    }

    interface CheckBoxToggle {
        void set(boolean checked);
    }

    /** Readiness line: icon, title, detail (beside it when wide, under it when narrow). */
    View checkRow(boolean ok, String title, String detail) {
        return checkRow(ok ? I_OK : I_WARN, title, detail);
    }

    View checkRow(int kind, String title, String detail) {
        LinearLayout r = hbox();
        r.setGravity(Gravity.TOP);
        r.setPadding(0, dp(7), 0, dp(7));
        View ic = icon(kind, 22, kind == I_OK ? t.ok : kind == I_WARN ? t.warn : t.muted);
        r.addView(ic);
        boolean side = twoCols();
        LinearLayout tx = side ? hbox() : vbox();
        tx.setPadding(dp(14), 0, 0, 0);
        TextView tt = tv(title, 16, fText, t.text);
        tx.addView(tt, side ? lp(0, WRAP, 1f) : lp(MATCH, WRAP, 0));
        if (detail != null) {
            TextView d = tv(detail, 14, fText, t.muted);
            if (side) d.setPadding(dp(16), dp(2), 0, 0);
            tx.addView(d);
        }
        r.addView(tx, lp(0, WRAP, 1f));
        return r;
    }

    /** Summary line: icon, title and detail, optional Change link. */
    View sumRow(int kind, String title, String detail, Runnable change) {
        LinearLayout r = hbox();
        r.setGravity(Gravity.TOP);
        r.setPadding(0, dp(14), 0, dp(14));
        r.addView(icon(kind, 26, t.accentText));
        LinearLayout tx = vbox();
        tx.setPadding(dp(16), 0, dp(10), 0);
        tx.addView(tv(title, 17, fSemi, t.text));
        if (detail != null) tx.addView(tv(detail, 14, fText, t.muted));
        r.addView(tx, lp(0, WRAP, 1f));
        if (change != null) {
            TextView c = link("Change", change);
            c.setPadding(dp(8), 0, 0, dp(8));
            r.addView(c);
        }
        return r;
    }

    int[] battery() { // level %, charging 1/0
        Intent bi = registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (bi == null) return new int[]{-1, 0};
        int lvl = bi.getIntExtra(BatteryManager.EXTRA_LEVEL, -1), sc = bi.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        int st = bi.getIntExtra(BatteryManager.EXTRA_STATUS, 0);
        return new int[]{lvl * 100 / Math.max(1, sc), st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL ? 1 : 0};
    }

    static String when(String path) {
        String folder = path.substring(path.lastIndexOf('/') + 1);
        try {
            Date d = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).parse(folder);
            return new SimpleDateFormat("d MMM, HH:mm", Locale.getDefault()).format(d);
        } catch (Exception e) {
            return folder;
        }
    }

    String whereOf(String path) {
        for (Vol v : vols) if (path.startsWith(v.path + "/")) return vName(v);
        return path.startsWith("/data/media") ? "internal storage" : "external drive";
    }

    // ------------------------------------------------------------------ 1. Introduction

    void home() {
        curStep = 0;
        pendingRerender = this::home;
        LinearLayout body = vbox();

        LinearLayout ready = card();
        boolean model = Build.MODEL.startsWith("SM-T860");
        Vol best = targetVol();
        int[] bat = battery();
        boolean batOk = bat[0] >= 60 || bat[1] == 1;
        ready.addView(tv(model && best != null ? "This tablet is ready" : "Before you start", 19, fDisplay, t.text));
        ready.addView(gap(6));
        ready.addView(checkRow(model, "Galaxy Tab S6 Wi-Fi (SM-T860)", model ? "Supported model" : "This is a " + Build.MODEL + ": only the SM-T860 is supported"));
        ready.addView(checkRow(true, "Root access works", "Needed to copy app data"));
        ready.addView(checkRow(best != null, best != null ? vName(best) + " found" : "No microSD card or USB drive",
                best != null ? human(best.freeKb) + " free" : "Plug one in: your stuff waits there during the switch"));
        ready.addView(checkRow(batOk, "Battery " + (bat[0] < 0 ? "?" : bat[0] + "%") + (bat[1] == 1 ? ", charging" : ""), "Keep it plugged in"));
        ready.addView(checkRow(false, "The Fedora build for this tablet is a community pre-release", "S Pen, headphone jack and the keyboard cover don't work yet"));
        body.addView(ready);

        if (!packages.isEmpty()) {
            body.addView(gap(16));
            LinearLayout pc = card();
            pc.addView(tv(packages.size() == 1 ? "Your saved package" : "Your saved packages", 19, fDisplay, t.text));
            for (String[] p : packages) {
                LinearLayout r = hbox();
                r.setPadding(0, dp(8), 0, 0);
                r.addView(icon(I_BOX, 24, t.accentText));
                String status = "complete".equals(p[4]) ? "verified" : "errors".equals(p[4]) ? "some items need packing again" : "packing didn't finish";
                LinearLayout tx = vbox();
                tx.setPadding(dp(14), 0, dp(8), 0);
                tx.addView(tv(when(p[1]) + "  ·  " + parse(p[2]) + " items, " + human(parse(p[3])), 16, fText, t.text));
                int np = partsOf(p).size();
                tx.addView(muted("On the " + whereOf(p[1]) + " (" + status + ")" + (np > 1 ? " \u00b7 one of " + np + " parts on different drives" : "")));
                r.addView(tx, lp(0, WRAP, 1f));
                final String w = when(p[1]), where = whereOf(p[1]);
                LinearLayout acts = vbox();
                if (!"complete".equals(p[4])) {
                    TextView fix = link("Fix it", () -> repairPackage(p));
                    acts.addView(fix);
                }
                acts.addView(link("Check for changes", () -> openPackage(p, w, where)));
                TextView del = link("Delete", () -> confirmDelete(p));
                del.setTextColor(t.warn);
                acts.addView(del);
                r.addView(acts);
                pc.addView(r);
            }
            pc.addView(gap(6));
            pc.addView(muted("Checking shows what changed since you packed and updates only those items."));
            body.addView(pc);
        }
        body.addView(gap(8));
        LinearLayout links = hbox();
        links.addView(link("What changes on my tablet?", () -> info("What changes on my tablet?",
                "Nothing, until the very last step.\n\n"
                        + "S6 Migrate first copies what you choose to a microSD card or USB drive and checks it. "
                        + "Then it downloads Fedora to the card or drive. Only when you confirm at the end does the tablet "
                        + "restart into TWRP, which erases Android and installs Fedora. On first start, Fedora puts your files, "
                        + "settings and apps back.\n\nThe card or drive is never erased: S6 Migrate only adds an S6Migrate folder.")));
        body.addView(links);

        eyebrow = "Android " + Build.VERSION.RELEASE + " → Fedora 44";
        if (packages.isEmpty()) {
            frame("Move this tablet to Fedora",
                    "S6 Migrate packs the apps and files you choose, installs Fedora with the touch-friendly KDE Plasma desktop, "
                            + "and puts everything back where you expect it. Keep your Android apps, or switch to Linux ones: your choice, app by app.",
                    body, null, "Get started", this::keep, null, null);
        } else {
            frame("Move this tablet to Fedora",
                    "Your package is saved. Continue to the upgrade, or make a new package with a different selection.",
                    body, null, "Continue to upgrade", this::switchStart, "New package", this::keep);
        }
    }

    /** Items of a package that need re-packing: recorded failures, plus planned items with no archive on the drive. */
    static final String MISSING_SH = "cd \"$1\" || exit 0; [ -f failed.txt ] && sed 's/^/MISSING|/' failed.txt;"
            + " while IFS='|' read -r t a b c; do case \"$t\" in"
            + " APP) [ -d \"apps/$a\" ] || echo \"MISSING|$t|$a|$b|$c\" ;;"
            + " DIR) s=$(printf '%s' \"$a\" | tr -c 'A-Za-z0-9._-' '_'); ls \"files/$s\".tar.* >/dev/null 2>&1 || echo \"MISSING|$t|$a|$b|$c\" ;;"
            + " TOP) ls files/_loose_files.tar.* >/dev/null 2>&1 || echo \"MISSING|$t|$a|$b|$c\" ;;"
            + " SET) [ -d settings ] || echo \"MISSING|$t|$a|$b|$c\" ;;"
            + " esac; done < plan.txt";

    void repairPackage(String[] p) {
        curStep = 0;
        LinearLayout body = vbox();
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        body.addView(text("Checking which items need packing again (read-only)...", 16, false));
        frame("Fix your package", null, body, null, null, null, "Back", this::home);
        new Thread(() -> {
            Map<String, StringBuilder> plans = new java.util.LinkedHashMap<>();
            Map<String, long[]> sizes = new HashMap<>();
            List<String> names = new ArrayList<>();
            Set<String> seen = new HashSet<>();
            for (String[] part : partsOf(p)) {
                List<String> out = new ArrayList<>();
                try {
                    runRoot("sh -c " + q(MISSING_SH) + " sh " + q(part[1]), out::add);
                } catch (Exception ignored) {
                }
                for (String l : out) {
                    if (!l.startsWith("MISSING|")) continue;
                    String line = l.substring(8);
                    String[] f = line.split("\\|", -1);
                    if (f.length < 2 || !seen.add(f[0] + "|" + f[1])) continue;
                    Change c = makeChange(f[0], f[1], line);
                    plans.computeIfAbsent(part[1], k -> new StringBuilder()).append(line).append('\n');
                    long[] sz = sizes.computeIfAbsent(part[1], k -> new long[2]);
                    sz[0]++;
                    sz[1] += c.kb;
                    names.add(c.label);
                }
            }
            ui.post(() -> {
                if (names.isEmpty()) { // nothing is missing: the earlier problem was fixed or a copy was kept
                    new Thread(() -> {
                        for (String[] part : partsOf(p)) {
                            try { runRoot("echo complete > " + q(part[1] + "/status.txt") + "; rm -f " + q(part[1] + "/failed.txt"), l -> { }); } catch (Exception ignored) { }
                            part[4] = "complete";
                        }
                        ui.post(() -> { Toast.makeText(this, "Everything is in the package. It's marked as complete now.", Toast.LENGTH_LONG).show(); home(); });
                    }).start();
                    return;
                }
                LinearLayout b = vbox();
                LinearLayout c = warnCard(names.size() + (names.size() == 1 ? " item needs" : " items need") + " packing again");
                for (String n : names.subList(0, Math.min(12, names.size()))) bullet(c, n, t.warnText);
                if (names.size() > 12) bullet(c, "and " + (names.size() - 12) + " more", t.warnText);
                b.addView(c);
                b.addView(gap(12));
                b.addView(muted("Usually a file changed while it was being packed (an app syncing, a download finishing). "
                        + "Only these items are packed again; everything else stays as it is."));
                List<String> dests = new ArrayList<>(plans.keySet());
                frame("Fix your package", null, b, null, "Pack them again", () -> updatePart(dests, 0, plans, sizes), "Back", this::home);
            });
        }).start();
    }

    void confirmDelete(String[] p) {
        List<String[]> parts = partsOf(p);
        long kb = 0;
        StringBuilder where = new StringBuilder();
        for (String[] x : parts) { kb += parse(x[3]); where.append("\n").append(x[1]); }
        new AlertDialog.Builder(this).setTitle("Delete this package?")
                .setMessage("Your package from " + when(p[1]) + " (" + human(kb) + ") will be deleted from:" + where
                        + "\n\nNothing on Android is changed, but you can't switch with this package anymore.")
                .setPositiveButton("Delete", (d, x) -> new Thread(() -> {
                    deletePackages(parts);
                    ui.post(() -> {
                        packages.removeAll(parts);
                        Toast.makeText(this, "Package deleted.", Toast.LENGTH_SHORT).show();
                        home();
                    });
                }).start())
                .setNegativeButton("Cancel", null).show();
    }

    // ------------------------------------------------------------------ 2. What to keep

    String keepMode = "all"; // all, files (no apps), fresh (nothing)

    boolean appSel(AppItem a) { return "all".equals(keepMode) && a.selected; }

    boolean dirSel(DirItem d) { return !"fresh".equals(keepMode) && d.selected; }

    void keep() {
        curStep = 1;
        pendingRerender = this::keep;
        boolean two = twoCols();
        LinearLayout body = vbox();
        LinearLayout modes = choiceRow(two);
        String[][] opts = {{"all", "Selected apps and files", "Apps move with their data"},
                {"files", "Files only", "Photos, downloads, documents, settings"},
                {"fresh", "Start fresh", "Keep nothing"}};
        for (int i = 0; i < opts.length; i++) {
            String id = opts[i][0];
            addChoice(modes, choiceCard(opts[i][1], opts[i][2], id.equals(keepMode), true, () -> { keepMode = id; keep(); }), two, i == 0);
        }
        body.addView(modes);
        body.addView(gap(18));

        if ("fresh".equals(keepMode)) {
            LinearLayout w = warnCard("Nothing will be kept");
            bullet(w, "Fedora starts empty. Everything on Android is erased during the switch.", t.warnText);
            bullet(w, "Copy anything you want to keep to a computer or cloud storage first.", t.warnText);
            body.addView(w);
            frame("Choose what to keep", "Everything you don't pick is erased when Fedora is installed.",
                    body, null, "Continue", this::summary, "Back", this::home);
            return;
        }

        LinearLayout cols = two ? hbox() : vbox();
        if (two) cols.setGravity(Gravity.TOP);
        final TextView appsHead = h2(""), dirsHead = h2("");
        Runnable counts = () -> {
            int na = 0, nd = 0;
            for (AppItem a : apps) if (a.selected) na++;
            for (DirItem d : dirs) if (d.selected) nd++;
            appsHead.setText("Apps · " + na + " of " + apps.size() + " selected");
            dirsHead.setText("Folders and settings · " + nd + " of " + dirs.size() + " selected");
            updateSpace();
        };

        if ("all".equals(keepMode)) {
            LinearLayout ap = card();
            ap.addView(appsHead);
            ap.addView(muted("Only apps you installed are listed. Google and Samsung apps stay behind."));
            if (!keystoreChecked) ap.addView(muted("(Couldn't check which apps lock their data to this tablet.)"));
            for (AppItem a : apps) {
                ap.addView(row(a.icon, a.label, null,
                        a.keystore ? "Data locked to this tablet: the app moves, you sign in again" : null,
                        human(a.kb), a.selected, c -> { a.selected = c; counts.run(); }));
            }
            cols.addView(ap, two ? lp(0, WRAP, 1f) : lp(MATCH, WRAP, 0));
        }

        LinearLayout dp_ = card();
        dp_.addView(dirsHead);
        for (DirItem d : dirs) {
            String sub = d.sub != null ? d.sub : d.top ? d.count + " files that are not in a folder" : null;
            dp_.addView(row(null, d.top ? TOP_LABEL : d.name, sub, null, d.kind.equals("SET") || d.kind.equals("WIFI") ? null : human(d.kb),
                    d.selected, c -> { d.selected = c; counts.run(); }));
            if ("DIR".equals(d.kind)) {
                TextView dest = tv("Goes to ~/" + destOf(d) + "   Change", 13, fText, t.link);
                dest.setPadding(dp(44), 0, 0, dp(8));
                dest.setOnClickListener(v -> pickFolderDest(d, dest));
                dp_.addView(dest);
            }
        }
        LinearLayout.LayoutParams dlp = two ? lp(0, WRAP, 1f) : lp(MATCH, WRAP, 0);
        if (cols.getChildCount() > 0) { if (two) dlp.leftMargin = dp(18); else dlp.topMargin = dp(16); }
        cols.addView(dp_, dlp);
        body.addView(cols);
        counts.run();
        frame("Choose what to keep",
                "Everything you don't pick is erased when Fedora is installed. Google and Samsung apps stay behind; the next step shows what replaces them.",
                body, spaceFooter(), "Continue", () -> {
                    boolean any = false;
                    for (AppItem a : apps) any |= appSel(a);
                    for (DirItem d : dirs) any |= dirSel(d);
                    if (!any && "files".equals(keepMode)) {
                        Toast.makeText(this, "Pick at least one folder, or choose Start fresh.", Toast.LENGTH_LONG).show();
                    } else if (!any) {
                        Toast.makeText(this, "Pick at least one app or folder, or choose Start fresh.", Toast.LENGTH_LONG).show();
                    } else {
                        appsStep();
                    }
                }, "Back", this::home);
        counts.run();
    }

    /** Where a folder goes on Fedora, relative to the home folder (mirrors s6-restore's target_for). */
    static String defaultDest(String n) {
        switch (n) {
            case "DCIM": return "Pictures/DCIM";
            case "Pictures": case "Screenshots": return "Pictures";
            case "Download": case "Downloads": return "Downloads";
            case "Documents": return "Documents";
            case "Music": return "Music";
            case "Movies": case "Videos": return "Videos";
            case "Podcasts": case "Audiobooks": case "Recordings": case "Ringtones": case "Alarms": case "Notifications":
            case "Voice Recorder": case "Sound recordings": case "Call":
                return "Music/" + n;
            default: return isAppFolder(n) ? "Android/" + n : n;
        }
    }

    static boolean isAppFolder(String name) {
        String n = name.toLowerCase(Locale.US);
        if (n.startsWith(".") || n.startsWith("com.") || n.startsWith("org.") || n.startsWith("net.") || n.startsWith("io.")
                || n.matches(".*\\..*\\..*")) return true;
        return n.matches("telegram( .*)?|whatsapp|signal|snapchat|instagram|facebook|messenger|viber|discord|voxer.*|inshot|capcut"
                + "|kinemaster|bluetooth|samsung.*|soundcamp|walkband|twrp|temp|tmp|cache|backups|tencent|miui|fonts|logs|log|android");
    }

    String destOf(DirItem d) { return d.dest != null ? d.dest : defaultDest(d.name); }

    void pickFolderDest(DirItem d, TextView label) {
        String def = defaultDest(d.name);
        List<String> opts = new ArrayList<>();
        for (String o : new String[]{def, d.name, "Android/" + d.name, "Pictures/" + d.name, "Documents/" + d.name,
                "Music/" + d.name, "Videos/" + d.name, "Downloads/" + d.name})
            if (!opts.contains(o)) opts.add(o);
        String[] items = new String[opts.size()];
        for (int i = 0; i < items.length; i++) items[i] = "~/" + opts.get(i) + (i == 0 ? "   (suggested)" : "");
        new AlertDialog.Builder(this).setTitle("Where should " + d.name + " go on Fedora?")
                .setSingleChoiceItems(items, Math.max(0, opts.indexOf(destOf(d))), (dl, which) -> {
                    String o = opts.get(which);
                    d.dest = o.equals(def) ? null : o;
                    label.setText("Goes to ~/" + destOf(d) + "   Change");
                    dl.dismiss();
                })
                .setNegativeButton("Cancel", null).show();
    }

    String destinationsTxt() {
        StringBuilder sb = new StringBuilder();
        for (DirItem d : dirs) if (dirSel(d) && "DIR".equals(d.kind) && d.dest != null) sb.append(d.name).append('|').append(d.dest).append('\n');
        return sb.toString();
    }

    // ------------------------------------------------------------------ 3. Apps on Fedora

    final Set<String> lookedUp = new HashSet<>();

    void appsStep() {
        curStep = 2;
        List<AppItem> todo = new ArrayList<>();
        for (AppItem a : apps) if (appSel(a) && altFor(a.pkg) == null && !lookedUp.contains(a.pkg)) todo.add(a);
        if (!todo.isEmpty()) {
            lookupLinuxVersions(todo, this::appsStep);
            return;
        }
        pendingRerender = this::appsStep;
        boolean two = twoCols();
        LinearLayout body = two ? hbox() : vbox();
        if (two) body.setGravity(Gravity.TOP);

        LinearLayout left = vbox();
        left.addView(h2("Apps you are bringing"));
        int brought = 0;
        for (AppItem a : apps) {
            if (!appSel(a)) continue;
            brought++;
            defaultChoice(a);
            String ln = linuxName(a);
            Found fd;
            synchronized (found) { fd = found.get(a.pkg); }
            LinearLayout c = card();
            LinearLayout head = hbox();
            if (a.icon != null) {
                ImageView iv = new ImageView(this);
                iv.setImageDrawable(a.icon);
                head.addView(iv, lpm(dp(36), dp(36), 0, 0, 12, 0));
            }
            LinearLayout tx = vbox();
            tx.addView(tv(a.label, 16, fSemi, t.text));
            String sub = ln == null ? "No Linux version found. Keeps your data."
                    : altFor(a.pkg) != null ? "Linux version: " + ln
                    : "high".equals(fd != null ? fd.conf : "") ? "Linux version on Flathub: " + ln
                    : "Possible Linux version on Flathub: " + ln + " (check it's the same app)";
            tx.addView(muted(sub));
            String note = altNote(a.pkg);
            if (note.isEmpty() && fd != null) note = fd.note;
            if (!note.isEmpty() && !note.startsWith("http")) tx.addView(tv(note, 13, fText, t.warn));
            if (a.keystore) tx.addView(tv("Data locked to this tablet: the app moves, you sign in again", 13, fText, t.warn));
            head.addView(tx, lp(0, WRAP, 1f));
            if (ln == null) head.addView(tv("Keep Android app", 14, fSemi, t.ok));
            c.addView(head);
            if (ln != null) {
                boolean side = widthDp() >= 600;
                LinearLayout opts = choiceRow(side);
                opts.setPadding(0, dp(12), 0, 0);
                TextView saved = tv("", 13, fText, t.muted);
                fillChips(opts, saved, a, ln, side);
                c.addView(opts);
                c.addView(saved);
            }
            left.addView(c, lpm(MATCH, WRAP, 0, 0, 0, 12));
        }
        if (brought == 0) left.addView(muted("You're not bringing any Android apps."));

        LinearLayout right = vbox();
        right.addView(h2("Staying behind, and what replaces them"));
        LinearLayout rc = card();
        rc.setPadding(dp(18), dp(4), dp(18), dp(4));
        int rows = 0;
        Set<String> shown = new HashSet<>();
        for (AppItem a : apps) {
            if (appSel(a)) continue;
            String[] alt = altRow(a.pkg);
            if (alt == null) continue;
            if (rows++ > 0) rc.addView(hair());
            boolean pre = "preinstalled".equals(alt[2]);
            if (pre) {
                rc.addView(replaceRow(a.label + " → " + alt[1], "In Fedora", alt.length > 4 ? alt[4] : ""));
                shown.add(alt[1]);
            } else {
                String note = alt.length > 4 && !alt[4].startsWith("http") ? alt[4] : null;
                rc.addView(row(a.icon, a.label + " → " + alt[1], note, null, "Install", a.installLinux, on -> a.installLinux = on));
            }
        }
        String[][] builtIn = {{"Web browser", "Firefox"}, {"Files", "Dolphin"}, {"Photos", "Gwenview"}, {"PDFs", "Okular"}, {"Phone link", "KDE Connect"}};
        for (String[] b : builtIn) {
            if (shown.contains(b[1])) continue;
            if (rows++ > 0) rc.addView(hair());
            rc.addView(replaceRow(b[0] + " → " + b[1], "In Fedora", ""));
        }
        right.addView(rc);

        if (two) {
            body.addView(left, lp(0, WRAP, 3f));
            LinearLayout.LayoutParams rp = lp(0, WRAP, 2f);
            rp.leftMargin = dp(20);
            body.addView(right, rp);
        } else {
            body.addView(left);
            body.addView(gap(8));
            body.addView(right);
        }
        TextView foot = muted("Android apps see your Linux Pictures, Documents and Downloads folders.");
        frame("Your apps on Fedora",
                "Keep the Android app (it runs in its own window, with its data), switch to a native Linux app, or have both.",
                body, foot, "Continue", this::spaceStep, "Back", this::keep);
    }

    /** Keep / Use Linux / Both for one app; redrawn in place so the list doesn't jump. */
    void fillChips(LinearLayout opts, TextView saved, AppItem a, String ln, boolean side) {
        opts.removeAllViews();
        String[][] o = {{"keep", "Keep Android app"}, {"linux", "Use " + ln}, {"both", "Both"}};
        for (int i = 0; i < o.length; i++) {
            String id = o[i][0];
            addChoice(opts, chip(o[i][1], id.equals(a.choice), () -> {
                a.choice = id;
                a.choiceSet = true;
                fillChips(opts, saved, a, ln, side);
            }), side, i == 0);
        }
        boolean lin = "linux".equals(a.choice);
        saved.setText(lin ? "The Android app and its data aren't packed (saves " + human(a.kb) + ")." : "");
        saved.setVisibility(lin ? View.VISIBLE : View.GONE);
        saved.setPadding(0, dp(8), 0, 0);
    }

    View chip(String label, boolean on, Runnable pick) {
        LinearLayout c = hbox();
        c.setBackground(on ? box(t.sel, t.accent, 2, 10) : box(t.bg, t.border, 1, 10));
        c.setPadding(dp(12), dp(10), dp(12), dp(10));
        c.setMinimumHeight(dp(46));
        c.addView(icon(on ? I_RADIO_ON : I_RADIO, 18, t.accent));
        TextView l = tv(label, 14, on ? fSemi : fText, t.text);
        l.setPadding(dp(8), 0, 0, 0);
        c.addView(l, lp(0, WRAP, 1f));
        c.setClickable(true);
        c.setOnClickListener(v -> pick.run());
        return c;
    }

    View replaceRow(String title, String state, String note) {
        LinearLayout r = hbox();
        r.setMinimumHeight(dp(52));
        LinearLayout tx = vbox();
        tx.addView(tv(title, 15, fText, t.text));
        if (note != null && !note.isEmpty() && !note.startsWith("http")) tx.addView(tv(note, 13, fText, t.muted));
        r.addView(tx, lp(0, WRAP, 1f));
        r.addView(tv(state, 13, fSemi, t.ok));
        return r;
    }

    // ------------------------------------------------------------------ 4. Space check

    void spaceStep() {
        curStep = 3;
        pendingRerender = this::spaceStep;
        long sel = selectedKb(), need = sel + margin(sel);
        final List<Part> split = splitPlan();
        if (chosenDest == SPLIT && split != null) {
            // keep the split
        } else if (chosenDest < 1 || chosenDest > vols.size() || vols.get(chosenDest - 1).freeKb < need) {
            chosenDest = -1;
            for (int pass = 0; pass < 2 && chosenDest < 0; pass++)
                for (int i = 0; i < vols.size(); i++) {
                    long req = need + (pass == 0 ? FEDORA_DOWNLOAD_KB : 0);
                    if (vols.get(i).freeKb >= req && (chosenDest < 0 || vols.get(i).freeKb > vols.get(chosenDest - 1).freeKb)) chosenDest = i + 1;
                }
            if (chosenDest < 0 && split != null) chosenDest = SPLIT; // nothing fits on one drive: spread it out
        }
        boolean two = twoCols();
        LinearLayout body = choiceRow(two);

        // Plan A
        LinearLayout a = vbox();
        a.setBackground(box(t.sel, t.accent, 2, 16));
        a.setPadding(dp(22), dp(20), dp(22), dp(20));
        LinearLayout ah = hbox();
        ah.addView(icon(I_RADIO_ON, 20, t.accent));
        TextView at = tv("Replace Android, carry it on a drive", 19, fDisplay, t.text);
        at.setPadding(dp(12), 0, dp(8), 0);
        ah.addView(at, lp(0, WRAP, 1f));
        ah.addView(pill("Recommended", t.onOk, t.okBg));
        a.addView(ah);
        TextView ad = tv("Fedora gets the whole tablet. Your apps and files ride along on a USB drive or microSD card and are restored on first start.", 15, fText, t.sub);
        ad.setPadding(0, dp(12), 0, dp(4));
        a.addView(ad);
        if (vols.isEmpty()) {
            a.addView(tv("No microSD card or USB drive found. Plug one in (it is not erased).", 15, fSemi, t.warn));
            a.addView(button("Check again", false, () -> rescanDrives(this::spaceStep)), lpm(WRAP, WRAP, 0, 12, 0, 0));
        }
        for (int i = 0; i < vols.size(); i++) {
            Vol v = vols.get(i);
            final int idx = i + 1;
            boolean on = chosenDest == idx, fitsStuff = v.freeKb >= need, fitsAll = v.freeKb >= need + FEDORA_DOWNLOAD_KB;
            LinearLayout d = vbox();
            d.setPadding(0, dp(14), 0, 0);
            LinearLayout dh = hbox();
            dh.addView(icon(on ? I_RADIO_ON : I_RADIO, 18, t.accent));
            TextView dn = tv(vName(v), 14, fSemi, t.text);
            dn.setPadding(dp(10), 0, dp(8), 0);
            dh.addView(dn, lp(0, WRAP, 1f));
            dh.addView(tv(fitsAll ? "Fits, with Fedora download" : fitsStuff ? "Fits your stuff, " + human(need + FEDORA_DOWNLOAD_KB - v.freeKb) + " short with Fedora"
                    : human(need - v.freeKb) + " short", 14, fSemi, fitsAll ? t.ok : t.warn));
            d.addView(dh);
            d.addView(segBar(new long[]{need, FEDORA_DOWNLOAD_KB}, new int[]{t.accent, fitsAll ? t.accent2 : t.warn}, Math.max(v.freeKb, 1)));
            d.addView(muted(human(sel) + " your stuff · " + human(FEDORA_DOWNLOAD_KB) + " Fedora · " + human(v.freeKb) + " free now ("
                    + v.fs + ")" + (fitsStuff && !fitsAll ? ". Fedora can go on another drive, or free up space later." : "")));
            if (fitsStuff) {
                d.setClickable(true);
                d.setOnClickListener(x -> { chosenDest = idx; spaceStep(); });
            } else {
                d.setAlpha(0.6f);
            }
            a.addView(d);
        }
        if (vols.size() >= 2) {
            boolean on = chosenDest == SPLIT;
            LinearLayout d = vbox();
            d.setPadding(0, dp(18), 0, 0);
            LinearLayout dh = hbox();
            dh.addView(icon(on ? I_RADIO_ON : I_RADIO, 18, t.accent));
            TextView dn = tv("Split it across your drives", 14, fSemi, t.text);
            dn.setPadding(dp(10), 0, dp(8), 0);
            dh.addView(dn, lp(0, WRAP, 1f));
            dh.addView(tv(split != null ? "Fits" : "Doesn't fit, even split", 14, fSemi, split != null ? t.ok : t.warn));
            d.addView(dh);
            if (split != null) {
                for (Part pt : split) {
                    d.addView(segBar(new long[]{pt.kb + margin(pt.kb)}, new int[]{t.accent}, Math.max(1, pt.vol.freeKb)));
                    d.addView(muted(vName(pt.vol) + ": " + human(pt.kb) + ", " + pt.lines.size() + (pt.lines.size() == 1 ? " item" : " items")
                            + " (" + human(pt.vol.freeKb) + " free)"));
                }
                d.addView(muted("The biggest items go where there's room. During the upgrade the card's part is copied into Fedora; "
                        + "keep the USB drive plugged in for the first start."));
                d.setClickable(true);
                d.setOnClickListener(x -> { chosenDest = SPLIT; spaceStep(); });
            } else {
                d.setAlpha(0.6f);
            }
            a.addView(d);
        }
        addChoice(body, a, two, true);

        // Plan B (not built yet)
        LinearLayout b = vbox();
        b.setBackground(box(t.bg, t.border, 1, 16));
        b.setPadding(dp(22), dp(20), dp(22), dp(20));
        LinearLayout bh = hbox();
        bh.addView(icon(I_RADIO, 20, t.accent));
        TextView bt = tv("Keep Android alongside Fedora", 19, fDisplay, t.sub);
        bt.setPadding(dp(12), 0, 0, 0);
        bh.addView(bt, lp(0, WRAP, 1f));
        b.addView(bh);
        TextView bd = tv("Fedora lives inside internal storage next to Android. Pick which one to start each time you turn the tablet on.", 15, fText, t.sub);
        bd.setPadding(0, dp(12), 0, dp(4));
        b.addView(bd);
        long needB = FEDORA_IMAGE_KB + sel + margin(sel) + FEDORA_HEADROOM_KB;
        LinearLayout ih = hbox();
        ih.setPadding(0, dp(12), 0, 0);
        TextView in = tv("Internal storage", 14, fSemi, t.text);
        ih.addView(in, lp(0, WRAP, 1f));
        ih.addView(tv(internalFreeKb >= needB ? "Fits" : human(needB - internalFreeKb) + " short", 14, fSemi, internalFreeKb >= needB ? t.ok : t.warn));
        b.addView(ih);
        b.addView(segBar(new long[]{Math.min(internalFreeKb, needB)}, new int[]{t.ring}, needB));
        b.addView(muted("Needs " + human(needB) + " (Fedora 18 GB, your stuff " + human(sel) + ", 4 GB room). " + human(internalFreeKb) + " free."));
        b.addView(checkRow(I_CLOCK, "Not available yet: comes in a later version", null));
        addChoice(body, b, two, false);

        TextView foot = muted("Nothing is erased on the drive or card: S6 Migrate only adds an S6Migrate folder.");
        frame("How should your stuff travel?",
                "Your " + human(sel) + " selection needs somewhere to wait while Fedora is installed. Here is what fits.",
                body, foot, "Continue", () -> {
                    if (chosenDest < 1 && chosenDest != SPLIT) Toast.makeText(this, "Pick a card or USB drive with enough room.", Toast.LENGTH_LONG).show();
                    else summary();
                }, "Back", this::appsStep);
    }

    /** Looks for cards and USB drives again (after one is plugged in), keeping every other choice. */
    void rescanDrives(Runnable next) {
        LinearLayout body = vbox();
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        body.addView(text("Looking for cards and USB drives...", 16, false));
        frame("How should your stuff travel?", null, body, null, null, null, null, null);
        new Thread(() -> {
            List<Vol> found = new ArrayList<>();
            try {
                runRoot("sh " + q(new File(getCacheDir(), "scan.sh").getAbsolutePath()) + " ''", l -> {
                    String[] f = l.split("\\|", -1);
                    if (f.length >= 5 && "VOL".equals(f[0])) {
                        Vol v = new Vol();
                        v.path = f[1]; v.freeKb = parse(f[2]); v.fs = f[3]; v.kind = f[4];
                        found.add(v);
                    }
                });
            } catch (Exception ignored) {
            }
            ui.post(() -> {
                vols.clear();
                vols.addAll(found);
                chosenDest = -1;
                next.run();
            });
        }).start();
    }

    String destPath() {
        if (chosenDest >= 1 && chosenDest <= vols.size()) return vols.get(chosenDest - 1).path + "/S6Migrate";
        return null;
    }

    // ------------------------------------------------------------------ 5. Summary

    void summary() {
        curStep = 4;
        pendingRerender = this::summary;
        boolean fresh = "fresh".equals(keepMode);
        LinearLayout body = vbox();
        LinearLayout list = card();
        list.setPadding(dp(20), dp(2), dp(20), dp(2));
        int na = 0, nd = 0, nk = 0;
        List<String> kept = new ArrayList<>(), added = new ArrayList<>(), folders = new ArrayList<>();
        boolean settings = false, wifi = false;
        for (AppItem a : apps) {
            if (appSel(a)) {
                na++;
                if (a.keystore) nk++;
                if (!"linux".equals(a.choice)) kept.add(a.label);
                if (!"keep".equals(a.choice) && linuxName(a) != null) added.add(linuxName(a));
            } else if (a.installLinux && altFor(a.pkg) != null) {
                added.add(altFor(a.pkg));
            }
        }
        for (DirItem d : dirs) {
            if (!dirSel(d)) continue;
            nd++;
            if ("SET".equals(d.kind)) settings = true;
            else if ("WIFI".equals(d.kind)) wifi = true;
            else if ("DIR".equals(d.kind)) folders.add(d.name + " → ~/" + destOf(d));
        }
        Vol dv = targetVol();
        if (fresh) {
            list.addView(sumRow(I_BOX, "Keep nothing", "Fedora starts empty", this::keep));
        } else {
            int np = kept.size();
            String to = chosenDest == SPLIT ? "split across your card and drive" : "packed to the " + (dv != null ? vName(dv) : "drive");
            list.addView(sumRow(I_BOX, "Keep " + np + (np == 1 ? " app" : " apps") + " and " + nd + (nd == 1 ? " item" : " items"),
                    human(selectedKb()) + ", " + to + " and checked before anything is erased", this::spaceStep));
            list.addView(hair());
            list.addView(sumRow(I_PHONE, kept.size() + " Android " + (kept.size() == 1 ? "app" : "apps") + " kept, " + added.size() + " Linux "
                            + (added.size() == 1 ? "app" : "apps") + " added",
                    names(kept, "run in their own windows") + (added.isEmpty() ? "" : "; " + names(added, "installed")), this::appsStep));
            if (!folders.isEmpty()) {
                list.addView(hair());
                list.addView(sumRow(I_FOLDER, "Your folders on Fedora", String.join(", ", folders.subList(0, Math.min(5, folders.size())))
                        + (folders.size() > 5 ? " and " + (folders.size() - 5) + " more" : ""), this::keep));
            }
        }
        list.addView(hair());
        list.addView(sumRow(I_SCREEN, "Install Fedora 44 with KDE Plasma",
                "Light or dark to match this tablet" + (settings ? ", your wallpaper, language and time zone" : "")
                        + (wifi ? ", your Wi-Fi networks" : "") + ". Touch keyboard, auto-rotate, Wi-Fi, Bluetooth, sound, battery.", null));
        body.addView(list);
        body.addView(gap(16));
        if (!fresh && !packages.isEmpty()) {
            LinearLayout oc = card();
            CheckBox del = new CheckBox(this);
            tint(del);
            del.setTextSize(16);
            del.setText(packages.size() == 1 ? "Delete my older package after this one is verified" : "Delete my older packages after this one is verified");
            del.setChecked(deleteOld);
            del.setOnCheckedChangeListener((v, c) -> deleteOld = c);
            oc.addView(del);
            long oldKb = 0;
            for (String[] p : packages) oldKb += parse(p[3]);
            oc.addView(muted("Frees " + human(oldKb) + ". The old one stays until the new one has packed and checked out, so you're never without a copy."));
            body.addView(oc);
            body.addView(gap(16));
        }
        LinearLayout w = warnCard("Before you start");
        if (!fresh) bullet(w, "Packing changes nothing on Android. Apps close briefly while their data is copied.", t.warnText);
        bullet(w, "Next is the upgrade: it checks everything and downloads Fedora (" + human(FEDORA_DOWNLOAD_KB)
                + ") to a card or USB drive. Nothing is erased until you confirm at the very end.", t.warnText);
        bullet(w, "The upgrade takes about 40 minutes and restarts the tablet twice. Keep it plugged in.", t.warnText);
        if (nk > 0) bullet(w, nk + (nk == 1 ? " app keeps" : " apps keep") + " data locked to this tablet: they move, but you'll sign in again.", t.warnText);
        if (fresh && !packages.isEmpty()) bullet(w, "A package from earlier is still on your drive and would be restored. Delete its S6Migrate folder first to start empty.", t.warnText);
        body.addView(w);
        if (fresh) {
            frame("Summary", null, body, null, "Continue to upgrade", this::switchStart, "Back", this::keep);
        } else {
            frame("Summary", null, body, null, "Pack now", () -> {
                String stamp = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
                if (chosenDest == SPLIT) { packSplit(stamp); return; }
                String base = destPath();
                if (base == null) { spaceStep(); return; }
                pack(base + "/" + stamp);
            }, "Back", this::spaceStep);
        }
    }

    static String names(List<String> l, String verb) {
        if (l.isEmpty()) return "";
        List<String> u = new ArrayList<>(new java.util.LinkedHashSet<>(l));
        String s = String.join(", ", u.subList(0, Math.min(4, u.size()))) + (u.size() > 4 ? " and " + (u.size() - 4) + " more" : "");
        return s + " " + (u.size() == 1 ? verb.replace("run in their own windows", "runs in its own window") : verb);
    }

    // ------------------------------------------------------------------ about

    void credits() {
        final Runnable back = rerender != null ? rerender : this::home;
        LinearLayout body = vbox();
        TextView tx = tv("S6 Migrate packs your Android apps, data, files and settings, installs an existing Fedora port "
                + "for the Galaxy Tab S6 from the tablet itself, and puts everything back. The hard work of running Linux "
                + "on this tablet was done by these projects:\n\n"
                + "• Bentlybro: gts6l-mainline-linux, the mainline Linux port\n  https://github.com/Bentlybro/gts6l-mainline-linux\n\n"
                + "• starlight4you: t860-fedora, the Fedora build and installer used for the switch\n  https://github.com/starlight4you/t860-fedora\n\n"
                + "• Project Aloha: SM8150 UEFI and DualBootKernelPatcher\n  https://github.com/Project-Aloha\n\n"
                + "• Magisk (topjohnwu), TWRP, Waydroid, LineageOS, Fedora, KDE, Mesa, linux-msm\n\n"
                + "• Linux apps suggested for your apps, such as Pear Desktop for YouTube Music\n  https://github.com/pear-devs/pear-desktop\n\n"
                + "• Linux versions found live on Flathub\n  https://flathub.org\n\n"
                + "• Red Hat Display and Red Hat Text fonts by Red Hat (SIL Open Font License 1.1)\n  https://github.com/RedHatOfficial/RedHatFont\n\n"
                + "Full list: CREDITS.md in the S6 Migrate repository.", 15, fText, t.text);
        tx.setAutoLinkMask(android.text.util.Linkify.WEB_URLS);
        tx.setLinkTextColor(t.link);
        tx.setLinksClickable(true);
        body.addView(tx);
        frame("About and credits", null, body, null, null, null, "Back", back);
    }

    // ------------------------------------------------------------------ Linux versions

    /** Hand-picked list (alternatives.tsv): package or prefix -> full row (pkg, name, method, target, note). */
    final Map<String, String[]> altExact = new HashMap<>();
    final List<String[]> altPrefix = new ArrayList<>();

    static final String[] LIVE_LIST = {
            "https://raw.githubusercontent.com/suxhi-space/TabS6-desktop/main/tools/migrate/lib/alternatives.tsv",
            "https://raw.githubusercontent.com/suxhi-space/TabS6-desktop/claude/android-tablet-desktop-ui-755uqh/tools/migrate/lib/alternatives.tsv"};

    /** Newest hand-picked list from GitHub (works once the repository is public); keeps the bundled one otherwise. */
    void loadLiveAlternatives() {
        for (String u : LIVE_LIST) {
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(u).openConnection();
                c.setConnectTimeout(5000);
                c.setReadTimeout(8000);
                if (c.getResponseCode() != 200) continue;
                Map<String, String[]> ex = new HashMap<>();
                List<String[]> pre = new ArrayList<>();
                try (BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), "UTF-8"))) {
                    parseAlternatives(r, ex, pre);
                }
                if (ex.isEmpty()) continue;
                synchronized (altExact) { altExact.clear(); altExact.putAll(ex); altPrefix.clear(); altPrefix.addAll(pre); }
                return;
            } catch (Exception ignored) {
            }
        }
    }

    static void parseAlternatives(BufferedReader r, Map<String, String[]> ex, List<String[]> pre) throws IOException {
        String l;
        while ((l = r.readLine()) != null) {
            if (l.startsWith("#") || l.trim().isEmpty()) continue;
            String[] f = l.split("\t");
            if (f.length < 3) continue;
            if (f[0].endsWith("*")) {
                f[0] = f[0].substring(0, f[0].length() - 1);
                pre.add(f);
            } else {
                ex.put(f[0], f);
            }
        }
    }

    void loadAlternatives() {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(getAssets().open("alternatives.tsv"), "UTF-8"))) {
            synchronized (altExact) { parseAlternatives(r, altExact, altPrefix); }
        } catch (IOException ignored) {
        }
    }

    String[] altRow(String pkg) {
        synchronized (altExact) {
            String[] a = altExact.get(pkg);
            if (a != null) return a;
            for (String[] p : altPrefix) if (pkg.startsWith(p[0])) return p;
        }
        return null;
    }

    String altFor(String pkg) {
        String[] a = altRow(pkg);
        return a == null ? null : a[1];
    }

    String altNote(String pkg) {
        String[] a = altRow(pkg);
        return a != null && a.length > 4 ? a[4] : "";
    }

    final Map<String, Found> found = new HashMap<>();

    /** Looks up the given apps on Flathub (only their names are sent), then runs next. Results are cached 14 days. */
    void lookupLinuxVersions(List<AppItem> todo, Runnable next) {
        final File cacheFile = new File(getFilesDir(), "flathub-cache.json");
        LinearLayout body = vbox();
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        ProgressBar pb = new ProgressBar(this);
        pb.setIndeterminateTintList(ColorStateList.valueOf(t.accent));
        body.addView(pb, lpm(WRAP, WRAP, 0, 24, 0, 16));
        TextView st = tv("Looking up Linux versions of the " + todo.size() + (todo.size() == 1 ? " app" : " apps") + " you chose...", 16, fSemi, t.text);
        st.setGravity(Gravity.CENTER);
        body.addView(st);
        TextView nt = muted("Only app names are sent to Flathub's public search. Results are remembered for 14 days.");
        nt.setGravity(Gravity.CENTER);
        nt.setPadding(0, dp(8), 0, 0);
        body.addView(nt);
        cancelDownload = false;
        frame("Your apps on Fedora", "Checking which of your apps have a Linux version.", body, null,
                null, null, "Skip", () -> cancelDownload = true);
        new Thread(() -> {
            JSONObject cache = new JSONObject();
            try {
                if (cacheFile.exists()) cache = new JSONObject(new String(java.nio.file.Files.readAllBytes(cacheFile.toPath()), "UTF-8"));
            } catch (Exception ignored) {
            }
            long now = System.currentTimeMillis();
            boolean online = true;
            int n = 0;
            for (AppItem a : todo) {
                if (cancelDownload) break;
                n++;
                JSONObject e = cache.optJSONObject(a.pkg);
                Found f = new Found();
                if (e != null && now - e.optLong("t") < 14L * 86400000L && a.label.equals(e.optString("label"))) {
                    f.name = e.optString("name"); f.appId = e.optString("appId"); f.conf = e.optString("conf"); f.note = e.optString("note");
                } else if (online) {
                    final String msg = "Looking up Linux versions on Flathub (" + n + " of " + todo.size() + "): " + a.label;
                    ui.post(() -> st.setText(msg));
                    try {
                        f = flathubLookup(a.label);
                        cache.put(a.pkg, new JSONObject().put("t", now).put("label", a.label).put("name", f.name)
                                .put("appId", f.appId).put("conf", f.conf).put("note", f.note));
                    } catch (Exception ex) {
                        online = false; // offline or Flathub unreachable: stop asking, keep what we have
                    }
                }
                synchronized (found) { found.put(a.pkg, f); }
            }
            try (FileOutputStream o = new FileOutputStream(cacheFile)) { o.write(cache.toString().getBytes("UTF-8")); } catch (Exception ignored) { }
            ui.post(() -> {
                for (AppItem a : todo) lookedUp.add(a.pkg); // skipped ones too: don't ask again this session
                next.run();
            });
        }).start();
    }

    String foundTsv() {
        StringBuilder sb = new StringBuilder("# Linux versions found on Flathub by S6 Migrate (high = installed, maybe = suggested)\n");
        synchronized (found) {
            for (Map.Entry<String, Found> e : found.entrySet()) {
                Found f = e.getValue();
                if ("none".equals(f.conf)) continue;
                sb.append(e.getKey()).append('\t').append(f.name).append("\tflatpak\t").append(f.appId).append('\t')
                        .append(f.conf).append('\t').append(f.note).append('\n');
            }
        }
        return sb.toString();
    }

    /** Name of the Linux version of an app (hand-picked list or Flathub), or null. */
    String linuxName(AppItem a) {
        String alt = altFor(a.pkg);
        if (alt != null) return alt;
        Found fd;
        synchronized (found) { fd = found.get(a.pkg); }
        return fd != null && !"none".equals(fd.conf) ? fd.name : null;
    }

    /** First time an app is shown with a Linux version: confident matches default to both, others stay Android. */
    void defaultChoice(AppItem a) {
        if (a.choiceSet) return;
        a.choiceSet = true;
        Found fd;
        synchronized (found) { fd = found.get(a.pkg); }
        if (altFor(a.pkg) != null || (fd != null && "high".equals(fd.conf))) a.choice = "both";
    }

    /** Plan line for an app: packed (APP), Linux version only (LINUX), or nothing. */
    String appLine(AppItem a) {
        if (appSel(a)) return "linux".equals(a.choice) && linuxName(a) != null ? "LINUX|" + a.pkg + "|" + linuxName(a) : planLine(a);
        if (a.installLinux && altFor(a.pkg) != null) return "LINUX|" + a.pkg + "|" + altFor(a.pkg);
        return null;
    }

    String choicesTxt() {
        StringBuilder sb = new StringBuilder();
        for (AppItem a : apps) {
            if (appSel(a) && linuxName(a) != null) sb.append(a.pkg).append('|').append(a.choice).append('\n');
            else if (!appSel(a) && a.installLinux && altFor(a.pkg) != null) sb.append(a.pkg).append("|linux\n");
        }
        return sb.toString();
    }

    // ------------------------------------------------------------------ pack

    long selectedKb() {
        long t = 0;
        for (AppItem a : apps) if (appSel(a) && !"linux".equals(a.choice)) t += a.kb;
        for (DirItem d : dirs) if (dirSel(d)) t += d.kb;
        return t;
    }

    void pack(String out) {
        StringBuilder sb = new StringBuilder();
        int n = 0;
        for (AppItem a : apps) {
            String l = appLine(a);
            if (l != null) { sb.append(l).append('\n'); n++; }
        }
        for (DirItem d : dirs)
            if (dirSel(d)) {
                sb.append(dirLine(d)).append('\n');
                n++;
            }
        runPack(out, sb.toString(), n, selectedKb(), false);
    }

    long oldFreedKb = -1;

    void done(boolean ok, String out, String log, boolean update) {
        busy = false;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        LinearLayout body = vbox();
        LinearLayout c = ok ? card() : warnCard(null);
        c.addView(checkRow(ok, ok ? (update ? "Package updated and verified" : "Packed and verified") : "Finished with errors",
                ok ? out : "Details: " + out + "/pack-warnings.log"));
        if (ok && !update && oldFreedKb >= 0) {
            c.addView(checkRow(true, "Your older package was deleted", human(oldFreedKb) + " freed"));
            oldFreedKb = -1;
        }
        c.addView(tv(ok ? "Nothing on Android was changed. Keep the card or drive in the tablet until you have switched."
                : "Nothing on Android was changed" + (update ? ", and items that failed kept their previous copy." : ".")
                + " You can fix the problem and pack again.", 15, fText, ok ? t.text : t.warnText));
        body.addView(c);
        body.addView(gap(14));
        body.addView(h2("Details"));
        TextView l = tv(log, 12, Typeface.MONOSPACE, t.muted);
        body.addView(l);
        if (ok && !update) {
            frame("Your stuff is packed", "Next: download Fedora and run the upgrade.", body, null,
                    "Continue to upgrade", this::switchStart, "Close", this::finish);
        } else {
            String[] entry = null;
            for (String[] p : packages) if (p[1].equals(out)) entry = p;
            final String[] fe = entry;
            if (!ok && fe != null) frame("Some items didn't pack", "Nothing on Android was changed. Fix it packs only those items again.", body, null,
                    "Fix it", () -> repairPackage(fe), "Later", this::home);
            else frame(ok ? "Package updated" : "Packing finished with errors", null, body, null, "Done", this::home, null, null);
        }
    }
}
