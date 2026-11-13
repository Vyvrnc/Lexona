package com.orailnoor.droiddesk.runtime

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.os.IBinder
import android.util.Log
import com.orailnoor.droiddesk.IShellFiles
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Android/data and Android/obb for Linux (lexona-android-data, a WebDAV server for Thunar).
 * Needs Shizuku with Lexona allowed: ShellFilesService runs as the shell user and opens the
 * files; their descriptors go to the Linux client over the abstract socket
 * "lexona.android-data" (same uid only), which then reads and writes them itself.
 *
 * Protocol: one JSON line per request {"op": list|stat|open|mkdir|delete|rename, ...}; one JSON
 * line back {"ok": bool, ...}. For "open" the descriptor travels with that reply (SCM_RIGHTS).
 */
object AndroidDataBridge {
    private const val TAG = "AndroidDataBridge"
    private const val SOCKET_NAME = "lexona.android-data"

    @Volatile private var server: LocalServerSocket? = null
    @Volatile private var files: IShellFiles? = null
    private var connection: ServiceConnection? = null

    fun start(context: Context) {
        if (server != null) return
        synchronized(this) {
            if (server != null) return
            try {
                val socket = LocalServerSocket(SOCKET_NAME)
                server = socket
                val app = context.applicationContext
                thread(name = "android-data-bridge", isDaemon = true) { serve(app, socket) }
            } catch (error: Exception) {
                Log.e(TAG, "Could not start the Android data bridge", error)
            }
        }
    }

    /** The shell-side service (also ShellBridge's), bound through Shizuku on first use (up to 10 s). */
    private val serviceLock = Any()

    fun service(context: Context): IShellFiles? = synchronized(serviceLock) { bindService(context) }

    private fun bindService(context: Context): IShellFiles? {
        files?.takeIf { it.asBinder().isBinderAlive }?.let { return it }
        if (ShizukuSupport.state(context) != "granted") return null
        val ready = CountDownLatch(1)
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                files = binder?.takeIf { it.pingBinder() }?.let { IShellFiles.Stub.asInterface(it) }
                ready.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName?) {
                files = null
            }
        }
        val args = Shizuku.UserServiceArgs(ComponentName(context.packageName, ShellFilesService::class.java.name))
            .daemon(false)
            .processNameSuffix("shellfiles")
            .debuggable(false)
            .version(2)
        runCatching {
            connection?.let { Shizuku.unbindUserService(args, it, true) }
            Shizuku.bindUserService(args, conn)
            connection = conn
        }.onFailure { Log.w(TAG, "bindUserService: ${it.message}"); return null }
        ready.await(10, TimeUnit.SECONDS)
        return files
    }

    private fun serve(context: Context, socket: LocalServerSocket) {
        while (server === socket) {
            val client = try {
                socket.accept()
            } catch (error: Exception) {
                continue
            }
            if (client.peerCredentials.uid != android.os.Process.myUid()) {
                runCatching { client.close() }
                continue
            }
            thread(name = "android-data-client", isDaemon = true) {
                try {
                    handle(context, client)
                } catch (error: Exception) {
                    Log.d(TAG, "Android data request ended: ${error.message}")
                } finally {
                    runCatching { client.close() }
                }
            }
        }
    }

    /** One connection, many requests (the WebDAV server keeps it open). */
    private fun handle(context: Context, client: LocalSocket) {
        val reader = client.inputStream.bufferedReader()
        val out = client.outputStream
        fun reply(json: JSONObject) {
            out.write((json.toString() + "\n").toByteArray())
            out.flush()
        }
        while (true) {
            val line = reader.readLine() ?: return
            val req = runCatching { JSONObject(line) }.getOrNull() ?: return
            val svc = service(context)
            if (svc == null) {
                reply(JSONObject().put("ok", false).put("error", "shizuku:" + ShizukuSupport.state(context)))
                continue
            }
            val path = req.optString("path")
            when (req.optString("op")) {
                "list" -> {
                    val text = svc.list(path)
                    reply(JSONObject().put("ok", text != null).put("entries", text ?: ""))
                }
                "stat" -> {
                    val text = svc.stat(path)
                    reply(JSONObject().put("ok", text != null).put("stat", text ?: ""))
                }
                "open" -> {
                    val pfd = svc.open(path, req.optString("mode", "r"))
                    if (pfd == null) {
                        reply(JSONObject().put("ok", false))
                    } else {
                        pfd.use {
                            client.setFileDescriptorsForSend(arrayOf(it.fileDescriptor))
                            reply(JSONObject().put("ok", true))
                            client.setFileDescriptorsForSend(null)
                        }
                    }
                }
                "mkdir" -> reply(JSONObject().put("ok", svc.mkdir(path)))
                "delete" -> reply(JSONObject().put("ok", svc.delete(path, req.optBoolean("recursive"))))
                "rename" -> reply(JSONObject().put("ok", svc.rename(path, req.optString("to"))))
                else -> reply(JSONObject().put("ok", false).put("error", "unknown op"))
            }
        }
    }
}
