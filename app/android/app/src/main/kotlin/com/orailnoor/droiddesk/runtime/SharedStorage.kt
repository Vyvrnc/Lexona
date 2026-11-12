package com.orailnoor.droiddesk.runtime

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.system.Os
import android.util.Log
import java.io.File

/**
 * Android shared storage (/sdcard) for the Linux desktop. The permissions were only
 * declared in the manifest, so the Linux side got "Permission denied". With
 * targetSdk 28 + requestLegacyExternalStorage the runtime grant gives plain file
 * access, like termux-setup-storage.
 */
object SharedStorage {
    const val REQUEST_CODE = 4711
    private const val TAG = "SharedStorage"

    private val PERMISSIONS = arrayOf(
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.WRITE_EXTERNAL_STORAGE,
    )

    /**
     * targetSdk >= 30 on Android 11+: the runtime permissions no longer give file access
     * (requestLegacyExternalStorage is ignored, READ does nothing from 33), so Linux programs
     * need "All files access" (MANAGE_EXTERNAL_STORAGE), granted on a settings page.
     */
    fun usesAllFilesAccess(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 30 && context.applicationInfo.targetSdkVersion >= 30

    fun isGranted(context: Context): Boolean =
        if (usesAllFilesAccess(context)) Environment.isExternalStorageManager()
        else PERMISSIONS.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    /** Old targets: asks once per launch; Android stops showing the dialog after repeated denials. */
    fun requestIfNeeded(activity: Activity) {
        if (isGranted(activity)) linkIntoHome(activity)
        else if (!usesAllFilesAccess(activity)) activity.requestPermissions(PERMISSIONS, REQUEST_CODE)
    }

    /**
     * New targets: opens the "All files access" page for this app once; the user can grant it
     * there later too. The links into home follow in MainActivity.onResume.
     */
    fun requestAllFilesAccessOnce(activity: Activity) {
        if (!usesAllFilesAccess(activity) || isGranted(activity)) return
        val prefs = activity.getSharedPreferences("droiddesk_permissions", Context.MODE_PRIVATE)
        if (prefs.getBoolean("all_files_asked", false)) return
        prefs.edit().putBoolean("all_files_asked", true).apply()
        runCatching {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${activity.packageName}")),
            )
        }.recoverCatching {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }.onFailure { Log.w(TAG, "No All files access page", it) }
    }

    /** ~/storage/{shared,downloads,...} for the native (non-root) session; chroot mounts /sdcard itself. */
    fun linkIntoHome(context: Context) {
        val root = Environment.getExternalStorageDirectory()
        val links = mapOf(
            "shared" to root,
            "downloads" to File(root, Environment.DIRECTORY_DOWNLOADS),
            "documents" to File(root, Environment.DIRECTORY_DOCUMENTS),
            "pictures" to File(root, Environment.DIRECTORY_PICTURES),
            "dcim" to File(root, Environment.DIRECTORY_DCIM),
            "music" to File(root, Environment.DIRECTORY_MUSIC),
            "movies" to File(root, Environment.DIRECTORY_MOVIES),
        )
        val storageDir = File(context.filesDir, "home/storage").apply { mkdirs() }
        links.forEach { (name, target) ->
            val link = File(storageDir, name)
            // exists() follows the link, so also skip dangling links we created earlier.
            if (link.exists() || runCatching { Os.readlink(link.path) }.isSuccess) return@forEach
            runCatching { Os.symlink(target.absolutePath, link.path) }
                .onFailure { Log.w(TAG, "Could not link ${link.path} -> $target", it) }
        }
        addFileManagerBookmarks(context, root)
    }

    /** Without these the phone storage is invisible in Thunar; browsing up from home ends in /data/user/0. */
    private fun addFileManagerBookmarks(context: Context, root: File) {
        val bookmarks = File(context.filesDir, "home/.config/gtk-3.0/bookmarks")
        bookmarks.parentFile?.mkdirs()
        val existing = if (bookmarks.exists()) bookmarks.readLines() else emptyList()
        val wanted = listOf(
            "file://${root.absolutePath} Telefon",
            "file://${File(root, Environment.DIRECTORY_DOWNLOADS).absolutePath} Stažené",
        )
        val missing = wanted.filter { line -> existing.none { it.substringBefore(' ') == line.substringBefore(' ') } }
        if (missing.isNotEmpty()) bookmarks.writeText((existing + missing).joinToString("\n", postfix = "\n"))
    }
}
