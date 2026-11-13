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
}
