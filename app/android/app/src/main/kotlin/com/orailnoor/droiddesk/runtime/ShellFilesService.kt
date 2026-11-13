package com.orailnoor.droiddesk.runtime

import android.os.ParcelFileDescriptor
import com.orailnoor.droiddesk.IShellFiles
import java.io.File
import kotlin.system.exitProcess

/**
 * Runs as the shell user in its own process (Shizuku UserService) and opens files that apps
 * may not reach since Android 11: /storage/emulated/0/Android/data and /Android/obb. Nothing
 * outside those two trees. The app passes the opened descriptors on to Linux (AndroidDataBridge).
 */
class ShellFilesService : IShellFiles.Stub() {
    companion object {
        private val ROOTS = listOf("/storage/emulated/0/Android/data", "/storage/emulated/0/Android/obb")

        /** The canonical file when it lies in one of ROOTS (or is one), else null. */
        fun allowed(path: String?): File? {
            if (path.isNullOrEmpty() || path.contains('\u0000')) return null
            val file = runCatching { File(path).canonicalFile }.getOrNull() ?: return null
            val p = file.path
            return file.takeIf { ROOTS.any { root -> p == root || p.startsWith("$root/") } }
        }
    }

    override fun destroy() {
        exitProcess(0)
    }

    override fun list(path: String?): String? {
        val dir = allowed(path) ?: return null
        val entries = dir.listFiles() ?: return null
        return entries.joinToString("\n") { e ->
            "${if (e.isDirectory) "d" else "f"}\t${if (e.isDirectory) 0 else e.length()}\t${e.lastModified()}\t${e.name}"
        }
    }

    override fun stat(path: String?): String? {
        val f = allowed(path) ?: return null
        if (!f.exists()) return null
        return "${if (f.isDirectory) "d" else "f"}\t${if (f.isDirectory) 0 else f.length()}\t${f.lastModified()}"
    }

    override fun open(path: String?, mode: String?): ParcelFileDescriptor? {
        val f = allowed(path) ?: return null
        val flags = when (mode) {
            "w" -> ParcelFileDescriptor.MODE_WRITE_ONLY or ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_TRUNCATE
            "rw" -> ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE
            else -> ParcelFileDescriptor.MODE_READ_ONLY
        }
        return runCatching { ParcelFileDescriptor.open(f, flags) }.getOrNull()
    }

    override fun mkdir(path: String?): Boolean = allowed(path)?.mkdirs() == true

    override fun delete(path: String?, recursive: Boolean): Boolean {
        val f = allowed(path) ?: return false
        if (ROOTS.contains(f.path)) return false  // never the roots themselves
        return if (recursive) f.deleteRecursively() else f.delete()
    }

    override fun rename(from: String?, to: String?): Boolean {
        val a = allowed(from) ?: return false
        val b = allowed(to) ?: return false
        if (ROOTS.contains(a.path)) return false
        return a.renameTo(b)
    }

    /**
     * /system/bin/sh on a new pty, through Termux's JNI (libtermux.so from the APK; the service
     * loads it from the app's library directory). Returns the master; the child is reaped here.
     */
    override fun openShell(rows: Int, cols: Int, env: Array<String>?): ParcelFileDescriptor? =
        runCatching { shell(rows, cols, env) }.getOrNull()

    private fun shell(rows: Int, cols: Int, env: Array<String>?): ParcelFileDescriptor? {
        val jni = runCatching { Class.forName("com.termux.terminal.JNI") }.getOrNull() ?: return null
        val create = jni.getDeclaredMethod(
            "createSubprocess", String::class.java, String::class.java, Array<String>::class.java,
            Array<String>::class.java, IntArray::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
        ).apply { isAccessible = true }
        val waitFor = jni.getDeclaredMethod("waitFor", Int::class.javaPrimitiveType).apply { isAccessible = true }
        // Termux's createSubprocess clears the environment: pass the service's own (the shell
        // user's, as from adb) plus the client's TERM and friends.
        val vars = LinkedHashMap(System.getenv())
        env.orEmpty().forEach { entry ->
            val i = entry.indexOf('=')
            if (i > 0) vars[entry.substring(0, i)] = entry.substring(i + 1)
        }
        if (vars["HOME"].isNullOrEmpty() || vars["HOME"] == "/") vars["HOME"] = "/data/local/tmp"
        val pid = IntArray(1)
        val fd = runCatching {
            create.invoke(
                null, "/system/bin/sh", vars["HOME"], arrayOf("-sh"),
                vars.map { "${it.key}=${it.value}" }.toTypedArray(), pid, rows.coerceAtLeast(1), cols.coerceAtLeast(1),
            ) as Int
        }.getOrNull() ?: return null
        Thread { runCatching { waitFor.invoke(null, pid[0]) } }.apply { isDaemon = true; start() }
        return ParcelFileDescriptor.adoptFd(fd)
    }
}
