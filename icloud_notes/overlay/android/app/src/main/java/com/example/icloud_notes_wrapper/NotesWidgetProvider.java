package com.example.icloud_notes_wrapper;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.widget.RemoteViews;

public class NotesWidgetProvider extends AppWidgetProvider {

    private static final String PREFS_NAME = "com.example.icloud_notes_wrapper.PREFERENCES";
    private static final String LAST_TITLE_KEY = "last_snapshot_title";

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    public static void updateWidget(Context context, AppWidgetManager manager, int widgetId) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String title = prefs.getString(LAST_TITLE_KEY, "📒 iCloud Notes");

        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.notes_widget);
        views.setTextViewText(R.id.widget_text, title);

        Intent intent = new Intent(context, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                context, 0, intent, PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_container, pendingIntent);

        manager.updateAppWidget(widgetId, views);
    }

    public static void refreshAllWidgets(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, NotesWidgetProvider.class));
        for (int id : ids) {
            updateWidget(context, manager, id);
        }
    }
}
