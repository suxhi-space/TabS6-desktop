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
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

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
    }

    static class Vol {
        String path, fs, kind;
        long freeKb;
    }

    final List<AppItem> apps = new ArrayList<>();
    final List<DirItem> dirs = new ArrayList<>();
    final List<Vol> vols = new ArrayList<>();
    long internalFreeKb;
    String cryptoMode = "", probeHash = "";
    boolean metadataEncryption, keystoreChecked;
    int chosenDest = -1;

    final Handler ui = new Handler(Looper.getMainLooper());
    boolean busy;
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
        pickApps();
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

    void pickApps() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        if (!keystoreChecked) {
            body.addView(text("(Keystore check unavailable: no warnings about apps whose data cannot move.)", 12, false));
        }
        for (AppItem a : apps) {
            body.addView(row(a.icon, a.label, a.pkg + "  ·  " + human(a.kb),
                    a.keystore ? "Data is locked to this tablet's security chip: the app moves, its data may not" : null,
                    a.selected, c -> {
                        a.selected = c;
                        updateSpace();
                    }));
        }
        screen("1. Apps to take along", "Only apps you installed are listed. Google and Samsung apps stay behind.",
                body, true, "Next", this::pickDirs, "Cancel", this::finish);
    }

    void pickDirs() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        for (DirItem d : dirs) {
            body.addView(row(null, d.name, human(d.kb), null, d.selected, c -> {
                d.selected = c;
                updateSpace();
            }));
        }
        screen("2. Folders to take along", "From internal storage (photos, downloads, documents...).",
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

    void pack(String out) {
        final int total;
        File plan = new File(getCacheDir(), "plan.txt");
        try (FileOutputStream os = new FileOutputStream(plan)) {
            int n = 0;
            StringBuilder sb = new StringBuilder();
            for (AppItem a : apps)
                if (a.selected) {
                    sb.append("APP|").append(a.pkg).append('|').append(a.uid).append('|')
                            .append(a.keystore ? "keystore" : "").append('\n');
                    n++;
                }
            for (DirItem d : dirs)
                if (d.selected) {
                    sb.append("DIR|").append(d.name).append('\n');
                    n++;
                }
            os.write(sb.toString().getBytes("UTF-8"));
            total = n;
        } catch (IOException e) {
            message("Error", "Could not write the plan: " + e.getMessage());
            return;
        }

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView status = text("Starting...", 16, true);
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(total);
        TextView log = text("", 12, false);
        log.setTypeface(Typeface.MONOSPACE);
        body.addView(status);
        body.addView(bar);
        body.addView(log);
        screen("Packing", "Keep this screen open. It stays on until packing finishes.", body, false,
                null, null, null, null);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        busy = true;

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
            ui.post(() -> done(ok, out, all.toString()));
        }).start();
    }

    void done(boolean ok, String out, String log) {
        busy = false;
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.addView(text(ok
                ? "Your package was written and verified:\n\n" + out
                + "\n\nNothing on Android was changed. Keep the drive or card safe until you have switched."
                : "Packing finished with errors. Nothing on Android was changed.\n\nDetails are in "
                + out + "/pack-warnings.log and below.", 15, false));
        TextView l = text("\n" + log, 12, false);
        l.setTypeface(Typeface.MONOSPACE);
        body.addView(l);
        screen(ok ? "Done ✓" : "Finished with errors", null, body, false, "Close", this::finish, null, null);
    }
}
