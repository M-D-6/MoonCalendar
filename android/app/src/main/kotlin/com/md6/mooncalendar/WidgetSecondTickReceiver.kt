package com.md6.mooncalendar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetSecondTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Widget4x2.ACTION_SECOND_TICK) return
        Widget4x2.tickSeconds(context)
    }
}
