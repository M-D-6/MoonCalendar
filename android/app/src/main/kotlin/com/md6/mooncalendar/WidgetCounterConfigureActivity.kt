package com.md6.mooncalendar

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import androidx.core.view.WindowCompat
import kotlin.math.min
import kotlin.math.roundToInt

class WidgetCounterConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var selectedTarget = CounterWidgetSupport.PRIVATE_TARGET
    private var followTheme = true
    private var customColor = 0
    private var transferCountToNewTarget = true
    private var showDecrementButton = false
    private var resetLabelFollowsLanguage = false
    private var committed = false
    /** Targets created while this screen was open; removed again if the screen is cancelled (like the desktop screen). */
    private val createdSaveIds = mutableListOf<String>()

    private lateinit var previewHost: FrameLayout
    private lateinit var targetSummaryRow: LinearLayout
    private lateinit var targetTransferSwitch: Switch
    private lateinit var targetTransferRow: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        Tr.init(this)
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        widgetId = resolveWidgetId(intent)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }

        selectedTarget = CounterWidgetSupport.targetId(this, widgetId)
        followTheme = CounterWidgetSupport.followTheme(this, widgetId)
        customColor = CounterWidgetSupport.customColor(this, widgetId)
        transferCountToNewTarget = CounterWidgetSupport.transferCountToNewTarget(this, widgetId)
        showDecrementButton = CounterWidgetSupport.showDecrement(this, widgetId)
        resetLabelFollowsLanguage = CounterWidgetSupport.resetLabelFollowsLanguage(this, widgetId)

        val outer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            WidgetSettingsUi.styleRoot(this@WidgetCounterConfigureActivity, this)
        }
        WidgetSettingsUi.header(
            this,
            outer,
            "شمارنده",
            "همان دستگاه شمارندهٔ برنامه با هدف مستقل برای هر ویجت",
        )

        previewHost = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipChildren = false
            clipToPadding = false
        }
        outer.addView(previewHost, LinearLayout.LayoutParams(-1, WidgetSettingsUi.dp(this, 224)).apply {
            leftMargin = WidgetSettingsUi.dp(this@WidgetCounterConfigureActivity, 2)
            rightMargin = WidgetSettingsUi.dp(this@WidgetCounterConfigureActivity, 2)
            bottomMargin = WidgetSettingsUi.dp(this@WidgetCounterConfigureActivity, 8)
        })
        val settings = WidgetSettingsUi.settingsSurface(this, outer)
        WidgetSettingsUi.actionButtons(this, settings, { commitAndFinish() }, {
            setResult(RESULT_CANCELED)
            finish()
        })
        val (_, content) = WidgetSettingsUi.settingsScroll(this, settings)

        buildCounterSettings(content)
        setResult(RESULT_CANCELED)
        setContentView(outer)
        previewHost.post { updatePreview() }
    }

    private fun buildCounterSettings(parent: LinearLayout) {
        // Same rows, wording and order as the desktop widget settings.
        WidgetSettingsUi.sectionHeader(this, parent, "شمارنده")

        targetSummaryRow = WidgetSettingsUi.settingRow(
            this,
            parent,
            "هدف ویجت",
            targetSummaryText(),
            onClick = { chooseTarget() },
            compact = true,
        )

        WidgetSettingsUi.switchRow(
            this,
            parent,
            "پیروی از تم ویجت",
            followThemeSummary(),
            followTheme,
            compact = true,
        ) { checked ->
            followTheme = checked
            if (!checked && customColor == Color.TRANSPARENT) customColor = CounterWidgetSupport.themePrimaryColor(this)
            updatePreview()
            rebuildColorRow(parent)
        }

        targetTransferSwitch = WidgetSettingsUi.switchRow(
            this,
            parent,
            "انتقال عدد فعلی به هدف جدید",
            transferSummary(),
            transferCountToNewTarget,
            compact = true,
        ) { checked ->
            transferCountToNewTarget = checked
            updateTransferSummary()
        }
        targetTransferRow = targetTransferSwitch.parent as LinearLayout

        WidgetSettingsUi.switchRow(
            this,
            parent,
            "نمایش دکمه ۱-",
            if (showDecrementButton) "دکمهٔ کاهش روی همین ویجت نمایش داده می‌شود" else "دکمهٔ کاهش روی همین ویجت مخفی است",
            showDecrementButton,
            compact = true,
        ) { checked ->
            showDecrementButton = checked
            updatePreview()
        }

        WidgetSettingsUi.switchRow(
            this,
            parent,
            "هماهنگ‌سازی متن RESET با زبان برنامه",
            if (resetLabelFollowsLanguage) "متن RESET با زبان برنامه هماهنگ می‌شود" else "متن RESET به‌صورت RESET نمایش داده می‌شود",
            resetLabelFollowsLanguage,
            compact = true,
        ) { checked ->
            resetLabelFollowsLanguage = checked
            updatePreview()
        }

        rebuildColorRow(parent)
    }

    private var colorRow: LinearLayout? = null

    private fun followThemeSummary(): String = if (followTheme) {
        "رنگ بدنه دقیقاً از رنگ سیستم/تم ویجت گرفته می‌شود"
    } else {
        "رنگ بدنه فقط برای همین ویجت و مستقل از شمارندهٔ اصلی است"
    }

    private fun transferSummary(): String = if (transferCountToNewTarget) {
        "هنگام ساخت هدف جدید، شمارش فعلی هم منتقل می‌شود"
    } else {
        "هدف جدید از صفر شروع می‌شود"
    }

    /** Like the desktop screen, the colour row only exists while the widget does not follow the theme. */
    private fun rebuildColorRow(parent: LinearLayout) {
        colorRow?.let { parent.removeView(it) }
        colorRow = null
        if (followTheme) return
        val colorDot = TextView(this).apply {
            text = "●"
            textSize = 30f
            gravity = Gravity.CENTER
            setTextColor(customColor)
        }
        colorRow = WidgetSettingsUi.settingRow(
            this,
            parent,
            "رنگ بدنهٔ ویجت",
            "انتخاب رنگ مستقل برای همین ویجت",
            colorDot,
            { pickColor() },
            controlWidthDp = 48,
            compact = true,
        )
    }

    private fun targetSummaryText(): String {
        val save = if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) null else CounterWidgetSupport.findSave(this, selectedTarget)
        return if (save == null) {
            "بدون هدف — شمارندهٔ خصوصی این ویجت است و در ذخیره‌های برنامه دیده نمی‌شود"
        } else {
            "${save.name} — عدد فعلی ${persianDigits(save.count)}${save.target?.let { " از هدف ${persianDigits(it)}" } ?: ""}"
        }
    }

    private fun updateTargetSummary() {
        val texts = targetSummaryRow.getChildAt(0) as? LinearLayout ?: return
        val summary = texts.getChildAt(1) as? TextView ?: return
        summary.text = Tr.t(targetSummaryText())
    }

    private fun updateTransferSummary() {
        val texts = targetTransferRow.getChildAt(0) as? LinearLayout ?: return
        val summary = texts.getChildAt(1) as? TextView ?: return
        summary.text = Tr.t(transferSummary())
    }

    private fun chooseTarget() {
        val ids = mutableListOf(CounterWidgetSupport.PRIVATE_TARGET)
        val choices = mutableListOf(
            WidgetDialogs.Choice(
                "بدون هدف",
                "عدد فعلی همین ویجت؛ ${persianDigits(CounterWidgetSupport.privateCount(this, widgetId))} هنگام ساخت هدف جدید منتقل می‌شود",
            ),
        )
        CounterWidgetSupport.targetChoices(this).forEach { save ->
            ids += save.id
            choices += WidgetDialogs.Choice(
                save.name,
                "عدد فعلی: ${persianDigits(save.count)}${save.target?.let { " — هدف ${persianDigits(it)}" } ?: ""}",
            )
        }
        WidgetDialogs.singleChoice(
            activity = this,
            title = "هدف همین ویجت",
            choices = choices,
            selected = ids.indexOf(selectedTarget).coerceAtLeast(0),
            neutralText = "ساخت هدف جدید",
            onNeutral = { createNewTarget() },
        ) { which ->
            selectedTarget = ids[which]
            updateTargetSummary()
            updatePreview()
        }
    }

    private fun createNewTarget() {
        val current = CounterWidgetSupport.resolveCounter(this, widgetId).second
        var transfer = transferCountToNewTarget
        fun message() = if (transfer) {
            "عدد فعلی ${persianDigits(current)} به هدف جدید منتقل می‌شود."
        } else {
            "هدف جدید از صفر شروع می‌شود و عدد فعلی منتقل نمی‌شود."
        }
        lateinit var handle: WidgetDialogs.Handle
        handle = WidgetDialogs.form(
            activity = this,
            title = "ساخت هدف جدید",
            fields = listOf(
                WidgetDialogs.Field("نام هدف", "", ltr = false),
                WidgetDialogs.Field("عدد هدف", "", ltr = true, numeric = true),
            ),
            positiveText = "ساخت",
            message = message(),
            toggle = WidgetDialogs.Toggle(
                "انتقال عدد فعلی به هدف جدید",
                "می‌توانی این گزینه را در تنظیمات ویجت هم تغییر بدهی.",
                transfer,
            ) { value ->
                transfer = value
                handle.setMessage(message())
            },
        ) { values ->
            val name = values.getOrNull(0)?.trim().orEmpty()
            val target = latinDigits(values.getOrNull(1).orEmpty()).trim().toIntOrNull()
            when {
                name.isEmpty() -> "نام هدف را وارد کن"
                target == null || target !in 1..CounterWidgetSupport.MAX -> "عدد هدف باید بین ۱ تا ${persianDigits(CounterWidgetSupport.MAX)} باشد"
                else -> {
                    val id = CounterWidgetSupport.createSave(this, name, target, if (transfer) current else 0)
                    if (id == null) {
                        "ساخت هدف انجام نشد"
                    } else {
                        createdSaveIds += id
                        selectedTarget = id
                        if (transferCountToNewTarget != transfer) targetTransferSwitch.isChecked = transfer
                        updateTargetSummary()
                        updatePreview()
                        null
                    }
                }
            }
        }
    }

    private fun pickColor() {
        WidgetColorPicker.show(
            activity = this,
            title = "رنگ بدنهٔ همین ویجت",
            subtitle = "فقط همین ویجت را تغییر می‌دهد.",
            initial = customColor,
            allowAlpha = false,
            presets = WidgetColorPicker.TEXT_PRESETS,
        ) { color ->
            customColor = color
            followTheme = false
            updatePreview()
        }
    }

    private fun updatePreview() {
        if (!::previewHost.isInitialized) return
        previewHost.removeAllViews()

        val rootWidth = previewHost.width.coerceAtLeast(1)
        val rootHeight = previewHost.height.coerceAtLeast(1)
        val density = resources.displayMetrics.density
        val gapPx = 1f * density
        val frameWidthPx = min(rootWidth.toFloat() * .82f, 600f * density)
        val initialDeviceWidth = min(frameWidthPx, rootHeight.toFloat() * .76f)
        val initialScale = (initialDeviceWidth / (200f * density)).coerceIn(.75f, 1.25f)
        var targetHeightPx = 28f * density * initialScale
        var deviceWidth = min(
            frameWidthPx,
            (rootHeight - if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) 0f else targetHeightPx + gapPx - 8f * density)
                .coerceAtLeast(120f) * .76f,
        )
        targetHeightPx = 28f * density * (deviceWidth / (200f * density)).coerceIn(.75f, 1.25f)
        deviceWidth = min(
            frameWidthPx,
            (rootHeight - if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) 0f else targetHeightPx + gapPx - 8f * density)
                .coerceAtLeast(120f) * .76f,
        )
        val deviceHeight = deviceWidth / .76f

        val group = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            gravity = Gravity.CENTER_HORIZONTAL
        }
        previewHost.addView(group, FrameLayout.LayoutParams(deviceWidth.roundToInt(), (deviceHeight + if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) 0f else targetHeightPx + gapPx).roundToInt(), Gravity.CENTER))

        val save = if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) null else CounterWidgetSupport.findSave(this, selectedTarget)
        val targetName = save?.name
        if (!targetName.isNullOrBlank()) {
            val label = TextView(this).apply {
                text = targetName
                textSize = 11f
                gravity = Gravity.CENTER
                val bodyColor = if (followTheme) CounterWidgetSupport.themePrimaryColor(this@WidgetCounterConfigureActivity) else customColor
                setTextColor(if (androidx.core.graphics.ColorUtils.calculateLuminance(bodyColor) > .52) Color.BLACK else Color.WHITE)
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = WidgetSettingsUi.dp(this@WidgetCounterConfigureActivity, 10).toFloat()
                    setColor(Color.TRANSPARENT)
                    setStroke(WidgetSettingsUi.dp(this@WidgetCounterConfigureActivity, 1), CounterWidgetSupport.themePrimaryColor(this@WidgetCounterConfigureActivity))
                }
            }
            group.addView(label, LinearLayout.LayoutParams((deviceWidth * .72f).roundToInt().coerceAtLeast(56), targetHeightPx.roundToInt()))
            group.addView(View(this), LinearLayout.LayoutParams(1, gapPx.roundToInt()))
        }

        val device = FrameLayout(this).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LTR
        }
        group.addView(device, LinearLayout.LayoutParams(deviceWidth.roundToInt(), deviceHeight.roundToInt()))

        val screen = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER; setImageResource(R.drawable.tally_counter_screen) }
        device.addView(screen, FrameLayout.LayoutParams(-1, -1))
        val body = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(CounterWidgetSupport.buildTintedBodyBitmap(this@WidgetCounterConfigureActivity, CounterWidgetSupport.widgetPrimaryColor(this@WidgetCounterConfigureActivity, widgetId).let { if (followTheme) CounterWidgetSupport.themePrimaryColor(this@WidgetCounterConfigureActivity) else customColor }))
        }
        device.addView(body, FrameLayout.LayoutParams(-1, -1))

        val count = CounterWidgetSupport.resolveCounter(this, widgetId).second
        val countView = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageBitmap(CounterWidgetSupport.buildCountBitmap(this@WidgetCounterConfigureActivity, count, deviceWidth.roundToInt(), deviceHeight.roundToInt()))
        }
        device.addView(countView, FrameLayout.LayoutParams(-1, -1))

        fun addButton(asset: Int, dx: Float, dy: Float, finalSize: Float) {
            val size = finalSize.roundToInt().coerceAtLeast(2)
            val holder = ImageView(this).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                setImageResource(asset)
                translationX = dx
                translationY = dy
            }
            device.addView(holder, FrameLayout.LayoutParams(size, size, Gravity.CENTER))
        }

        addButton(R.drawable.tally_counter_main_button, deviceWidth * .02f, deviceHeight * .20f, deviceWidth * .507f)
        if (showDecrementButton) {
            addButton(R.drawable.tally_counter_reset_button, -deviceWidth * .22f, -deviceWidth * .02f, deviceWidth * .08f)
        }
        addButton(R.drawable.tally_counter_reset_button, deviceWidth * .22f, -deviceWidth * .02f, deviceWidth * .08f)
    }

    override fun onDestroy() {
        if (!committed) createdSaveIds.forEach { runCatching { CounterWidgetSupport.deleteSave(applicationContext, it) } }
        super.onDestroy()
    }

    private fun commitAndFinish() {
        committed = true
        val privateCount = if (selectedTarget == CounterWidgetSupport.PRIVATE_TARGET) {
            CounterWidgetSupport.privateCount(this, widgetId)
        } else 0
        CounterWidgetSupport.saveTarget(this, widgetId, selectedTarget, privateCount)
        CounterWidgetSupport.saveStyle(this, widgetId, followTheme, customColor, 0f)
        CounterWidgetSupport.saveTransferCountToNewTarget(this, widgetId, transferCountToNewTarget)
        CounterWidgetSupport.saveShowDecrement(this, widgetId, showDecrementButton)
        CounterWidgetSupport.saveResetLabelFollowsLanguage(this, widgetId, resetLabelFollowsLanguage)
        WidgetCounter.updateAll(applicationContext)
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        finish()
    }

    private fun resolveWidgetId(source: Intent?): Int {
        val invalid = AppWidgetManager.INVALID_APPWIDGET_ID
        val direct = source?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, invalid) ?: invalid
        if (direct != invalid) return direct
        val aliases = arrayOf(AppWidgetManager.EXTRA_APPWIDGET_ID, "appWidgetId", "widget_id", "widgetId")
        source?.extras?.let { extras ->
            for (key in aliases) {
                when (val value = extras.get(key)) {
                    is Number -> value.toInt().takeIf { it != invalid }?.let { return it }
                    is String -> value.toIntOrNull()?.takeIf { it != invalid }?.let { return it }
                }
            }
        }
        source?.data?.let { uri ->
            sequenceOf(
                uri.getQueryParameter(AppWidgetManager.EXTRA_APPWIDGET_ID),
                uri.getQueryParameter("appWidgetId"),
                uri.lastPathSegment,
            ).mapNotNull { it?.toIntOrNull() }
                .firstOrNull { it != invalid }
                ?.let { return it }
        }
        return invalid
    }

    private fun latinDigits(text: String): String = buildString {
        for (c in text) append(
            when (c) {
                in '۰'..'۹' -> '0' + (c - '۰')
                in '٠'..'٩' -> '0' + (c - '٠')
                else -> c
            },
        )
    }

    private fun persianDigits(value: Int): String = Tr.digits(value.toString())
}
