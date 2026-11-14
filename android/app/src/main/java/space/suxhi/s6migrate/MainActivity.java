package space.suxhi.s6migrate;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.CheckBox;
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

/**
 * Tab S6 Migration Assistant, v0.1 "Pack".
 *
 * Lists your own apps and internal-storage folders, shows live whether the selection fits Plan A
 * (pack to microSD / USB drive) and Plan B (Linux next to Android), and packs the selection with
 * root using the shared scripts in assets (tools/migrate/lib/scan.sh and pack.sh).
 * It only reads Android data and writes the package to the destination you choose.
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
    }

    static class DirItem {
        String name;
        long kb;
        boolean selected;
        boolean top;   // "files directly in internal storage" (not a folder)
        long count;
        String kind = "DIR"; // DIR, TOP (loose files), SET (settings), WIFI (Wi-Fi networks)
        String sub;          // optional description shown under the name
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
    TextView spacePanel;

    // ------------------------------------------------------------------ lifecycle

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        scan();
    }

    @Override
    public void onBackPressed() {
        if (busy) {
            Toast.makeText(this, "Packing is running. Please wait until it finishes.", Toast.LENGTH_SHORT).show();
        } else {
            super.onBackPressed();
        }
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

    TextView text(String s, float sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    /** Standard screen: title, scrolling body, optional space panel, buttons. */
    void screen(String title, String subtitle, View body, boolean withSpace,
                String primary, Runnable onPrimary, String secondary, Runnable onSecondary) {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(16), dp(16), dp(16), dp(12));

        page.addView(text(title, 22, true));
        if (subtitle != null) {
            TextView st = text(subtitle, 14, false);
            st.setPadding(0, dp(4), 0, dp(8));
            page.addView(st);
        }

        ScrollView sv = new ScrollView(this);
        sv.addView(body);
        page.addView(sv, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        spacePanel = null;
        if (withSpace) {
            spacePanel = text("", 13, false);
            spacePanel.setPadding(dp(12), dp(10), dp(12), dp(10));
            spacePanel.setBackgroundColor(0x22888888);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(8);
            page.addView(spacePanel, lp);
            updateSpace();
        }

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.END);
        bar.setPadding(0, dp(8), 0, 0);
        if (secondary != null) {
            Button s = new Button(this);
            s.setText(secondary);
            s.setOnClickListener(v -> onSecondary.run());
            bar.addView(s);
        }
        if (primary != null) {
            Button p = new Button(this);
            p.setText(primary);
            p.setOnClickListener(v -> onPrimary.run());
            bar.addView(p);
        }
        page.addView(bar);
        setContentView(page);
    }

    void message(String title, String msg) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(text(msg, 15, false));
        screen(title, null, body, false, "Close", this::finish, null, null);
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
        body.addView(new ProgressBar(this));
        body.addView(text("Looking at your apps and folders (read-only).\n\n"
                + "If Magisk asks, tap Grant. This can take a minute.", 15, false));
        screen("Tab S6 Migration Assistant", "v0.1: pack your apps, data and folders for the move to Linux",
                body, false, null, null, null, null);

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

    long selectedKb() {
        long t = 0;
        for (AppItem a : apps) if (a.selected) t += a.kb;
        for (DirItem d : dirs) if (d.selected) t += d.kb;
        return t;
    }

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

    String spaceText() {
        long sel = selectedKb(), m = margin(sel);
        StringBuilder s = new StringBuilder();
        s.append("Selected: ").append(human(sel)).append("\n\nPlan A: pack to a card or USB drive\n");
        if (vols.isEmpty()) s.append("  No microSD card or USB drive found. Plug one in.\n");
        for (Vol v : vols) {
            s.append("  ").append(vName(v)).append(", ").append(human(v.freeKb)).append(" free\n")
                    .append("    pack only: ").append(fit(v.freeKb, sel + m)).append("\n")
                    .append("    + Fedora download (one-button switch): ")
                    .append(fit(v.freeKb, sel + m + FEDORA_DOWNLOAD_KB)).append("\n");
        }
        long needB = FEDORA_IMAGE_KB + sel + m + FEDORA_HEADROOM_KB;
        s.append("\nPlan B: Linux next to Android (internal storage)\n")
                .append("  ").append(human(internalFreeKb)).append(" free, needs ").append(human(needB))
                .append(" (Fedora 18 GB + selection + 4 GB): ").append(fit(internalFreeKb, needB)).append("\n");
        if (metadataEncryption) {
            s.append("  Encryption: whole partition. Plan B is not possible on this tablet.");
        } else {
            s.append("  Encryption: file-based").append(cryptoMode.isEmpty() ? "" : " (" + cryptoMode + ")")
                    .append(". ").append(probeHash.isEmpty()
                            ? "TWRP test not set up yet."
                            : "TWRP test file present (" + probeHash.substring(0, Math.min(8, probeHash.length()))
                            + "): confirm it in TWRP.");
        }
        return s.toString();
    }

    void updateSpace() {
        if (spacePanel != null) spacePanel.setText(spaceText());
    }

    // ------------------------------------------------------------------ pickers

    View row(Drawable icon, String title, String sub, String warn, boolean checked, CheckBoxToggle onToggle) {
        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER_VERTICAL);
        r.setPadding(0, dp(6), 0, dp(6));
        CheckBox cb = new CheckBox(this);
        cb.setChecked(checked);
        cb.setOnCheckedChangeListener((v, c) -> onToggle.set(c));
        r.addView(cb);
        if (icon != null) {
            ImageView iv = new ImageView(this);
            iv.setImageDrawable(icon);
            LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(36), dp(36));
            ip.rightMargin = dp(10);
            r.addView(iv, ip);
        }
        LinearLayout tx = new LinearLayout(this);
        tx.setOrientation(LinearLayout.VERTICAL);
        tx.addView(text(title, 16, true));
        tx.addView(text(sub, 13, false));
        if (warn != null) {
            TextView w = text(warn, 13, false);
            w.setTextColor(Color.rgb(230, 126, 34));
            tx.addView(w);
        }
        r.addView(tx, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));
        r.setOnClickListener(v -> cb.toggle());
        return r;
    }

    interface CheckBoxToggle {
        void set(boolean checked);
    }

    /** Card listing packages already made, so the user knows their earlier run is safe. */
    View savedPackages() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(12), dp(14), dp(12));
        card.setBackgroundColor(0x2251A2DA);
        card.addView(text(packages.size() == 1 ? "You already have a saved package" : "You already have saved packages", 16, true));
        for (String[] p : packages) {
            String path = p[1];
            String folder = path.substring(path.lastIndexOf('/') + 1);
            String when = folder;
            try {
                Date d = new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).parse(folder);
                when = new SimpleDateFormat("d MMM, HH:mm", Locale.getDefault()).format(d);
            } catch (Exception ignored) {
            }
            String where = path.startsWith("/data/media") ? "internal storage" : "external drive";
            for (Vol v : vols) if (path.startsWith(v.path + "/")) where = vName(v);
            String status = "complete".equals(p[4]) ? "verified" : "errors".equals(p[4]) ? "finished with errors" : "status unknown";
            final String fWhen = when, fWhere = where;
            TextView row = text("\u2022 " + when + ": " + parse(p[2]) + " items, " + human(parse(p[3])) + " on " + where
                    + " (" + status + ")   See what changed \u203a", 14, false);
            row.setPadding(0, dp(10), 0, dp(10));
            row.setOnClickListener(v -> openPackage(p, fWhen, fWhere));
            card.addView(row);
        }
        card.addView(text("Tap a package to see what changed since you made it and update just those items.", 13, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(12);
        card.setLayoutParams(lp);
        return card;
    }

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
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(new ProgressBar(this));
        body.addView(text("Comparing your package with what is on the tablet now (read-only)...", 15, false));
        screen("Your package from " + when, null, body, false, null, null, "Back", this::home);
        new Thread(() -> {
            List<String> plan = new ArrayList<>();
            List<String> cmp = new ArrayList<>();
            try {
                runRoot("cat " + q(p[1] + "/plan.txt"), plan::add);
                runRoot("sh " + q(new File(getCacheDir(), "compare.sh").getAbsolutePath()) + " '' " + q(p[1]), cmp::add);
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
        body.addView(text(parse(p[2]) + " items, " + human(parse(p[3])) + " on " + where + ".\nSince then: "
                + changed.size() + " changed, " + fresh.size() + " new, " + gone.size() + " no longer on the tablet, "
                + same + " unchanged.", 15, false));
        TextView need = text("", 14, true);
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
            body.addView(text("\nChanged since then (ticked: re-pack recommended)", 16, true));
            for (Change c : changed)
                body.addView(row(c.icon, c.label, c.sub, null, c.selected, on -> { c.selected = on; refresh.run(); }));
        }
        if (!fresh.isEmpty()) {
            body.addView(text("\nOn the tablet but not in the package", 16, true));
            for (Change c : fresh)
                body.addView(row(c.icon, c.label, c.sub, null, c.selected, on -> { c.selected = on; refresh.run(); }));
        }
        if (!gone.isEmpty()) {
            body.addView(text("\nNo longer on the tablet", 16, true));
            body.addView(text(String.join(", ", gone) + "\nTheir copies stay in the package.", 14, false));
        }
        refresh.run();
        screen("Your package from " + when, null, body, false,
                "Update package", () -> confirmUpdate(p, all), "Back", this::home);
    }

    void confirmUpdate(String[] p, List<Change> all) {
        StringBuilder plan = new StringBuilder();
        int n = 0;
        long kb = 0;
        for (Change c : all)
            if (c.selected) {
                plan.append(c.line).append('\n');
                n++;
                kb += c.kb;
            }
        if (n == 0) {
            Toast.makeText(this, "Nothing selected to update.", Toast.LENGTH_SHORT).show();
            return;
        }
        if (freeFor(p[1]) < kb + margin(kb)) {
            Toast.makeText(this, "Not enough free space on that drive for this update.", Toast.LENGTH_LONG).show();
            return;
        }
        final int fn = n;
        final long fkb = kb;
        new AlertDialog.Builder(this).setTitle("Update this package?")
                .setMessage(n + (n == 1 ? " item" : " items") + " (about " + human(kb) + ") will be re-packed into\n" + p[1]
                        + "\n\nEach item replaces its old copy only after the new one is verified. Nothing on Android is changed.")
                .setPositiveButton("Update", (d, w) -> runPack(p[1], plan.toString(), fn, fkb, true))
                .setNegativeButton("Cancel", null).show();
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

    View checkRow(boolean ok, String title, String detail) {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.VERTICAL);
        r.setPadding(0, dp(6), 0, dp(6));
        TextView t = text((ok ? "✓  " : "✗  ") + title, 16, true);
        t.setTextColor(ok ? Color.rgb(46, 160, 90) : Color.rgb(230, 126, 34));
        r.addView(t);
        if (detail != null) r.addView(text("     " + detail, 13, false));
        return r;
    }

    void switchStart() {
        switchPkg = newestExternalPackage();
        if (switchPkg == null) {
            LinearLayout b = new LinearLayout(this);
            b.setOrientation(LinearLayout.VERTICAL);
            b.addView(text("The switch needs your package on a USB drive or microSD card (internal storage is erased). "
                    + "Make a package on a drive first, then come back here.", 15, false));
            screen("Switch to Fedora", null, b, false, null, null, "Back", this::home);
            return;
        }
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(new ProgressBar(this));
        body.addView(text("Checking your tablet (read-only)...", 15, false));
        screen("Switch to Fedora", null, body, false, null, null, "Back", this::home);
        final String drive = driveOf(switchPkg[1]);
        final String fdir = drive + "/S6Migrate/fedora";
        new Thread(() -> {
            StringBuilder names = new StringBuilder();
            for (String[] f : FEDORA_FILES) names.append(' ').append(f[0]);
            String sh = "echo MODEL=$(getprop ro.product.vendor.model);"
                    + "echo BAT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null);"
                    + "echo CHG=$(cat /sys/class/power_supply/battery/status 2>/dev/null);"
                    + "for f in" + names + "; do [ -f " + q(fdir) + "/$f.verified ] && echo VERIFIED=$f;"
                    + " [ -f " + q(fdir) + "/$f.partial ] && echo PARTIAL=$f=$(stat -c %s " + q(fdir) + "/$f.partial); done;"
                    + "echo FREE=$(df -k " + q(drive) + " | tail -1 | tr -s ' ' | cut -d' ' -f4);"
                    + "L=" + q(drive + "/S6Migrate/switch-log.txt") + "; [ -f \"$L\" ] && { grep -q S6MIGRATE-REHEARSAL-PASSED \"$L\" && echo LAST=passed"
                    + " || echo LAST=$(grep -m1 STOPPED \"$L\" | cut -c1-200); }";
            final Map<String, String> v = new HashMap<>();
            final Set<String> verified = new HashSet<>();
            final long[] partialBytes = {0};
            try {
                runRoot(sh, l -> {
                    int i = l.indexOf('=');
                    if (i < 0) return;
                    String k = l.substring(0, i), val = l.substring(i + 1);
                    if (k.equals("VERIFIED")) verified.add(val);
                    else if (k.equals("PARTIAL")) partialBytes[0] += parse(val.substring(val.lastIndexOf('=') + 1));
                    else v.put(k, val);
                });
            } catch (Exception e) {
                ui.post(() -> message("Could not check", String.valueOf(e.getMessage())));
                return;
            }
            ui.post(() -> showSwitchChecks(v, verified, partialBytes[0], drive, fdir));
        }).start();
    }

    void showSwitchChecks(Map<String, String> v, Set<String> verified, long partialBytes, String drive, String fdir) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        String model = v.getOrDefault("MODEL", "");
        boolean modelOk = model.startsWith("SM-T860");
        long bat = parse(v.getOrDefault("BAT", "0"));
        String chg = v.getOrDefault("CHG", "");
        boolean charging = chg.equalsIgnoreCase("Charging") || chg.equalsIgnoreCase("Full");
        boolean batOk = bat >= 60;
        boolean pkgOk = "complete".equals(switchPkg[4]);
        long need = 0, total = 0;
        for (String[] f : FEDORA_FILES) {
            total += Long.parseLong(f[1]);
            if (!verified.contains(f[0])) need += Long.parseLong(f[1]);
        }
        boolean fedoraOk = need == 0;
        long freeKb = parse(v.getOrDefault("FREE", "0"));
        long needKb = Math.max(0, need - partialBytes) / 1024 + 204800;

        String last = v.get("LAST");
        if (last != null) body.addView(checkRow("passed".equals(last), "passed".equals(last)
                ? "Last rehearsal in TWRP passed" : "Last TWRP run stopped", "passed".equals(last) ? null : last));
        body.addView(checkRow(modelOk, "Galaxy Tab S6 Wi-Fi (SM-T860)", modelOk ? null : "This tablet reports '" + model + "'. The switch only supports the SM-T860."));
        body.addView(checkRow(batOk, "Battery " + bat + "%" + (charging ? ", charging" : ""), batOk ? (charging ? null : "Plug in the charger during the switch.") : "Charge to at least 60% and keep the charger plugged in."));
        body.addView(checkRow(pkgOk, "Your package from " + folderOf(switchPkg[1]) + " (" + parse(switchPkg[2]) + " items, " + human(parse(switchPkg[3])) + ")",
                pkgOk ? "Tip: check it for changes right before switching." : "This package did not finish cleanly. Update it or make a new one."));
        Button upd = new Button(this);
        upd.setText("Check package for changes");
        upd.setOnClickListener(x -> openPackage(switchPkg, folderOf(switchPkg[1]), "your drive"));
        body.addView(upd);
        body.addView(checkRow(fedoraOk, "Fedora downloaded and verified (" + human(total / 1024) + ")",
                fedoraOk ? "Stored next to your package in S6Migrate/fedora." :
                        "Needs " + human(Math.max(0, need - partialBytes) / 1024) + " more" + (partialBytes > 0 ? " (resumes where it stopped)" : "")
                                + ". Free on the drive: " + human(freeKb) + "."));
        if (!fedoraOk) {
            Button dl = new Button(this);
            dl.setText(freeKb >= needKb ? "Download Fedora" : "Not enough space on the drive");
            dl.setEnabled(freeKb >= needKb);
            dl.setOnClickListener(x -> downloadFedora(fdir));
            body.addView(dl);
        }
        body.addView(text("\nBefore you continue, confirm:", 16, true));
        CheckBox twrp = new CheckBox(this);
        twrp.setText("TWRP (the official one for gts6lwifi) is installed as my recovery");
        CheckBox auth = new CheckBox(this);
        auth.setText("I exported my authenticator codes and backed up anything not in the package");
        body.addView(twrp);
        body.addView(auth);
        screen("Switch to Fedora", "Nothing is changed on this screen.", body, false, "Continue", () -> {
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
        TextView detail = text("", 14, false);
        body.addView(status);
        body.addView(bar);
        body.addView(detail);
        body.addView(text("\nKeep this screen open and Wi-Fi on. If it stops, start again: it resumes where it left off.", 13, false));
        cancelDownload = false;
        busy = true;
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        screen("Downloading Fedora", null, body, false, null, null, "Pause", () -> cancelDownload = true);
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
                    screen("Download stopped", null, b, false, "Try again", () -> downloadFedora(fdir), "Back", this::switchStart);
                }
            });
        }).start();
    }

    void finalConfirm(String drive) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(text("What happens now", 18, true));
        body.addView(text("1. The tablet restarts into TWRP. If TWRP asks for a password, tap Cancel.\n"
                + "2. TWRP checks the Fedora download and saves your Android boot backup to the drive.\n"
                + "3. Fedora is installed. Android and everything not in your package is erased.\n"
                + "4. The tablet restarts into Fedora (log in as fedora / fedora), and S6 Migrate brings your files, "
                + "settings and apps back.\n\nIt takes about 30-40 minutes. Keep the charger plugged in and the drive connected. "
                + "Don't press any buttons in TWRP.", 15, false));
        body.addView(text("\nIf anything fails before step 3, TWRP says \"Nothing was erased\" and you can go back to Android.", 14, false));
        body.addView(text("\nRecommended first: a rehearsal. TWRP runs every check and returns to Android without erasing anything.", 15, true));
        Button reh = new Button(this);
        reh.setText("Rehearse first (nothing is erased)");
        reh.setOnClickListener(x -> prepareSwitch(true));
        body.addView(reh);
        screen("Ready to switch", null, body, false, "Switch to Fedora", () -> {
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

    void prepareSwitch(boolean rehearsal) {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(new ProgressBar(this));
        body.addView(text("Preparing the switch for TWRP...", 15, false));
        screen("Switch to Fedora", null, body, false, null, null, null, null);
        new Thread(() -> {
            String err = null;
            try {
                File zip = new File(getCacheDir(), "s6migrate-switch.zip");
                try (ZipOutputStream z = new ZipOutputStream(new FileOutputStream(zip))) {
                    zipAsset(z, "META-INF/com/google/android/update-binary", "switch/update-binary");
                    z.putNextEntry(new ZipEntry("META-INF/com/google/android/updater-script"));
                    z.write("# S6 Migrate: the work is done by update-binary\n".getBytes("UTF-8"));
                    z.closeEntry();
                    zipAsset(z, "s6migrate/s6-restore", "s6-restore.sh");
                    zipAsset(z, "s6migrate/s6-doctor", "s6-doctor.sh");
                    zipAsset(z, "s6migrate/s6-android", "s6-android.sh");
                    zipAsset(z, "s6migrate/s6-firstrun", "switch/s6-firstrun");
                    zipAsset(z, "s6migrate/alternatives.tsv", "alternatives.tsv");
                    zipAsset(z, "s6migrate/s6migrate-firstrun.desktop", "switch/s6migrate-firstrun.desktop");
                    if (rehearsal) {
                        z.putNextEntry(new ZipEntry("s6migrate/REHEARSAL"));
                        z.write("checks only, nothing is erased\n".getBytes("UTF-8"));
                        z.closeEntry();
                    }
                }
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
                    screen("Switch not started", null, b, false, null, null, "Back", this::switchStart);
                    return;
                }
                b.addView(text(rehearsal
                        ? "Rehearsal ready. When you tap Restart, TWRP runs every check (about 5 minutes), erases nothing, and restarts into Android. "
                        + "Open S6 Migrate afterwards to see the result.\n\nIf TWRP asks for a password: tap Cancel."
                        : "Everything is ready. When you tap Restart, the tablet starts TWRP and the switch runs by itself.\n\n"
                        + "If TWRP asks for a password: tap Cancel.\nDon't touch anything else until Fedora starts.", 16, false));
                screen("Ready", null, b, false, "Restart into TWRP", () -> {
                    try { runRoot("reboot recovery", l -> { }); } catch (Exception ignored) { }
                }, "Cancel switch", () -> {
                    try { runRoot("rm -f /cache/recovery/openrecoveryscript /cache/recovery/s6migrate-switch.zip", l -> { }); } catch (Exception ignored) { }
                    Toast.makeText(this, "Switch cancelled. Nothing was changed.", Toast.LENGTH_LONG).show();
                    home();
                });
            });
        }).start();
    }

    /** Start screen: saved packages (compare / update) or make a new one. Shown only when packages exist. */
    void credits() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView t = text("S6 Migrate packs your Android apps, data, files and settings, installs an existing Fedora port "
                + "for the Galaxy Tab S6 from the tablet itself, and puts everything back. The hard work of running Linux "
                + "on this tablet was done by these projects:\n\n"
                + "\u2022 Bentlybro: gts6l-mainline-linux, the mainline Linux port\n  https://github.com/Bentlybro/gts6l-mainline-linux\n\n"
                + "\u2022 starlight4you: t860-fedora, the Fedora build and installer used for the switch\n  https://github.com/starlight4you/t860-fedora\n\n"
                + "\u2022 Project Aloha: SM8150 UEFI and DualBootKernelPatcher\n  https://github.com/Project-Aloha\n\n"
                + "\u2022 Magisk (topjohnwu), TWRP, Waydroid, LineageOS, Fedora, KDE, Mesa, linux-msm\n\n"
                + "\u2022 Linux apps suggested for your apps, such as Pear Desktop for YouTube Music\n  https://github.com/pear-devs/pear-desktop\n\n"
                + "Full list: CREDITS.md in the S6 Migrate repository.", 15, false);
        t.setAutoLinkMask(android.text.util.Linkify.WEB_URLS);
        t.setLinksClickable(true);
        body.addView(t);
        screen("About and credits", null, body, false, null, null, "Back", this::home);
    }

    void home() {
        if (packages.isEmpty()) {
            pickApps();
            return;
        }
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(savedPackages());
        Button sw = new Button(this);
        sw.setText("Switch to Fedora\u2026");
        sw.setOnClickListener(v -> switchStart());
        body.addView(sw);
        body.addView(text("Checks everything and downloads Fedora first. Nothing is erased until you confirm at the very end.", 13, false));
        body.addView(text("\nOr make a new, separate package with a different selection. Your saved package is not changed.", 14, false));
        Button cr = new Button(this);
        cr.setText("About and credits");
        cr.setOnClickListener(x -> credits());
        body.addView(cr);
        screen("Tab S6 Migration Assistant", "Your apps, data and files, packed for the move to Fedora",
                body, false, "Make a new package", this::pickApps, "Close", this::finish);
    }

    void pickApps() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        if (!keystoreChecked) {
            body.addView(text("(Keystore check unavailable: no warnings about apps whose data cannot move.)", 12, false));
        }
        for (AppItem a : apps) {
            String alt = altFor(a.pkg);
            body.addView(row(a.icon, a.label, a.pkg + "  ·  " + human(a.kb)
                            + (alt != null ? "\nOn Fedora: " + alt + " is installed for you, and this Android app is kept too" : ""),
                    a.keystore ? "Data is locked to this tablet's security chip: the app moves, its data may not" : null,
                    a.selected, c -> {
                        a.selected = c;
                        updateSpace();
                    }));
        }
        screen("1. Apps to take along", "Only apps you installed are listed. Google and Samsung apps stay behind.",
                body, true, "Next", this::pickDirs, packages.isEmpty() ? "Cancel" : "Back",
                packages.isEmpty() ? this::finish : this::home);
    }

    void pickDirs() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        for (DirItem d : dirs) {
            body.addView(row(null, d.name, d.sub != null ? d.sub
                    : d.top ? d.count + " files that are not in a folder \u00b7 " + human(d.kb) : human(d.kb),
                    null, d.selected, c -> {
                d.selected = c;
                updateSpace();
            }));
        }
        screen("2. Settings and folders to take along", "Your settings, Wi-Fi, and folders from internal storage.",
                body, true, "Next", this::pickDest, "Back", this::pickApps);
    }

    void pickDest() {
        long sel = selectedKb();
        if (sel == 0) {
            Toast.makeText(this, "Select at least one app or folder.", Toast.LENGTH_SHORT).show();
            return;
        }
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        RadioGroup g = new RadioGroup(this);
        long need = sel + margin(sel);
        for (int i = 0; i < vols.size(); i++) {
            Vol v = vols.get(i);
            RadioButton rb = new RadioButton(this);
            rb.setId(i + 1);
            rb.setText(vName(v) + "\n" + human(v.freeKb) + " free (" + v.fs + "): " + fit(v.freeKb, need)
                    + "\nOnly an S6Migrate folder is added. Nothing on the drive is erased.");
            rb.setEnabled(v.freeKb >= need);
            rb.setPadding(0, dp(8), 0, dp(8));
            g.addView(rb);
        }
        RadioButton ib = new RadioButton(this);
        ib.setId(1000);
        ib.setText("Internal storage\n" + human(internalFreeKb) + " free: " + fit(internalFreeKb, need)
                + "\nCopy it to a computer before switching: internal storage is erased by Plan A.");
        ib.setEnabled(internalFreeKb >= need);
        ib.setPadding(0, dp(8), 0, dp(8));
        g.addView(ib);
        g.setOnCheckedChangeListener((gr, id) -> chosenDest = id);
        body.addView(g);
        screen("3. Where to put the package", "A USB drive is best: Fedora can read it directly.",
                body, true, "Start packing", this::confirm, "Back", this::pickDirs);
    }

    String destPath() {
        if (chosenDest == 1000) return "/data/media/0/S6Migrate";
        if (chosenDest >= 1 && chosenDest <= vols.size()) return vols.get(chosenDest - 1).path + "/S6Migrate";
        return null;
    }

    void confirm() {
        String base = destPath();
        if (base == null) {
            Toast.makeText(this, "Choose a destination.", Toast.LENGTH_SHORT).show();
            return;
        }
        int na = 0, nd = 0, nk = 0;
        for (AppItem a : apps) if (a.selected) { na++; if (a.keystore) nk++; }
        for (DirItem d : dirs) if (d.selected) nd++;
        String out = base + "/" + new SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new Date());
        String msg = na + " apps and " + nd + " folders (" + human(selectedKb()) + ") will be packed into\n" + out
                + "\n\nApps are closed briefly while their data is copied. Nothing is deleted."
                + (nk > 0 ? "\n\n" + nk + " selected app(s) keep data locked to this tablet; their data may not restore." : "");
        new AlertDialog.Builder(this).setTitle("Start packing?").setMessage(msg)
                .setPositiveButton("Start", (d, w) -> pack(out))
                .setNegativeButton("Cancel", null).show();
    }

    // ------------------------------------------------------------------ pack

    /** Plan lines for the current selection on the pickers. */
    void pack(String out) {
        StringBuilder sb = new StringBuilder();
        int n = 0;
        for (AppItem a : apps)
            if (a.selected) {
                sb.append(planLine(a)).append('\n');
                n++;
            }
        for (DirItem d : dirs)
            if (d.selected) {
                sb.append(dirLine(d)).append('\n');
                n++;
            }
        runPack(out, sb.toString(), n, selectedKb(), false);
    }

    /** Android package -> Linux version name, from the shared alternatives.tsv. */
    final Map<String, String> altExact = new HashMap<>();
    final List<String[]> altPrefix = new ArrayList<>();

    void loadAlternatives() {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(getAssets().open("alternatives.tsv")))) {
            String l;
            while ((l = r.readLine()) != null) {
                if (l.startsWith("#") || l.trim().isEmpty()) continue;
                String[] f = l.split("\t");
                if (f.length < 3) continue;
                if (f[0].endsWith("*")) altPrefix.add(new String[]{f[0].substring(0, f[0].length() - 1), f[1]});
                else altExact.put(f[0], f[1]);
            }
        } catch (IOException ignored) {
        }
    }

    String altFor(String pkg) {
        String a = altExact.get(pkg);
        if (a != null) return a;
        for (String[] p : altPrefix) if (pkg.startsWith(p[0])) return p[1];
        return null;
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
        TextView written = text("", 14, false);
        TextView log = text("", 12, false);
        log.setTypeface(Typeface.MONOSPACE);
        body.addView(status);
        body.addView(bar);
        body.addView(written);
        body.addView(log);
        screen(update ? "Updating package" : "Packing", "Keep this screen open. It stays on until packing finishes.",
                body, false, null, null, null, null);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        busy = true; // set before the counter thread starts, or it would exit at once

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
            while (busy) {
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
            ui.post(() -> done(ok, out, all.toString(), update));
        }).start();
    }

    void done(boolean ok, String out, String log, boolean update) {
        busy = false;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(text(ok
                ? (update ? "Your package was updated and verified:\n\n" : "Your package was written and verified:\n\n") + out
                + "\n\nNothing on Android was changed. Keep the drive or card safe until you have switched."
                : "Packing finished with errors. Nothing on Android was changed"
                + (update ? ", and items that failed kept their previous copy." : ".")
                + "\n\nDetails are in " + out + "/pack-warnings.log and below.", 15, false));
        TextView l = text("\n" + log, 12, false);
        l.setTypeface(Typeface.MONOSPACE);
        body.addView(l);
        screen(ok ? "Done \u2713" : "Finished with errors", null, body, false, "Close", this::finish, null, null);
    }
}
