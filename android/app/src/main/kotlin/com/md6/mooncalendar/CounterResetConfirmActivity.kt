package com.md6.mooncalendar

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.os.Bundle
import android.util.Log

/**
 * Transparent host for the counter widget's reset confirmation. A launcher widget cannot show a dialog
 * by itself, so the RESET button opens this activity which shows the same dialog (same wording and
 * actions) as the app's counter screen and only then resets the widget's counter.
 */
class CounterResetConfirmActivity : Activity() {
    private var dialogHandle: WidgetDialogs.Handle? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        Tr.init(this)
        super.onCreate(savedInstanceState)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        WidgetCounter.flashPress(applicationContext, widgetId, WidgetCounter.Click.RESET)
        val handle = WidgetDialogs.show(
            activity = this,
            title = "بازنشانی شمارنده",
            message = "آیا مطمئنی می‌خواهی شمارنده بازنشانی شود؟",
            positiveText = "بازنشانی",
            negativeText = "لغو",
            surfaceOverride = dynamicSurface(),
        ) {
            runCatching {
                CounterWidgetSupport.reset(applicationContext, widgetId)
                WidgetCounter.updateAll(applicationContext)
            }.onFailure { Log.e("CounterResetConfirm", "reset failed for $widgetId", it) }
            true
        }
        handle.dialog.setOnDismissListener { if (!isFinishing) finish() }
        dialogHandle = handle
    }

    /** Follows the device (Material You) palette on Android 12+, like the app and the widget itself. */
    private fun dynamicSurface(): Int? {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) return null
        val night = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        return runCatching {
            getColor(if (night) android.R.color.system_neutral1_900 else android.R.color.system_neutral1_50)
        }.getOrNull()
    }

    override fun onDestroy() {
        runCatching { dialogHandle?.dialog?.dismiss() }
        dialogHandle = null
        super.onDestroy()
    }

    override fun finish() {
        super.finish()
        overridePendingTransition(0, 0)
    }
}
