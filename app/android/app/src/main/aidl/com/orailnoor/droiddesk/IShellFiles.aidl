package com.orailnoor.droiddesk;

import android.os.ParcelFileDescriptor;

// File access as the shell user (Shizuku UserService), only below Android/data and Android/obb.
interface IShellFiles {
    // Shizuku calls this transaction to end the service.
    void destroy() = 16777114;

    // One line per entry: "d|f<TAB>size<TAB>mtime_ms<TAB>name"; null when path is not a directory.
    String list(String path) = 1;

    // "d|f<TAB>size<TAB>mtime_ms", or null when it does not exist.
    String stat(String path) = 2;

    // mode: "r", "w" (create/truncate) or "rw".
    ParcelFileDescriptor open(String path, String mode) = 3;

    boolean mkdir(String path) = 4;

    // Files and empty directories; recursive=true for whole trees.
    boolean delete(String path, boolean recursive) = 5;

    boolean rename(String from, String to) = 6;
}
