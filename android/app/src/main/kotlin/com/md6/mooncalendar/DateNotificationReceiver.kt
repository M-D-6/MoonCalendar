package com.md6.mooncalendar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DateNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Midnight alarm, boot, package replaced, date/time/time-zone change:
        // everything funnels into the same refresh + re-arm.
        val pending = goAsync()
        try {
            DateRefresher.run(context)
        } finally {
            pending.finish()
        }
    }
}
