package com.orailnoor.droiddesk.runtime

import android.content.Context
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.util.Log
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * Runs a command outside the caller's process tree: lexona-host CMD ARGS…
 *
 * A Claude Code session in Lexona runs under proot (ptrace). apt forks children that stay in
 * ptrace_stop there, and a nested proot (debian-run) cannot attach at all (Fold 7, 2.0.6). The
 * app starts the command itself, as a child of the app with Termux's environment, so
 * "lexona-host debian-run apt-get install -y ./x.deb" works from such a session.
 *
 * Protocol on the abstract socket "lexona.host" (same uid only): one JSON line
 * {"argv": [...], "cwd": "..."}; the reply is the command's output (stdout and stderr), then
 * "\u0000LEXONA-EXIT:<status>\n". The command has no stdin. It keeps running when the client
 * goes away (an apt run is not cut in half).
 */
object HostBridge {
    private const val TAG = "HostBridge"
    private const val SOCKET_NAME = "lexona.host"
    const val EXIT_MARK = "\u0000LEXONA-EXIT:"

    @Volatile private var server: LocalServerSocket? = null

    fun start(context: Context) {
        if (server != null) return
        synchronized(this) {
            if (server != null) return
            try {
                val socket = LocalServerSocket(SOCKET_NAME)
                server = socket
                val app = context.applicationContext
                thread(name = "host-bridge", isDaemon = true) { serve(app, socket) }
                Log.i(TAG, "Host bridge started")
            } catch (error: Exception) {
                Log.e(TAG, "Could not start the host bridge", error)
            }
        }
    }

    private fun serve(context: Context, socket: LocalServerSocket) {
        while (server === socket) {
            val client = try {
                socket.accept()
            } catch (error: Exception) {
                if (server === socket) Log.w(TAG, "Host bridge accept failed", error)
                continue
            }
            if (client.peerCredentials.uid != android.os.Process.myUid()) {
                Log.w(TAG, "Rejected host request from uid ${client.peerCredentials.uid}")
                runCatching { client.close() }
                continue
            }
            thread(name = "host-bridge-client", isDaemon = true) {
                try {
                    handle(context, client)
                } catch (error: Exception) {
                    Log.d(TAG, "Host request ended: ${error.message}")
                } finally {
                    runCatching { client.close() }
                }
            }
        }
    }

    private fun handle(context: Context, client: LocalSocket) {
        val output = client.outputStream
        val line = client.inputStream.bufferedReader().readLine() ?: return
        val request = JSONObject(line)
        val array = request.optJSONArray("argv")
        val argv = (0 until (array?.length() ?: 0)).map { array!!.getString(it) }
        if (argv.isEmpty()) {
            output.write("lexona-host: no command\n${EXIT_MARK}2\n".toByteArray())
            return
        }
        val cwd = request.optString("cwd").takeIf { it.isNotEmpty() }?.let(::File)
        Log.i(TAG, "Running ${argv.first()} (${argv.size - 1} arguments)")
        val process = LinuxRuntime(context).hostProcess(argv, cwd)
        process.outputStream.close()
        var clientGone = false
        val buffer = ByteArray(8192)
        process.inputStream.use { input ->
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (!clientGone) {
                    try {
                        output.write(buffer, 0, n)
                        output.flush()
                    } catch (error: Exception) {
                        clientGone = true  // keep draining: the command runs to its end
                    }
                }
            }
        }
        val status = process.waitFor()
        if (!clientGone) output.write("$EXIT_MARK$status\n".toByteArray())
    }
}
