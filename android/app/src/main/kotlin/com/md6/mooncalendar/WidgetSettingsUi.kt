package com.md6.mooncalendar

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.ColorDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import kotlin.math.roundToInt

/** Shared, lightweight native settings chrome inspired by the Persian Calendar app (Android) settings UI. */
object WidgetSettingsUi {
    fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).roundToInt()

    fun primaryColor(context: Context): Int = resolveColor(context, android.R.attr.textColorPrimary,
        if (isNightMode(context)) Color.WHITE else Color.BLACK)

    fun secondaryColor(context: Context): Int = resolveColor(context, android.R.attr.textColorSecondary,
        if (isNightMode(context)) 0xFFB8B8B8.toInt() else 0xFF60656B.toInt())

    fun accentColor(context: Context): Int = resolveColor(context, android.R.attr.colorAccent,
        if (isNightMode(context)) 0xFFCFB7FF.toInt() else 0xFF6750A4.toInt())

    fun pageBackground(context: Context): Int = resolveColor(context, android.R.attr.colorBackground,
        if (isNightMode(context)) 0xFF101114.toInt() else 0xFFF7F7F9.toInt())

    fun surfaceColor(context: Context): Int {
        val fallback = if (isNightMode(context)) 0xFF1A1B1F.toInt() else Color.WHITE
        return resolveColor(context, android.R.attr.colorBackground, fallback)
    }

    fun outlineColor(context: Context): Int {
        val base = if (isNightMode(context)) Color.WHITE else Color.BLACK
        return Color.argb(if (isNightMode(context)) 52 else 32,
            Color.red(base), Color.green(base), Color.blue(base))
    }

    fun roundedBackground(context: Context, color: Int, radiusDp: Float = 20f, stroke: Boolean = true): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(context, radiusDp.roundToInt()).toFloat()
            setColor(color)
            if (stroke) setStroke(dp(context, 1), outlineColor(context))
        }

    fun styleRoot(context: Context, root: LinearLayout) {
        // Match the original Compose safeDrawingPadding(): configuration content must stay
        // below the status bar and above the navigation/gesture area on every launcher.
        root.setBackgroundColor(Color.TRANSPARENT)
        val left = dp(context, 16)
        val top = dp(context, 12)
        val right = dp(context, 16)
        val bottom = dp(context, 16)
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val safe = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            view.setPadding(left, top + safe.top, right, bottom + safe.bottom)
            insets
        }
        root.setPadding(left, top, right, bottom)
        ViewCompat.requestApplyInsets(root)
    }

    fun settingsSurface(context: Context, parent: LinearLayout): LinearLayout {
        val dark = isNightMode(context)
        val base = if (dark) Color.rgb(31, 32, 36) else Color.rgb(250, 250, 250)
        val surface = Color.argb(191, Color.red(base), Color.green(base), Color.blue(base)) // ~75%
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(dp(context, 8), dp(context, 8), dp(context, 8), dp(context, 10))
            background = roundedBackground(context, surface, 28f, stroke = false)
            clipToOutline = true
        }
        parent.addView(card, LinearLayout.LayoutParams(-1, 0, 1f).apply { topMargin = dp(context, 8) })
        return card
    }

    fun pageSurface(context: Context, parent: LinearLayout): LinearLayout = settingsSurface(context, parent)

    fun header(context: Context, parent: LinearLayout, title: String, subtitle: String) {
        val holder = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(dp(context, 8), dp(context, 2), dp(context, 8), dp(context, 8))
        }
        holder.addView(TextView(context).apply {
            text = Tr.t(title)
            textSize = 20f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.START
            setTextColor(primaryColor(context))
        }, lp(context))
        holder.addView(TextView(context).apply {
            text = Tr.t(subtitle)
            textSize = 12f
            gravity = Gravity.START
            setTextColor(secondaryColor(context))
            setPadding(0, dp(context, 3), 0, 0)
        }, lp(context))
        parent.addView(holder, lp(context, bottom = 4))
    }

    fun settingsScroll(context: Context, parent: LinearLayout): Pair<ScrollView, LinearLayout> {
        val scroll = ScrollView(context).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            background = ColorDrawable(Color.TRANSPARENT)
        }
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(dp(context, 2), dp(context, 2), dp(context, 2), dp(context, 10))
        }
        scroll.addView(content, ViewGroup.LayoutParams(-1, -2))
        parent.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        return scroll to content
    }

    fun sectionHeader(context: Context, parent: LinearLayout, title: String) {
        val lineColor = outlineColor(context)
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            setPadding(dp(context, 10), dp(context, 14), dp(context, 10), dp(context, 6))
        }
        row.addView(View(context).apply { setBackgroundColor(lineColor) }, LinearLayout.LayoutParams(0, dp(context, 1), 1f))
        row.addView(TextView(context).apply {
            text = Tr.t(title)
            textSize = 13f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(accentColor(context))
            setPadding(dp(context, 14), 0, dp(context, 14), 0)
        }, LinearLayout.LayoutParams(-2, -2))
        row.addView(View(context).apply { setBackgroundColor(lineColor) }, LinearLayout.LayoutParams(0, dp(context, 1), 1f))
        parent.addView(row, lp(context))
    }

    fun previewFrame(context: Context, parent: LinearLayout, heightDp: Int = 180): FrameLayout {
        val frame = FrameLayout(context).apply {
            setPadding(dp(context, 6), dp(context, 6), dp(context, 6), dp(context, 6))
            background = roundedBackground(context,
                if (isNightMode(context)) 0xFF111216.toInt() else 0xFFF0F1F4.toInt(), 22f)
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            clipToOutline = true
        }
        parent.addView(frame, LinearLayout.LayoutParams(-1, dp(context, heightDp)).apply {
            leftMargin = dp(context, 2); rightMargin = dp(context, 2); bottomMargin = dp(context, 8)
        })
        return frame
    }

    fun settingRow(context: Context, parent: LinearLayout, title: String, summary: String?, control: View? = null,
                   onClick: (() -> Unit)? = null, controlWidthDp: Int = 58, compact: Boolean = false): LinearLayout {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = Tr.layoutDir()
            minimumHeight = dp(context, if (compact) (if (summary.isNullOrBlank()) 52 else 60) else (if (summary.isNullOrBlank()) 60 else 72))
            setPadding(dp(context, 10), dp(context, if (compact) 4 else 7), dp(context, 10), dp(context, if (compact) 4 else 7))
            if (onClick != null) {
                isClickable = true
                isFocusable = true
                setOnClickListener { onClick.invoke() }
            }
        }
        val texts = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
            layoutDirection = Tr.layoutDir()
            textDirection = Tr.textDir()
            minimumWidth = dp(context, 1)
        }
        texts.addView(TextView(context).apply {
            id = android.R.id.text1
            text = Tr.t(title)
            textSize = 15f
            gravity = Gravity.START
            setTextColor(primaryColor(context))
        }, lp(context))
        if (!summary.isNullOrBlank()) texts.addView(TextView(context).apply {
            text = Tr.t(summary)
            textSize = 12f
            gravity = Gravity.START
            setTextColor(secondaryColor(context))
            setPadding(0, dp(context, 2), 0, 0)
        }, lp(context))
        row.addView(texts, LinearLayout.LayoutParams(0, -2, 1f))
        if (control != null) {
            row.addView(control, LinearLayout.LayoutParams(dp(context, controlWidthDp), -2).apply {
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
            })
        }
        if (onClick != null) {
            row.background = pressableBackground(context)
        }
        parent.addView(row, lp(context))
        row.layoutParams.width = -1
        return row
    }

    fun switchRow(context: Context, parent: LinearLayout, title: String, summary: String?, checked: Boolean,
                  enabled: Boolean = true, compact: Boolean = false, onChanged: (Boolean) -> Unit): Switch {
        val sw = Switch(context).apply {
            isChecked = checked
            isEnabled = enabled
            alpha = if (enabled) 1f else .55f
        }
        settingRow(context, parent, title, summary, sw, onClick = {
            if (enabled) sw.isChecked = !sw.isChecked
        }, compact = compact)
        sw.setOnCheckedChangeListener { _, value -> onChanged(value) }
        return sw
    }

    fun sliderRow(context: Context, parent: LinearLayout, title: String, summary: String?, seekBar: android.widget.SeekBar): LinearLayout {
        val holder = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(dp(context, 10), dp(context, 8), dp(context, 10), dp(context, 8))
        }
        holder.addView(TextView(context).apply {
            text = Tr.t(title)
            textSize = 15f
            gravity = Gravity.START
            setTextColor(primaryColor(context))
        }, lp(context))
        if (!summary.isNullOrBlank()) holder.addView(TextView(context).apply {
            id = android.R.id.text2
            text = Tr.t(summary)
            textSize = 12f
            gravity = Gravity.START
            setTextColor(secondaryColor(context))
            setPadding(0, dp(context, 2), 0, 0)
        }, lp(context))
        holder.addView(seekBar, lp(context, top = 5))
        holder.background = pressableBackground(context)
        parent.addView(holder, lp(context))
        return holder
    }

    fun actionButtons(context: Context, parent: LinearLayout, accept: () -> Unit, cancel: () -> Unit) {
        val actions = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutDirection = Tr.layoutDir()
            setPadding(dp(context, 4), dp(context, 2), dp(context, 4), dp(context, 6))
        }
        val ok = button(context, "تأیید", true).apply {
            setOnClickListener { accept() }
        }
        actions.addView(ok, LinearLayout.LayoutParams(dp(context, 120), dp(context, 48)))
        parent.addView(actions, lp(context))
    }

    fun button(context: Context, text: String, primary: Boolean): Button = Button(context).apply {
        this.text = Tr.t(text)
        textSize = 14f
        isAllCaps = false
        typeface = android.graphics.Typeface.DEFAULT_BOLD
        setTextColor(if (primary) Color.WHITE else primaryColor(context))
        background = roundedBackground(context,
            if (primary) accentColor(context) else Color.TRANSPARENT, 18f, stroke = !primary)
        minHeight = 0
        minimumHeight = 0
        stateListAnimator = null
        setPadding(dp(context, 12), 0, dp(context, 12), 0)
    }

    private fun pressableBackground(context: Context): android.graphics.drawable.Drawable =
        roundedBackground(context, Color.TRANSPARENT, 16f, stroke = false)

    private fun lp(context: Context, top: Int = 0, bottom: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = dp(context, top)
            bottomMargin = dp(context, bottom)
        }

    private fun resolveColor(context: Context, attr: Int, fallback: Int): Int = runCatching {
        val out = android.util.TypedValue()
        if (!context.theme.resolveAttribute(attr, out, true)) return@runCatching fallback
        if (out.type in android.util.TypedValue.TYPE_FIRST_COLOR_INT..android.util.TypedValue.TYPE_LAST_COLOR_INT) return@runCatching out.data
        val id = out.resourceId
        if (id != 0) {
            runCatching { androidx.core.content.ContextCompat.getColorStateList(context, id)?.defaultColor }
                .getOrNull()?.let { return@runCatching it }
            runCatching {
                if (android.os.Build.VERSION.SDK_INT >= 23) context.resources.getColor(id, context.theme)
                else @Suppress("DEPRECATION") context.resources.getColor(id)
            }.getOrNull()?.let { return@runCatching it }
        }
        fallback
    }.getOrDefault(fallback)

    private fun isNightMode(context: Context): Boolean =
        (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
}
