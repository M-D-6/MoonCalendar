package com.md6.mooncalendar

import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Keeps everything that shows "today" in step with the clock while the app is
 * closed - the same layered strategy as the Android Persian Calendar app:
 *   1. an alarm at local midnight (00:00:00.3) (exact when allowed, otherwise
 *      inexact-while-idle),
 *   2. an hourly WorkManager job as a safety net,
 *   3. system broadcasts (date/time/time-zone change, boot, package replaced)
 *      and, in-process, screen-on.
 * Every run re-posts the date notification, switches the launcher icon (never
 * while the app is on screen, see [AppIconManager]), refreshes widgets and
 * re-arms the next alarm.
 */
object DateRefresher {
    const val ACTION_REFRESH = "com.md6.Mooncalendar.DATE_REFRESH"
    private const val ALARM_CODE = 7101
    private const val WORK_NAME = "mooncalendar_date_refresh"
    private const val MIDNIGHT_WORK_NAME = "mooncalendar_date_refresh_midnight"

    @Volatile private var lastRunAt = 0L

    /**
     * [force] is false only for the screen-on broadcast, which can arrive many times an hour: those are
     * debounced (the Persian Calendar app also skips updates fired within a moment of each other), while the
     * midnight alarm, date / time / time-zone changes, the worker and backgrounding always run.
     */
    fun run(context: Context, force: Boolean = true, refreshIcon: Boolean = true) {
        val tick = android.os.SystemClock.elapsedRealtime()
        if (!force && tick - lastRunAt < 5_000L) return
        lastRunAt = tick
        val app = context.applicationContext
        runCatching { DateNotificationStore.postCurrent(app) }
        // Not at process start: the launcher alias must never be switched while the user is opening the app.
        if (refreshIcon) runCatching { AppIconManager.refresh(app) }
        runCatching { refreshWidgets(app) }
        ensureScheduled(app)
    }

    fun ensureScheduled(context: Context) {
        val app = context.applicationContext
        runCatching { scheduleMidnight(app) }
        runCatching { scheduleHourly(app) }
        runCatching { scheduleRepeatingAlarm(app) }
    }

    private fun nextMidnightMillis(): Long {
        val c = Calendar.getInstance()
        c.add(Calendar.DAY_OF_YEAR, 1)
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        // Right on 00:00 (a fraction of a second after, so the clock has certainly rolled over).
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 300)
        return c.timeInMillis
    }

    private fun scheduleMidnight(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, DateNotificationReceiver::class.java).setAction(ACTION_REFRESH)
        val pending = PendingIntent.getBroadcast(
            context, ALARM_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val at = nextMidnightMillis()
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
        if (canExact) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    /**
     * Third net, like the Persian Calendar app's repeating alarm: an inexact hourly alarm that is delivered even when
     * the process is gone (it wakes the device in a Doze maintenance window), re-posting the notification
     * if it was removed. Only armed when not already pending, so frequent runs never push it back.
     */
    private fun scheduleRepeatingAlarm(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, DateNotificationReceiver::class.java).setAction(ACTION_REFRESH)
        val existing = PendingIntent.getBroadcast(
            context, ALARM_CODE + 1, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (existing != null) return
        val pending = PendingIntent.getBroadcast(
            context, ALARM_CODE + 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 30 * 60 * 1000L,
            AlarmManager.INTERVAL_HOUR,
            pending,
        )
    }

    private fun scheduleHourly(context: Context) {
        val work = WorkManager.getInstance(context)
        val request = PeriodicWorkRequestBuilder<DateRefreshWorker>(1, TimeUnit.HOURS).build()
        work.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        // Second, persisted net for the day change (what the Persian Calendar app relies on): a one-time job
        // that becomes due right after midnight even if the exact alarm was dropped by the system.
        val delay = (nextMidnightMillis() - System.currentTimeMillis()).coerceAtLeast(1_000L)
        val midnight = OneTimeWorkRequestBuilder<DateRefreshWorker>()
            .setInitialDelay(delay + 1_000L, TimeUnit.MILLISECONDS)
            .build()
        work.enqueueUniqueWork(MIDNIGHT_WORK_NAME, ExistingWorkPolicy.REPLACE, midnight)
    }

    private fun refreshWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            Widget4x2::class.java,
            WidgetMoon::class.java,
            WidgetSunView::class.java,
            WidgetMap::class.java,
            WidgetCounter::class.java,
        )
        for (provider in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            context.sendBroadcast(
                Intent(context, provider)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }
    }
}

class DateRefreshWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        DateRefresher.run(applicationContext)
        return Result.success()
    }
}

/** Counts started activities so launcher-icon switching can wait until the app is not visible. */
object AppVisibility : Application.ActivityLifecycleCallbacks {
    @Volatile var startedCount = 0
        private set
    val isForeground: Boolean get() = startedCount > 0

    override fun onActivityStarted(activity: android.app.Activity) {
        startedCount++
    }

    override fun onActivityStopped(activity: android.app.Activity) {
        startedCount = (startedCount - 1).coerceAtLeast(0)
        // Config changes (rotation) recreate the activity without leaving the
        // foreground for long; only react when really backgrounded.
        if (startedCount == 0 && !activity.isChangingConfigurations) {
            DateRefresher.run(activity.applicationContext)
        }
    }

    override fun onActivityCreated(activity: android.app.Activity, savedInstanceState: android.os.Bundle?) {}
    override fun onActivityResumed(activity: android.app.Activity) {}
    override fun onActivityPaused(activity: android.app.Activity) {}
    override fun onActivitySaveInstanceState(activity: android.app.Activity, outState: android.os.Bundle) {}
    override fun onActivityDestroyed(activity: android.app.Activity) {}
}
