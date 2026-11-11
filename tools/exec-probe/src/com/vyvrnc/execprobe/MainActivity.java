package com.vyvrnc.execprobe;

import android.app.Activity;
import android.os.Bundle;
import android.widget.ScrollView;
import android.widget.TextView;

/** The probe with a screen; ProbeInstrumentation runs the same without one. */
public class MainActivity extends Activity {
    private final StringBuilder report = new StringBuilder();
    private TextView view;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        view = new TextView(this);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(view);
        setContentView(scroll);
        new Thread(() -> new Probe(this, s -> {
            report.append(s).append('\n');
            runOnUiThread(() -> view.setText(report));
        }).probe()).start();
    }
}
