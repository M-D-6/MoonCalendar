package com.md6.mooncalendar

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.content.Intent
import android.graphics.BlurMaskFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.Log
import android.widget.RemoteViews
import java.util.concurrent.Executors
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.cos
import kotlin.math.asin
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Lightweight bitmap world-map widget. It mirrors the Android map screen's visual language
 * without starting Flutter or requiring a network map SDK. */
class WidgetMap : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Tr.init(context)
        // Render on the worker thread but keep the process alive until it is done (goAsync).
        val pending = goAsync()
        EXECUTOR.execute {
            try {
                ids.forEach { renderOne(context, manager, it) }
            } finally {
                pending.finish()
            }
        }
    }

    override fun onEnabled(context: Context) {
        EXECUTOR.execute { runCatching { WorldMapRenderer.preload(context) } }
        updateAll(context)
        super.onEnabled(context)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        for (i in minOf(oldWidgetIds.size, newWidgetIds.size) downTo 1) {
            Widget4x2.copyWidgetSettings(context, oldWidgetIds[i - 1], newWidgetIds[i - 1])
        }
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { Widget4x2.clearWidgetSettings(context, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateOne(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        Tr.init(context)
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> updateAll(context)
        }
    }

    private fun updateOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
        // Resizing fires onAppWidgetOptionsChanged many times in a row; a render already waiting in the
        // queue will pick up the latest size anyway, so never queue more than one per widget.
        if (!QUEUED.add(widgetId)) return
        EXECUTOR.execute {
            QUEUED.remove(widgetId)
            renderOne(context, manager, widgetId)
        }
    }

    /**
     * Renders one widget instance synchronously. The static preview image is deliberately NOT pushed
     * first: it is an un-themed, opaque picture and showing it (even briefly) is what made the widget
     * appear without the user's theme/transparency until the real bitmap arrived. If rendering fails
     * the previously shown RemoteViews simply stay in place.
     */
    private fun renderOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
        runCatching {
                val prefs = Widget4x2.widgetPrefs(context, widgetId)
                val (width, height) = AstronomyWidgetSupport.widgetSizePx(context, manager, widgetId, 250, 110)
                val views = RemoteViews(context.packageName, R.layout.widget_map)
                // The map bitmap owns its fixed blue/warm map colors; only the shared transparency
                // setting is applied to the final image layer.
                views.setViewVisibility(R.id.map_background, android.view.View.GONE)
                val bitmap = WorldMapRenderer.render(context, prefs, width, height)
                views.setImageViewBitmap(R.id.image_map, bitmap)
                views.setContentDescription(R.id.image_map, Tr.t("نقشهٔ جهان و وضعیت روز و شب"))
                views.setOnClickPendingIntent(
                    R.id.widget_map_root,
                    AstronomyWidgetSupport.launchApp(context, "com.md6.Mooncalendar.SHORTCUT_MAP"),
                )
                manager.updateAppWidget(widgetId, views)
        }.onFailure {
            // A failed render must still show the recognizable blue map instead of a blank widget.
            Log.e(TAG, "Map update failed for $widgetId; showing preview", it)
            runCatching { manager.updateAppWidget(widgetId, safeRemoteViews(context, manager, widgetId)) }
        }
    }

    private fun safeRemoteViews(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_map).also {
            // Last-resort fallback: first retry the real renderer so shared transparency still applies
            // only to the sky. The static preview is used only when the renderer itself is unavailable.
            it.setViewVisibility(R.id.map_background, android.view.View.GONE)
            val prefs = Widget4x2.widgetPrefs(context, widgetId)
            val bitmap = runCatching {
                val (width, height) = AstronomyWidgetSupport.widgetSizePx(context, manager, widgetId, 250, 110)
                WorldMapRenderer.render(context, prefs, width, height)
            }.getOrElse {
                BitmapFactory.decodeResource(context.resources, R.drawable.widget_map_preview)
            }
            it.setImageViewBitmap(R.id.image_map, bitmap)
            it.setContentDescription(R.id.image_map, Tr.t("نقشهٔ جهان و وضعیت روز و شب"))
            it.setOnClickPendingIntent(
                R.id.widget_map_root,
                AstronomyWidgetSupport.launchApp(context, "com.md6.Mooncalendar.SHORTCUT_MAP"),
            )
        }

    companion object {
        private const val TAG = "MoonCalendarWidgetMap"
        private val QUEUED: MutableSet<Int> = java.util.concurrent.ConcurrentHashMap.newKeySet()
        private val EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MoonCalendarWidgetMap").apply { isDaemon = true }
        }
        /** Live preview for one configured widget instance. */
        fun renderPreview(
            context: Context,
            widgetId: Int,
            width: Int,
            height: Int,
            dynamic: Boolean,
            transparency: Float,
        ): Bitmap = WorldMapRenderer.render(
            context, Widget4x2.widgetPrefs(context, widgetId),
            width, height, dynamic, transparency,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WidgetMap::class.java))
            ids.forEach { WidgetMap().updateOne(context, manager, it) }
        }
    }
}

private object WorldMapRenderer {
    private const val MAP_W = 5760f
    private const val MAP_H = 2880f
    @Volatile
    private var cachedPath: Path? = null
    @Volatile
    private var cachedBitmap: Bitmap? = null
    @Volatile
    private var cachedKey: MapCacheKey? = null
    @Volatile
    private var cachedSunBitmap: Bitmap? = null

    private data class MapCacheKey(
        val minute: Long,
        val width: Int,
        val height: Int,
        val latitude: Double?,
        val longitude: Double?,
        // The *resolved* colors are part of the key (not just "dynamic on/off"), so a wallpaper /
        // Material-You change, a dark-mode switch, a new custom color or a new transparency value
        // can never be answered from a stale cached bitmap.
        val ocean: Int,
        val land: Int,
        val shade: Int,
        val pin: Int,
        val border: Int,
    )

    /** Fixed visual palette for the map. Device/custom widget theme never recolors the map itself.
     * Shared widget transparency is applied to the final image layer. */
    private data class MapPalette(
        val ocean: Int,
        val land: Int,
        val shade: Int,
        val pin: Int,
        val border: Int,
    )

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha.coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

    private fun scaleAlpha(color: Int, factor: Float): Int =
        withAlpha(color, (Color.alpha(color) * factor.coerceIn(0f, 1f)).roundToInt())

    private fun palette(
        context: Context,
        prefs: android.content.SharedPreferences,
        dynamicOverride: Boolean? = null,
        transparencyOverride: Float? = null,
    ): MapPalette {
        // The map keeps the original themed behaviour when the device/system theme is enabled.
        // When that option is disabled, only the SKY/OCEAN falls back to the map's original
        // blue; land, night shading, pin and border keep the normal widget palette.
        // Transparency belongs to the SKY/OCEAN layer only, matching the original widget behaviour.
        val dynamic = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
            (dynamicOverride ?: AstronomyWidgetSupport.bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true))
        val transparency = (transparencyOverride
            ?: Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f)).coerceIn(0f, 1f)
        val oceanAlpha = 1f - transparency
        val originalBlue = Color.rgb(137, 171, 192)

        return if (dynamic) {
            // Follow the device colors exactly like the original map widget. Transparency only
            // affects the sky/background and its border; the map artwork stays fully opaque.
            val background = androidx.core.content.ContextCompat.getColor(context, R.color.widget_background)
            val accent = androidx.core.content.ContextCompat.getColor(context, R.color.widget_accent)
            val divider = androidx.core.content.ContextCompat.getColor(context, R.color.widget_divider)
            val holiday = androidx.core.content.ContextCompat.getColor(context, R.color.remote_view_holiday_color)
            val shadeBase = androidx.core.content.ContextCompat.getColor(context, android.R.color.system_accent2_900)
            MapPalette(
                ocean = scaleAlpha(background, oceanAlpha),
                land = accent,
                shade = withAlpha(shadeBase, 255),
                pin = holiday,
                border = scaleAlpha(divider, oceanAlpha),
            )
        } else {
            // Theme disabled: restore the map's characteristic blue sky instead of recoloring the
            // entire map with the selected widget background. Only that sky layer receives the
            // shared transparency setting.
            val foreground = AstronomyWidgetSupport.readColor(
                prefs, Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR, Color.WHITE,
            )
            val backgroundStrength = oceanAlpha
            MapPalette(
                ocean = withAlpha(originalBlue, (255f * backgroundStrength).roundToInt()),
                land = foreground,
                shade = Color.rgb(8, 13, 18),
                pin = Color.rgb(246, 71, 76),
                border = scaleAlpha(withAlpha(foreground, 110), backgroundStrength),
            )
        }
    }

    fun preload(context: Context) { loadWorldPath(context) }

    fun render(
        context: Context,
        prefs: android.content.SharedPreferences,
        width: Int,
        height: Int,
        dynamicOverride: Boolean? = null,
        transparencyOverride: Float? = null,
    ): Bitmap {
        // Exact widget pixel size: the bitmap is rendered for the size it is shown at (never stretched).
        // The world map is 2:1. Like the Persian Calendar Android widget it is drawn at that ratio (never
        // stretched) inside the widget; the bitmap is capped so rendering stays fast and RemoteViews
        // never gets an oversized bitmap.
        val maxSide = 1100
        val shrink = minOf(1f, maxSide.toFloat() / maxOf(width, height, 1))
        val w = (width * shrink).roundToInt().coerceAtLeast(32)
        val h = (height * shrink).roundToInt().coerceAtLeast(32)
        val latitude = readDouble(prefs, Widget4x2.PREF_LATITUDE)?.takeIf { it in -90.0..90.0 }
        val longitude = readDouble(prefs, Widget4x2.PREF_LONGITUDE)?.takeIf { it in -180.0..180.0 }
        val transparency = (transparencyOverride
            ?: Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f)).coerceIn(0f, 1f)
        val colors = palette(context, prefs, dynamicOverride, transparency)
        val key = MapCacheKey(
            System.currentTimeMillis() / 60_000L, w, h, latitude, longitude,
            colors.ocean, colors.land, colors.shade, colors.pin, colors.border,
        )
        synchronized(this) {
            if (cachedKey == key) cachedBitmap?.let { return it.copy(Bitmap.Config.ARGB_8888, false) }
        }

        val bitmap = renderFresh(context, w, h, latitude, longitude, colors)
        synchronized(this) {
            cachedBitmap?.recycle()
            cachedBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
            cachedKey = key
        }
        return bitmap
    }

    private fun readDouble(prefs: android.content.SharedPreferences, key: String): Double? =
        when (val value = prefs.all[key]) {
            is Number -> value.toDouble()
            is String -> value.toDoubleOrNull()
            else -> null
        }

    private fun renderFresh(
        context: Context,
        w: Int,
        h: Int,
        latitude: Double?,
        longitude: Double?,
        colors: MapPalette,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val density = context.resources.displayMetrics.density
        // Largest 2:1 rectangle that fits, centered (the same fit-center behaviour as the original).
        val mapW = minOf(w.toFloat(), h * 2f)
        val mapH = mapW / 2f
        val left = (w - mapW) / 2f
        val top = (h - mapH) / 2f
        val radius = minOf(16f * density, mapH / 2f)
        val hasBackground = Color.alpha(colors.ocean) > 0

        canvas.save()
        canvas.clipPath(Path().apply {
            addRoundRect(RectF(left, top, left + mapW, top + mapH), radius, radius, Path.Direction.CW)
        })
        canvas.translate(left, top)

        if (hasBackground) {
            canvas.drawRect(0f, 0f, mapW, mapH, Paint().apply { color = colors.ocean })
        }

        val world = loadWorldPath(context)
        val scaled = Path(world)
        scaled.transform(android.graphics.Matrix().apply { setScale(mapW / MAP_W, mapH / MAP_H) })
        canvas.drawPath(scaled, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colors.land
            style = Paint.Style.FILL
        })
        if (Color.alpha(colors.ocean) < 96) {
            canvas.drawPath(scaled, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(150, 0, 0, 0)
                style = Paint.Style.STROKE
                strokeWidth = max(0.75f, density * 0.6f)
                strokeJoin = Paint.Join.ROUND
            })
        }

        // Night side: the mask is computed on a coarse 1-degree grid (360x180, like the Persian Calendar app's
        // low-resolution mask) and drawn scaled with filtering, which gives a soft terminator at a
        // tiny fraction of the cost of a per-pixel loop.
        val day = solarSubpoint(System.currentTimeMillis())
        val gw = 360
        val gh = 180
        val shadeRgb = colors.shade and 0x00FFFFFF
        val cosLon = DoubleArray(gw) { x -> cos(Math.toRadians(normalizeLongitude((x + .5) - 180.0 - day.second))) }
        val pix = IntArray(gw * gh)
        for (y in 0 until gh) {
            val latR = Math.toRadians(90.0 - (y + .5))
            val sinTerm = sin(latR) * day.first.sinDeclination
            val cosTerm = cos(latR) * day.first.cosDeclination
            val row = y * gw
            for (x in 0 until gw) {
                val cosZenith = sinTerm + cosTerm * cosLon[x]
                val transition = ((-cosZenith + 0.08) / 0.16).coerceIn(0.0, 1.0)
                pix[row + x] = ((transition * 150.0).toInt() shl 24) or shadeRgb
            }
        }
        val nightOverlay = Bitmap.createBitmap(pix, gw, gh, Bitmap.Config.ARGB_8888)
        canvas.drawBitmap(
            nightOverlay, null, RectF(0f, 0f, mapW, mapH),
            Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
        )
        nightOverlay.recycle()

        val minSide = min(mapW, mapH)
        // Use the exact astronomy artwork used elsewhere in the app. The moon is rendered through
        // AstronomyWidgetSupport so its phase/shadow treatment stays identical to the astronomy UI.
        val sunX = (((day.second + 180.0) / 360.0) * mapW).let { v ->
            val wrapped = v % mapW.toDouble()
            if (wrapped < 0) wrapped + mapW else wrapped
        }.toFloat()
        val sunY = ((90.0 - Math.toDegrees(asin(day.first.sinDeclination))) / 180.0 * mapH).toFloat()
        drawSunAsset(context, canvas, sunX, sunY, minSide * .065f)

        val moonLon = normalizeLongitude(day.second + 180.0)
        val moonX = ((moonLon + 180.0) / 360.0 * mapW).coerceIn(0.0, mapW.toDouble()).toFloat()
        val moonY = ((90.0 + Math.toDegrees(asin(day.first.sinDeclination))) / 180.0 * mapH).toFloat()
        AstronomyWidgetSupport.drawMoon(context, canvas, System.currentTimeMillis(), moonX, moonY, minSide * .045f)

        // Current location pin.
        if (latitude != null && longitude != null) {
            val px = ((longitude + 180.0) / 360.0 * mapW).coerceIn(0.0, mapW.toDouble()).toFloat()
            val py = ((90.0 - latitude) / 180.0 * mapH).coerceIn(0.0, mapH.toDouble()).toFloat()
            val r = minSide * .034f // head radius
            val cy = py - 2.25f * r // head centre; the tip sits exactly on the coordinate
            val pinPath = Path().apply {
                moveTo(px, py)
                cubicTo(px - .32f * r, py - .95f * r, px - r, py - 1.35f * r, px - r, cy)
                arcTo(RectF(px - r, cy - r, px + r, cy + r), 180f, 180f, false)
                cubicTo(px + r, py - 1.35f * r, px + .32f * r, py - .95f * r, px, py)
                close()
            }
            canvas.save()
            canvas.translate(0f, r * .12f)
            canvas.drawPath(pinPath, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(70, 0, 0, 0)
                maskFilter = BlurMaskFilter(r * .18f, BlurMaskFilter.Blur.NORMAL)
            })
            canvas.restore()
            canvas.drawPath(pinPath, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = colors.pin })
            canvas.drawPath(pinPath, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                style = Paint.Style.STROKE
                strokeWidth = max(1f, r * .14f)
                strokeJoin = Paint.Join.ROUND
            })
            canvas.drawCircle(px, cy, r * .42f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE })
        }

        if (Color.alpha(colors.border) > 0) {
            canvas.drawRoundRect(
                RectF(0.5f, 0.5f, mapW - .5f, mapH - .5f), radius, radius,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = colors.border
                    style = Paint.Style.STROKE
                    strokeWidth = max(1f, density)
                },
            )
        }
        canvas.restore()
        return bitmap
    }

    private fun drawSunAsset(context: Context, canvas: Canvas, cx: Float, cy: Float, radius: Float) {
        val bitmap = cachedSunBitmap ?: synchronized(this) {
            cachedSunBitmap ?: BitmapFactory.decodeResource(context.resources, R.drawable.ic_sun)?.also { cachedSunBitmap = it }
        } ?: return
        val r = radius.coerceAtLeast(2f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(bitmap, null, RectF(cx - r, cy - r, cx + r, cy + r), paint)
    }

    private data class SolarAngles(val sinDeclination: Double, val cosDeclination: Double)

    private fun solarSubpoint(timeMillis: Long): Pair<SolarAngles, Double> {
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { timeInMillis = timeMillis }
        val dayOfYear = cal.get(Calendar.DAY_OF_YEAR)
        val hour = cal.get(Calendar.HOUR_OF_DAY) + cal.get(Calendar.MINUTE) / 60.0 + cal.get(Calendar.SECOND) / 3600.0
        val gamma = 2.0 * Math.PI / 365.0 * (dayOfYear - 1 + (hour - 12.0) / 24.0)
        val decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma) +
            0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        val utcHour = hour
        val subsolarLon = normalizeLongitude(15.0 * (12.0 - utcHour))
        return SolarAngles(sin(decl), cos(decl)) to subsolarLon
    }

    private fun normalizeLongitude(value: Double): Double {
        var v = value % 360.0
        if (v > 180) v -= 360.0
        if (v < -180) v += 360.0
        return v
    }

    @Synchronized
    private fun loadWorldPath(context: Context): Path {
        cachedPath?.let { return it }
        val text = context.assets.open("map/worldmap.txt").use { input ->
            BufferedReader(InputStreamReader(input, Charsets.UTF_8)).readText()
        }
        val path = parseSvgPath(text)
        cachedPath = path
        return path
    }

    /** Minimal allocation-free parser for the M/L/H/V/Z (absolute + relative) subset the map uses. */
    private fun parseSvgPath(text: String): Path {
        val path = Path()
        val n = text.length
        var i = 0
        var x = 0f
        var y = 0f
        var startX = 0f
        var startY = 0f
        var cmd = ' '

        fun skipSeparators() {
            while (i < n) {
                val c = text[i]
                if (c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t') i++ else break
            }
        }
        fun readNumber(): Float? {
            skipSeparators()
            if (i >= n) return null
            val begin = i
            if (text[i] == '-' || text[i] == '+') i++
            var seenDot = false
            while (i < n) {
                val c = text[i]
                if (c in '0'..'9') i++
                else if (c == '.' && !seenDot) { seenDot = true; i++ }
                else break
            }
            if (i < n && (text[i] == 'e' || text[i] == 'E')) {
                i++
                if (i < n && (text[i] == '-' || text[i] == '+')) i++
                while (i < n && text[i] in '0'..'9') i++
            }
            if (i == begin) return null
            return text.substring(begin, i).toFloatOrNull()
        }

        while (true) {
            skipSeparators()
            if (i >= n) break
            val c = text[i]
            if (c.isLetter()) {
                cmd = c
                i++
                if (cmd == 'Z' || cmd == 'z') {
                    path.close(); x = startX; y = startY
                }
                continue
            }
            when (cmd) {
                'M', 'm' -> {
                    val a = readNumber() ?: break
                    val b = readNumber() ?: break
                    if (cmd == 'm') { x += a; y += b } else { x = a; y = b }
                    startX = x; startY = y
                    path.moveTo(x, y)
                    cmd = if (cmd == 'm') 'l' else 'L' // extra pairs after a move are line-tos
                }
                'L', 'l' -> {
                    val a = readNumber() ?: break
                    val b = readNumber() ?: break
                    if (cmd == 'l') { x += a; y += b } else { x = a; y = b }
                    path.lineTo(x, y)
                }
                'H', 'h' -> {
                    val a = readNumber() ?: break
                    x = if (cmd == 'h') x + a else a
                    path.lineTo(x, y)
                }
                'V', 'v' -> {
                    val a = readNumber() ?: break
                    y = if (cmd == 'v') y + a else a
                    path.lineTo(x, y)
                }
                else -> i++ // unknown/implicit token: skip so the loop always advances
            }
        }
        return path
    }
}
