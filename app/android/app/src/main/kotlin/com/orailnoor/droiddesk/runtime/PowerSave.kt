package com.orailnoor.droiddesk.runtime

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * Puts Android apps to sleep while the Linux desktop runs (Gitea #10): the apps the user picked
 * are force-stopped and may not run in the background (RUN_ANY_IN_BACKGROUND ignore), so they
 * hold no memory next to their web versions on the desktop. When the desktop stops, every app
 * gets its earlier background mode back.
 *
 * The earlier modes are written to files/state/powersave.json before anything changes. When
 * Lexona was killed with the desktop (low memory), the next start finds the file and puts the
 * apps back first. Everything goes through Shizuku (uid 2000); without it nothing happens.
 */
object PowerSave {
    private const val TAG = "PowerSave"
    private const val PREFS = "power_save"
    private const val OP = "RUN_ANY_IN_BACKGROUND"
    private val lock = Any()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun stateFile(context: Context) = File(context.filesDir, "state/powersave.json")

    fun enabled(context: Context) = prefs(context).getBoolean("enabled", false)

    fun selected(context: Context): Set<String> =
        prefs(context).getStringSet("packages", emptySet())?.toSet().orEmpty()

    /** Packages put to sleep right now (their earlier modes are kept in the state file). */
    fun sleeping(context: Context): Set<String> = synchronized(lock) { readState(context).keys }

    fun setEnabled(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean("enabled", on).apply()
        if (!on) restoreInBackground(context)
    }

    fun setSelected(context: Context, packageName: String, on: Boolean) {
        val packages = selected(context).toMutableSet()
        if (on) packages.add(packageName) else packages.remove(packageName)
        prefs(context).edit().putStringSet("packages", packages).apply()
    }

    private fun granted(context: Context) = ShizukuSupport.state(context) == "granted"
    private fun safePackage(name: String) = name.matches(Regex("[A-Za-z0-9_.]+"))

    /**
     * Running Android apps that have a launcher entry, with their memory (PSS from dumpsys
     * meminfo, summed over the app's processes), biggest first. Lexona and Shizuku are left out.
     */
    fun running(context: Context): List<Map<String, Any>> {
        if (!granted(context)) return emptyList()
        val (_, output) = runCatching { ShizukuSupport.shell("dumpsys meminfo", 60) }.getOrElse { return emptyList() }
        // "Total PSS by process:" comes first; later sections (by OOM adjustment) repeat the processes.
        val section = output.substringAfter("Total PSS by process:", "").substringBefore("\n\n")
        val line = Regex("""^\s*([\d,]+)K: (\S+) \(pid \d+""", RegexOption.MULTILINE)
        val kb = mutableMapOf<String, Long>()
        for (m in line.findAll(section)) {
            val pkg = m.groupValues[2].substringBefore(':')
            kb[pkg] = (kb[pkg] ?: 0L) + (m.groupValues[1].replace(",", "").toLongOrNull() ?: 0L)
        }
        val pm = context.packageManager
        val own = context.packageName
        val sleeping = sleeping(context)
        val picked = selected(context)
        return kb.entries.mapNotNull { (pkg, size) ->
            if (pkg == own || pkg.startsWith("moe.shizuku") || !safePackage(pkg)) return@mapNotNull null
            pm.getLaunchIntentForPackage(pkg) ?: return@mapNotNull null
            val info = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull() ?: return@mapNotNull null
            mapOf(
                "package" to pkg,
                "label" to pm.getApplicationLabel(info).toString(),
                "mb" to (size / 1024).toInt(),
                "system" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                "selected" to (pkg in picked),
                "sleeping" to (pkg in sleeping),
            )
        }.sortedByDescending { it["mb"] as Int }
    }

    /** Stops one app now (the overview's button); its background mode stays as it is. */
    fun stopNow(context: Context, packageName: String): Boolean {
        if (!granted(context) || !safePackage(packageName)) return false
        return runCatching { ShizukuSupport.shell("am force-stop $packageName").first == 0 }.getOrDefault(false)
    }

    /** The desktop started: the selected apps go to sleep. */
    fun applyInBackground(context: Context) {
        val app = context.applicationContext
        thread(name = "power-save-apply") { runCatching { apply(app) }.onFailure { Log.w(TAG, "apply: ${it.message}") } }
    }

    /** The desktop stopped (or the feature was turned off): every app gets its mode back. */
    fun restoreInBackground(context: Context) {
        val app = context.applicationContext
        thread(name = "power-save-restore") { runCatching { restore(app) }.onFailure { Log.w(TAG, "restore: ${it.message}") } }
    }

    fun apply(context: Context) = synchronized(lock) {
        if (!enabled(context) || !granted(context)) return@synchronized
        val packages = selected(context).filter(::safePackage)
        if (packages.isEmpty()) return@synchronized
        val state = readState(context).toMutableMap()
        // The earlier mode first, saved before anything changes. A package already in the state
        // (still asleep from a killed session) keeps the mode recorded then, not "ignore".
        for (pkg in packages) {
            if (pkg in state) continue
            val (_, out) = ShizukuSupport.shell("cmd appops get $pkg $OP")
            state[pkg] = Regex("$OP: (\\w+)").find(out)?.groupValues?.get(1) ?: "default"
        }
        writeState(context, state)
        val command = packages.joinToString("; ") { "cmd appops set $it $OP ignore; am force-stop $it" }
        val (status, out) = ShizukuSupport.shell(command, 60)
        Log.i(TAG, "Asleep: ${packages.joinToString()} (status $status) ${out.trim().take(300)}")
    }

    fun restore(context: Context) = synchronized(lock) {
        val state = readState(context)
        if (state.isEmpty()) return@synchronized
        if (!granted(context)) {
            Log.w(TAG, "Shizuku not available; ${state.size} apps stay asleep until it runs")
            return@synchronized
        }
        val modes = setOf("allow", "ignore", "deny", "default", "foreground")
        val command = state.entries.filter { safePackage(it.key) }.joinToString("; ") { (pkg, mode) ->
            "cmd appops set $pkg $OP ${if (mode in modes) mode else "default"}"
        }
        val (status, out) = ShizukuSupport.shell(command, 60)
        if (status == 0) stateFile(context).delete()
        Log.i(TAG, "Awake again: ${state.keys.joinToString()} (status $status) ${out.trim().take(300)}")
    }

    /**
     * At app start: apps left asleep by a killed session wake up. [desktopRunning] is asked under
     * the lock, so a desktop that started meanwhile (and put them to sleep again) is left alone.
     */
    fun restoreIfStale(context: Context, desktopRunning: () -> Boolean) {
        val app = context.applicationContext
        if (!stateFile(app).exists()) return
        thread(name = "power-save-stale") {
            runCatching {
                synchronized(lock) { if (!desktopRunning()) restore(app) }
            }.onFailure { Log.w(TAG, "stale restore: ${it.message}") }
        }
    }

    private fun readState(context: Context): Map<String, String> = runCatching {
        val json = JSONObject(stateFile(context).readText())
        json.keys().asSequence().associateWith { json.getString(it) }
    }.getOrDefault(emptyMap())

    private fun writeState(context: Context, state: Map<String, String>) {
        val file = stateFile(context)
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.writeText(JSONObject(state).toString())
        tmp.renameTo(file)
    }
}
