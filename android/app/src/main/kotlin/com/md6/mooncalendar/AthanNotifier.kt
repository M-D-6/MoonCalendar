package com.md6.mooncalendar

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/** Android notification implementation kept close to the Persian Calendar app. */
object AthanNotifier {
    fun show(
        context: Context,
        alarm: AthanAlarm,
        soundUriOverride: String? = null,
        vibrationOverride: Boolean? = null,
    ) {
        val app = context.applicationContext
        Tr.init(app)
        val notificationId = currentChannelId(app)
        val notificationChannelId = "$notificationId"
        val notificationManager = app.getSystemService(NotificationManager::class.java) ?: return
        val soundString = soundUriOverride?.takeIf { it.isNotBlank() } ?: AthanStore.soundUri(app)
        val soundUri = Uri.parse(soundString)
        val vibration = vibrationOverride ?: AthanStore.vibration(app)
        val isFajr = alarm.prayer == "fajr"

        if (soundUri.scheme == "content") {
            runCatching {
                app.grantUriPermission(
                    "com.android.systemui", soundUri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                notificationChannelId,
                Tr.t(app, "اذان"),
                NotificationManager.IMPORTANCE_HIGH,
            ).also {
                it.description = Tr.t(app, "اذان")
                it.enableLights(true)
                it.lightColor = Color.GREEN
                if (vibration) it.vibrationPattern = longArrayOf(500, 500)
                it.enableVibration(vibration)
                it.setBypassDnd(isFajr)
                it.setSound(
                    soundUri,
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setLegacyStreamType(AudioManager.STREAM_NOTIFICATION)
                        .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)
                        .build(),
                )
            }
            notificationManager.createNotificationChannel(channel)
        }

        val builder = NotificationCompat.Builder(app, notificationChannelId)
            .setAutoCancel(true)
            .setWhen(System.currentTimeMillis())
            // Exactly the same status-bar icon as the persistent date notification
            // (calendar frame with today's day number).
            .setSmallIcon(DateNotificationStore.smallIcon(app))
            .setContentTitle(alarm.title)
            .setContentText(alarm.body)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setSound(soundUri, AudioManager.STREAM_NOTIFICATION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val cv = RemoteViews(app.packageName, R.layout.custom_notification)
            val rtl = isRtl(app)
            cv.setInt(
                R.id.custom_notification_root,
                "setLayoutDirection",
                if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
            )
            cv.setTextViewText(R.id.title, alarm.title)
            if (alarm.body.isEmpty()) {
                cv.setViewVisibility(R.id.body, View.GONE)
            } else {
                cv.setTextViewText(R.id.body, alarm.body)
                cv.setViewVisibility(R.id.body, View.VISIBLE)
            }
            builder.setCustomContentView(cv).setStyle(NotificationCompat.DecoratedCustomViewStyle())
        } else if (vibration) {
            builder.setVibrate(longArrayOf(500, 500))
        }

        runCatching { notificationManager.notify(notificationId, builder.build()) }
    }

    fun invalidateChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val id = currentChannelId(context)
        context.getSystemService(NotificationManager::class.java)?.deleteNotificationChannel("$id")
        AthanStore.setChannelId(context, id + 1)
    }

    private fun currentChannelId(context: Context): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return 3005
        val current = AthanStore.channelId(context)
        if (!AthanStore.hasChannelId(context)) {
            context.getSystemService(NotificationManager::class.java)?.let { nm ->
                (3000..3003).forEach { nm.deleteNotificationChannel("$it") }
            }
            AthanStore.setChannelId(context, 3005)
            return 3005
        }
        return current
    }

    private fun isRtl(context: Context): Boolean {
        @Suppress("DEPRECATION")
        val locale = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.resources.configuration.locales[0]
        } else {
            context.resources.configuration.locale
        }
        return locale.language == "fa" ||
            locale.language == "ar" ||
            locale.language == "ur" ||
            locale.language == "ps" ||
            Character.getDirectionality(locale.displayName.firstOrNull() ?: 'a') == Character.DIRECTIONALITY_RIGHT_TO_LEFT
    }
}
