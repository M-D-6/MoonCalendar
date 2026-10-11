package com.md6.mooncalendar

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build

class MoonApplication : Application() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent?) {
            // Screen-on can fire many times an hour: debounced. Date/time changes always run.
            DateRefresher.run(context, force = intent?.action != Intent.ACTION_SCREEN_ON)
        }
    }

    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(AppVisibility)
        // Not deliverable through the manifest on modern Android (screen on) or
        // unreliable there (date change), so also listen while the process lives.
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_DATE_CHANGED)
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        // Like the Persian Calendar app (update() in Application.onCreate): whatever starts the process - a widget
        // update, an alarm, the boot receiver, the launcher - also re-posts the date notification, refreshes the
        // widgets and re-arms every schedule. Off the main thread, so it never delays the first screen.
        Thread({ DateRefresher.run(this, force = false, refreshIcon = false) }, "MoonCalendarSchedule")
            .apply { isDaemon = true }.start()
    }
}
