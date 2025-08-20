package com.example.icloud_notes_wrapper;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "icloud_notes_widget_channel";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if ("refreshWidgets".equals(call.method)) {
                    NotesWidgetProvider.refreshAllWidgets(getApplicationContext());
                    result.success(null);
                } else {
                    result.notImplemented();
                }
            });
    }
}
