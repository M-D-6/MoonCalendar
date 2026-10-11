package com.md6.mooncalendar

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class AthanWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val prayer = inputData.getString("prayer") ?: return Result.success()
        val at = inputData.getLong("at", -1L)
        if (at <= 0L) return Result.success()
        AthanScheduler.fire(applicationContext, prayer, at)
        return Result.success()
    }
}
