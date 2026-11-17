package com.orailnoor.droiddesk.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.orailnoor.droiddesk.MainActivity
import com.orailnoor.droiddesk.view.TerminalSessions

/**
 * Keeps the app process in the foreground while a terminal session runs without the desktop.
 *
 * Without it a terminal-only Claude Code session was cached (oom_score_adj 850) once Lexona went
 * to the background, and lmkd reclaimed the whole process under memory pressure (Galaxy A16,
 * Chrome and YouTube in front, twice in an afternoon). DroidDeskService covers the desktop; it
 * also binds the X server and runs the PulseAudio watchdog, too much for a terminal alone.
 *
 * Started by TerminalSessions when a session starts, stopped when none runs. The notification
 * shows the count, ends all sessions, and can hold a partial wake lock (off by default).
 */
class TerminalService : Service() {

    companion object {
        private const val TAG = "TerminalService"
        private const val NOTIFICATION_ID = 1002
        private const val ACTION_UPDATE = "update"
        private const val ACTION_EXIT_ALL = "exit_all"
        private const val ACTION_WAKE_LOCK = "wake_lock"

        /** Starts the service or refreshes its notification; call while the app is in front. */
        fun update(context: Context) {
            val intent = Intent(context, TerminalService::class.java).setAction(ACTION_UPDATE)
            try {
                if (TerminalSessions.runningCount() > 0) {
                    context.startForegroundService(intent)
                } else {
                    context.stopService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ refuses a foreground service started from the background.
                Log.w(TAG, "Terminal service not started: ${e.message}")
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_EXIT_ALL -> TerminalSessions.finishAll()
            ACTION_WAKE_LOCK -> if (wakeLock?.isHeld == true) releaseWakeLock() else acquireWakeLock()
        }
        val count = TerminalSessions.runningCount()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(count),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                } else {
                    0
                },
            )
        } catch (e: Exception) {
            // Restarted from the background (START_STICKY) where Android refuses it.
            Log.w(TAG, "Foreground start refused: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (count == 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Not sticky: after the process died there are no sessions to keep.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun buildNotification(count: Int) = run {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(DroidDeskService.CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(DroidDeskService.CHANNEL_ID, "Lexona Linux Service", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) },
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun action(name: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, TerminalService::class.java).setAction(name),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val held = wakeLock?.isHeld == true
        NotificationCompat.Builder(this, DroidDeskService.CHANNEL_ID)
            .setContentTitle("Lexona")
            .setContentText(
                (if (count == 1) "1 terminal session running" else "$count terminal sessions running") +
                    if (held) " · CPU kept awake" else "",
            )
            .setSmallIcon(com.orailnoor.droiddesk.R.drawable.ic_stat_lexona)
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(0, "Exit all", action(ACTION_EXIT_ALL, 1))
            .addAction(0, if (held) "Release wake lock" else "Keep CPU awake", action(ACTION_WAKE_LOCK, 2))
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Lexona::Terminal")
            .apply { acquire(Long.MAX_VALUE) }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
