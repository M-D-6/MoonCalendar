package com.md6.mooncalendar

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.IconCompat
import kotlin.math.roundToInt

/**
 * Silent, ongoing notification with the current temperature, separate from the calendar notification.
 * Status-bar icon: the temperature as text. Body: only the temperature with its degree sign.
 */
internal object TemperatureNotification {
    private const val NOTIFICATION_ID = 1004
    private const val CHANNEL_ID = "mooncalendar_temperature_notification"

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Status-bar glyph: the temperature digits, drawn white (the system tints it). */
    private fun temperatureIcon(context: Context, text: String): IconCompat {
        val size = (48f * context.resources.displayMetrics.density).roundToInt().coerceAtLeast(96)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val s = size.toFloat()
        // Frame: a rounded thermometer-style badge (rounded square with a small bulb notch at the bottom).
        val stroke = s * 0.075f
        val framePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = stroke
        }
        val frame = RectF(stroke, stroke, s - stroke, s - stroke)
        canvas.drawRoundRect(frame, s * 0.26f, s * 0.26f, framePaint)
        // Digits only (the degree sign is drawn as a small ring at the top corner, like a superscript).
        val digits = text.trim().replace("°", "").ifEmpty { "--" }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            textSize = s
        }
        val bounds = android.graphics.Rect()
        paint.getTextBounds(digits, 0, digits.length, bounds)
        // Same glyph height for Latin and Persian digits: size by height, then narrow the glyphs
        // (up to 20 %) before shrinking when the number is wide.
        val targetH = s * 0.48f
        val maxW = s * 0.64f
        paint.textSize = s * (targetH / bounds.height().coerceAtLeast(1))
        paint.getTextBounds(digits, 0, digits.length, bounds)
        if (bounds.width() > maxW) {
            val need = maxW / bounds.width()
            paint.textScaleX = need.coerceAtLeast(0.8f)
            paint.getTextBounds(digits, 0, digits.length, bounds)
            if (bounds.width() > maxW) {
                paint.textSize = paint.textSize * maxW / bounds.width()
                paint.getTextBounds(digits, 0, digits.length, bounds)
            }
        }
        val cx = s * 0.46f
        canvas.drawText(digits, cx - bounds.exactCenterX(), s * 0.55f - bounds.exactCenterY(), paint)
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = s * 0.05f
        }
        canvas.drawCircle(s * 0.80f, s * 0.27f, s * 0.065f, ring)
        return IconCompat.createWithBitmap(bitmap)
    }

    /** The temperature glyph, or the app's plain status icon when it cannot be drawn. */
    private fun smallIcon(context: Context, temperature: String): IconCompat =
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) runCatching { temperatureIcon(context, temperature) }.getOrNull() else null)
            ?: IconCompat.createWithResource(context, R.drawable.ic_stat_mooncalendar)

    fun show(
        context: Context,
        city: String,
        temperature: String,
        wind: String,
        windDegrees: Double,
        feelsLike: String,
        icon: ByteArray?,
        rtl: Boolean,
        lockScreen: Boolean,
    ) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                Tr.t(context, "اعلان دما"),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = Tr.t(context, "دمای فعلی هوا")
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIcon(context, temperature))
            // Plain notification: just the temperature with its degree sign (the status bar shows it as the icon).
            .setContentTitle(temperature)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup("mooncalendar_temperature")
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(if (lockScreen) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_SECRET)
        AstronomyWidgetSupport.launchApp(context, requestCode = 1004)?.let { builder.setContentIntent(it) }
        // A notification problem must never take the app (or the other notifications) down with it.
        runCatching { manager.notify(NOTIFICATION_ID, builder.build()) }
    }
}
