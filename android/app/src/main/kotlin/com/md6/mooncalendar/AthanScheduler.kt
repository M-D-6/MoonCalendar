package com.md6.mooncalendar

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/** Exact Android-style athan scheduling with WorkManager as a persistent backup. */
object AthanScheduler {
    const val ACTION_ALARM = "com.md6.Mooncalendar.ATHAN_ALARM"

    private const val REQUEST_BASE = 2000
    private const val WORK_TAG = "mooncalendar_athan"
    private const val LEAD_MS = 3_000L
    private const val GRACE_MS = 15 * 60_000L

    private val prayers = listOf("fajr", "dhuhr", "asr", "maghrib", "isha")

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    fun reschedule(context: Context) {
        val app = context.applicationContext
        cancelAlarmManagers(app)
        runCatching { WorkManager.getInstance(app).cancelAllWorkByTag(WORK_TAG) }
        val alarms = AthanStore.loadAlarms(app)
        val now = System.currentTimeMillis()
        prayers.forEach { prayer ->
            scheduleNextForPrayer(app, alarms, prayer, now)
        }
    }

    /**
     * Safety net run whenever the process starts or the date rolls over: an athan whose alarm the system delayed or
     * dropped (doze, battery savers, a killed process) is still announced within the grace period, and every
     * prayer's next alarm is armed again.
     */
    @Synchronized
    fun ensureArmed(context: Context) {
        val app = context.applicationContext
        val alarms = AthanStore.loadAlarms(app)
        if (alarms.isEmpty()) return
        val now = System.currentTimeMillis()
        alarms.filter { it.at <= now + LEAD_MS && now - it.at <= GRACE_MS }.forEach { fire(app, it.prayer, it.at) }
        // Re-arming is idempotent (same request code, same time), and it also repairs a stale entry whose time passed
        // without being delivered.
        prayers.forEach { prayer -> scheduleNextForPrayer(app, alarms, prayer, now) }
    }

    fun cancel(context: Context) {
        val app = context.applicationContext
        cancelAlarmManagers(app)
        runCatching { WorkManager.getInstance(app).cancelAllWorkByTag(WORK_TAG) }
    }

    fun handle(context: Context, intent: Intent?) {
        val app = context.applicationContext
        when (intent?.action) {
            ACTION_ALARM -> {
                val prayer = intent.getStringExtra("prayer") ?: return
                val at = intent.getLongExtra("at", -1L)
                if (at > 0L) fire(app, prayer, at)
            }

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            -> reschedule(app)
        }
    }

    @Synchronized
    fun fire(context: Context, prayer: String, intendedAt: Long) {
        val app = context.applicationContext
        val alarms = AthanStore.loadAlarms(app)
        val now = System.currentTimeMillis()
        val alarm = alarms
            .filter { it.prayer == prayer }
            .minByOrNull { abs(it.at - intendedAt) }

        if (alarm != null && abs(now - intendedAt) <= GRACE_MS) {
            val duplicateKey = "$prayer|${alarm.at}"
            if (!AthanStore.wasFired(app, duplicateKey)) {
                AthanStore.markFired(app, duplicateKey)
                runCatching { AthanNotifier.show(app, alarm) }
            }
        }

        scheduleNextForPrayer(app, alarms, prayer, now)
    }

    private fun scheduleNextForPrayer(
        context: Context,
        alarms: List<AthanAlarm>,
        prayer: String,
        now: Long,
    ) {
        val next = alarms
            .asSequence()
            .filter { it.prayer == prayer && it.at > now + LEAD_MS }
            .minByOrNull { it.at }
        if (next == null) {
            cancelOne(context, prayer)
            return
        }
        scheduleAlarm(context, prayer, next.at)
        scheduleWork(context, prayer, next.at)
    }

    private fun requestCode(prayer: String): Int = REQUEST_BASE + prayers.indexOf(prayer).coerceAtLeast(0)

    private fun workName(prayer: String) = "$WORK_TAG-$prayer"

    private fun scheduleAlarm(context: Context, prayer: String, at: Long) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, AthanReceiver::class.java)
            .setAction(ACTION_ALARM)
            .putExtra("prayer", prayer)
            .putExtra("at", at)
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode(prayer),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (canScheduleExact(context)) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    private fun scheduleWork(context: Context, prayer: String, at: Long) {
        val delay = (at - System.currentTimeMillis()).coerceAtLeast(0L)
        val data = Data.Builder()
            .putString("prayer", prayer)
            .putLong("at", at)
            .build()
        val request = OneTimeWorkRequestBuilder<AthanWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(WORK_TAG)
            .build()
        runCatching {
            WorkManager.getInstance(context).enqueueUniqueWork(
                workName(prayer),
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }

    private fun cancelAlarmManagers(context: Context) {
        prayers.forEach { cancelOne(context, it) }
    }

    private fun cancelOne(context: Context, prayer: String) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(context, AthanReceiver::class.java).setAction(ACTION_ALARM)
        val pi = PendingIntent.getBroadcast(
            context,
            requestCode(prayer),
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pi != null) am.cancel(pi)
        runCatching { pi?.cancel() }
        runCatching { WorkManager.getInstance(context).cancelUniqueWork(workName(prayer)) }
    }
}
