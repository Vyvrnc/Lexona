package com.orailnoor.droiddesk.runtime

import android.content.Context
import java.io.File

/**
 * Parts of the XFCE desktop a user can turn off so it runs fewer processes: Android 12+ stops
 * an app's oldest child processes once all apps together run more than 32. The parts and their
 * process counts come from the desktops on the Galaxy A16 and the Fold 7 (2026-11-12: gvfsd,
 * gvfsd-trash, gvfsd-metadata, tumblerd, xfce4-notifyd, the USB tray's python3, pulseaudio;
 * Debian's bus = proot + droiddesk-session-bus + dbus-daemon + gnome-keyring). The Fold's base
 * desktop was 20 processes. Changes apply when the desktop starts; nothing is uninstalled.
 */
object LeanDesktop {
    class Part(val id: String, val title: String, val detail: String, val processes: Int)

    val parts = listOf(
        Part(
            "gvfs", "Trash and disks in the file manager",
            "gvfs: Trash, USB disks and network places in Thunar. Home, the SD card and " +
                "lexona-usb in the terminal keep working.", 3,
        ),
        Part("thumbnails", "Picture previews", "tumbler: thumbnails of images and videos in Thunar.", 1),
        Part("notifications", "Desktop notifications", "xfce4-notifyd: pop-up notifications of Linux apps.", 1),
        Part("usbtray", "USB icon in the panel", "The panel's USB icon; lexona-usb in the terminal keeps working.", 1),
        Part("sound", "Sound", "PulseAudio: Linux apps play and record no sound.", 1),
        Part(
            "debianbus", "Password store for Debian apps",
            "Debian's session bus with gnome-keyring: VS Code, Electron apps and GitHub tools " +
                "keep their sign-ins there and will ask again, or fail to save them.", 4,
        ),
    )

    /** D-Bus names a part's programs are started by. */
    private val dbusNames = mapOf(
        "thumbnails" to listOf(
            "org.freedesktop.thumbnails.Thumbnailer1",
            "org.freedesktop.thumbnails.Manager1",
            "org.freedesktop.thumbnails.Cache1",
        ),
        "notifications" to listOf("org.freedesktop.Notifications"),
    )

    /** XDG autostart entries a part starts with the desktop. */
    private val autostart = mapOf("notifications" to listOf("xfce4-notifyd"))

    /** pkill arguments for a part's programs still running from before it was turned off. */
    private val programs = mapOf(
        "gvfs" to listOf("-x gvfsd", "-x gvfsd-trash", "-x gvfsd-metadata", "-f libexec/gvfsd-"),
        "thumbnails" to listOf("-x tumblerd"),
        "notifications" to listOf("-x xfce4-notifyd"),
        "usbtray" to listOf("-f droiddesk-usb-tray.py"),
        // proot ends with its last traced program.
        "debianbus" to listOf(
            "-f droiddesk-session-bus", "-f 'path=/tmp/dbus-debian'", "-f 'gnome-keyring-daemon --foreground'",
        ),
    )

    private const val MARK = "X-Lexona-Lean=true"

    /** Which parts are off, to compare with the state a running bus started with. */
    fun state(context: Context) = parts.joinToString(",") { "${it.id}=${isOff(context, it.id)}" }

    /** Shell lines for the desktop start: end the programs of the parts that are off. */
    fun killScript(context: Context) = programs.filterKeys { isOff(context, it) }.values.flatten()
        .joinToString("; ") { "pkill $it >/dev/null 2>&1" }.ifEmpty { ":" } + "; true"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("lean_desktop", Context.MODE_PRIVATE)

    fun isOff(context: Context, id: String) = prefs(context).getBoolean(id, false)

    fun setOff(context: Context, id: String, off: Boolean) {
        prefs(context).edit().putBoolean(id, off).apply()
    }

    fun options(context: Context): List<Map<String, Any>> = parts.map {
        mapOf("id" to it.id, "title" to it.title, "detail" to it.detail,
            "processes" to it.processes, "off" to isOff(context, it.id))
    }

    /**
     * Blocks the D-Bus services and hides the autostart entries of the parts that are off; puts
     * back what an earlier run blocked. Only files carrying the Lexona mark are removed, a user's
     * own autostart overrides stay. [userServices] must come before Termux's services directory
     * in the bus configuration.
     */
    fun apply(context: Context, userServices: File, autostartDir: File) {
        for ((id, names) in dbusNames) {
            val off = isOff(context, id)
            for (name in names) {
                val file = File(userServices, "$name.service")
                if (off) {
                    userServices.mkdirs()
                    // The bus starts /system/bin/false: activation fails, clients go without.
                    file.writeText("[D-BUS Service]\nName=$name\nExec=/system/bin/false\n$MARK\n")
                } else if (file.isFile && file.readText().contains(MARK)) {
                    file.delete()
                }
            }
        }
        for ((id, names) in autostart) {
            val off = isOff(context, id)
            for (name in names) {
                val file = File(autostartDir, "$name.desktop")
                val ours = file.isFile && file.readText().contains(MARK)
                if (off && (!file.exists() || ours)) {
                    autostartDir.mkdirs()
                    file.writeText("[Desktop Entry]\nType=Application\nName=$name\nHidden=true\n$MARK\n")
                } else if (!off && ours) {
                    file.delete()
                }
            }
        }
    }
}
