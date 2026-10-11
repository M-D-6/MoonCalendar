package com.md6.mooncalendar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AthanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        runCatching { AthanScheduler.handle(context, intent) }
    }
}
