package com.md6.mooncalendar

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import androidx.core.content.ContextCompat
import kotlin.math.roundToInt

/** Configuration screen for the world-map widget.
 * Mirrors the Persian Calendar app: device dynamic colors + background transparency.
 */
class WidgetMapConfigureActivity : Activity() {
    private val prefs get() = Widget4x2.widgetPrefs(this, widgetId)
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var transparencySeek: SeekBar
    private lateinit var dynamicSwitch: Switch
    @Volatile private var previewTicket = 0
    private val previewExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun onDestroy() {
        previewExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Tr.init(this)
        super.onCreate(savedInstanceState)
        widgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        setResult(RESULT_CANCELED)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            WidgetSettingsUi.styleRoot(this@WidgetMapConfigureActivity, this)
        }

        val preview = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            setBackgroundColor(Color.TRANSPARENT)
            contentDescription = Tr.t("پیش‌نمایش ویجت نقشه")
        }
        root.addView(preview, LinearLayout.LayoutParams(-1, dp(205)).apply {
            leftMargin = dp(2)
            rightMargin = dp(2)
        })

        val settings = WidgetSettingsUi.settingsSurface(this, root)
        WidgetSettingsUi.actionButtons(this, settings, {
            val checked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && dynamicSwitch.isChecked
            val transparency = transparencySeek.progress / 100f
            prefs.edit()
                .putBoolean(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, checked)
                .putFloat(Widget4x2.PREF_WIDGET_TRANSPARENCY, transparency)
                .apply()
            Widget4x2.refresh(applicationContext)
            WidgetMap.updateAll(applicationContext)
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }, {
            setResult(RESULT_CANCELED)
            finish()
        })
        val (_, content) = WidgetSettingsUi.settingsScroll(this, settings)

        WidgetSettingsUi.sectionHeader(this, content, "نمایش")
        dynamicSwitch = Switch(this).apply {
            isChecked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                AstronomyWidgetSupport.bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
            isEnabled = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
            alpha = if (isEnabled) 1f else .55f
        }
        WidgetSettingsUi.settingRow(
            this, content,
            "پیروی از رنگ‌بندی دستگاه در ویجت‌ها",
            "در اندروید ۱۲ و بالاتر رنگ‌های پویا از سیستم گرفته می‌شوند",
            dynamicSwitch,
        )
        content.addView(TextView(this).apply {
            text = Tr.t("با خاموش بودن این گزینه، آسمان نقشه آبی اصلی خود را حفظ می‌کند. شفافیت فقط روی آسمان اعمال می‌شود.")
            textSize = 12f
            gravity = Gravity.START
            setTextColor(WidgetSettingsUi.secondaryColor(this@WidgetMapConfigureActivity))
            setPadding(dp(16), dp(2), dp(16), dp(10))
        }, lp())

        transparencySeek = SeekBar(this).apply {
            max = 100
            progress = (Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f)
                .coerceIn(0f, 1f) * 100f).roundToInt()
        }
        val transparencyRow = WidgetSettingsUi.sliderRow(
            this, content,
            "شفافیت پس‌زمینهٔ ویجت",
            "${persianDigits(transparencySeek.progress)}٪ — فقط آسمان نقشه",
            transparencySeek,
        )
        val transparencySummary = transparencyRow.findViewById<TextView>(android.R.id.text2)
        fun updateTransparencyLabel(value: Int) {
            transparencySummary?.text = Tr.t("${persianDigits(value)}٪ — فقط آسمان نقشه")
        }
        updateTransparencyLabel(transparencySeek.progress)
        // Keep the preview visible at 100% transparency by letting the wallpaper/background show
        // through the transparent bitmap instead of hiding the ImageView itself.
        fun refreshPreview() {
            val dynamic = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && dynamicSwitch.isChecked
            val transparency = transparencySeek.progress / 100f
            val ticket = ++previewTicket
            val w = dp(320)
            val h = dp(195)
            val app = applicationContext
            previewExecutor.execute {
                if (ticket != previewTicket) return@execute
                val bitmap = runCatching { WidgetMap.renderPreview(app, widgetId, w, h, dynamic, transparency) }.getOrNull()
                    ?: return@execute
                runOnUiThread {
                    if (!isFinishing && ticket == previewTicket) preview.setImageBitmap(bitmap)
                }
            }
        }

        transparencySeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                updateTransparencyLabel(progress)
                refreshPreview()
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
        })

        dynamicSwitch.setOnCheckedChangeListener { _, checked ->
            val effective = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && checked
            prefs.edit().putBoolean(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, effective).apply()
            Widget4x2.refresh(applicationContext)
            WidgetMap.updateAll(applicationContext)
            refreshPreview()
        }
        setContentView(root)
        refreshPreview()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    private fun lp(top: Int = 0): LinearLayout.LayoutParams = LinearLayout.LayoutParams(-1, -2).apply {
        if (top != 0) topMargin = dp(top)
    }

    private fun resolveColor(attr: Int, fallback: Int = if (isNightMode()) Color.WHITE else Color.BLACK): Int = runCatching {
        val out = android.util.TypedValue()
        if (!theme.resolveAttribute(attr, out, true)) return@runCatching fallback
        if (out.type in android.util.TypedValue.TYPE_FIRST_COLOR_INT..android.util.TypedValue.TYPE_LAST_COLOR_INT) return@runCatching out.data
        val id = out.resourceId
        if (id != 0) {
            runCatching { ContextCompat.getColorStateList(this, id)?.defaultColor }.getOrNull()?.let { return@runCatching it }
            runCatching {
                if (Build.VERSION.SDK_INT >= 23) resources.getColor(id, theme)
                else @Suppress("DEPRECATION") resources.getColor(id)
            }.getOrNull()?.let { return@runCatching it }
        }
        fallback
    }.getOrDefault(fallback)

    private fun primaryColor(): Int = resolveColor(android.R.attr.textColorPrimary, if (isNightMode()) Color.WHITE else Color.BLACK)
    private fun secondaryColor(): Int = resolveColor(android.R.attr.textColorSecondary, if (isNightMode()) 0xFFB8B8B8.toInt() else 0xFF5F6368.toInt())
    private fun isNightMode(): Boolean =
        (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

    private fun persianDigits(value: Int): String = Tr.digits(value.toString())
}
