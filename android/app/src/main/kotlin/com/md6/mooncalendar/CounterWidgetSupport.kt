package com.md6.mooncalendar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.roundToInt

object CounterWidgetSupport {
    const val PRIVATE_TARGET = "__private__"
    const val STATE_KEY = "flutter.mooncalendar_counter_state_v1"
    const val WIDGET_PREFS = "mooncalendar_counter_widgets_v1"
    const val TARGET_PREFIX = "target_"
    const val COUNT_PREFIX = "count_"
    const val FOLLOW_THEME_PREFIX = "follow_theme_"
    const val CUSTOM_COLOR_PREFIX = "custom_color_"
    const val BACKGROUND_TRANSPARENCY_PREFIX = "background_transparency_"
    const val TRANSFER_COUNT_PREFIX = "transfer_count_"
    const val SHOW_DECREMENT_PREFIX = "show_decrement_"
    const val RESET_LABEL_PREFIX = "reset_label_language_"
    const val MAX = 999999
    /** Digit top as a fraction of the device height (same as the app). */
    const val DIGIT_TOP = 0.22f
    /** Transparent margin above the visible body inside the device box (fraction of device width). */
    const val BODY_TOP_PAD = 0.1036f
    private const val ASSET_SIZE_WIDTH = 580f
    private const val ASSET_SIZE_HEIGHT = 655f

    private val tintedBodyCache = ConcurrentHashMap<String, Bitmap>()

    data class Save(val id: String, val name: String, val count: Int, val target: Int?)
    data class State(val saves: List<Save>, val json: JSONObject)

    fun prefs(context: Context) = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)

    fun targetId(context: Context, widgetId: Int): String =
        prefs(context).getString(TARGET_PREFIX + widgetId, PRIVATE_TARGET) ?: PRIVATE_TARGET

    fun privateCount(context: Context, widgetId: Int): Int =
        prefs(context).getInt(COUNT_PREFIX + widgetId, 0).coerceIn(0, MAX)

    fun saveTarget(context: Context, widgetId: Int, targetId: String, privateCount: Int = 0) {
        val edit = prefs(context).edit().putString(TARGET_PREFIX + widgetId, targetId)
        if (targetId == PRIVATE_TARGET) edit.putInt(COUNT_PREFIX + widgetId, privateCount.coerceIn(0, MAX))
        else edit.remove(COUNT_PREFIX + widgetId)
        edit.apply()
    }

    fun clearWidget(context: Context, widgetId: Int) {
        prefs(context).edit()
            .remove(TARGET_PREFIX + widgetId)
            .remove(COUNT_PREFIX + widgetId)
            .remove(FOLLOW_THEME_PREFIX + widgetId)
            .remove(CUSTOM_COLOR_PREFIX + widgetId)
            .remove(BACKGROUND_TRANSPARENCY_PREFIX + widgetId)
            .remove(TRANSFER_COUNT_PREFIX + widgetId)
            .remove(SHOW_DECREMENT_PREFIX + widgetId)
            .remove(RESET_LABEL_PREFIX + widgetId)
            .apply()
        val suffix = "_${widgetId}|"
        tintedBodyCache.keys.removeIf { it.contains(suffix) }
    }

    fun loadState(context: Context): State {
        val store = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = store.getString(STATE_KEY, null)
        val state = if (!raw.isNullOrBlank()) runCatching { JSONObject(raw) }.getOrNull() else null
        val normalized = state ?: JSONObject().apply {
            put("saves", JSONArray().put(JSONObject().apply {
                put("id", "default_save")
                put("name", "پیش فرض")
                put("count", 0)
                put("target", JSONObject.NULL)
                put("soundEnabled", true)
                put("vibrationEnabled", true)
            }))
            put("selectedSaveId", "default_save")
            put("settings", JSONObject())
        }
        val saves = arrayListOf<Save>()
        val rawSaves = normalized.optJSONArray("saves") ?: JSONArray()
        for (i in 0 until rawSaves.length()) {
            val item = rawSaves.optJSONObject(i) ?: continue
            val id = item.optString("id").trim()
            if (id.isEmpty()) continue
            val name = item.optString("name", "بدون نام").trim().ifEmpty { "بدون نام" }
            val count = item.optInt("count", 0).coerceIn(0, MAX)
            val target = if (item.isNull("target")) null else item.optInt("target", 0).takeIf { it > 0 }?.coerceIn(1, MAX)
            saves += Save(id, name, count, target)
        }
        if (saves.none { it.id == "default_save" }) saves.add(0, Save("default_save", "پیش فرض", 0, null))
        return State(saves, normalized)
    }

    fun targetChoices(context: Context): List<Save> = loadState(context).saves

    fun findSave(context: Context, id: String): Save? = loadState(context).saves.firstOrNull { it.id == id }

    fun createSave(context: Context, name: String, target: Int, initialCount: Int): String? {
        val clean = name.trim()
        if (clean.isEmpty() || target !in 1..MAX) return null
        val store = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val state = loadState(context)
        val saves = state.json.optJSONArray("saves") ?: JSONArray()
        val id = "save_${System.currentTimeMillis()}_${kotlin.random.Random.Default.nextInt(100000)}"
        saves.put(JSONObject().apply {
            put("id", id)
            put("name", clean)
            put("count", initialCount.coerceIn(0, MAX))
            put("target", target)
            put("soundEnabled", true)
            put("vibrationEnabled", true)
        })
        state.json.put("saves", saves)
        store.edit().putString(STATE_KEY, state.json.toString()).apply()
        return id
    }

    /** Removes a save created from a widget settings screen that was then cancelled (never the default save). */
    fun deleteSave(context: Context, id: String) {
        if (id == "default_save") return
        val store = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val state = loadState(context)
        val saves = state.json.optJSONArray("saves") ?: return
        val kept = JSONArray()
        var removed = false
        for (i in 0 until saves.length()) {
            val item = saves.optJSONObject(i) ?: continue
            if (item.optString("id") == id) { removed = true; continue }
            kept.put(item)
        }
        if (!removed) return
        state.json.put("saves", kept)
        if (state.json.optString("selectedSaveId") == id) state.json.put("selectedSaveId", "default_save")
        store.edit().putString(STATE_KEY, state.json.toString()).apply()
    }

    fun saveCount(context: Context, id: String, next: Int): Save? {
        val store = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val state = loadState(context)
        val saves = state.json.optJSONArray("saves") ?: JSONArray()
        var found: Save? = null
        for (i in 0 until saves.length()) {
            val item = saves.optJSONObject(i) ?: continue
            if (item.optString("id") != id) continue
            val normalized = next.coerceIn(0, MAX)
            item.put("count", normalized)
            found = Save(
                id,
                item.optString("name", "بدون نام").trim().ifEmpty { "بدون نام" },
                normalized,
                if (item.isNull("target")) null else item.optInt("target", 0).takeIf { it > 0 }?.coerceIn(1, MAX),
            )
            break
        }
        if (found == null) return null
        state.json.put("saves", saves)
        store.edit().putString(STATE_KEY, state.json.toString()).apply()
        return found
    }

    fun resolveCounter(context: Context, widgetId: Int): Pair<String, Int> {
        val target = targetId(context, widgetId)
        if (target == PRIVATE_TARGET) return target to privateCount(context, widgetId)
        val save = findSave(context, target)
        return if (save == null) PRIVATE_TARGET to privateCount(context, widgetId) else target to save.count
    }

    fun increment(context: Context, widgetId: Int): Pair<String, Int> {
        val (target, current) = resolveCounter(context, widgetId)
        val next = if (current >= MAX) 0 else current + 1
        if (target == PRIVATE_TARGET) prefs(context).edit().putInt(COUNT_PREFIX + widgetId, next).apply()
        else saveCount(context, target, next)
        return target to next
    }

    fun decrement(context: Context, widgetId: Int): Pair<String, Int> {
        val (target, current) = resolveCounter(context, widgetId)
        if (current <= 0) return target to 0
        val next = current - 1
        if (target == PRIVATE_TARGET) prefs(context).edit().putInt(COUNT_PREFIX + widgetId, next).apply()
        else saveCount(context, target, next)
        return target to next
    }

    fun reset(context: Context, widgetId: Int): Pair<String, Int> {
        val target = targetId(context, widgetId)
        if (target == PRIVATE_TARGET) prefs(context).edit().putInt(COUNT_PREFIX + widgetId, 0).apply()
        else saveCount(context, target, 0)
        return target to 0
    }

    fun targetName(context: Context, widgetId: Int): String? {
        val target = targetId(context, widgetId)
        if (target == PRIVATE_TARGET) return null
        return findSave(context, target)?.name
    }

    fun showDecrement(context: Context, widgetId: Int): Boolean =
        prefs(context).getBoolean(SHOW_DECREMENT_PREFIX + widgetId, false)

    fun saveShowDecrement(context: Context, widgetId: Int, enabled: Boolean) {
        prefs(context).edit().putBoolean(SHOW_DECREMENT_PREFIX + widgetId, enabled).apply()
    }

    fun resetLabelFollowsLanguage(context: Context, widgetId: Int): Boolean {
        val key = RESET_LABEL_PREFIX + widgetId
        if (prefs(context).contains(key)) return prefs(context).getBoolean(key, false)
        return loadState(context).json.optJSONObject("settings")?.optBoolean("resetLabelFollowsLanguage", false) ?: false
    }

    fun saveResetLabelFollowsLanguage(context: Context, widgetId: Int, enabled: Boolean) {
        prefs(context).edit().putBoolean(RESET_LABEL_PREFIX + widgetId, enabled).apply()
    }

    fun followTheme(context: Context, widgetId: Int): Boolean =
        prefs(context).getBoolean(FOLLOW_THEME_PREFIX + widgetId, true)

    fun backgroundTransparency(context: Context, widgetId: Int): Float =
        (prefs(context).getInt(BACKGROUND_TRANSPARENCY_PREFIX + widgetId, 0) / 100f).coerceIn(0f, 1f)

    fun transferCountToNewTarget(context: Context, widgetId: Int): Boolean =
        prefs(context).getBoolean(TRANSFER_COUNT_PREFIX + widgetId, true)

    fun saveTransferCountToNewTarget(context: Context, widgetId: Int, enabled: Boolean) {
        prefs(context).edit().putBoolean(TRANSFER_COUNT_PREFIX + widgetId, enabled).apply()
    }

    fun themePrimaryColor(context: Context): Int = runCatching {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            context.getColor(android.R.color.system_accent1_600)
        } else {
            val attrs = context.theme.obtainStyledAttributes(intArrayOf(android.R.attr.colorAccent))
            try { attrs.getColor(0, 0xFF8B0027.toInt()) } finally { attrs.recycle() }
        }
    }.getOrDefault(0xFF8B0027.toInt())

    fun customColor(context: Context, widgetId: Int): Int =
        prefs(context).getInt(CUSTOM_COLOR_PREFIX + widgetId, themePrimaryColor(context))

    fun widgetPrimaryColor(context: Context, widgetId: Int): Int =
        if (followTheme(context, widgetId)) themePrimaryColor(context) else customColor(context, widgetId)

    fun saveStyle(context: Context, widgetId: Int, followTheme: Boolean, color: Int, transparency: Float) {
        prefs(context).edit()
            .putBoolean(FOLLOW_THEME_PREFIX + widgetId, followTheme)
            .putInt(CUSTOM_COLOR_PREFIX + widgetId, color)
            .putInt(BACKGROUND_TRANSPARENCY_PREFIX + widgetId, (transparency.coerceIn(0f, 1f) * 100f).roundToInt())
            .apply()
    }

    fun buildThemedBackground(context: Context, widgetId: Int, width: Int, height: Int): Bitmap? {
        val visibility = (1f - backgroundTransparency(context, widgetId)).coerceIn(0f, 1f)
        if (visibility <= 0f) return null
        val bitmap = Bitmap.createBitmap(max(width, 2), max(height, 2), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val base = themePrimaryColor(context)
        val fillAlpha = (255f * 0.14f * visibility).roundToInt().coerceIn(0, 255)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(fillAlpha, Color.red(base), Color.green(base), Color.blue(base))
        }
        val radius = 16f * context.resources.displayMetrics.density
        canvas.drawRoundRect(RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat()), radius, radius, paint)
        return bitmap
    }

    fun buildTintedBodyBitmap(context: Context, color: Int): Bitmap {
        val key = "${context.resources.configuration.uiMode}|${color and 0x00FFFFFF}|shader-v2"
        tintedBodyCache[key]?.let { if (!it.isRecycled) return it }
        val source = BitmapFactory.decodeResource(context.resources, R.drawable.tally_counter_body)
            ?: return Bitmap.createBitmap(580, 655, Bitmap.Config.ARGB_8888)

        // The Flutter counter uses ShaderMask + BlendMode.modulate on the grayscale body asset.
        // Recreate that operation here instead of flattening the body with a ColorMatrix. This keeps
        // the exact highlights/shadows while applying the chosen system/custom color.
        val lighten = fun(base: Int, amount: Float): Int {
            val r = (Color.red(base) + (255 - Color.red(base)) * amount).roundToInt().coerceIn(0, 255)
            val g = (Color.green(base) + (255 - Color.green(base)) * amount).roundToInt().coerceIn(0, 255)
            val b = (Color.blue(base) + (255 - Color.blue(base)) * amount).roundToInt().coerceIn(0, 255)
            return Color.rgb(r, g, b)
        }
        val top = lighten(color, .10f)
        val middle = lighten(color, .04f)
        val bottom = color or (Color.alpha(color) shl 24)

        val out = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawBitmap(source, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
        val shader = android.graphics.LinearGradient(
            0f,
            0f,
            0f,
            source.height.toFloat(),
            intArrayOf(top, middle, bottom),
            floatArrayOf(0f, .5f, 1f),
            android.graphics.Shader.TileMode.CLAMP,
        )
        val multiplyPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            this.shader = shader
            xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.MULTIPLY)
        }
        canvas.drawRect(0f, 0f, source.width.toFloat(), source.height.toFloat(), multiplyPaint)
        multiplyPaint.xfermode = null

        tintedBodyCache[key] = out
        if (tintedBodyCache.size > 12) {
            val first = tintedBodyCache.keys.firstOrNull()
            if (first != null && first != key) tintedBodyCache.remove(first)?.takeUnless { it === out }?.recycle()
        }
        return out
    }

    fun buildCountBitmap(context: Context, count: Int, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(max(width, 32), max(height, 32), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = Color.rgb(0, 16, 6)
            textAlign = Paint.Align.LEFT
            textSize = bitmap.width * 0.20f
            typeface = runCatching { Typeface.createFromAsset(context.assets, "fonts/segment7.ttf") }
                .getOrElse { Typeface.create("monospace", Typeface.BOLD) }
            isDither = true
        }
        val text = count.coerceIn(0, MAX).toString()
        val x = (bitmap.width - bitmap.width * 0.225f - paint.measureText(text)).coerceAtLeast(0f)
        // Flutter lays the digit out with `height: 1` (line box == font size) starting at top = .22 * height.
        // segment7.ttf: ascent 864, descent 192 of 1024 => baseline sits at 864/1056 of the line box.
        val baseline = bitmap.height * DIGIT_TOP + paint.textSize * (864f / 1056f)
        canvas.drawText(text, x, baseline, paint)
        return bitmap
    }

    private fun isNight(context: Context): Boolean =
        (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

    /**
     * Target label above the counter: lettering in the widget's theme colour, outlined (not boxed) in the
     * colour opposite to the system theme (white on dark, black on light), on a pill that follows dark/light.
     * It is drawn into one bitmap so the outline is a real glyph stroke.
     */
    fun styleTargetBox(views: RemoteViews, widgetId: Int, context: Context, targetName: String?, widthPx: Int, heightPx: Int) {
        val visible = !targetName.isNullOrBlank()
        views.setViewVisibility(R.id.target_container, if (visible) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.target_box, View.GONE)
        views.setViewVisibility(R.id.target_outline, if (visible) View.VISIBLE else View.GONE)
        if (!visible) return
        views.setImageViewBitmap(
            R.id.target_outline,
            buildTargetLabelBitmap(context, targetName!!, widgetPrimaryColor(context, widgetId), widthPx, heightPx),
        )
    }

    private fun buildTargetLabelBitmap(context: Context, name: String, fill: Int, width: Int, height: Int): Bitmap {
        val w = max(width, 24)
        val h = max(height, 16)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val density = context.resources.displayMetrics.density
        val night = isNight(context)

        val strokeW = (h * .12f).coerceIn(1.5f * density, 3.5f * density)
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = Typeface.create("sans", Typeface.BOLD)
            textAlign = Paint.Align.CENTER
            textSize = h * .52f
            strokeJoin = Paint.Join.ROUND
        }
        val padX = h * .42f
        val maxTextW = w - padX * 2 - strokeW * 2
        var label = name
        while (label.length > 1 && textPaint.measureText(label) > maxTextW) {
            val shrunk = textPaint.textSize * .92f
            if (shrunk < h * .30f) {
                label = label.dropLast(1)
            } else {
                textPaint.textSize = shrunk
            }
        }
        if (label.length < name.length) label = label.trimEnd() + "…"

        // Pill hugs the label (like the Windows widget) instead of filling the whole container.
        val pillW = (textPaint.measureText(label) + padX * 2 + strokeW * 2).coerceAtMost(w.toFloat())
        val pillLeft = (w - pillW) / 2f
        val pill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = if (night) 0xCC1F2024.toInt() else 0xCCFAFAFA.toInt()
        }
        val radius = h * .42f
        canvas.drawRoundRect(RectF(pillLeft, 0f, pillLeft + pillW, h.toFloat()), radius, radius, pill)

        val x = w / 2f
        val y = h / 2f - (textPaint.fontMetrics.ascent + textPaint.fontMetrics.descent) / 2f
        textPaint.style = Paint.Style.STROKE
        textPaint.strokeWidth = strokeW
        textPaint.color = if (night) Color.WHITE else Color.BLACK
        canvas.drawText(label, x, y, textPaint)
        textPaint.style = Paint.Style.FILL
        textPaint.color = fill
        canvas.drawText(label, x, y, textPaint)
        return bitmap
    }

    /**
     * Button artwork drawn "contain" (aspect preserved, like BoxFit.contain in the app) at [scale] inside a
     * [sizePx] square. The pressed-state animation frame is the same artwork drawn smaller.
     */
    fun buildButtonBitmap(context: Context, resId: Int, sizePx: Int, scale: Float): Bitmap {
        val size = max(sizePx, 8)
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val src = BitmapFactory.decodeResource(context.resources, resId) ?: return out
        val fit = minOf(size.toFloat() / src.width, size.toFloat() / src.height) * scale
        val w = src.width * fit
        val h = src.height * fit
        val left = (size - w) / 2f
        val top = (size - h) / 2f
        Canvas(out).drawBitmap(
            src,
            null,
            RectF(left, top, left + w, top + h),
            Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG),
        )
        src.recycle()
        return out
    }

    private fun RemoteViews.setTextColorCompat(viewId: Int, color: Int) {
        setInt(viewId, "setTextColor", color)
    }
}
