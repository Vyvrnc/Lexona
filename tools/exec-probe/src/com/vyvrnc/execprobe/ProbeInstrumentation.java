package com.vyvrnc.execprobe;

import android.app.Instrumentation;
import android.os.Bundle;

/**
 * The probe without UI, in the app's own process and SELinux domain, also on a locked phone:
 *   adb shell am instrument -w com.vyvrnc.execprobe/.ProbeInstrumentation
 * Results go to logcat (tag ExecProbe) and to the instrumentation result.
 */
public class ProbeInstrumentation extends Instrumentation {
    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override
    public void onStart() {
        StringBuilder report = new StringBuilder();
        new Probe(getTargetContext(), s -> report.append(s).append('\n')).probe();
        Bundle result = new Bundle();
        result.putString(REPORT_KEY_STREAMRESULT, report.toString());
        finish(0, result);
    }
}
