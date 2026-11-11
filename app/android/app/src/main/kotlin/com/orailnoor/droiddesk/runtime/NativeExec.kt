package com.orailnoor.droiddesk.runtime

import android.content.Context
import java.io.File
import java.io.RandomAccessFile

/**
 * How the app starts programs from its own data dir. From targetSdk 29 SELinux refuses to exec
 * those files (W^X), but /system/bin/linker64 still loads them (exec-probe, Galaxy A16): the
 * first program goes through linker64, and the socket hook (LD_PRELOAD, DROIDDESK_LINKER_EXEC=1)
 * does the same for everything it starts. Same decisions as make_exec_plan in socket_hook.c.
 * With targetSdk 28 commands stay as they are.
 */
object NativeExec {
    const val LINKER = "/system/bin/linker64"
    private const val TERMUX_PREFIX = "/data/data/com.termux/files/usr"

    fun linkerExec(context: Context): Boolean = context.applicationInfo.targetSdkVersion >= 29

    /** The command to give ProcessBuilder for [argv]. */
    fun command(context: Context, argv: List<String>): List<String> {
        if (!linkerExec(context) || argv.isEmpty()) return argv
        val prefix = File(context.filesDir, "usr").absolutePath
        var current = argv
        repeat(4) {
            val path = current[0]
            if (!underAppData(path)) return current
            val file = File(path)
            when (kind(file)) {
                Kind.BIONIC -> return listOf(LINKER) + current
                Kind.SCRIPT -> {
                    val (interp, arg) = shebang(file) ?: return current
                    val real = if (interp.startsWith(TERMUX_PREFIX)) prefix + interp.removePrefix(TERMUX_PREFIX) else interp
                    current = listOfNotNull(real, arg) + current
                }
                Kind.OTHER -> return current
            }
        }
        return current
    }

    /**
     * Shell path and argv for a terminal session (TerminalSession takes argv[0] separately):
     * linker64 with [argv0, program, args…], so a login shell keeps "-bash" as argv[0].
     */
    fun terminal(context: Context, program: String, argv0: String, args: List<String> = emptyList()): Pair<String, Array<String>> {
        if (!linkerExec(context)) return program to (listOf(argv0) + args).toTypedArray()
        val cmd = command(context, listOf(program) + args)
        if (cmd.firstOrNull() != LINKER) return program to (listOf(argv0) + args).toTypedArray()
        // cmd = linker64, program-or-interpreter, …: argv0 replaces linker64's own name.
        return LINKER to (listOf(argv0) + cmd.drop(1)).toTypedArray()
    }

    private fun underAppData(path: String) = path.startsWith("/data/user/") || path.startsWith("/data/data/")

    private enum class Kind { BIONIC, SCRIPT, OTHER }

    private fun kind(file: File): Kind = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val head = ByteArray(64)
            val n = raf.read(head)
            if (n >= 2 && head[0] == '#'.code.toByte() && head[1] == '!'.code.toByte()) return Kind.SCRIPT
            if (n < 64 || head[0] != 0x7f.toByte() || head[1] != 'E'.code.toByte() || head[4] != 2.toByte()) return Kind.OTHER
            val phoff = le64(head, 32)
            val phentsize = le16(head, 54)
            val phnum = le16(head, 56)
            val ph = ByteArray(56)
            for (i in 0 until minOf(phnum, 64)) {
                raf.seek(phoff + i.toLong() * phentsize)
                if (raf.read(ph) != ph.size) break
                if (le32(ph, 0) != 3) continue // PT_INTERP
                val off = le64(ph, 8)
                val size = le64(ph, 32).toInt()
                if (size <= 0 || size > 255) return Kind.OTHER
                val interp = ByteArray(size)
                raf.seek(off)
                raf.readFully(interp)
                return if (String(interp).contains("linker64")) Kind.BIONIC else Kind.OTHER
            }
            Kind.OTHER
        }
    }.getOrDefault(Kind.OTHER)

    private fun shebang(file: File): Pair<String, String?>? = runCatching {
        val line = file.bufferedReader().use { it.readLine() } ?: return null
        val body = line.removePrefix("#!").trim()
        if (body.isEmpty()) return null
        val space = body.indexOfFirst { it == ' ' || it == '\t' }
        if (space < 0) body to null else body.substring(0, space) to body.substring(space).trim().ifEmpty { null }
    }.getOrNull()

    private fun le16(b: ByteArray, o: Int) = (b[o].toInt() and 0xff) or ((b[o + 1].toInt() and 0xff) shl 8)
    private fun le32(b: ByteArray, o: Int) = le16(b, o) or (le16(b, o + 2) shl 16)
    private fun le64(b: ByteArray, o: Int) = (le32(b, o).toLong() and 0xffffffffL) or (le32(b, o + 4).toLong() shl 32)
}
