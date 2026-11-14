package com.orailnoor.droiddesk.runtime

import android.content.Context
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.os.ParcelFileDescriptor
import android.system.Os
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileDescriptor
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream
import kotlin.concurrent.thread

/**
 * Android shell rights for Linux tools through Shizuku (lexona-apk-install, lexona-logcat,
 * lexona-screenshot, lexona-input, lexona-adb). Every group sits behind its own switch in
 * Advanced, all off until the user turns them on: a program in Linux runs as Lexona's uid,
 * and the shell user may install apps, read every app's log and tap the screen.
 *
 * Abstract socket "lexona.shell", same uid only. The client sends one JSON line
 * {"op": ..., ...}; the app answers one JSON line {"ok": bool, "error"?: text} and, for
 * streamed ops, the output followed by "\u0000LEXONA-EXIT:<status>\n" (as lexona-host).
 * With "stdin": true ("exec" only) the client then sends its input as frames (4-byte
 * big-endian length, bytes), a frame of length 0 ending the input; the end of the connection
 * always means the client went away and ends the command. The app shuts its side down after
 * the exit mark, so only the mark at the very end of the stream counts.
 */
object ShellBridge {
    private const val TAG = "ShellBridge"
    private const val SOCKET_NAME = "lexona.shell"
    private const val PREFS = "lexona_shell"
    private val MARK = "\u0000LEXONA-EXIT:".toByteArray()

    /** Switch name per op. */
    private val SWITCH = mapOf(
        "install" to "apk", "logcat" to "logcat", "screencap" to "screen", "input" to "screen",
        "exec" to "adb", "pty" to "adb",
    )

    /** The switches Advanced shows, in order. */
    val SWITCHES = listOf("apk", "logcat", "screen", "adb")

    @Volatile private var server: LocalServerSocket? = null

    fun enabled(context: Context, switch: String): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(switch, false)

    fun setEnabled(context: Context, switch: String, on: Boolean) {
        require(switch in SWITCHES) { "unknown switch $switch" }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(switch, on).apply()
    }

    fun switches(context: Context): Map<String, Boolean> = SWITCHES.associateWith { enabled(context, it) }

    fun start(context: Context) {
        if (server != null) return
        synchronized(this) {
            if (server != null) return
            try {
                val socket = LocalServerSocket(SOCKET_NAME)
                server = socket
                val app = context.applicationContext
                thread(name = "shell-bridge", isDaemon = true) { serve(app, socket) }
            } catch (error: Exception) {
                Log.e(TAG, "Could not start the shell bridge", error)
            }
        }
    }

    private fun serve(context: Context, socket: LocalServerSocket) {
        while (server === socket) {
            val client = try {
                socket.accept()
            } catch (error: Exception) {
                if (server !== socket) break
                Thread.sleep(200)
                continue
            }
            if (client.peerCredentials.uid != android.os.Process.myUid()) {
                runCatching { client.close() }
                continue
            }
            thread(name = "shell-bridge-client", isDaemon = true) {
                try {
                    handle(context, client)
                } catch (error: Exception) {
                    Log.d(TAG, "Shell request ended: ${error.message}")
                } finally {
                    // shutdown first: close() alone neither wakes the input watcher blocked in
                    // read nor ends the connection while that read holds the socket.
                    runCatching { client.shutdownOutput() }
                    runCatching { client.shutdownInput() }
                    runCatching { client.close() }
                }
            }
        }
    }

    /** The request line, read byte by byte so that what follows stays in the stream. */
    private fun readLine(input: InputStream): String? {
        val bytes = java.io.ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b < 0) return null
            if (b == '\n'.code) return bytes.toString("UTF-8")
            bytes.write(b)
            if (bytes.size() > 1 shl 20) return null
        }
    }

    private fun handle(context: Context, client: LocalSocket) {
        val input = client.inputStream
        val out = client.outputStream
        val line = readLine(input) ?: return
        // Descriptors sent with the request (APKs for "install").
        val fds: Array<FileDescriptor> = client.ancillaryFileDescriptors?.filterNotNull()?.toTypedArray() ?: emptyArray()
        try {
            val req = runCatching { JSONObject(line) }.getOrNull() ?: return
            val op = req.optString("op")
            fun header(json: JSONObject) {
                out.write((json.toString() + "\n").toByteArray())
                out.flush()
            }
            fun refuse(error: String) = header(JSONObject().put("ok", false).put("error", error))

            val switch = SWITCH[op] ?: return refuse("unknown op $op")
            if (!enabled(context, switch)) return refuse("switch:$switch")
            val state = ShizukuSupport.state(context)
            if (state != "granted") return refuse("shizuku:$state")

            when (op) {
                "install" -> install(context, req, fds, out, ::header)
                "pty" -> pty(context, req, client, ::header)
                else -> {
                    val command = when (op) {
                        "logcat" -> "exec logcat " + args(req) + " 2>&1"
                        "screencap" -> "exec screencap -p 2>/dev/null"
                        "input" -> "input " + args(req) + " 2>&1"
                        // As adb shell: the words joined, the shell parses them. The group puts
                        // stderr of every command in a list on the output, not only the last's.
                        else -> "{ " + words(req).joinToString(" ").ifBlank { "true" } + "\n} 2>&1"
                    }
                    header(JSONObject().put("ok", true))
                    stream(command, input, op == "exec" && req.optBoolean("stdin"), out)
                }
            }
        } finally {
            fds.forEach { runCatching { Os.close(it) } }
        }
    }

    private fun words(req: JSONObject): List<String> {
        val array = req.optJSONArray("args") ?: JSONArray()
        return (0 until array.length()).map { array.optString(it) }
    }

    private fun args(req: JSONObject) = words(req).joinToString(" ") { ShizukuSupport.quote(it) }

    /** Fills [buffer] from [input]; false when the stream ends first. */
    private fun readFully(input: InputStream, buffer: ByteArray, length: Int): Boolean {
        var done = 0
        while (done < length) {
            val n = input.read(buffer, done, length - done)
            if (n < 0) return false
            done += n
        }
        return true
    }

    /**
     * Copies the client's input frames (4-byte big-endian length, then the bytes) to the
     * command; a frame of length 0 is the end of the input. The connection's own end, before
     * or after that frame, is the client going away.
     */
    private fun feedFrames(input: InputStream, stdin: OutputStream) {
        val head = ByteArray(4)
        val buffer = ByteArray(64 * 1024)
        var open = true
        try {
            while (readFully(input, head, 4)) {
                val length = java.nio.ByteBuffer.wrap(head).int
                if (length == 0) {
                    runCatching { stdin.close() }
                    open = false
                    continue
                }
                if (length < 0 || !open) return
                var left = length
                while (left > 0) {
                    val n = input.read(buffer, 0, minOf(left, buffer.size))
                    if (n < 0) return
                    stdin.write(buffer, 0, n)
                    stdin.flush()
                    left -= n
                }
            }
        } finally {
            runCatching { stdin.close() }
        }
    }

    /**
     * Runs [command] as the shell user and copies its output to [out], then the exit mark.
     * With [feed], the client's input frames go to the command's input; without, nothing
     * comes. Either way the end of the connection (Ctrl-C, the client killed) ends the command.
     */
    private fun stream(command: String, input: InputStream, feed: Boolean, out: OutputStream) {
        val process = ShizukuSupport.newProcess(command)
        Log.d(TAG, "started: $command (input ${if (feed) "fed" else "closed"})")
        // Calls on the process go through Shizuku's binder and throw once Shizuku is gone; an
        // exception in the watcher thread would end the whole app, so every call is guarded.
        fun kill() = runCatching { process.destroy() }
        if (!feed) runCatching { process.outputStream.close() }
        val feeder = thread(name = "shell-bridge-input", isDaemon = true) {
            try {
                if (feed) feedFrames(input, process.outputStream)
                else while (input.read() >= 0) Unit // nothing comes: an end is the client gone
            } catch (error: Throwable) {
                Log.d(TAG, "input ended: ${error.message}")
            }
            kill()
        }
        var clientGone = false
        var total = 0L
        try {
            process.inputStream.use { source ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = source.read(buffer)
                    if (n < 0) break
                    try {
                        out.write(buffer, 0, n)
                        out.flush()
                    } catch (error: java.io.IOException) {
                        clientGone = true
                        break
                    }
                    total += n
                }
            }
        } catch (error: Exception) {
            Log.d(TAG, "output failed: ${error.message}")
            kill()
        }
        if (clientGone) kill()
        Log.d(TAG, "output ended after $total bytes, client gone: $clientGone")
        val status = runCatching { process.waitFor() }.getOrDefault(255)
        Log.d(TAG, "exit status $status")
        if (feed) runCatching { process.outputStream.close() }
        feeder.interrupt()
        if (!clientGone) {
            runCatching {
                out.write(MARK + "$status\n".toByteArray())
                out.flush()
            }
        }
    }

    /**
     * APKs from Linux: the client sends them as descriptors with the request ("names" in the
     * same order). One install session takes them all, so split APKs work.
     */
    private fun install(
        context: Context,
        req: JSONObject,
        fds: Array<FileDescriptor>,
        out: OutputStream,
        header: (JSONObject) -> Unit,
    ) {
        val names = words(JSONObject().put("args", req.optJSONArray("names") ?: JSONArray()))
        if (fds.isEmpty() || fds.size != names.size) {
            header(JSONObject().put("ok", false).put("error", "no APK received"))
            return
        }
        header(JSONObject().put("ok", true))
        fun say(text: String) {
            out.write((text + "\n").toByteArray())
            out.flush()
        }
        fun finish(status: Int) {
            out.write(MARK + "$status\n".toByteArray())
            out.flush()
        }
        val sizes = fds.map { Os.fstat(it).st_size }
        val (createStatus, created) = ShizukuSupport.shell("pm install-create -r -S ${sizes.sum()}")
        val session = Regex("\\[(\\d+)]").find(created)?.groupValues?.get(1)
        if (createStatus != 0 || session == null) {
            say(created.trim())
            return finish(1)
        }
        try {
            for (i in fds.indices) {
                val name = names[i].replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "base.apk" }
                val process = ShizukuSupport.newProcess("pm install-write -S ${sizes[i]} $session ${ShizukuSupport.quote(name)} - 2>&1")
                // Our own copy of the descriptor: the stream closes it, the array's copy closes later.
                ParcelFileDescriptor.dup(fds[i]).use { pfd ->
                    FileInputStream(pfd.fileDescriptor).use { apk ->
                        Os.lseek(pfd.fileDescriptor, 0, android.system.OsConstants.SEEK_SET)
                        process.outputStream.use { apk.copyTo(it, 256 * 1024) }
                    }
                }
                val written = process.inputStream.bufferedReader().use { it.readText() }.trim()
                val status = process.waitFor()
                if (status != 0 || !written.contains("Success")) {
                    say("$name: $written")
                    ShizukuSupport.shell("pm install-abandon $session")
                    return finish(1)
                }
                say("$name: ${sizes[i]} bytes")
            }
            val (status, committed) = ShizukuSupport.shell("pm install-commit $session", timeoutSeconds = 300)
            say(committed.trim())
            Log.i(TAG, "Install from Linux (${names.joinToString()}): ${committed.trim()}")
            finish(if (status == 0 && committed.contains("Success")) 0 else 1)
        } catch (error: Exception) {
            runCatching { ShizukuSupport.shell("pm install-abandon $session") }
            throw error
        }
    }

    /** An interactive shell: the pty master from the shell-side service goes to the client. */
    private fun pty(context: Context, req: JSONObject, client: LocalSocket, header: (JSONObject) -> Unit) {
        val service = AndroidDataBridge.service(context)
            ?: return header(JSONObject().put("ok", false).put("error", "shizuku:service"))
        val env = words(JSONObject().put("args", req.optJSONArray("env") ?: JSONArray()))
            .filter { Regex("^(TERM|COLORTERM|LANG|LC_[A-Z]+)=").containsMatchIn(it) }
        val master = runCatching {
            service.openShell(req.optInt("rows", 24), req.optInt("cols", 80), env.toTypedArray())
        }.getOrNull() ?: return header(JSONObject().put("ok", false).put("error", "no pty"))
        master.use {
            client.setFileDescriptorsForSend(arrayOf(it.fileDescriptor))
            header(JSONObject().put("ok", true))
            client.setFileDescriptorsForSend(null)
        }
    }
}
