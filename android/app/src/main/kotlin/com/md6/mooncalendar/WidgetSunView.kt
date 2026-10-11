package com.md6.mooncalendar

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.Executors

class WidgetSunView : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Tr.init(context)
        // Render on the worker thread but keep the process alive until it is done (goAsync).
        val pending = goAsync()
        EXECUTOR.execute {
            try {
                ids.forEach { renderOne(context, manager, it) }
            } finally {
                pending.finish()
            }
        }
    }

    override fun onEnabled(context: Context) {
        updateAll(context)
        super.onEnabled(context)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        for (i in minOf(oldWidgetIds.size, newWidgetIds.size) downTo 1) {
            Widget4x2.copyWidgetSettings(context, oldWidgetIds[i - 1], newWidgetIds[i - 1])
        }
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { Widget4x2.clearWidgetSettings(context, it) }
        super.onDeleted(context, appWidgetIds)
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
        EXECUTOR.execute { renderOne(context, manager, widgetId) }
    }

    /**
     * Renders one widget instance synchronously. The static preview image is deliberately NOT pushed
     * first: it is an un-themed, opaque picture and showing it (even briefly) is what made the widget
     * appear without the user's theme/transparency until the real bitmap arrived. If rendering fails
     * the previously shown RemoteViews simply stay in place.
     */
    private fun renderOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
        runCatching {
                val (width, height) = AstronomyWidgetSupport.widgetSizePx(context, manager, widgetId, 250, 110)
                val views = RemoteViews(context.packageName, R.layout.widget_sun_view)
                AstronomyWidgetSupport.applyBackground(context, views, R.id.image_background, widgetId, width, height, Widget4x2.widgetPrefs(context, widgetId))
                val prefs = Widget4x2.widgetPrefs(context, widgetId)
                val (bitmap, description) = AstronomyWidgetSupport.drawSunPath(
                    context, prefs, width, height, System.currentTimeMillis(),
                )
                views.setImageViewBitmap(R.id.image, bitmap)
                val dynamic = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
                    AstronomyWidgetSupport.bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
                views.setTextColor(R.id.message, AstronomyWidgetSupport.applyTextColor(context, prefs, dynamic))
                views.setViewVisibility(R.id.message, if (description.isNullOrBlank()) View.GONE else View.VISIBLE)
                if (!description.isNullOrBlank()) views.setTextViewText(R.id.message, Tr.t(description))
                views.setContentDescription(R.id.image, Tr.t(description ?: "مسیر طلوع و غروب خورشید؛ مدت روز و زمان باقی‌مانده"))
                views.setOnClickPendingIntent(R.id.widget_layout_sun_view, AstronomyWidgetSupport.launchApp(context))
                manager.updateAppWidget(widgetId, views)
        }.onFailure {
            Log.e(TAG, "Update failed for $widgetId; preview retained", it)
        }
    }

    private fun safeRemoteViews(context: Context): RemoteViews = RemoteViews(context.packageName, R.layout.widget_sun_view).also {
        it.setImageViewResource(R.id.image_background, R.drawable.widget_background)
        it.setImageViewResource(R.id.image, R.drawable.widget_sunview_preview)
        it.setViewVisibility(R.id.message, View.GONE)
        it.setOnClickPendingIntent(R.id.widget_layout_sun_view, AstronomyWidgetSupport.launchApp(context))
    }

    companion object {
        private const val TAG = "MoonCalendarWidgetSun"
        private val EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MoonCalendarWidgetSun").apply { isDaemon = true }
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WidgetSunView::class.java))
            ids.forEach { WidgetSunView().updateOne(context, manager, it) }
        }
    }
}
