package com.md6.mooncalendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class WidgetCounter : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Tr.init(context)
        ids.forEach { requestUpdate(context, manager, it) }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { CounterWidgetSupport.clearWidget(context, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        // A restored launcher widget must never accidentally bind to another saved target.
        newWidgetIds.forEach { CounterWidgetSupport.saveTarget(context, it, CounterWidgetSupport.PRIVATE_TARGET, 0) }
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        updateAll(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        requestUpdate(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        Tr.init(context)
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_INCREMENT -> handleClick(context, intent, Click.INCREMENT)
            ACTION_DECREMENT -> handleClick(context, intent, Click.DECREMENT)
            ACTION_RESET -> openResetConfirmation(context, intent)
            ACTION_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> updateAll(context)
        }
    }

    enum class Click { INCREMENT, DECREMENT, RESET }

    /** Fallback path (e.g. an old pending intent): RESET always goes through the confirmation dialog. */
    private fun openResetConfirmation(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        runCatching { context.startActivity(resetConfirmIntent(context, widgetId).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            .onFailure { Log.e(TAG, "Could not open reset confirmation for $widgetId", it) }
    }

    private fun handleClick(context: Context, intent: Intent, click: Click) {
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        EXECUTOR.execute {
            runCatching {
                when (click) {
                    Click.INCREMENT -> CounterWidgetSupport.increment(context, widgetId)
                    Click.DECREMENT -> CounterWidgetSupport.decrement(context, widgetId)
                    Click.RESET -> Unit // never reached: reset is confirmed in CounterResetConfirmActivity
                }
                val manager = AppWidgetManager.getInstance(context)
                // Same press animation as the app: 110 ms shrink, then back to full size. Only the count and
                // the three button bitmaps are sent (partial update), so the rest of the widget is never
                // re-applied and cannot flicker or "pulse" together with the pressed button.
                pressSync(context, manager, widgetId, click, refreshCount = true)
                Thread.sleep(PRESS_MS)
                pressSync(context, manager, widgetId, null, refreshCount = false)
            }.onFailure { Log.e(TAG, "Counter action failed for $widgetId", it) }
        }
    }

    companion object {
        private const val TAG = "MoonCalendarWidgetCounter"
        const val ACTION_INCREMENT = "com.md6.Mooncalendar.COUNTER_INCREMENT"
        const val ACTION_DECREMENT = "com.md6.Mooncalendar.COUNTER_DECREMENT"
        const val ACTION_RESET = "com.md6.Mooncalendar.COUNTER_RESET"
        const val ACTION_REFRESH = "com.md6.Mooncalendar.COUNTER_REFRESH"
        private const val DEVICE_ASPECT = 0.76f
        private const val PRESS_MS = 110L
        // Pressed scale relative to the resting size; identical to the app (1.20/1.30 and 1.40/1.60).
        private const val MAIN_PRESSED_SCALE = 1.20f / 1.30f
        private const val SMALL_PRESSED_SCALE = 1.40f / 1.60f
        private val EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MoonCalendarCounterWidget").apply { isDaemon = true }
        }

        fun resetConfirmIntent(context: Context, widgetId: Int): Intent =
            Intent(context, CounterResetConfirmActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = android.net.Uri.parse("mooncalendar://counter-reset/$widgetId")
            }

        /** Plays the press animation for a button whose click does not come through this receiver. */
        fun flashPress(context: Context, widgetId: Int, click: Click) {
            EXECUTOR.execute {
                runCatching {
                    val manager = AppWidgetManager.getInstance(context)
                    pressSync(context, manager, widgetId, click, refreshCount = false)
                    Thread.sleep(PRESS_MS)
                    pressSync(context, manager, widgetId, null, refreshCount = false)
                }.onFailure { Log.e(TAG, "Press animation failed for $widgetId", it) }
            }
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WidgetCounter::class.java))
            ids.forEach { requestUpdate(context, manager, it) }
        }

        private fun requestUpdate(context: Context, manager: AppWidgetManager, widgetId: Int) {
            EXECUTOR.execute {
                runCatching { updateOneSync(context, manager, widgetId) }
                    .onFailure { Log.e(TAG, "Counter render failed for $widgetId", it) }
            }
        }

        private class CounterLayout(
            val density: Float,
            val hasTarget: Boolean,
            val deviceWidth: Float,
            val deviceHeight: Float,
            val actualTargetHeightPx: Float,
            val deviceMarginPx: Float,
            val groupHeight: Float,
        )

        private fun computeLayout(context: Context, manager: AppWidgetManager, widgetId: Int, targetName: String?): CounterLayout {
            val (frameWidth, frameHeight) = AstronomyWidgetSupport.widgetSizePx(context, manager, widgetId, 160, 190)
            val density = context.resources.displayMetrics.density
            val frameW = frameWidth.toFloat().coerceAtLeast(80f)
            val frameH = frameHeight.toFloat().coerceAtLeast(80f)

            // Target + counter are one visual group. Both scale together; the gap is a fixed
            // small fraction of the device so launcher resizing cannot make the gap grow.
            val provisionalDeviceWidth = minOf(frameW * .96f, frameH * DEVICE_ASPECT)
            val targetHeightPx = (provisionalDeviceWidth * .115f).coerceIn(18f * density, 34f * density)
            val hasTarget = !targetName.isNullOrBlank()
            // The body artwork has a transparent band above it; pull the device up so the visible gap
            // between target label and counter stays small (4dp + band would be too loose).
            fun deviceTopMarginPx(deviceW: Float): Float {
                if (!hasTarget) return 0f
                val band = deviceW * CounterWidgetSupport.BODY_TOP_PAD
                return (4f * density + band) * .25f - band
            }
            val maxDeviceHeight = (frameH - if (hasTarget) targetHeightPx + deviceTopMarginPx(provisionalDeviceWidth) else 0f)
                .coerceAtLeast(80f)
            val deviceWidth = minOf(frameW * .96f, maxDeviceHeight * DEVICE_ASPECT)
            val deviceHeight = (deviceWidth / DEVICE_ASPECT).coerceAtLeast(80f)
            val actualTargetHeightPx = (deviceWidth * .115f).coerceIn(18f * density, 34f * density)
            val deviceMarginPx = deviceTopMarginPx(deviceWidth)
            val groupHeight = deviceHeight + if (hasTarget) actualTargetHeightPx + deviceMarginPx else 0f
            return CounterLayout(density, hasTarget, deviceWidth, deviceHeight, actualTargetHeightPx, deviceMarginPx, groupHeight)
        }

        private fun mainButtonPx(context: Context, deviceWidth: Float, density: Float): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) (deviceWidth * .507f).roundToInt() else (48f * density).roundToInt()

        private fun smallButtonPx(context: Context, deviceWidth: Float, density: Float): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) (deviceWidth * .08f).roundToInt() else (48f * density).roundToInt()

        /**
         * Press feedback / count change as a partial update: only the count and the button artwork are
         * re-sent, so the launcher does not re-apply (and visibly re-draw) the whole widget twice per tap.
         */
        private fun pressSync(context: Context, manager: AppWidgetManager, widgetId: Int, pressed: Click?, refreshCount: Boolean) {
            val targetName = CounterWidgetSupport.targetName(context, widgetId)
            val layout = computeLayout(context, manager, widgetId, targetName)
            val views = RemoteViews(context.packageName, R.layout.widget_counter)
            if (refreshCount) {
                val count = CounterWidgetSupport.resolveCounter(context, widgetId).second
                views.setImageViewBitmap(R.id.count, CounterWidgetSupport.buildCountBitmap(
                    context,
                    count,
                    layout.deviceWidth.roundToInt().coerceAtLeast(32),
                    layout.deviceHeight.roundToInt().coerceAtLeast(32),
                ))
            }
            val mainPx = mainButtonPx(context, layout.deviceWidth, layout.density)
            val smallPx = smallButtonPx(context, layout.deviceWidth, layout.density)
            views.setImageViewBitmap(R.id.increment_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_main_button, mainPx, if (pressed == Click.INCREMENT) MAIN_PRESSED_SCALE else 1f))
            views.setImageViewBitmap(R.id.decrement_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_reset_button, smallPx, if (pressed == Click.DECREMENT) SMALL_PRESSED_SCALE else 1f))
            views.setImageViewBitmap(R.id.reset_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_reset_button, smallPx, if (pressed == Click.RESET) SMALL_PRESSED_SCALE else 1f))
            manager.partiallyUpdateAppWidget(widgetId, views)
        }

        private fun updateOneSync(context: Context, manager: AppWidgetManager, widgetId: Int, pressed: Click? = null) {
            val views = RemoteViews(context.packageName, R.layout.widget_counter)
            val targetName = CounterWidgetSupport.targetName(context, widgetId)
            val layout = computeLayout(context, manager, widgetId, targetName)
            val density = layout.density
            val deviceWidth = layout.deviceWidth
            val deviceHeight = layout.deviceHeight
            val actualTargetHeightPx = layout.actualTargetHeightPx
            val deviceMarginPx = layout.deviceMarginPx
            val groupHeight = layout.groupHeight

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val deviceWidthDp = (deviceWidth / density).coerceAtLeast(1f)
                val deviceHeightDp = (deviceHeight / density).coerceAtLeast(1f)
                val groupWidthDp = deviceWidthDp
                val groupHeightDp = (groupHeight / density).coerceAtLeast(1f)
                views.setViewLayoutWidth(R.id.counter_group, groupWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.counter_group, groupHeightDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutWidth(R.id.counter_device, deviceWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.counter_device, deviceHeightDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutWidth(R.id.counter_device_content, deviceWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.counter_device_content, deviceHeightDp, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutMargin(R.id.counter_device, RemoteViews.MARGIN_TOP, deviceMarginPx / density, TypedValue.COMPLEX_UNIT_DIP)
                if (!targetName.isNullOrBlank()) {
                    val targetWidthDp = (deviceWidthDp * .72f).coerceAtLeast(56f)
                    views.setViewLayoutWidth(R.id.target_container, targetWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                    views.setViewLayoutHeight(R.id.target_container, (actualTargetHeightPx / density).coerceAtLeast(1f), TypedValue.COMPLEX_UNIT_DIP)
                    views.setViewLayoutWidth(R.id.target_box, targetWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                    views.setViewLayoutHeight(R.id.target_box, (actualTargetHeightPx / density).coerceAtLeast(1f), TypedValue.COMPLEX_UNIT_DIP)
                    views.setViewLayoutWidth(R.id.target_outline, targetWidthDp, TypedValue.COMPLEX_UNIT_DIP)
                    views.setViewLayoutHeight(R.id.target_outline, (actualTargetHeightPx / density).coerceAtLeast(1f), TypedValue.COMPLEX_UNIT_DIP)
                    views.setTextViewTextSize(R.id.target_box, TypedValue.COMPLEX_UNIT_SP, (12f * (deviceWidthDp / 200f)).coerceIn(8f, 16f))
                    views.setViewLayoutHeight(R.id.counter_device, deviceHeightDp, TypedValue.COMPLEX_UNIT_DIP)
                }

                // Match the Flutter counter's exact visual sizes, but do not use scaleX/scaleY.
                val mainButton = deviceWidth * .507f
                val smallButton = deviceWidth * .08f
                val mainW = (mainButton / density).coerceAtLeast(1f)
                val smallW = (smallButton / density).coerceAtLeast(1f)
                views.setViewLayoutWidth(R.id.increment_button, mainW, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.increment_button, mainW, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutWidth(R.id.decrement_button, smallW, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.decrement_button, smallW, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutWidth(R.id.reset_button, smallW, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.reset_button, smallW, TypedValue.COMPLEX_UNIT_DIP)
            }

            CounterWidgetSupport.styleTargetBox(views, widgetId, context, targetName, (deviceWidth * .72f).roundToInt().coerceAtLeast(56), actualTargetHeightPx.roundToInt().coerceAtLeast(16))

            val primary = CounterWidgetSupport.widgetPrimaryColor(context, widgetId)
            val bodyBitmap = CounterWidgetSupport.buildTintedBodyBitmap(context, primary)
            views.setImageViewBitmap(R.id.body, bodyBitmap)

            // All images use fitCenter, so they preserve the exact Flutter device artwork ratio.
            // Only the actual fitted device box is used for button/count geometry; this prevents
            // the controls from drifting when Android resizes the widget to a different aspect.
            views.setFloat(R.id.increment_button, "setTranslationX", deviceWidth * .02f)
            views.setFloat(R.id.increment_button, "setTranslationY", deviceHeight * .20f)
            views.setFloat(R.id.decrement_button, "setTranslationX", -deviceWidth * .22f)
            views.setFloat(R.id.decrement_button, "setTranslationY", -deviceWidth * .02f)
            views.setFloat(R.id.reset_button, "setTranslationX", deviceWidth * .22f)
            views.setFloat(R.id.reset_button, "setTranslationY", -deviceWidth * .02f)
            views.setFloat(R.id.decrement_label, "setTranslationX", -deviceWidth * .22f)
            views.setFloat(R.id.decrement_label, "setTranslationY", -deviceHeight * .105f)
            views.setFloat(R.id.reset_label, "setTranslationX", deviceWidth * .22f)
            views.setFloat(R.id.reset_label, "setTranslationY", -deviceHeight * .105f)

            val count = CounterWidgetSupport.resolveCounter(context, widgetId).second
            val countBitmap = CounterWidgetSupport.buildCountBitmap(
                context,
                count,
                deviceWidth.roundToInt().coerceAtLeast(32),
                deviceHeight.roundToInt().coerceAtLeast(32),
            )
            views.setImageViewBitmap(R.id.count, countBitmap)

            val decrementVisible = CounterWidgetSupport.showDecrement(context, widgetId)
            views.setViewVisibility(R.id.decrement_button, if (decrementVisible) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.decrement_label, if (decrementVisible) View.VISIBLE else View.GONE)
            val resetInPersian = CounterWidgetSupport.resetLabelFollowsLanguage(context, widgetId)
            views.setTextViewText(R.id.reset_label, if (resetInPersian) Tr.t("بازنشانی") else "RESET")
            views.setTextViewTextSize(
                R.id.reset_label,
                TypedValue.COMPLEX_UNIT_PX,
                if (resetInPersian) deviceWidth * .04f else deviceWidth * .035f,
            )
            views.setTextViewTextSize(R.id.decrement_label, TypedValue.COMPLEX_UNIT_PX, deviceWidth * .035f)

            // Button artwork is drawn into a fixed square; the pressed frame just draws it smaller, which
            // gives every launcher the same scale animation as the app.
            val mainPx = mainButtonPx(context, deviceWidth, density)
            val smallPx = smallButtonPx(context, deviceWidth, density)
            views.setImageViewBitmap(R.id.increment_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_main_button, mainPx, if (pressed == Click.INCREMENT) MAIN_PRESSED_SCALE else 1f))
            views.setImageViewBitmap(R.id.decrement_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_reset_button, smallPx, if (pressed == Click.DECREMENT) SMALL_PRESSED_SCALE else 1f))
            views.setImageViewBitmap(R.id.reset_button, CounterWidgetSupport.buildButtonBitmap(
                context, R.drawable.tally_counter_reset_button, smallPx, if (pressed == Click.RESET) SMALL_PRESSED_SCALE else 1f))

            views.setOnClickPendingIntent(R.id.increment_button, pendingBroadcast(context, ACTION_INCREMENT, widgetId))
            views.setOnClickPendingIntent(R.id.decrement_button, pendingBroadcast(context, ACTION_DECREMENT, widgetId))
            views.setOnClickPendingIntent(R.id.reset_button, PendingIntent.getActivity(
                context,
                (widgetId * 31 + ACTION_RESET.hashCode()).and(0x7FFFFFFF),
                resetConfirmIntent(context, widgetId),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
            views.setContentDescription(R.id.increment_button, Tr.t("افزایش شمارنده"))
            views.setContentDescription(R.id.decrement_button, Tr.t("کاهش شمارنده"))
            views.setContentDescription(R.id.reset_button, Tr.t("بازنشانی شمارنده"))
            manager.updateAppWidget(widgetId, views)
        }

        private fun pendingBroadcast(context: Context, action: String, widgetId: Int): PendingIntent {
            val intent = Intent(context, WidgetCounter::class.java).setAction(action).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            val requestCode = (widgetId * 31 + action.hashCode()).and(0x7FFFFFFF)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
