package com.md6.mooncalendar

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import androidx.core.app.NotificationCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

internal object DateNotificationStore {
    private const val PREFS = "mooncalendar_date_notification"
    private const val KEY_PAYLOADS = "payloads"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_LOCK_SCREEN = "lock_screen"
    private const val KEY_LARGE_DAY = "large_day"
    private const val KEY_RTL = "rtl"
    const val NOTIFICATION_ID = 1003
    const val CHANNEL_ID = "mooncalendar_date_notification"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun sync(context: Context, enabled: Boolean, lockScreen: Boolean, largeDayNumber: Boolean, payloads: List<Map<String, String>>, rtl: Boolean = true) {
        val json = JSONArray()
        payloads.forEach { item ->
            json.put(JSONObject().apply {
                put("date", item["date"].orEmpty())
                put("title", item["title"].orEmpty())
                put("body", item["body"].orEmpty())
                put("day", item["day"].orEmpty())
                put("latin", item["latin"].orEmpty())
                put("styles", item["styles"].orEmpty())
            })
        }
        prefs(context).edit {
            putBoolean(KEY_ENABLED, enabled)
            putBoolean(KEY_LOCK_SCREEN, lockScreen)
            putBoolean(KEY_LARGE_DAY, largeDayNumber)
            putBoolean(KEY_RTL, rtl)
            putString(KEY_PAYLOADS, json.toString())
        }
        if (enabled) postCurrent(context) else cancel(context)
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    fun postCurrent(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ENABLED, false)) {
            cancel(context)
            return
        }
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val notificationManager = context.getSystemService(NotificationManager::class.java) ?: return
        ensureChannel(context, notificationManager)

        val key = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val payload = findPayload(p.getString(KEY_PAYLOADS, null), key) ?: return
        val title = payload.optString("title").ifBlank { "Mooncalendar" }
        val body = payload.optString("body")
        val bodyLines = if (body.isEmpty()) emptyList() else body.split("\n")
        val styleTokens = payload.optString("styles").split(";").map { part -> part.split(",").filter { it.isNotBlank() }.toSet() }
        val expandedBody = SpannableStringBuilder().also { sb ->
            bodyLines.forEachIndexed { i, line ->
                if (i > 0) sb.append("\n")
                sb.append(styledLine(line, styleTokens.getOrNull(i + 1), isTitle = false))
            }
        }

        val contentIntent = AstronomyWidgetSupport.launchApp(context, requestCode = 1003)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIcon(context, payload))
            .setContentTitle(styledLine(title, styleTokens.getOrNull(0), isTitle = true))
            // Collapsed view: line 1 (title) and, on its own row, line 2 only.
            // The remaining lines are shown when the notification is expanded.
            .setContentText(bodyLines.firstOrNull()?.let { styledLine(it, styleTokens.getOrNull(1), isTitle = false) })
            .setOngoing(true)
            .setSilent(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setWhen(0L)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(
                if (p.getBoolean(KEY_LOCK_SCREEN, true)) NotificationCompat.VISIBILITY_PUBLIC
                else NotificationCompat.VISIBILITY_SECRET,
            )
        if (contentIntent != null) builder.setContentIntent(contentIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Same design as the Persian Calendar app: custom collapsed + expanded views, decorated by the system,
            // with the layout direction chosen by the user (default: app language).
            val direction = if (p.getBoolean(KEY_RTL, true)) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
            val titleText = styledLine(title, styleTokens.getOrNull(0), isTitle = true)
            val firstLine = bodyLines.firstOrNull()?.let { styledLine(it, styleTokens.getOrNull(1), isTitle = false) }
            val small = RemoteViews(context.packageName, R.layout.custom_notification).also {
                it.setInt(R.id.custom_notification_root, "setLayoutDirection", direction)
                it.setTextViewText(R.id.title, titleText)
                if (firstLine == null) it.setViewVisibility(R.id.body, View.GONE)
                else {
                    it.setTextViewText(R.id.body, firstLine)
                    it.setViewVisibility(R.id.body, View.VISIBLE)
                }
            }
            builder.setCustomContentView(small)
            if (bodyLines.size > 1) {
                val big = RemoteViews(context.packageName, R.layout.custom_notification_big).also {
                    it.setInt(R.id.custom_notification_root, "setLayoutDirection", direction)
                    it.setTextViewText(R.id.title, titleText)
                    it.setTextViewText(R.id.body, expandedBody)
                }
                builder.setCustomBigContentView(big)
            }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle())
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(expandedBody))
        }

        runCatching { notificationManager.notify(NOTIFICATION_ID, builder.build()) }
    }

    /**
     * Status-bar icon shared by the persistent date notification and the athan notification:
     * calendar frame with today's day number (or the plain "M" icon when the setting is off).
     */
    fun smallIcon(context: Context, payload: JSONObject? = null): IconCompat {
        val fallback = IconCompat.createWithResource(context, com.md6.mooncalendar.R.drawable.ic_stat_mooncalendar)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return fallback
        val p = prefs(context)
        if (!p.getBoolean(KEY_LARGE_DAY, true)) return fallback
        val item = payload ?: run {
            val key = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            findPayload(p.getString(KEY_PAYLOADS, null), key)
        } ?: return fallback
        val day = item.optString("day").toIntOrNull()?.takeIf { it in 1..31 }
            ?: item.optString("title").takeIf { it.isNotBlank() }?.let { extractDayNumber(it) }
            ?: return fallback
        return createDayIcon(context, day, item.optString("latin") == "1")
    }

    /** Applies the per-line style flags (heading / bold / light / underline). */
    private fun styledLine(text: String, tokens: Set<String>?, isTitle: Boolean): CharSequence {
        if (tokens.isNullOrEmpty() || text.isEmpty()) return text
        val sp = SpannableString(text)
        val end = text.length
        val flag = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        if ("heading" in tokens) {
            sp.setSpan(StyleSpan(android.graphics.Typeface.BOLD), 0, end, flag)
            if (!isTitle) sp.setSpan(RelativeSizeSpan(1.15f), 0, end, flag)
        }
        if ("bold" in tokens) sp.setSpan(StyleSpan(android.graphics.Typeface.BOLD), 0, end, flag)
        if ("light" in tokens) sp.setSpan(ForegroundColorSpan(Color.parseColor("#8E8E93")), 0, end, flag)
        if ("underline" in tokens) sp.setSpan(UnderlineSpan(), 0, end, flag)
        return sp
    }

    private fun extractDayNumber(title: String): Int {
        val normalized = buildString(title.length) {
            title.forEach { ch ->
                append(when (ch) {
                    '۰' -> '0'; '۱' -> '1'; '۲' -> '2'; '۳' -> '3'; '۴' -> '4';
                    '۵' -> '5'; '۶' -> '6'; '۷' -> '7'; '۸' -> '8'; '۹' -> '9'; else -> ch
                })
            }
        }
        val match = Regex("\\d{1,2}").find(normalized)
        return match?.value?.toIntOrNull()?.takeIf { it in 1..31 } ?: 1
    }

    // Interior of drawable/ic_stat_frame.png (384px square) as fractions of its size.
    private const val FRAME_IN_LEFT = 31f / 384f
    private const val FRAME_IN_RIGHT = 352f / 384f
    private const val FRAME_IN_TOP = 64f / 384f
    private const val FRAME_IN_BOTTOM = 350f / 384f
    private const val FRAME_STROKE = 30f / 384f
    private const val DIGIT_FILL = 0.94f

    private fun dayIconBitmap(context: Context, day: Int, latin: Boolean): Bitmap {
        val size = (48f * context.resources.displayMetrics.density).roundToInt().coerceAtLeast(96)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Same calendar frame as the athan icon (without the "M"), stretched to the full icon.
        val opts = android.graphics.BitmapFactory.Options().apply { inScaled = false }
        val frame = android.graphics.BitmapFactory.decodeResource(
            context.resources, com.md6.mooncalendar.R.drawable.ic_stat_frame, opts,
        )
        if (frame != null) {
            canvas.drawBitmap(
                frame, null, RectF(0f, 0f, size.toFloat(), size.toFloat()),
                Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
            )
            frame.recycle()
        }
        val inner = RectF(
            size * FRAME_IN_LEFT, size * FRAME_IN_TOP,
            size * FRAME_IN_RIGHT, size * FRAME_IN_BOTTOM,
        )

        val text = Tr.init(context).let { if (latin) day.toString() else Tr.digits(context, day.toString()) }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
            typeface = dayTypeface(context)
            textAlign = Paint.Align.LEFT // positioned manually from measured bounds
        }
        // Fit the digits inside the frame with a visible margin from the border.
        val margin = size * FRAME_STROKE * 0.25f
        val innerW = inner.width() - margin * 2f
        val innerH = inner.height() - margin * 2f
        textPaint.textSize = size.toFloat()
        val bounds = android.graphics.Rect()
        textPaint.getTextBounds(text, 0, text.length, bounds)
        val scale = minOf(innerW / bounds.width().coerceAtLeast(1), innerH / bounds.height().coerceAtLeast(1))
        // DIGIT_FILL < 1 leaves clear breathing room between the digits and the frame.
        textPaint.textSize = size * scale * DIGIT_FILL
        textPaint.getTextBounds(text, 0, text.length, bounds)
        // Ink box centred exactly on the frame interior centre (both axes).
        val x = inner.centerX() - bounds.exactCenterX()
        val y = inner.centerY() - bounds.exactCenterY()
        canvas.drawText(text, x, y, textPaint)
        return bitmap
    }

    @Volatile private var cachedDayTypeface: android.graphics.Typeface? = null

    /** Vazirmatn Regular (assets/fonts/day_icon_font.ttf) with a safe system fallback. */
    private fun dayTypeface(context: Context): android.graphics.Typeface {
        cachedDayTypeface?.let { return it }
        val face = try {
            android.graphics.Typeface.createFromAsset(context.applicationContext.assets, "fonts/day_icon_font.ttf")
        } catch (e: Exception) {
            android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        }
        cachedDayTypeface = face
        return face
    }

    private fun createDayIcon(context: Context, day: Int, latin: Boolean = false): IconCompat = IconCompat.createWithBitmap(dayIconBitmap(context, day, latin))

    private fun persianDigits(value: Int): String {
        val western = value.toString()
        return western.map { ch ->
            when (ch) {
                '0' -> '۰'; '1' -> '۱'; '2' -> '۲'; '3' -> '۳'; '4' -> '۴';
                '5' -> '۵'; '6' -> '۶'; '7' -> '۷'; '8' -> '۸'; '9' -> '۹'; else -> ch
            }
        }.joinToString("")
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            Tr.t(context, "اعلان همیشگی تقویم"),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = Tr.t(context, "تاریخ و اطلاعات روزانه Mooncalendar")
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    // The payload list covers a year (hundreds of entries). It is looked up on every refresh (midnight,
    // screen on, hourly job), so the parsed array is kept until the stored text changes.
    @Volatile private var parsedRaw: String? = null
    @Volatile private var parsedArray: JSONArray? = null

    private fun payloadArray(raw: String): JSONArray {
        val cached = parsedArray
        if (cached != null && parsedRaw == raw) return cached
        val array = JSONArray(raw)
        parsedArray = array
        parsedRaw = raw
        return array
    }

    private fun findPayload(raw: String?, key: String): JSONObject? {
        if (raw.isNullOrBlank()) return null
        return runCatching {
            val array = payloadArray(raw)
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                if (item.optString("date") == key) return item
            }
            null
        }.getOrNull()
    }
}
