package com.orailnoor.droiddesk.x11

import android.content.Context
import android.view.InputDevice
import android.view.MotionEvent
import java.io.File

/**
 * Captured-mouse diagnostics: with the file $TMPDIR/lexona-mouse-diag present (touch it in the
 * terminal), one line per second goes to $TMPDIR/lexona-mouse.log: which path the events took,
 * their source, the raw movement, the speed factor, the density and what was sent to X. Written
 * for "captured mouse slow outside DeX, speed setting has no effect" (Fold 7, 2026-11-12).
 */
object MouseDiag {
    private var dir: File? = null
    private var checkedAt = 0L
    private var enabled = false
    private var windowStart = 0L
    private var events = 0
    private var rawSum = 0f
    private var sentSum = 0f
    private var last = ""

    @JvmStatic
    fun init(context: Context) {
        dir = File(context.filesDir, "tmp")
    }

    private fun on(now: Long): Boolean {
        if (now - checkedAt > 3000) {
            checkedAt = now
            enabled = dir?.let { File(it, "lexona-mouse-diag").exists() } == true
        }
        return enabled
    }

    /** One captured movement: the path ("captured" / "touchpad"), raw and sent values. */
    @JvmStatic
    fun record(path: String, e: MotionEvent, rawX: Float, rawY: Float, factor: Float, density: Float,
               sentX: Float, sentY: Float) {
        val now = System.currentTimeMillis()
        if (!on(now)) return
        events++
        rawSum += kotlin.math.abs(rawX) + kotlin.math.abs(rawY)
        sentSum += kotlin.math.abs(sentX) + kotlin.math.abs(sentY)
        val relRange = e.device?.getMotionRange(MotionEvent.AXIS_RELATIVE_X) != null
        last = "path=$path src=0x${Integer.toHexString(e.source)} tool=${e.getToolType(0)} " +
            "dev=${e.device?.name} relAxis=$relRange getX=${e.x} relX=${e.getAxisValue(MotionEvent.AXIS_RELATIVE_X)} " +
            "factor=$factor density=$density"
        if (now - windowStart >= 1000) flush(now)
    }

    /** A captured event that did not move the cursor here (routing check). */
    @JvmStatic
    fun routed(where: String, e: MotionEvent) {
        val now = System.currentTimeMillis()
        if (!on(now) || e.actionMasked != MotionEvent.ACTION_MOVE) return
        val mouseRel = (e.source and InputDevice.SOURCE_MOUSE_RELATIVE) == InputDevice.SOURCE_MOUSE_RELATIVE
        last = "routed=$where src=0x${Integer.toHexString(e.source)} tool=${e.getToolType(0)} mouseRel=$mouseRel"
        if (now - windowStart >= 1000) flush(now)
    }

    private fun flush(now: Long) {
        val d = dir ?: return
        runCatching {
            val log = File(d, "lexona-mouse.log")
            if (log.length() > 262144) log.delete()
            log.appendText("${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date(now))} " +
                "events=$events raw=${"%.0f".format(rawSum)} sent=${"%.0f".format(sentSum)} $last\n")
        }
        windowStart = now
        events = 0
        rawSum = 0f
        sentSum = 0f
    }
}
