package com.vyvrnc.execprobe;

import android.content.Context;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Consumer;

/** Runs each way of starting a program once and reports the result (log tag ExecProbe). */
final class Probe {
    static final String TAG = "ExecProbe";
    private static final String LINKER = "/system/bin/linker64";

    private final Context context;
    private final Consumer<String> out;
    private String preload; // LD_PRELOAD for the hook cases, null for none

    Probe(Context context, Consumer<String> out) {
        this.context = context;
        this.out = out;
    }

    private void line(String s) {
        Log.i(TAG, s);
        out.accept(s);
    }

    private File extract(String asset, File dir) throws Exception {
        File file = new File(dir, asset);
        file.getParentFile().mkdirs();
        try (InputStream in = context.getAssets().open(asset); FileOutputStream os = new FileOutputStream(file)) {
            byte[] buf = new byte[65536];
            for (int n; (n = in.read(buf)) > 0; ) os.write(buf, 0, n);
        }
        file.setExecutable(true, false);
        return file;
    }

    private void run(String name, String... cmd) {
        try {
            ProcessBuilder pb = new ProcessBuilder(Arrays.asList(cmd)).redirectErrorStream(true);
            if (preload != null) pb.environment().put("LD_PRELOAD", preload);
            else pb.environment().remove("LD_PRELOAD");
            Process p = pb.start();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            InputStream in = p.getInputStream();
            byte[] chunk = new byte[4096];
            for (int n; (n = in.read(chunk)) > 0; ) buf.write(chunk, 0, n);
            int rc = p.waitFor();
            line(name + ": rc=" + rc + " out=" + buf.toString().trim().replace('\n', '|'));
        } catch (Exception e) {
            line(name + ": EXCEPTION " + e.getMessage());
        }
    }

    void probe() {
        try {
            String lib = context.getApplicationInfo().nativeLibraryDir;
            File data = new File(context.getFilesDir(), "probe");
            line("targetSdk=" + context.getApplicationInfo().targetSdkVersion + " nativeLibraryDir=" + lib);
            line("selinux=" + readFirstLine("/proc/self/attr/current"));
            File libc = extract("glibc/libc.so.6", data);
            File glibcHello = extract("hello-glibc", data);
            File bionic = extract("hello-bionic", data);
            File hook = extract("libpreload.so", data);
            String libPath = libc.getParent();
            String ld = lib + "/libld.so";
            String b = bionic.getPath();

            preload = null;
            run("A direct exec of app data file (expect EACCES)", b);
            run("B packaged lib*.so exec (control)", lib + "/libhello.so");
            run("C glibc program via libld.so", ld, "--library-path", libPath, glibcHello.getPath());
            run("D glibc program spawning glibc child via libld.so", ld, "--library-path", libPath,
                glibcHello.getPath(), "spawn", ld, libPath, glibcHello.getPath());
            run("E bionic program via linker64", LINKER, b);
            run("F glibc direct exec of data file (expect EACCES)", ld, "--library-path", libPath,
                glibcHello.getPath(), "spawn-direct", glibcHello.getPath());
            run("G bionic via linker64, identity without hook", LINKER, b, "info");
            run("H bionic via linker64 spawning data child without hook (expect fail)", LINKER, b,
                "spawn-direct", b, "info");

            preload = hook.getPath();
            run("I app-data preload under linker64 (ctor + identity)", LINKER, b, "info");
            run("J hooked posix_spawn of data child", LINKER, b, "spawn-direct", b, "info");
            run("K hooked execv of data child", LINKER, b, "exec-direct", b, "info");
            run("L hooked grandchild (spawn -> spawn -> info)", LINKER, b, "spawn-direct", b,
                "spawn-direct", b, "info");
            run("M preload into /system/bin/sh, sh runs data program", "/system/bin/sh", "-c",
                b + " info; echo sh-rc=$?");
            preload = lib + "/libpreload.so";
            run("N preload from nativeLibraryDir", LINKER, b, "spawn-direct", b, "info");
            preload = null;
            line("DONE");
        } catch (Exception e) {
            line("FAILED " + e);
        }
    }

    private static String readFirstLine(String path) {
        try (InputStream in = new java.io.FileInputStream(path)) {
            byte[] buf = new byte[256];
            int n = in.read(buf);
            return n > 0 ? new String(buf, 0, n).trim() : "?";
        } catch (Exception e) {
            return "? " + e.getMessage();
        }
    }
}
