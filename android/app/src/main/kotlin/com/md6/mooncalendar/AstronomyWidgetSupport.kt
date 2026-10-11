package com.md6.mooncalendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import java.util.Calendar
import java.util.TimeZone

/** Shared native helpers for the three Android widgets that are not part of Flutter's UI tree. */
object AstronomyWidgetSupport {
    const val IRAN_TZ = "Asia/Tehran"

    /**
     * Exact size of the widget in *pixels*, so that generated bitmaps are drawn 1:1 for the space the
     * launcher really gives the widget. They must never be up-scaled by the ImageView (that is what made
     * the text look huge/blurry when a fixed-size bitmap was stretched over a larger widget).
     *
     * Only the RemoteViews Binder/memory budget can shrink the result: a widget's bitmaps together must
     * stay below ~1.5x the screen's byte size, so each bitmap is limited to 45% of the screen pixels.
     * That only ever triggers for widgets that cover almost the whole screen.
     */
    fun widgetSizePx(context: Context, manager: AppWidgetManager, widgetId: Int, defaultW: Int = 250, defaultH: Int = 120): Pair<Int, Int> {
        val (wDp, hDp) = widgetSizeDp(context, manager, widgetId, defaultW, defaultH)
        val d = context.resources.displayMetrics.density
        var w = (wDp * d).roundToInt().coerceAtLeast(64)
        var h = (hDp * d).roundToInt().coerceAtLeast(64)
        val dm = context.resources.displayMetrics
        val budget = dm.widthPixels.toDouble() * dm.heightPixels.toDouble() * 0.45
        val pixels = w.toDouble() * h.toDouble()
        if (pixels > budget) {
            val k = kotlin.math.sqrt(budget / pixels)
            w = (w * k).roundToInt().coerceAtLeast(64)
            h = (h * k).roundToInt().coerceAtLeast(64)
        }
        return w to h
    }

    fun widgetSizeDp(context: Context, manager: AppWidgetManager, widgetId: Int, defaultW: Int = 250, defaultH: Int = 120): Pair<Int, Int> {
        val o = manager.getAppWidgetOptions(widgetId)
        val landscape = context.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        // Portrait: the widget is min-width x max-height. Landscape: max-width x min-height.
        val w = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val h = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        return (if (w > 0) w else defaultW) to (if (h > 0) h else defaultH)
    }

    fun zone(prefs: android.content.SharedPreferences): TimeZone =
        if (bool(prefs, Widget4x2.PREF_IRAN_TIME, false)) TimeZone.getTimeZone(IRAN_TZ) else TimeZone.getDefault()

    fun bool(prefs: android.content.SharedPreferences, key: String, fallback: Boolean): Boolean {
        val value = prefs.all[key] ?: return fallback
        return when (value) {
            is Boolean -> value
            is String -> value.toBooleanStrictOrNull() ?: fallback
            is Number -> value.toInt() != 0
            else -> fallback
        }
    }

    fun parseColor(raw: String?, fallback: Int): Int = runCatching {
        val value = raw?.trim().orEmpty()
        if (value.isBlank()) return@runCatching fallback
        Color.parseColor(if (value.startsWith("#")) value else "#$value")
    }.getOrDefault(fallback)

    fun readColor(prefs: android.content.SharedPreferences, key: String, fallback: Int): Int =
        when (val value = prefs.all[key]) {
            is Number -> value.toInt()
            is String -> parseColor(value, fallback)
            else -> fallback
        }

    fun parseMinutes(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        val ascii = raw.trim()
            .replace('۰', '0').replace('۱', '1').replace('۲', '2').replace('۳', '3').replace('۴', '4')
            .replace('۵', '5').replace('۶', '6').replace('۷', '7').replace('۸', '8').replace('۹', '9')
        val parts = ascii.split(':')
        val h = parts.firstOrNull()?.toIntOrNull() ?: return null
        val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
        return ((h % 24) * 60 + m).coerceIn(0, 1439)
    }

    fun persianDigits(value: String): String = Tr.digits(value)

    fun roundedBackground(context: Context, width: Int, height: Int, color: Int, radiusDp: Float = 16f): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val d = context.resources.displayMetrics.density
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()),
            radiusDp * d,
            radiusDp * d,
            paint,
        )
        return bitmap
    }

    fun applyBackground(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        widgetId: Int,
        width: Int,
        height: Int,
        prefs: android.content.SharedPreferences,
    ) {
        val dynamic = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
        if (dynamic) {
            views.setImageViewResource(viewId, R.drawable.widget_background)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alpha = 1f - Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f).coerceIn(0f, 1f)
                views.setFloat(viewId, "setAlpha", alpha)
            }
        } else {
            val color = readColor(
                prefs, Widget4x2.PREF_SELECTED_WIDGET_BACKGROUND_COLOR, Color.TRANSPARENT,
            )
            val transparency = Widget4x2.readFloat(
                prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f,
            ).coerceIn(0f, 1f)
            val effectiveColor = Color.argb(
                (Color.alpha(color) * (1f - transparency)).roundToInt().coerceIn(0, 255),
                Color.red(color),
                Color.green(color),
                Color.blue(color),
            )
            if (Color.alpha(effectiveColor) == 0 || effectiveColor == Color.TRANSPARENT) {
                views.setImageViewResource(viewId, 0)
            } else {
                views.setImageViewBitmap(viewId, roundedBackground(context, width, height, effectiveColor))
            }
        }
    }

    fun applyTextColor(context: Context, prefs: android.content.SharedPreferences, dynamic: Boolean): Int {
        return if (dynamic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.getColor(context, R.color.widget_foreground)
        } else {
            readColor(
                prefs, Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR, Color.WHITE,
            )
        }
    }

    /**
     * Explicit intent for the real activity. It must NOT be built from getLaunchIntentForPackage():
     * that returns whichever launcher <activity-alias> is enabled *right now*, and the day-number
     * icon feature disables the previous alias every day. A PendingIntent baked into a widget or
     * notification would then point at a disabled component and tapping it would do nothing.
     */
    fun mainActivityIntent(context: Context, action: String? = null): Intent =
        Intent(context, MainActivity::class.java).apply {
            this.action = action ?: Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

    fun launchApp(context: Context, action: String? = null, requestCode: Int? = null): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode ?: ((action?.hashCode() ?: 0) + 5000),
            mainActivityIntent(context, action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * Fraction through the synodic month. The epoch is a commonly used new-moon
     * reference; this is intentionally dependency-free so the launcher can update
     * the widget without starting Flutter.
     */
    fun lunarPhaseFraction(timeMillis: Long): Double {
        val jd = 2440587.5 + timeMillis / 86400000.0
        val synodic = 29.530588853
        val epoch = 2451550.09765
        var f = (jd - epoch) / synodic
        f -= kotlin.math.floor(f)
        return if (f < 0) f + 1 else f
    }

    fun moonPhaseDegrees(timeMillis: Long): Double = lunarPhaseFraction(timeMillis) * 360.0

    fun drawMoon(
        context: Context,
        canvas: Canvas,
        timeMillis: Long,
        cx: Float,
        cy: Float,
        radius: Float,
    ) {
        val drawable = context.getDrawable(R.drawable.ic_moon) ?: return
        val safeRadius = radius.coerceAtLeast(2f)
        drawable.alpha = 255
        drawable.setBounds(
            (cx - safeRadius).toInt(), (cy - safeRadius).toInt(),
            (cx + safeRadius).toInt(), (cy + safeRadius).toInt(),
        )
        drawable.draw(canvas)

        val phase = moonPhaseDegrees(timeMillis)
        val sr = safeRadius * .97f
        val arcWidth = (cos(Math.toRadians(phase)) * sr).toFloat()
        val path = Path()
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x90000000.toInt() }
        val rotation = if (phase < 180.0) 180f else 0f
        canvas.save()
        canvas.rotate(rotation, cx, cy)
        path.arcTo(
            cx - kotlin.math.abs(arcWidth), cy - sr,
            cx + kotlin.math.abs(arcWidth), cy + sr,
            90f,
            if (arcWidth > 0) 180f else -180f,
            false,
        )
        path.arcTo(cx - sr, cy - sr, cx + sr, cy + sr, 270f, 180f, false)
        path.close()
        canvas.drawPath(path, shadow)
        canvas.restore()
    }

    @Volatile
    private var vazirTypeface: android.graphics.Typeface? = null

    /** The app's own font (Vazirmatn, bundled by Flutter), so the widget text is identical to the app. */
    fun appTypeface(context: Context): android.graphics.Typeface {
        vazirTypeface?.let { return it }
        val loaded = runCatching {
            android.graphics.Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/Vazirmatn-Regular.ttf")
        }.getOrNull() ?: android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        vazirTypeface = loaded
        return loaded
    }


    /** Same wording as Flutter's clockRemainingText (Clock.kt): "۱۱س ۵۳د" or the long form. */
    private fun clockRemainingText(value: Double): String {
        if (value.isNaN()) return ""
        val hours = value.toInt()
        val minutes = ((value - hours) * 60).toInt()
        if (hours != 0 && minutes != 0) return "${persianDigits(hours.toString())}س ${persianDigits(minutes.toString())}د"
        val parts = buildList {
            if (hours != 0) add("${persianDigits(hours.toString())} ساعت")
            if (minutes != 0) add("${persianDigits(minutes.toString())} دقیقه")
        }
        return if (parts.isEmpty()) "${persianDigits("0")} دقیقه" else parts.joinToString(" و ")
    }

    /**
     * Native port of lib/ui/widgets/sun_view.dart, drawn 1:1 for the widget's real pixel size.
     *
     * Differences from the in-app view that are deliberate:
     *  - the app view is unclipped (the moon/text may overflow its box), a widget bitmap is not, so the
     *    scene is drawn inside a padded content rect that leaves room for the moon, sun and labels;
     *  - the whole bitmap is clipped to the widget's rounded corners so fills never square them off.
     */
    fun drawSunPath(
        context: Context,
        prefs: android.content.SharedPreferences,
        width: Int,
        height: Int,
        nowMillis: Long,
    ): Pair<Bitmap, String?> {
        val bw = width.coerceAtLeast(1)
        val bh = height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val density = context.resources.displayMetrics.density

        val dynamic = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
        val nightMode = (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val textColor = if (dynamic) {
            if (nightMode) Color.WHITE else Color.BLACK
        } else {
            readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR, Color.WHITE)
        }
        val day = ContextCompat.getColor(context, if (dynamic) R.color.sun_view_dynamic_day_color else R.color.sun_view_day_color)
        val midday = ContextCompat.getColor(context, if (dynamic) R.color.sun_view_dynamic_midday_color else R.color.sun_view_midday_color)
        val night = ContextCompat.getColor(context, if (dynamic) R.color.sun_view_dynamic_night_color else R.color.sun_view_night_color)
        val linesColor = Color.argb(64, Color.red(textColor), Color.green(textColor), Color.blue(textColor))
        val secondaryColor = Color.argb(191, Color.red(textColor), Color.green(textColor), Color.blue(textColor))
        val sunriseText = Color.rgb(255, 152, 0)
        val middayText = Color.rgb(255, 193, 7)
        val sunsetText = Color.rgb(242, 36, 36)
        // Follows the app language (Persian / Arabic right-to-left, English left-to-right).
        val rtl = Tr.isRtl()

        val sunTimes = Widget4x2.sunriseSunsetHours(prefs)
        val sunrise = sunTimes?.first
        val sunset = sunTimes?.second
        if (sunrise == null || sunset == null || sunset <= sunrise) {
            return bitmap to "ابتدا موقعیت جغرافیایی را برای نمایش اوقات شرعی تنظیم کنید"
        }

        val cal = Calendar.getInstance(zone(prefs)).apply { timeInMillis = nowMillis }
        val now = cal.get(Calendar.HOUR_OF_DAY) + cal.get(Calendar.MINUTE) / 60.0 + cal.get(Calendar.SECOND) / 3600.0
        val current = when {
            now <= sunrise -> safeDivide(now, sunrise) * .17
            now <= sunset -> safeDivide(now - sunrise, sunset - sunrise) * .66 + .17
            else -> safeDivide(now - sunset, 24 - sunset) * .17 + .17 + .66
        }
        val value = current.coerceIn(0.0, 1.0).toFloat()

        // ---- content rect: same geometry as the app, inset so nothing is cut off ----
        val labelSize = 14f * density
        val bottomSize = 12f * density
        val padX = 6f * density
        val cw = (bw - 2 * padX).coerceAtLeast(1f)
        var padTop = 4f * density
        var padBottom = 8f * density
        repeat(3) {
            val ch = (bh - padTop - padBottom).coerceAtLeast(1f)
            val r = kotlin.math.sqrt(cw * ch * .002f)
            // top: sun at noon (cy = .10h) and the sunrise/sunset labels (baseline .20h, ~0.95em tall)
            padTop = maxOf(3f * density, r - .10f * ch, labelSize * .95f - .20f * ch) + 3f * density
            // bottom: moon at the curve's end (cy ~ h) and text descenders below the .94h baseline
            padBottom = maxOf(r, bottomSize * .3f - .06f * ch) + 3f * density
        }
        val ch = (bh - padTop - padBottom).coerceAtLeast(1f)

        val corner = 16f * density
        canvas.clipPath(Path().apply { addRoundRect(RectF(0f, 0f, bw.toFloat(), bh.toFloat()), corner, corner, Path.Direction.CW) })
        canvas.translate(padX, padTop)

        val w = cw
        val h = ch
        fun y(x: Float): Float = h * (.55f + cos(x / w * 2.0 * Math.PI).toFloat() * .45f)
        // Extend the actual fill path into the side padding. The visible line already reaches these
        // coordinates; using the same curve for the fill prevents a thin uncolored strip between the
        // colored region and the line at either frame edge.
        val curveStart = -padX
        val curveEnd = w + padX
        val curve = Path().apply {
            moveTo(curveStart, y(curveStart))
            var x = curveStart
            while (x <= curveEnd) { lineTo(x, y(x)); x += 1f }
        }
        val dayPath = Path(curve).apply {
            // Close the daylight region against the bottom, just like the original path did at
            // x=0/w, but now including the side padding so the fill reaches the frame edge.
            lineTo(curveEnd, h)
            lineTo(curveStart, h)
            close()
        }
        val endX = curveEnd
        val nightPath = Path(curve).apply {
            lineTo(endX, h); lineTo(endX, 0f); lineTo(curveStart, 0f); close()
        }
        val dayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = android.graphics.LinearGradient(
                (kotlin.math.acos(4.0 / 9.0) / (2.0 * Math.PI) * w).toFloat(), 0f, w / 2f, 0f, day, midday, android.graphics.Shader.TileMode.MIRROR,
            )
        }
        val nightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = night }

        canvas.save()
        if (rtl) {
            canvas.translate(w / 2f, 0f)
            canvas.scale(-1f, 1f)
            canvas.translate(-w / 2f, 0f)
        }
        val valuePx = w * value
        canvas.save()
        canvas.clipRect(-padX, h * .75f, valuePx, h)
        canvas.drawPath(nightPath, nightPaint)
        canvas.restore()
        canvas.save()
        canvas.clipRect(-padX, 0f, valuePx, h * .75f)
        canvas.drawPath(dayPath, dayPaint)
        canvas.restore()
        canvas.restore()

        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = density; color = linesColor
        }
        val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeWidth = .75f * density; color = linesColor
        }
        // The curve already spans the exact same visible range as the straight line.
        canvas.drawPath(curve, linePaint)
        canvas.drawLine(-padX, h * .75f, w + padX, h * .75f, linePaint)
        // Put the sunrise/sunset guides exactly at the two curve/horizon intersections.
        // Solving .55 + .45*cos(2*pi*x/w) = .75 gives cos(...) = 4/9.
        val guideX = kotlin.math.acos(4.0 / 9.0) / (2.0 * Math.PI) * w
        val guideRightX = w - guideX
        canvas.drawLine(guideX.toFloat(), h * .3f, guideX.toFloat(), h * .75f, guidePaint)
        canvas.drawLine(guideRightX.toFloat(), h * .3f, guideRightX.toFloat(), h * .75f, guidePaint)
        canvas.drawLine(w / 2f, h * .7f, w / 2f, h * .8f, guidePaint)

        val radius = kotlin.math.sqrt(w * h * .002f)
        val cx = w * if (rtl) 1f - value else value
        val cy = y(cx)
        if (value >= .17f && value <= .83f) {
            canvas.save()
            canvas.translate(cx, cy)
            canvas.rotate(value * if (rtl) -900f else 900f)
            canvas.translate(-cx, -cy)
            drawWidgetSun(canvas, cx, cy, radius, sunColorFor(value))
            canvas.restore()
        } else {
            drawMoon(context, canvas, nowMillis, cx, cy, radius)
        }

        // Text: the Flutter painter puts the ALPHABETIC BASELINE at the given y (not the text centre).
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = appTypeface(context)
            isSubpixelText = true
            isLinearText = true
        }
        fun drawLabel(rawText: String, x: Float, baseline: Float, color: Int, sizePx: Float, maxWidth: Float? = null) {
            val text = Tr.t(rawText)
            if (text.isBlank()) return
            textPaint.color = color
            textPaint.textSize = sizePx
            if (maxWidth != null && maxWidth > 0f) {
                val measured = textPaint.measureText(text)
                if (measured > maxWidth) {
                    textPaint.textSize = (sizePx * maxWidth / measured).coerceIn(8.5f * density, sizePx)
                }
            }
            canvas.drawText(text, x, baseline, textPaint)
        }
        drawLabel("طلوع", if (rtl) guideRightX.toFloat() else guideX.toFloat(), h * .2f, sunriseText, labelSize)
        drawLabel("ظهر", w / 2f, h * .94f, middayText, labelSize)
        drawLabel("غروب", if (rtl) guideX.toFloat() else guideRightX.toFloat(), h * .2f, sunsetText, labelSize)

        val inDay = now >= sunrise && now <= sunset
        val dayLengthText = "طول روز: ${clockRemainingText(sunset - sunrise)}"
        val remainingText = if (inDay) "باقی‌مانده: ${clockRemainingText(sunset - now)}" else ""
        // Bottom labels stay strictly between the guide lines and the midday label.
        val edgeGap = 6f * density
        val midGap = 20f * density
        val leftStart = guideX.toFloat() + edgeGap
        val leftEnd = w * .5f - midGap
        val rightStart = w * .5f + midGap
        val rightEnd = guideRightX.toFloat() - edgeGap
        val leftCenter = (leftStart + leftEnd) / 2f
        val rightCenter = (rightStart + rightEnd) / 2f
        val bottomMax = (leftEnd - leftStart).coerceAtLeast(1f)
        drawLabel(dayLengthText, if (rtl) rightCenter else leftCenter, h * .94f, secondaryColor, bottomSize, bottomMax)
        drawLabel(remainingText, if (rtl) leftCenter else rightCenter, h * .94f, secondaryColor, bottomSize, bottomMax)

        return bitmap to null
    }

    private fun sunColorFor(progress: Float): Int {
        val p = progress.coerceIn(0f, 1f)
        val a = Color.rgb(255, 249, 196)
        val b = Color.rgb(255, 145, 0)
        fun mix(x: Int, y: Int): Int = (x + ((y - x) * p)).roundToInt()
        return Color.rgb(mix(Color.red(a), Color.red(b)), mix(Color.green(a), Color.green(b)), mix(Color.blue(a), Color.blue(b)))
    }

    private fun drawWidgetSun(canvas: Canvas, cx: Float, cy: Float, radius: Float, color: Int) {
        val r = radius.coerceAtLeast(2f)
        val p = Path().apply {
            moveTo(256f,44f); lineTo(325f,2f); lineTo(361f,72f); lineTo(443f,67.6f); lineTo(439.3f,150.6f)
            lineTo(511.3f,187.6f); lineTo(467.3f,255.6f); lineTo(511.3f,321.6f); lineTo(439.3f,360.6f)
            lineTo(443.7f,441.6f); lineTo(363.7f,437.4f); lineTo(325.7f,507.4f); lineTo(255.7f,466.4f)
            lineTo(187.7f,508.4f); lineTo(150.7f,438.4f); lineTo(68.7f,442.5f); lineTo(73.6f,361.5f)
            lineTo(2.6f,324.5f); lineTo(44.6f,254.5f); lineTo(2.6f,188.5f); lineTo(73.6f,148.5f)
            lineTo(69.9f,67.5f); lineTo(149.9f,71.7f); lineTo(189.9f,.7f); close()
        }
        canvas.save()
        canvas.translate(cx - r, cy - r)
        canvas.scale(2f * r / 512f, 2f * r / 512f)
        canvas.drawPath(p, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.argb(176, Color.red(color), Color.green(color), Color.blue(color)) })
        canvas.drawCircle(256f, 256f, 194f, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color })
        canvas.restore()
    }

    private fun safeDivide(a: Double, b: Double): Double = if (b == 0.0) 0.0 else a / b

    private fun formatDuration(minutes: Int): String {
        val h = (minutes.coerceAtLeast(0)) / 60
        val m = minutes.coerceAtLeast(0) % 60
        return persianDigits("${h}س ${m}د")
    }
}
