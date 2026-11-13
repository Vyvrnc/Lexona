package com.orailnoor.droiddesk.runtime

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Optional Android shell access (uid 2000) through Shizuku, for power users: the same rights
 * as adb, without a computer once Shizuku runs. Works with any app that implements the
 * Shizuku API (Shizuku-Next, the original, Porter with its compatibility app, Shizuku+'s
 * drop-in build). Shizuku shows its own permission dialog for Lexona; nothing happens before.
 */
object ShizukuSupport {
    private const val TAG = "ShizukuSupport"
    private const val MANAGER = "moe.shizuku.privileged.api"
    const val REQUEST_CODE = 4711

    /** "missing" (no Shizuku app), "stopped" (app there, service not started), "denied",
     *  "granted", or "old" (pre-v11 Shizuku without the permission API). */
    fun state(context: Context): String {
        val installed = runCatching { context.packageManager.getPackageInfo(MANAGER, 0) }.isSuccess
        val alive = runCatching { Shizuku.pingBinder() }.getOrDefault(false)
        if (!alive) return if (installed) "stopped" else "missing"
        if (runCatching { Shizuku.isPreV11() }.getOrDefault(false)) return "old"
        return if (runCatching { Shizuku.checkSelfPermission() }.getOrDefault(-1) == PackageManager.PERMISSION_GRANTED)
            "granted" else "denied"
    }

    /** Shizuku's own dialog; the answer arrives through [onPermissionResult]. */
    fun requestPermission(onPermissionResult: (Boolean) -> Unit) {
        val listener = object : Shizuku.OnRequestPermissionResultListener {
            override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
                if (requestCode != REQUEST_CODE) return
                Shizuku.removeRequestPermissionResultListener(this)
                onPermissionResult(grantResult == PackageManager.PERMISSION_GRANTED)
            }
        }
        Shizuku.addRequestPermissionResultListener(listener)
        runCatching { Shizuku.requestPermission(REQUEST_CODE) }.onFailure {
            Shizuku.removeRequestPermissionResultListener(listener)
            onPermissionResult(false)
        }
    }

    /**
     * One shell command as uid 2000. Shizuku's newProcess is not public in API 13 (it
     * recommends a UserService), but it is the documented way for plain shell commands and
     * every Shizuku app ships it. Returns (exit status, output).
     */
    fun shell(command: String, timeoutSeconds: Long = 30): Pair<Int, String> {
        val method = Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java,
        ).apply { isAccessible = true }
        val process = method.invoke(null, arrayOf("sh", "-c", "$command 2>&1"), null, null) as Process
        process.outputStream.close()
        // Shizuku's remote process has no timed waitFor (exitValue throws "process hasn't
        // exited" while it runs), so a watchdog destroys it and the plain waitFor() blocks.
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        val timedOut = java.util.concurrent.atomic.AtomicBoolean(false)
        val watchdog = Thread {
            try {
                Thread.sleep(TimeUnit.SECONDS.toMillis(timeoutSeconds))
                if (!done.get()) {
                    timedOut.set(true)
                    process.destroy()
                }
            } catch (_: InterruptedException) {
            }
        }.apply { isDaemon = true; start() }
        val output = runCatching { process.inputStream.bufferedReader().readText() }.getOrDefault("")
        val status = process.waitFor()
        done.set(true)
        watchdog.interrupt()
        return (if (timedOut.get()) 124 else status) to output
    }

    /** The child process limit off, as lexona-unlimit does over Wireless debugging. */
    fun unlimitPhantomProcesses(context: Context, undo: Boolean): Pair<Boolean, String> {
        val marker = File(context.filesDir, "home/.config/lexona/phantom-unlocked")
        val commands = if (undo) {
            "settings delete global settings_enable_monitor_phantom_procs; " +
                "device_config delete activity_manager max_phantom_processes; " +
                "device_config set_sync_disabled_for_tests none; echo done"
        } else {
            "settings put global settings_enable_monitor_phantom_procs false && " +
                "device_config set_sync_disabled_for_tests persistent && " +
                "device_config put activity_manager max_phantom_processes 2147483647 && " +
                "echo max=$(device_config get activity_manager max_phantom_processes) " +
                "mon=$(settings get global settings_enable_monitor_phantom_procs)"
        }
        val (status, output) = runCatching { shell(commands) }.getOrElse { return false to (it.message ?: "Shizuku error") }
        Log.i(TAG, "Phantom limit ${if (undo) "default" else "off"}: status $status, ${output.trim()}")
        if (status != 0) return false to output.trim()
        if (undo) {
            marker.delete()
            return true to "Android's default is back"
        }
        val ok = output.contains("max=2147483647") && output.contains("mon=false")
        if (ok) {
            marker.parentFile?.mkdirs()
            marker.writeText("shizuku\n")
        }
        return ok to output.trim()
    }
}
