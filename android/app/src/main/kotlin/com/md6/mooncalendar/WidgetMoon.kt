package com.md6.mooncalendar

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.Executors

class WidgetMoon : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Tr.init(context)
        ids.forEach { updateOne(context, manager, it) }
    }

    override fun onEnabled(context: Context) {
        updateAll(context)
        super.onEnabled(context)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        updateAll(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateOne(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        Tr.init(context)
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> updateAll(context)
        }
    }

    private fun updateOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val preview = safeRemoteViews(context)
        runCatching { manager.updateAppWidget(widgetId, preview) }
            .onFailure { Log.e(TAG, "Preview update failed for $widgetId", it) }
        EXECUTOR.execute {
            runCatching {
                val (width, height) = AstronomyWidgetSupport.widgetSizePx(context, manager, widgetId, 80, 80)
                val bitmap = android.graphics.Bitmap.createBitmap(
                    width.coerceAtLeast(40), height.coerceAtLeast(40), android.graphics.Bitmap.Config.ARGB_8888,
                )
                val canvas = android.graphics.Canvas(bitmap)
                AstronomyWidgetSupport.drawMoon(
                    context, canvas, System.currentTimeMillis(),
                    bitmap.width / 2f, bitmap.height / 2f,
                    kotlin.math.min(bitmap.width, bitmap.height) / 2f,
                )
                val views = safeRemoteViews(context)
                views.setImageViewBitmap(R.id.image, bitmap)
                manager.updateAppWidget(widgetId, views)
            }.onFailure {
                Log.e(TAG, "Update failed for $widgetId; preview retained", it)
            }
        }
    }

    private fun safeRemoteViews(context: Context): RemoteViews = RemoteViews(context.packageName, R.layout.widget_moon).also {
        it.setImageViewResource(R.id.image, R.drawable.widget_moon)
        it.setContentDescription(R.id.image, Tr.t("ماه"))
        it.setOnClickPendingIntent(R.id.image, AstronomyWidgetSupport.launchApp(context, "com.md6.Mooncalendar.SHORTCUT_ASTRONOMY"))
    }

    companion object {
        private const val TAG = "MoonCalendarWidgetMoon"
        private val EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MoonCalendarWidget").apply { isDaemon = true }
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WidgetMoon::class.java))
            ids.forEach { WidgetMoon().updateOne(context, manager, it) }
        }
    }
}
