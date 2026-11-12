package com.orailnoor.droiddesk

import android.app.Instrumentation
import android.os.Bundle
import com.orailnoor.droiddesk.runtime.LinuxRuntime

/**
 * Test entry for the targetSdk 36 work (docs/targetsdk36-plan.md): extracts the bootstrap and
 * runs one shell command through the app's own exec path, in the app process, also on a locked
 * phone. Only adb can start an instrumentation:
 *   adb shell am instrument -w -e cmd 'echo hi' io.github.vyvrnc.lexona/com.orailnoor.droiddesk.SmokeInstrumentation
 * In the debug source set only; release APKs do not contain it.
 */
class SmokeInstrumentation : Instrumentation() {
    private var command = "echo hello"

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        arguments?.getString("cmd")?.let { command = it }
        start()
    }

    override fun onStart() {
        val report = StringBuilder()
        val result = Bundle()
        try {
            val context = targetContext
            val runtime = LinuxRuntime(context)
            report.append("targetSdk=").append(context.applicationInfo.targetSdkVersion).append('\n')
            runtime.setupBootstrap()
            runtime.extractBootstrapIfNeeded(context)
            report.append("bootstrapped=").append(runtime.isBootstrapped()).append('\n')
            // The launchers of this app version, as the terminal writes them.
            runCatching { runtime.writeDeviceTools() }
                .onFailure { report.append("device tools: ").append(it.message).append('\n') }
            report.append(runtime.executeCommand(command)).append('\n')
        } catch (e: Throwable) {
            report.append("FAILED ").append(e).append('\n')
        }
        result.putString(REPORT_KEY_STREAMRESULT, report.toString())
        finish(0, result)
    }
}
