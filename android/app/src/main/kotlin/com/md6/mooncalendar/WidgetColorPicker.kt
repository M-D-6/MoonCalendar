package com.md6.mooncalendar

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.ColorDrawable
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * One modern colour picker shared by every widget settings screen:
 * saturation/brightness square, hue bar, optional opacity bar, hex field, before/after preview and a
 * palette of ready-made swatches.
 *
 * The result is delivered as an ARGB int. Without [allowAlpha] it is always fully opaque.
 */
object WidgetColorPicker {

    private fun colors(vararg values: Long): IntArray = IntArray(values.size) { values[it].toInt() }

    /** Ready-made colours for texts. */
    val TEXT_PRESETS: IntArray = colors(
        0xFFFFFFFF, 0xFF000000, 0xFFFFD54F, 0xFFFF8A65, 0xFFEF5350, 0xFFF06292,
        0xFFBA68C8, 0xFF7986CB, 0xFF4FC3F7, 0xFF4DD0E1, 0xFF4DB6AC, 0xFF81C784,
    )

    /** Ready-made colours for the widget background (the first one is "no background"). */
    val BACKGROUND_PRESETS: IntArray = colors(
        0x00000000, 0x99000000, 0xFF000000, 0x66FFFFFF, 0xCCFFFFFF, 0xFFFFFFFF,
        0xFF1F2937, 0xFF0F766E, 0xFF1E3A8A, 0xFF6D28D9, 0xFF9F1239, 0xFF92400E,
    )

    fun show(
        activity: Activity,
        title: String,
        subtitle: String,
        initial: Int,
        allowAlpha: Boolean,
        presets: IntArray,
        onPicked: (Int) -> Unit,
    ) {
        PickerDialog(activity, title, subtitle, initial, allowAlpha, presets, onPicked).show()
    }

    // ---------------------------------------------------------------------------------------------

    private class State(initial: Int, private val allowAlpha: Boolean) {
        val hsv = FloatArray(3)
        var alpha = 255

        init { set(initial) }

        fun set(argb: Int, keepHueForGray: Boolean = false) {
            val oldHue = hsv[0]
            Color.colorToHSV(argb, hsv)
            if (keepHueForGray && (hsv[1] < 0.001f || hsv[2] < 0.001f)) hsv[0] = oldHue
            alpha = if (allowAlpha) Color.alpha(argb) else 255
        }

        fun rgb(): Int = Color.HSVToColor(255, hsv)
        fun argb(): Int = Color.HSVToColor(alpha, hsv)
    }

    private fun dp(context: Context, value: Float): Float = value * context.resources.displayMetrics.density

    private fun persianDigits(value: Int): String = Tr.digits(value.toString())

    /** Light/dark chequerboard that shows through transparent colours. */
    internal fun checkerPaint(context: Context, cellDp: Float = 6f): Paint {
        val cell = dp(context, cellDp).roundToInt().coerceAtLeast(2)
        val bitmap = Bitmap.createBitmap(cell * 2, cell * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val p = Paint()
        p.color = 0xFFFFFFFF.toInt()
        canvas.drawRect(0f, 0f, cell * 2f, cell * 2f, p)
        p.color = 0xFFD5D8DD.toInt()
        canvas.drawRect(0f, 0f, cell.toFloat(), cell.toFloat(), p)
        canvas.drawRect(cell.toFloat(), cell.toFloat(), cell * 2f, cell * 2f, p)
        return Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(bitmap, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT) }
    }

    /** Readable text colour on top of [color] (which may be translucent over a light chequerboard). */
    private fun contrastOn(color: Int): Int {
        if (Color.alpha(color) < 120) return 0xFF2B2D31.toInt()
        val lum = (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255.0
        return if (lum > 0.6) 0xFF202124.toInt() else Color.WHITE
    }

    /** HSV round trips can be off by one per channel, so "same colour" is compared with a tiny tolerance. */
    private fun nearlyEqual(a: Int, b: Int): Boolean =
        kotlin.math.abs(Color.alpha(a) - Color.alpha(b)) <= 2 &&
            kotlin.math.abs(Color.red(a) - Color.red(b)) <= 2 &&
            kotlin.math.abs(Color.green(a) - Color.green(b)) <= 2 &&
            kotlin.math.abs(Color.blue(a) - Color.blue(b)) <= 2

    private fun drawThumb(canvas: Canvas, x: Float, y: Float, r: Float, fill: Int, stroke: Float, shadowStroke: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.style = Paint.Style.FILL
        p.color = fill
        canvas.drawCircle(x, y, r, p)
        p.style = Paint.Style.STROKE
        p.strokeWidth = shadowStroke
        p.color = Color.argb(70, 0, 0, 0)
        canvas.drawCircle(x, y, r + stroke / 2f, p)
        p.strokeWidth = stroke
        p.color = Color.WHITE
        canvas.drawCircle(x, y, r, p)
    }

    /** Small round colour chip shown at the end of a settings row so the current colour is visible at a glance. */
    class ColorDot(context: Context, color: Int) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val checker = checkerPaint(context, 4f)
        var color: Int = color
            set(value) { field = value; invalidate() }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            setMeasuredDimension(
                resolveSize(dp(context, 58f).roundToInt(), widthMeasureSpec),
                dp(context, 34f).roundToInt(),
            )
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val r = dp(context, 13f)
            val clip = Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }
            canvas.save()
            canvas.clipPath(clip)
            if (Color.alpha(color) < 255) canvas.drawRect(cx - r, cy - r, cx + r, cy + r, checker)
            paint.style = Paint.Style.FILL
            paint.color = color
            canvas.drawCircle(cx, cy, r, paint)
            canvas.restore()
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = dp(context, 1.5f)
            paint.color = Color.argb(90, 128, 128, 128)
            canvas.drawCircle(cx, cy, r, paint)
        }
    }

    // ------------------------------------------------------------------------------------ views

    private class SvView(context: Context, private val state: State, private val onChange: () -> Unit) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val clip = Path()
        private val corner = dp(context, 16f)
        private val thumbR = dp(context, 11f)
        private val thumbStroke = dp(context, 3f)
        private val hairline = dp(context, 1f)

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            clip.reset()
            clip.addRoundRect(RectF(0f, 0f, w, h), corner, corner, Path.Direction.CW)
            canvas.save()
            canvas.clipPath(clip)
            val pure = Color.HSVToColor(floatArrayOf(state.hsv[0], 1f, 1f))
            paint.shader = LinearGradient(0f, 0f, w, 0f, Color.WHITE, pure, Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, w, h, paint)
            paint.shader = LinearGradient(0f, 0f, 0f, h, Color.TRANSPARENT, Color.BLACK, Shader.TileMode.CLAMP)
            canvas.drawRect(0f, 0f, w, h, paint)
            paint.shader = null
            canvas.restore()
            val x = state.hsv[1] * w
            val y = (1f - state.hsv[2]) * h
            drawThumb(canvas, x.coerceIn(thumbR, w - thumbR), y.coerceIn(thumbR, h - thumbR), thumbR, state.rgb(), thumbStroke, hairline)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> parent?.requestDisallowInterceptTouchEvent(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> parent?.requestDisallowInterceptTouchEvent(false)
            }
            if (width <= 0 || height <= 0) return true
            state.hsv[1] = (event.x / width).coerceIn(0f, 1f)
            state.hsv[2] = 1f - (event.y / height).coerceIn(0f, 1f)
            onChange()
            return true
        }
    }

    private class BarView(
        context: Context,
        private val state: State,
        private val alphaMode: Boolean,
        private val onChange: () -> Unit,
    ) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val checker = checkerPaint(context, 5f)
        private val clip = Path()
        private val hueColors = IntArray(7) { Color.HSVToColor(floatArrayOf(it * 60f, 1f, 1f)) }
        private val thumbStroke = dp(context, 3f)
        private val hairline = dp(context, 1f)

        private fun thumbRadius(): Float = height / 2f - dp(context, 2f)

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val trackR = h / 2f
            val track = RectF(0f, h * 0.18f, w, h * 0.82f)
            clip.reset()
            clip.addRoundRect(track, trackR, trackR, Path.Direction.CW)
            canvas.save()
            canvas.clipPath(clip)
            if (alphaMode) {
                canvas.drawRect(track, checker)
                val rgb = state.rgb()
                paint.shader = LinearGradient(
                    0f, 0f, w, 0f,
                    Color.argb(0, Color.red(rgb), Color.green(rgb), Color.blue(rgb)),
                    Color.argb(255, Color.red(rgb), Color.green(rgb), Color.blue(rgb)),
                    Shader.TileMode.CLAMP,
                )
            } else {
                paint.shader = LinearGradient(0f, 0f, w, 0f, hueColors, null, Shader.TileMode.CLAMP)
            }
            canvas.drawRect(track, paint)
            paint.shader = null
            canvas.restore()

            val r = thumbRadius()
            val fraction = if (alphaMode) state.alpha / 255f else state.hsv[0] / 360f
            val x = r + fraction * (w - 2f * r)
            val fill = if (alphaMode) state.argb() else Color.HSVToColor(floatArrayOf(state.hsv[0], 1f, 1f))
            if (alphaMode) {
                // chequerboard under the thumb as well, so a translucent colour is visible as such
                canvas.save()
                val thumbClip = Path().apply { addCircle(x, h / 2f, r, Path.Direction.CW) }
                canvas.clipPath(thumbClip)
                canvas.drawRect(x - r, h / 2f - r, x + r, h / 2f + r, checker)
                canvas.restore()
            }
            drawThumb(canvas, x, h / 2f, r, fill, thumbStroke, hairline)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> parent?.requestDisallowInterceptTouchEvent(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> parent?.requestDisallowInterceptTouchEvent(false)
            }
            if (width <= 0) return true
            val r = thumbRadius()
            val fraction = ((event.x - r) / (width - 2f * r).coerceAtLeast(1f)).coerceIn(0f, 1f)
            if (alphaMode) state.alpha = (fraction * 255f).roundToInt() else state.hsv[0] = (fraction * 360f).coerceAtMost(359.99f)
            onChange()
            return true
        }
    }

    /**
     * Two separate rounded tiles with a gap between them: the colour that is stored now (previous) and the
     * one being picked (new). They never touch each other.
     */
    private class PreviewView(context: Context, private val state: State, private val previous: Int) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val checker = checkerPaint(context, 7f)
        private val clip = Path()
        private val corner = dp(context, 18f)
        private val gap = dp(context, 12f)
        private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(context, 1f)
            color = Color.argb(70, 128, 128, 128)
        }
        private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = dp(context, 11.5f)
            textAlign = Paint.Align.CENTER
            isFakeBoldText = true
        }

        private fun tile(canvas: Canvas, box: RectF, color: Int, text: String) {
            clip.reset()
            clip.addRoundRect(box, corner, corner, Path.Direction.CW)
            canvas.save()
            canvas.clipPath(clip)
            canvas.drawRect(box, checker)
            paint.style = Paint.Style.FILL
            paint.color = color
            canvas.drawRect(box, paint)
            label.color = contrastOn(color)
            canvas.drawText(text, box.centerX(), box.bottom - dp(context, 12f), label)
            canvas.restore()
            canvas.drawRoundRect(
                RectF(box.left + 0.5f, box.top + 0.5f, box.right - 0.5f, box.bottom - 0.5f),
                corner, corner, outline,
            )
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val tileW = (w - gap) / 2f
            // physical layout: new on the left, previous on the right
            tile(canvas, RectF(0f, 0f, tileW, h), state.argb(), "جدید")
            tile(canvas, RectF(tileW + gap, 0f, w, h), previous, "قبلی")
        }
    }

    private class SwatchView(context: Context, val color: Int, private val accent: Int) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val checker = checkerPaint(context, 5f)
        private val tick = Path()
        var selectedSwatch = false
            set(value) { field = value; invalidate() }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val r = min(width, height) / 2f - dp(context, 4f)
            val clip = Path().apply { addCircle(cx, cy, r, Path.Direction.CW) }
            canvas.save()
            canvas.clipPath(clip)
            if (Color.alpha(color) < 255) canvas.drawRect(cx - r, cy - r, cx + r, cy + r, checker)
            paint.style = Paint.Style.FILL
            paint.color = color
            canvas.drawCircle(cx, cy, r, paint)
            canvas.restore()
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = dp(context, 1f)
            paint.color = Color.argb(70, 128, 128, 128)
            canvas.drawCircle(cx, cy, r, paint)
            if (selectedSwatch) {
                paint.strokeWidth = dp(context, 2.5f)
                paint.color = accent
                canvas.drawCircle(cx, cy, r + dp(context, 3f), paint)
                tick.reset()
                tick.moveTo(cx - r * 0.38f, cy + r * 0.02f)
                tick.lineTo(cx - r * 0.08f, cy + r * 0.34f)
                tick.lineTo(cx + r * 0.42f, cy - r * 0.3f)
                paint.strokeWidth = dp(context, 2.4f)
                paint.strokeCap = Paint.Cap.ROUND
                paint.strokeJoin = Paint.Join.ROUND
                paint.color = contrastOn(color)
                canvas.drawPath(tick, paint)
                paint.strokeCap = Paint.Cap.BUTT
            }
        }
    }

    // ----------------------------------------------------------------------------------- dialog

    private class PickerDialog(
        private val activity: Activity,
        private val title: String,
        private val subtitle: String,
        private val initial: Int,
        private val allowAlpha: Boolean,
        private val presets: IntArray,
        private val onPicked: (Int) -> Unit,
    ) {
        private val state = State(initial, allowAlpha)
        private val swatches = mutableListOf<SwatchView>()
        private lateinit var sv: SvView
        private lateinit var hue: BarView
        private var alphaBar: BarView? = null
        private lateinit var preview: PreviewView
        private lateinit var hexField: EditText
        private var alphaValue: TextView? = null
        private var updatingHex = false

        private fun ui(value: Int): Int = WidgetSettingsUi.dp(activity, value)

        private fun refresh(fromHex: Boolean = false) {
            sv.invalidate()
            hue.invalidate()
            alphaBar?.invalidate()
            preview.invalidate()
            alphaValue?.text = Tr.t("${persianDigits((state.alpha / 255f * 100f).roundToInt())}٪")
            if (!fromHex) {
                updatingHex = true
                val hex = String.format(java.util.Locale.US, "%06X", state.rgb() and 0xFFFFFF)
                if (hexField.text.toString() != hex) {
                    hexField.setText(hex)
                    hexField.setSelection(hex.length)
                }
                updatingHex = false
            }
            val current = state.argb()
            swatches.forEach { it.selectedSwatch = nearlyEqual(it.color, current) }
        }

        fun show() {
            val ctx: Context = activity
            val accent = WidgetSettingsUi.accentColor(ctx)
            val dark = (ctx.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
            val surface = if (dark) 0xFF1F2024.toInt() else 0xFFFAFAFB.toInt()

            val card = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                layoutDirection = Tr.layoutDir()
                background = WidgetSettingsUi.roundedBackground(ctx, surface, 28f, stroke = true)
                clipToOutline = true
            }

            // Header
            val header = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(ui(22), ui(18), ui(22), ui(6))
            }
            header.addView(TextView(ctx).apply {
                text = Tr.t(title)
                textSize = 18f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.primaryColor(ctx))
            }, LinearLayout.LayoutParams(-1, -2))
            if (subtitle.isNotBlank()) header.addView(TextView(ctx).apply {
                text = Tr.t(subtitle)
                textSize = 12f
                gravity = Gravity.START
                setPadding(0, ui(3), 0, 0)
                setTextColor(WidgetSettingsUi.secondaryColor(ctx))
            }, LinearLayout.LayoutParams(-1, -2))
            card.addView(header, LinearLayout.LayoutParams(-1, -2))

            // Scrollable body
            val body = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                layoutDirection = View.LAYOUT_DIRECTION_LTR
                setPadding(ui(22), ui(8), ui(22), ui(6))
            }
            val scroll = ScrollView(ctx).apply {
                isVerticalScrollBarEnabled = false
                overScrollMode = View.OVER_SCROLL_NEVER
                addView(body, ViewGroup.LayoutParams(-1, -2))
            }
            card.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))

            preview = PreviewView(ctx, state, initial)
            body.addView(preview, LinearLayout.LayoutParams(-1, ui(76)).apply { bottomMargin = ui(14) })

            sv = SvView(ctx, state) { refresh() }
            body.addView(sv, LinearLayout.LayoutParams(-1, ui(168)))

            hue = BarView(ctx, state, alphaMode = false) { refresh() }
            body.addView(hue, LinearLayout.LayoutParams(-1, ui(34)).apply { topMargin = ui(10) })

            if (allowAlpha) {
                val labels = LinearLayout(ctx).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutDirection = Tr.layoutDir()
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(ui(2), ui(8), ui(2), 0)
                }
                labels.addView(TextView(ctx).apply {
                    text = Tr.t("کدری رنگ")
                    textSize = 13f
                    setTextColor(WidgetSettingsUi.secondaryColor(ctx))
                }, LinearLayout.LayoutParams(0, -2, 1f))
                alphaValue = TextView(ctx).apply {
                    textSize = 13f
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                    setTextColor(WidgetSettingsUi.primaryColor(ctx))
                }
                labels.addView(alphaValue, LinearLayout.LayoutParams(-2, -2))
                body.addView(labels, LinearLayout.LayoutParams(-1, -2))
                alphaBar = BarView(ctx, state, alphaMode = true) { refresh() }
                body.addView(alphaBar, LinearLayout.LayoutParams(-1, ui(34)))
            }

            // Hex row: label on the right, code field on the left
            val hexRow = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = Tr.layoutDir()
                gravity = Gravity.CENTER_VERTICAL
                setPadding(ui(2), ui(14), ui(2), ui(2))
            }
            hexRow.addView(TextView(ctx).apply {
                text = Tr.t("کد رنگ")
                textSize = 13f
                setTextColor(WidgetSettingsUi.secondaryColor(ctx))
            }, LinearLayout.LayoutParams(0, -2, 1f))
            val hexBox = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = View.LAYOUT_DIRECTION_LTR
                gravity = Gravity.CENTER_VERTICAL
                setPadding(ui(14), 0, ui(14), 0)
                background = WidgetSettingsUi.roundedBackground(ctx, Color.TRANSPARENT, 14f, stroke = true)
            }
            hexBox.addView(TextView(ctx).apply {
                text = "#"
                textSize = 15f
                typeface = android.graphics.Typeface.MONOSPACE
                setTextColor(WidgetSettingsUi.secondaryColor(ctx))
            }, LinearLayout.LayoutParams(-2, -2))
            hexField = EditText(ctx).apply {
                setBackgroundColor(Color.TRANSPARENT)
                typeface = android.graphics.Typeface.MONOSPACE
                textSize = 15f
                textDirection = View.TEXT_DIRECTION_LTR
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
                setSingleLine(true)
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                imeOptions = EditorInfo.IME_ACTION_DONE
                setTextColor(WidgetSettingsUi.primaryColor(ctx))
                setPadding(ui(4), ui(10), 0, ui(10))
                minWidth = ui(86)
                filters = arrayOf(
                    InputFilter { source, start, end, _, _, _ ->
                        val out = StringBuilder()
                        for (i in start until end) {
                            val ch = source[i].uppercaseChar()
                            if (ch in '0'..'9' || ch in 'A'..'F') out.append(ch)
                        }
                        if (out.length == end - start && out.toString() == source.subSequence(start, end).toString()) null else out.toString()
                    },
                    InputFilter.LengthFilter(6),
                )
                addTextChangedListener(object : TextWatcher {
                    override fun beforeTextChanged(s: CharSequence?, st: Int, c: Int, a: Int) = Unit
                    override fun onTextChanged(s: CharSequence?, st: Int, b: Int, c: Int) = Unit
                    override fun afterTextChanged(s: Editable?) {
                        if (updatingHex) return
                        val text = s?.toString().orEmpty()
                        if (text.length != 6) return
                        val rgb = text.toIntOrNull(16) ?: return
                        state.set(Color.argb(state.alpha, (rgb shr 16) and 0xFF, (rgb shr 8) and 0xFF, rgb and 0xFF), keepHueForGray = true)
                        refresh(fromHex = true)
                    }
                })
            }
            hexBox.addView(hexField, LinearLayout.LayoutParams(-2, -2))
            hexRow.addView(hexBox, LinearLayout.LayoutParams(-2, ui(46)))
            body.addView(hexRow, LinearLayout.LayoutParams(-1, -2))

            // Swatches
            if (presets.isNotEmpty()) {
                body.addView(TextView(activity).apply {
                    text = Tr.t("رنگ‌های آماده")
                    textSize = 13f
                    gravity = Gravity.START
                    layoutDirection = Tr.layoutDir()
                    setPadding(ui(2), ui(14), ui(2), ui(4))
                    setTextColor(WidgetSettingsUi.secondaryColor(ctx))
                }, LinearLayout.LayoutParams(-1, -2))
                val perRow = 6
                presets.toList().chunked(perRow).forEach { rowColors ->
                    val row = LinearLayout(ctx).apply {
                        orientation = LinearLayout.HORIZONTAL
                        layoutDirection = View.LAYOUT_DIRECTION_LTR
                        gravity = Gravity.CENTER
                    }
                    rowColors.forEach { c ->
                        val sw = SwatchView(ctx, c, accent).apply {
                            isClickable = true
                            isFocusable = true
                            contentDescription = Tr.t("رنگ آماده")
                            setOnClickListener {
                                state.set(c)
                                refresh()
                            }
                        }
                        swatches += sw
                        row.addView(sw, LinearLayout.LayoutParams(0, ui(46), 1f))
                    }
                    repeat(perRow - rowColors.size) { row.addView(View(ctx), LinearLayout.LayoutParams(0, ui(46), 1f)) }
                    body.addView(row, LinearLayout.LayoutParams(-1, -2))
                }
            }

            val dialog = Dialog(activity)
            dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

            // Actions
            val actions = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = Tr.layoutDir()
                gravity = Gravity.CENTER
                setPadding(ui(16), ui(8), ui(16), ui(16))
            }
            val ok = WidgetSettingsUi.button(ctx, "تأیید", true).apply {
                setOnClickListener {
                    onPicked(state.argb())
                    dialog.dismiss()
                }
            }
            val cancel = WidgetSettingsUi.button(ctx, "لغو", false).apply {
                setOnClickListener { dialog.dismiss() }
            }
            actions.addView(ok, LinearLayout.LayoutParams(0, ui(48), 1f).apply { setMargins(ui(6), 0, ui(6), 0) })
            actions.addView(cancel, LinearLayout.LayoutParams(0, ui(48), 1f).apply { setMargins(ui(6), 0, ui(6), 0) })
            card.addView(actions, LinearLayout.LayoutParams(-1, -2))

            dialog.setContentView(card)
            dialog.setCanceledOnTouchOutside(true)
            dialog.window?.apply {
                setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                setDimAmount(0.55f)
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
                val metrics = ctx.resources.displayMetrics
                val width = min(metrics.widthPixels - ui(24) * 2, ui(400))
                setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
            }
            refresh()
            dialog.show()
        }
    }
}
