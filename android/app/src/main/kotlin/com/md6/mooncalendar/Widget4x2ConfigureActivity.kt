package com.md6.mooncalendar

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.location.Location
import android.location.LocationManager
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.content.res.ColorStateList
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

class Widget4x2ConfigureActivity : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var isSunViewConfiguration = false
    private val prefs get() = Widget4x2.widgetPrefs(this, widgetId)
    private lateinit var previewHost: FrameLayout
    private lateinit var scaleLabel: TextView
    private lateinit var scaleSeek: SeekBar
    private val switches = mutableListOf<Switch>()
    private val REQUEST_LOCATION = 4402
    private var prayerTimesRow: LinearLayout? = null

    private val contentKeys = arrayOf(
        "other_calendars",
        "holidays",
        "non_holiday_events",
        "owghat",
        "owghat_location",
    )
    private val contentLabels = arrayOf(
        "تقویم‌های دیگر",
        "تعطیلات رسمی",
        "مناسبت‌های غیر تعطیل",
        "اوقات شرعی",
        "مکان اوقات شرعی",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        Tr.init(this)
        super.onCreate(savedInstanceState)
        // The 4x2 configuration activity uses the same edge-to-edge model as the
        // Persian Calendar Android configuration screen. WidgetSettingsUi then applies the
        // safe system-bar insets so the preview/settings never enter the status bar.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        widgetId = resolveWidgetId(intent)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        isSunViewConfiguration = runCatching {
            AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider?.className == WidgetSunView::class.java.name
        }.getOrDefault(false)

        val outer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            WidgetSettingsUi.styleRoot(this@Widget4x2ConfigureActivity, this)
        }

        previewHost = FrameLayout(this).apply {
            minimumHeight = dp(150)
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            background = WidgetSettingsUi.roundedBackground(
                this@Widget4x2ConfigureActivity,
                Color.TRANSPARENT,
                24f,
                stroke = false,
            )
            clipToOutline = true
        }
        outer.addView(previewHost, LinearLayout.LayoutParams(-1, dp(if (isSunViewConfiguration) 186 else 205)).apply {
            leftMargin = dp(2)
            rightMargin = dp(2)
        })

        val settings = WidgetSettingsUi.settingsSurface(this, outer)
        WidgetSettingsUi.actionButtons(this, settings, {
            Widget4x2.refresh(this)
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }, {
            setResult(RESULT_CANCELED)
            finish()
        })
        val (_, content) = WidgetSettingsUi.settingsScroll(this, settings)

        if (isSunViewConfiguration) {
            buildSunViewSettings(content)
        } else {
            buildAppearance(content)
            buildWidgetSettings(content)
            buildLocationSettings(content)
        }

        if (!isSunViewConfiguration) updateScaleText()
        if (!isSunViewConfiguration) refreshLocationRows()

        setResult(RESULT_CANCELED)
        setContentView(outer)
        previewHost.post { updatePreview() }
    }

    private fun resolveWidgetId(source: Intent?): Int {
        val invalid = AppWidgetManager.INVALID_APPWIDGET_ID
        val direct = source?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, invalid) ?: invalid
        if (direct != invalid) return direct

        // A few launchers historically forwarded the id as a string or in the data URI when
        // reconfiguring an existing widget. Accept those forms too so Edit never opens blank/canceled.
        val aliases = arrayOf(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            "appWidgetId",
            "widget_id",
            "widgetId",
        )
        aliases.forEach { key ->
            val value = source?.extras?.get(key)
            when (value) {
                is Number -> value.toInt().takeIf { it != invalid }?.let { return it }
                is String -> value.toIntOrNull()?.takeIf { it != invalid }?.let { return it }
            }
        }
        source?.data?.let { uri ->
            sequenceOf(
                uri.getQueryParameter(AppWidgetManager.EXTRA_APPWIDGET_ID),
                uri.getQueryParameter("appWidgetId"),
                uri.lastPathSegment,
            ).mapNotNull { it?.toIntOrNull() }.firstOrNull()?.takeIf { it != invalid }?.let { return it }
        }
        // Some launchers use the widget id in the Intent action when editing an existing widget.
        // Accept that legacy form as well so the configuration screen can always reconstruct the
        // real widget state and preview instead of opening with an invalid id.
        source?.action?.let { action ->
            val suffix = action.removePrefix(AppWidgetManager.EXTRA_APPWIDGET_ID)
            if (suffix != action) suffix.toIntOrNull()?.takeIf { it != invalid }?.let { return it }
        }
        return invalid
    }

    private fun buildAppearance(parent: LinearLayout) {
        sectionHeader(parent, "نمایش")

        val scaleContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(4))
            layoutDirection = Tr.layoutDir()
            background = WidgetSettingsUi.roundedBackground(this@Widget4x2ConfigureActivity, Color.TRANSPARENT, 16f, false)
        }
        scaleContainer.addView(TextView(this).apply {
            text = Tr.t("اندازهٔ متن")
            textSize = 15f
            gravity = Gravity.START
            setTextColor(primaryColor())
        }, lp())
        scaleSeek = SeekBar(this).apply {
            max = 235
            progress = (((Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TEXT_SCALE, 1f)
                .coerceIn(.65f, 3f) - .65f) * 100f).roundToInt()).coerceIn(0, 235)
        }
        scaleContainer.addView(scaleSeek, lp())
        scaleLabel = TextView(this).apply {
            gravity = Gravity.START
            textSize = 12f
            setTextColor(secondaryColor())
            setPadding(0, 0, 0, dp(4))
        }
        scaleContainer.addView(scaleLabel, lp())
        parent.addView(scaleContainer, lp())
        scaleSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) {
                persistScale(currentScale())
                updateScaleText()
                if (fromUser) updatePreview()
            }
            override fun onStartTrackingTouch(bar: SeekBar?) = Unit
            override fun onStopTrackingTouch(bar: SeekBar?) = Unit
        })

        val dynamic = addSwitchRow(
            parent,
            "پیروی از رنگ‌بندی دستگاه در ویجت‌ها",
            null,
            Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS,
            true,
        )
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            (dynamic.parent as? View)?.visibility = View.GONE
        }

        val transparencyRow = clickableRow(
            parent,
            "شفافیت پس‌زمینهٔ ویجت",
            "میزان شفافیت زمینهٔ ویجت",
        ) { showTransparencyDialog() }

        val textColorRow = clickableRow(
            parent,
            "رنگ نوشته‌های ویجت",
            "انتخاب رنگ دلخواه برای نوشته‌های ویجت",
            newTextColorDot(),
        ) { showColorDialog(false) }
        val bgColorRow = clickableRow(
            parent,
            "رنگ پس‌زمینهٔ ویجت",
            "انتخاب رنگ دلخواه برای پس‌زمینهٔ ویجت",
            newBgColorDot(),
        ) { showColorDialog(true) }

        fun updateColorRows(checked: Boolean) {
            // Transparency and colors belong only to this widget instance.
            transparencyRow.visibility = View.VISIBLE
            textColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            bgColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            transparencyRow.findViewById<TextView>(android.R.id.text1)?.text =
                Tr.t("شفافیت پس‌زمینهٔ ویجت")
            transparencyRow.contentDescription =
                Tr.t("شفافیت پس‌زمینهٔ ویجت، ${persianDigits((floatValue(Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f) * 100).roundToInt())} درصد")
        }
        dynamic.setOnCheckedChangeListener { _, checked ->
            persistBool(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, checked)
            updateColorRows(checked)
            Widget4x2.refresh(applicationContext)
            updatePreview()
        }
        updateColorRows(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && bool(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true))
    }

    private fun buildSunViewSettings(parent: LinearLayout) {
        sectionHeader(parent, "نمایش")
        val dynamic = addSwitchRow(
            parent,
            "پیروی از رنگ‌بندی دستگاه در ویجت‌ها",
            null,
            Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS,
            true,
        )
        dynamic.visibility = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) View.VISIBLE else View.GONE

        val textColorRow = clickableRow(
            parent,
            "رنگ نوشته‌های ویجت",
            "انتخاب رنگ دلخواه برای نوشته‌های ویجت",
            newTextColorDot(),
        ) { showColorDialog(false) }
        val bgColorRow = clickableRow(
            parent,
            "رنگ پس‌زمینهٔ ویجت",
            "انتخاب رنگ دلخواه برای پس‌زمینهٔ ویجت",
            newBgColorDot(),
        ) { showColorDialog(true) }
        val transparencyRow = clickableRow(
            parent,
            "شفافیت پس‌زمینهٔ ویجت",
            "میزان شفافیت زمینهٔ ویجت",
        ) { showTransparencyDialog() }

        fun updateRows(checked: Boolean) {
            // Transparency and colors belong only to this widget instance.
            transparencyRow.visibility = View.VISIBLE
            textColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            bgColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            transparencyRow.findViewById<TextView>(android.R.id.text1)?.text = Tr.t("شفافیت پس‌زمینهٔ ویجت")
            transparencyRow.contentDescription =
                Tr.t("شفافیت پس‌زمینهٔ ویجت، ${persianDigits((floatValue(Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f) * 100).roundToInt())} درصد")
        }
        dynamic.setOnCheckedChangeListener { _, checked ->
            persistBool(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, checked)
            updateRows(checked)
            Widget4x2.refresh(applicationContext)
            updatePreview()
        }
        updateRows(Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && bool(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true))

        buildLocationSettings(parent, allowClearPrayerTimes = false)
    }

    private fun buildWidgetSettings(parent: LinearLayout) {
        sectionHeader(parent, "تنظیمات ویجت")
        addSwitchRow(
            parent,
            "نمایش تاریخ به‌صورت عددی",
            "استفاده از ۱۳۹۰/۱/۱ شمسی به‌جای ۱ فروردین ۱۳۹۰ در ویجت و اعلان",
            Widget4x2.PREF_NUMERICAL_DATE,
            false,
        )
        addSwitchRow(
            parent,
            "ساعت در ویجت",
            "نمایش ساعت در ویجت‌ها",
            Widget4x2.PREF_WIDGET_CLOCK,
            true,
        )
        addSwitchRow(
            parent,
            "۲۴ ساعته",
            "نمایش ساعت به‌صورت ۲۴تایی",
            Widget4x2.PREF_WIDGET_IN_24,
            false,
        )
        addSwitchRow(
            parent,
            "نمایش ثانیه",
            "نمایش ثانیه در ساعت ویجت؛ به‌صورت پیش‌فرض خاموش است",
            Widget4x2.PREF_WIDGET_SHOW_SECONDS,
            false,
        )
        addSwitchRow(
            parent,
            "تراز کناری ساعت و تاریخ",
            "ساعت چپ‌چین و تاریخ راست‌چین؛ پیش‌فرض همچنان وسط‌چین است",
            Widget4x2.PREF_WIDGET_EDGE_ALIGN,
            false,
        )
        addSwitchRow(
            parent,
            "تراز وسط ویجت‌ها",
            "تراز وسط ویجت‌های ۴×۱ و ۲×۲",
            Widget4x2.PREF_CENTER_ALIGN_WIDGETS,
            true,
        )
        if (TimeZone.getDefault().id != "Asia/Tehran") {
            addSwitchRow(
                parent,
                "وقت ایران",
                "نمایش ویجت و اعلان برنامه به‌وقت ایران در همه‌جا، مناسب ایرانیان خارج از ایران",
                Widget4x2.PREF_IRAN_TIME,
                false,
            )
        }
        clickableRow(
            parent,
            "سفارشی‌سازی ویجت",
            "چه چیزهایی در ویجت و اعلان نمایش داده شوند",
        ) { showContentDialog() }
        prayerTimesRow = clickableRow(
            parent,
            "اوقات نمایش‌داده‌شده در ویجت",
            prayerTimesSummary(),
        ) { showPrayerTimesDialog() }
    }

    private fun buildLocationSettings(parent: LinearLayout, allowClearPrayerTimes: Boolean = true) {
        sectionHeader(parent, "موقعیت")
        clickableRow(
            parent,
            "دریافت مختصات از مکان‌یاب (GPS)",
            "اگر از این طریق ممکن باشد، نیازی به سایر تنظیمات این بخش نیست",
        ) { requestGpsLocation() }
        clickableRow(
            parent,
            "موقعیت",
            "اگر موقعیتتان در این فهرست نبود، مختصات را در گزینهٔ بعدی وارد کنید",
        ) { showCityDialog() }
        coordinatesRow = clickableRow(
            parent,
            "مختصات جغرافیایی",
            coordinatesSummary(),
        ) { showCoordinatesDialog() }
        if (allowClearPrayerTimes) {
            // One row, two states: with a location it hides the times, without one it brings them back.
            timesToggleRow = clickableRow(
                parent,
                timesToggleTitle(),
                timesToggleSummary(),
            ) { onTimesToggle() }
        }
    }

    private var coordinatesRow: LinearLayout? = null
    private var timesToggleRow: LinearLayout? = null

    private fun timesToggleTitle(): String = if (hasCoordinates()) "عدم نمایش اوقات" else "نمایش اوقات"

    private fun timesToggleSummary(): String = when {
        hasCoordinates() -> "موقعیت پاک می‌شود و اوقات در ویجت نمایش داده نمی‌شود"
        hasLocationBackup() -> "بازگرداندن آخرین موقعیت${locationBackupName().let { if (it.isBlank()) "" else ": $it" }}"
        else -> "برای نمایش اوقات، یک موقعیت انتخاب کنید"
    }

    private fun onTimesToggle() {
        when {
            hasCoordinates() -> clearLocationAndRefresh()
            hasLocationBackup() -> restoreLocationBackup()
            else -> showCityDialog()
        }
    }

    private fun refreshLocationRows() {
        timesToggleRow?.findViewById<TextView>(android.R.id.text1)?.text = Tr.t(timesToggleTitle())
        setRowSummary(timesToggleRow, timesToggleSummary())
        setRowSummary(coordinatesRow, coordinatesSummary())
    }

    private val BACKUP_LAT = "LocationBackupLat"
    private val BACKUP_LON = "LocationBackupLon"
    private val BACKUP_ALT = "LocationBackupAlt"
    private val BACKUP_NAME = "LocationBackupName"

    private fun hasLocationBackup(): Boolean =
        prefs.getString(BACKUP_LAT, null)?.toDoubleOrNull() != null && prefs.getString(BACKUP_LON, null)?.toDoubleOrNull() != null

    private fun locationBackupName(): String = prefs.getString(BACKUP_NAME, "").orEmpty()

    /** Remember the location before "عدم نمایش اوقات" clears it, so "نمایش اوقات" can bring it back. */
    private fun backupLocation() {
        if (!hasCoordinates()) return
        prefs.edit()
            .putString(BACKUP_LAT, doubleValue(Widget4x2.PREF_LATITUDE, 0.0).toString())
            .putString(BACKUP_LON, doubleValue(Widget4x2.PREF_LONGITUDE, 0.0).toString())
            .putString(BACKUP_ALT, doubleValue(Widget4x2.PREF_ALTITUDE, 0.0).toString())
            .putString(BACKUP_NAME, prefs.getString(Widget4x2.PREF_LOCATION, "").orEmpty())
            .apply()
    }

    private fun restoreLocationBackup() {
        val lat = prefs.getString(BACKUP_LAT, null)?.toDoubleOrNull() ?: return
        val lon = prefs.getString(BACKUP_LON, null)?.toDoubleOrNull() ?: return
        val alt = prefs.getString(BACKUP_ALT, null)?.toDoubleOrNull() ?: 0.0
        saveLocation(lat, lon, alt, locationBackupName())
    }

    private fun addSwitchRow(
        parent: LinearLayout,
        title: String,
        summary: String?,
        key: String,
        defaultValue: Boolean,
    ): Switch {
        val enabled = key != Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS || android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S
        return WidgetSettingsUi.switchRow(this, parent, title, summary, bool(key, defaultValue), enabled) { checked ->
            persistBool(key, checked)
            // The prayer times the app synced were computed for the old time zone setting.
            if (key == Widget4x2.PREF_IRAN_TIME) Widget4x2.resyncPrayerTimes(applicationContext, widgetId)
            updatePreview()
            if (key == Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS) Widget4x2.refresh(applicationContext)
        }
    }

    private fun clickableRow(parent: LinearLayout, title: String, summary: String, control: View? = null, onClick: () -> Unit): LinearLayout =
        WidgetSettingsUi.settingRow(this, parent, title, summary, control, onClick)

    private var textColorDot: WidgetColorPicker.ColorDot? = null
    private var bgColorDot: WidgetColorPicker.ColorDot? = null

    private fun newTextColorDot(): WidgetColorPicker.ColorDot =
        WidgetColorPicker.ColorDot(this, Widget4x2.readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR, Color.WHITE))
            .also { textColorDot = it }

    private fun newBgColorDot(): WidgetColorPicker.ColorDot =
        WidgetColorPicker.ColorDot(this, Widget4x2.readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_BACKGROUND_COLOR, Color.TRANSPARENT))
            .also { bgColorDot = it }

    /** Settings are saved as soon as they change, so make sure the real widgets show them even if the screen is left with Back. */
    override fun onPause() {
        Widget4x2.refresh(applicationContext)
        super.onPause()
    }

    private fun sectionHeader(parent: LinearLayout, title: String) {
        WidgetSettingsUi.sectionHeader(this, parent, title)
    }

    private fun showContentDialog() {
        val current = contentSet()
        WidgetDialogs.multiChoice(
            activity = this,
            title = "کدام موارد در ویجت نمایش داده شوند؟",
            subtitle = "هر موردی را که نمی‌خواهید خاموش کنید",
            labels = contentLabels.toList(),
            checked = contentKeys.map { it in current }.toBooleanArray(),
        ) { state ->
            // The marker tells the widget this selection already knows about "holidays", so an unchecked
            // holidays item really means "hide them" (older saved selections without it keep showing holidays).
            val nativeValues = contentKeys.filterIndexed { i, _ -> state[i] }.toMutableSet()
                .apply { add(Widget4x2.CONTENT_MARKER) }
            prefs.edit().putStringSet(Widget4x2.PREF_WHAT_TO_SHOW_WIDGETS, nativeValues).apply()
            Widget4x2.refresh(this)
            updatePreview()
        }
    }

    private fun prayerTimesSummary(): String {
        val selected = Widget4x2.selectedPrayerKeys(prefs)
        if (selected.size == Widget4x2.PRAYER_TIME_KEYS.size) return "همه"
        return Widget4x2.PRAYER_TIME_KEYS.indices
            .filter { Widget4x2.PRAYER_TIME_KEYS[it] in selected }
            .joinToString("، ") { Widget4x2.PRAYER_TIME_LABELS[it] }
    }

    /** Add / remove each prayer time shown in the widget (at least one always stays selected). */
    private fun showPrayerTimesDialog() {
        val keys = Widget4x2.PRAYER_TIME_KEYS
        val selected = Widget4x2.selectedPrayerKeys(prefs)
        WidgetDialogs.multiChoice(
            activity = this,
            title = "اوقات نمایش‌داده‌شده در ویجت",
            subtitle = "امساک، اذان عصر و اذان عشاء به‌صورت پیش‌فرض خاموش‌اند",
            labels = Widget4x2.PRAYER_TIME_LABELS.toList(),
            checked = keys.map { it in selected }.toBooleanArray(),
            minSelected = 1,
            minMessage = "حداقل یک وقت باید انتخاب شود",
        ) { state ->
            val ordered = keys.filterIndexed { i, _ -> state[i] }.joinToString(",")
            prefs.edit().putString(Widget4x2.PREF_WIDGET_PRAYER_TIMES, ordered).apply()
            Widget4x2.refresh(this)
            setRowSummary(prayerTimesRow, prayerTimesSummary())
            updatePreview()
        }
    }

    /** The summary line of a [WidgetSettingsUi.settingRow] lives inside its first child (the text column). */
    private fun setRowSummary(row: LinearLayout?, text: String) {
        ((row?.getChildAt(0) as? LinearLayout)?.getChildAt(1) as? TextView)?.text = Tr.t(text)
    }

    private fun showTransparencyDialog() {
        val initial = floatValue(Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f)
        WidgetDialogs.slider(
            activity = this,
            title = "شفافیت پس‌زمینهٔ ویجت",
            subtitle = "فقط برای همین ویجت اعمال می‌شود",
            initialPercent = (initial * 100).roundToInt(),
        ) { percent ->
            val v = percent / 100f
            prefs.edit().putFloat(Widget4x2.PREF_WIDGET_TRANSPARENCY, v).apply()
            Widget4x2.refresh(applicationContext)
            updatePreview()
        }
    }

    private fun showColorDialog(background: Boolean) {
        val key = if (background) Widget4x2.PREF_SELECTED_WIDGET_BACKGROUND_COLOR else Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR
        val fallback = if (background) Color.TRANSPARENT else Color.WHITE
        WidgetColorPicker.show(
            activity = this,
            title = if (background) "رنگ پس‌زمینهٔ ویجت" else "رنگ نوشته‌های ویجت",
            subtitle = if (background) "رنگ و کدری زمینهٔ ویجت" else "رنگ متن‌ها و نوشته‌ها در ویجت",
            initial = Widget4x2.readColor(prefs, key, fallback),
            allowAlpha = background,
            presets = if (background) WidgetColorPicker.BACKGROUND_PRESETS else WidgetColorPicker.TEXT_PRESETS,
        ) { picked ->
            val value = if (background) {
                String.format(Locale.US, "#%08X", picked.toLong() and 0xFFFFFFFFL)
            } else {
                String.format(Locale.US, "#%06X", picked and 0xFFFFFF)
            }
            prefs.edit().putString(key, value).apply()
            (if (background) bgColorDot else textColorDot)?.color = picked
            Widget4x2.refresh(applicationContext)
            updatePreview()
        }
    }

    private fun showCoordinatesDialog() {
        WidgetDialogs.form(
            activity = this,
            title = "ورود دستی مختصات",
            subtitle = "اعداد اعشاری را با نقطه بنویسید؛ مثل 35.6892",
            fields = listOf(
                WidgetDialogs.Field("عرض جغرافیایی", doubleValue(Widget4x2.PREF_LATITUDE, 0.0).toString()),
                WidgetDialogs.Field("طول جغرافیایی", doubleValue(Widget4x2.PREF_LONGITUDE, 0.0).toString()),
                WidgetDialogs.Field("ارتفاع (متر، اختیاری)", doubleValue(Widget4x2.PREF_ALTITUDE, 0.0).toString()),
                WidgetDialogs.Field("نام موقعیت (اختیاری)", prefs.getString(Widget4x2.PREF_LOCATION, "") ?: "", ltr = false),
            ),
        ) { values ->
            val latitude = parseNumber(values[0])
            val longitude = parseNumber(values[1])
            val altitude = if (values[2].isBlank()) 0.0 else parseNumber(values[2])
            if (latitude == null || longitude == null || altitude == null || altitude !in -418.0..8849.0 ||
                latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
                "مختصات معتبر نیست."
            } else {
                saveLocation(latitude, longitude, altitude, values[3].trim())
                null
            }
        }
    }

    private fun parseNumber(raw: String): Double? = raw.trim()
        .replace('۰', '0').replace('۱', '1').replace('۲', '2').replace('۳', '3').replace('۴', '4')
        .replace('۵', '5').replace('۶', '6').replace('۷', '7').replace('۸', '8').replace('۹', '9')
        .replace('٫', '.')
        .toDoubleOrNull()

    private fun reverseGeocode(latitude: Double, longitude: Double): Pair<String, String> {
        if (!android.location.Geocoder.isPresent()) return "" to ""
        return runCatching {
            @Suppress("DEPRECATION")
            val address = android.location.Geocoder(this, Locale("fa"))
                .getFromLocation(latitude, longitude, 1)?.firstOrNull()
            val city = listOf(address?.locality, address?.subAdminArea, address?.adminArea)
                .firstOrNull { !it.isNullOrBlank() }.orEmpty()
            city to address?.countryCode.orEmpty()
        }.getOrDefault("" to "")
    }

    private fun editField(hint: String, value: Any): android.widget.EditText = android.widget.EditText(this).apply {
        this.hint = Tr.t(hint)
        setText(value.toString())
        inputType = InputType.TYPE_CLASS_TEXT
        textDirection = View.TEXT_DIRECTION_LTR
        setPadding(dp(4), dp(8), dp(4), dp(8))
    }

    private fun showCityDialog() {
        val cities = loadCities()
        val labels = cities.map { if (it.countryName.isBlank()) it.name else "${it.name} — ${it.countryName}" }
        WidgetDialogs.list(
            activity = this,
            title = "انتخاب شهر",
            labels = labels,
            neutralText = "بیشتر (استان‌های ایران)",
            onNeutral = { showProvinceDialog() },
        ) { which ->
            val c = cities[which]
            saveLocation(c.lat, c.lon, if (c.countryCode == "ir") 0.0 else c.altitude, c.name)
        }
    }

    private fun showProvinceDialog() {
        val provinces = loadProvinces()
        WidgetDialogs.list(this, "انتخاب استان", labels = provinces) { which -> showDistrictDialog(provinces[which]) }
    }

    private fun showDistrictDialog(province: String) {
        val districts = loadDistricts(province)
        val labels = districts.map { "${it.name} — ${it.county}" }
        WidgetDialogs.list(this, province, labels = labels) { which ->
            val d = districts[which]
            saveLocation(d.lat, d.lon, 0.0, d.name)
        }
    }

    private fun requestGpsLocation() {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION),
                REQUEST_LOCATION,
            )
            return
        }

        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val handle = WidgetDialogs.show(
            activity = this,
            title = "دریافت مختصات از مکان‌یاب (GPS)",
            message = "در حال دریافت موقعیت…",
            positiveText = "تنظیمات مکان",
            negativeText = "لغو",
            onPositive = {
                startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                true
            },
        )

        var completed = false
        lateinit var listener: android.location.LocationListener
        fun finishWith(location: Location?) {
            if (completed) return
            completed = true
            runCatching { lm.removeUpdates(listener) }
            if (location != null) {
                val (name, _) = reverseGeocode(location.latitude, location.longitude)
                saveLocation(location.latitude, location.longitude, 0.0, name)
                handle.dismiss()
            } else {
                handle.setMessage("موقعیت پیدا نشد. مکان‌یاب را روشن کنید و دوباره تلاش کنید.")
            }
        }

        listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: Location) = finishWith(location)
            override fun onProviderEnabled(provider: String) = Unit
            override fun onProviderDisabled(provider: String) = Unit
        }

        var requested = false
        runCatching {
            if (lm.allProviders.contains(LocationManager.GPS_PROVIDER) && lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener)
                requested = true
            }
            if (lm.allProviders.contains(LocationManager.NETWORK_PROVIDER) && lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0L, 0f, listener)
                requested = true
            }
            val last = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .mapNotNull { provider -> runCatching { lm.getLastKnownLocation(provider) }.getOrNull() }
                .minByOrNull { it.accuracy }
            if (last != null) finishWith(last)
            else if (!requested) finishWith(null)
        }.onFailure { finishWith(null) }

        Handler(Looper.getMainLooper()).postDelayed({ finishWith(null) }, 12_000L)
        handle.dialog.setOnDismissListener { runCatching { lm.removeUpdates(listener) } }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_LOCATION && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) requestGpsLocation()
    }

    private fun saveLocation(lat: Double, lon: Double, altitude: Double, name: String) {
        prefs.edit()
            .putString(Widget4x2.PREF_LATITUDE, lat.toString())
            .putString(Widget4x2.PREF_LONGITUDE, lon.toString())
            .putString(Widget4x2.PREF_ALTITUDE, altitude.toString())
            .putString(Widget4x2.PREF_LOCATION, name)
            .apply()
        Widget4x2.resyncPrayerTimes(applicationContext, widgetId)
        Widget4x2.refresh(this)
        refreshLocationRows()
        updatePreview()
    }

    private fun clearLocationAndRefresh() {
        backupLocation()
        prefs.edit()
            .putString(Widget4x2.PREF_LATITUDE, "")
            .putString(Widget4x2.PREF_LONGITUDE, "")
            .putString(Widget4x2.PREF_ALTITUDE, "")
            .putString(Widget4x2.PREF_LOCATION, "")
            .apply()
        Widget4x2.resyncPrayerTimes(applicationContext, widgetId)
        Widget4x2.refresh(this)
        refreshLocationRows()
        updatePreview()
    }

    private fun hasCoordinates(): Boolean {
        val lat = doubleValue(Widget4x2.PREF_LATITUDE, Double.NaN)
        val lon = doubleValue(Widget4x2.PREF_LONGITUDE, Double.NaN)
        return lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0
    }

    private fun loadCities(): List<CityItem> {
        val root = JSONObject(readAsset("data/cities.json"))
        val result = mutableListOf<CityItem>()
        root.keys().forEach { code ->
            val country = root.optJSONObject(code) ?: return@forEach
            val countryName = localized(country, "fa", "en")
            val cities = country.optJSONObject("cities") ?: return@forEach
            cities.keys().forEach { cityKey ->
                val city = cities.optJSONObject(cityKey) ?: return@forEach
                if (cityKey == "CUSTOM") return@forEach
                result += CityItem(
                    name = localized(city, "fa", "en"),
                    countryName = countryName,
                    countryCode = code,
                    lat = city.optDouble("latitude", 0.0),
                    lon = city.optDouble("longitude", 0.0),
                    altitude = city.optDouble("elevation", 0.0),
                )
            }
        }
        return result.sortedBy { it.name }
    }

    private fun loadProvinces(): List<String> = JSONObject(readAsset("data/districts.json")).keys().asSequence().sorted().toList()

    private fun loadDistricts(province: String): List<DistrictItem> {
        val root = JSONObject(readAsset("data/districts.json"))
        val provinceObj = root.optJSONObject(province) ?: return emptyList()
        val result = mutableListOf<DistrictItem>()
        provinceObj.keys().forEach { county ->
            val countyObj = provinceObj.optJSONObject(county) ?: return@forEach
            countyObj.keys().forEach { townGroup ->
                val towns = countyObj.optJSONObject(townGroup) ?: return@forEach
                towns.keys().forEach { town ->
                    val point = towns.optJSONObject(town) ?: return@forEach
                    result += DistrictItem(town, county, point.optDouble("lat"), point.optDouble("long"))
                }
            }
        }
        return result.sortedBy { it.name }
    }

    private fun readAsset(path: String): String = BufferedReader(InputStreamReader(assets.open(path), Charsets.UTF_8)).use { it.readText() }

    private fun localized(json: JSONObject, preferred: String, fallback: String): String =
        json.optString(preferred).takeIf { it.isNotBlank() } ?: json.optString(fallback)

    private fun contentSummary(): String {
        val selected = contentSet()
        return contentKeys.indices
            .filter { contentKeys[it] in selected }
            .joinToString("، ") { contentLabels[it] }
            .ifBlank { "هیچ‌کدام" }
    }

    private fun locationSummary(): String = prefs.getString(Widget4x2.PREF_LOCATION, "").orEmpty().ifBlank {
        val lat = doubleValue(Widget4x2.PREF_LATITUDE, Double.NaN)
        val lon = doubleValue(Widget4x2.PREF_LONGITUDE, Double.NaN)
        if (lat.isNaN() || lon.isNaN()) "مکان تنظیم نشده" else "${format6(lat)} ، ${format6(lon)}"
    }

    private fun coordinatesSummary(): String {
        val lat = doubleValue(Widget4x2.PREF_LATITUDE, Double.NaN)
        val lon = doubleValue(Widget4x2.PREF_LONGITUDE, Double.NaN)
        val alt = doubleValue(Widget4x2.PREF_ALTITUDE, 0.0)
        return if (lat.isNaN() || lon.isNaN()) "عرض، طول و ارتفاع جغرافیایی را وارد کنید" else "${format6(lat)} ، ${format6(lon)}\nارتفاع: ${format1(alt)} متر"
    }

    private fun contentSet(): Set<String> {
        val raw = prefs.all[Widget4x2.PREF_WHAT_TO_SHOW_WIDGETS] ?: return contentKeys.toSet()
        val items = when (raw) {
            is Set<*> -> raw.mapNotNull { it?.toString()?.trim() }.toSet()
            is String -> raw.split(',').map(String::trim).filter(String::isNotBlank).toSet()
            else -> return contentKeys.toSet()
        }
        // A selection saved before "holidays" existed has no marker: holidays were always shown then.
        return if (Widget4x2.CONTENT_MARKER in items) items else items + Widget4x2.CONTENT_HOLIDAYS
    }



    private fun persistScale(value: Float) {
        prefs.edit().putFloat(Widget4x2.PREF_WIDGET_TEXT_SCALE, value).apply()
    }

    private fun currentScale(): Float = .65f + scaleSeek.progress / 100f

    private fun updateScaleText() {
        scaleLabel.text = Tr.t("ضریب اندازه: ${String.format(Locale.US, "%.2f×", currentScale())}")
    }

    private fun updatePreview() {
        if (isSunViewConfiguration) {
            updateSunPreview()
            return
        }
        runCatching {
            previewHost.removeAllViews()
            // Use the application context just like a launcher does. The configuration activity uses
            // a Wallpaper theme, so using the Activity context here can leak configuration-theme
            // colors/resources into the preview and make it differ from the real widget.
            val previewContext = applicationContext
            val rendered = Widget4x2.createRemoteViews(previewContext, widgetId).apply(previewContext, previewHost)

            val options = AppWidgetManager.getInstance(this).getAppWidgetOptions(widgetId)
            val landscape = resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
            val widthKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            val heightKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            val widthAltKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
            val heightAltKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            val widgetWidthDp = (options.getInt(widthKey, 0).takeIf { it > 0 }
                ?: options.getInt(widthAltKey, 0).takeIf { it > 0 } ?: 250).coerceAtLeast(100)
            val widgetHeightDp = (options.getInt(heightKey, 0).takeIf { it > 0 }
                ?: options.getInt(heightAltKey, 0).takeIf { it > 0 } ?: 110).coerceAtLeast(80)
            val density = resources.displayMetrics.density
            val targetW = (widgetWidthDp * density).roundToInt().coerceAtLeast(1)
            val targetH = (widgetHeightDp * density).roundToInt().coerceAtLeast(1)
            val availableW = previewHost.width.coerceAtLeast(1)
            val availableH = previewHost.height.coerceAtLeast(1)
            val scale = minOf(availableW.toFloat() / targetW, availableH.toFloat() / targetH, 1f)
            rendered.layoutParams = FrameLayout.LayoutParams(targetW, targetH, Gravity.CENTER)
            rendered.pivotX = targetW / 2f
            rendered.pivotY = targetH / 2f
            rendered.scaleX = scale
            rendered.scaleY = scale
            previewHost.addView(rendered)
        }.onFailure { throwable ->
            previewHost.removeAllViews()
            previewHost.addView(TextView(this).apply {
                text = Tr.t("پیش‌نمایش ویجت")
                gravity = Gravity.CENTER
                textSize = 14f
                setTextColor(primaryColor())
            }, FrameLayout.LayoutParams(-1, -1))
            android.util.Log.e("Widget4x2Configure", "Real RemoteViews preview rendering failed", throwable)
        }
    }

    private fun updateSunPreview() {
        runCatching {
            previewHost.removeAllViews()
            val frame = FrameLayout(this).apply {
                setBackgroundColor(Color.TRANSPARENT)
                layoutDirection = View.LAYOUT_DIRECTION_LTR
            }
            val image = android.widget.ImageView(this).apply {
                scaleType = android.widget.ImageView.ScaleType.FIT_XY
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            val width = (resources.displayMetrics.widthPixels * .88f).roundToInt().coerceIn(dp(220), dp(520))
            val height = dp(108)
            val (bitmap, description) = AstronomyWidgetSupport.drawSunPath(
                this,
                prefs,
                width,
                height,
                System.currentTimeMillis(),
            )
            image.setImageBitmap(bitmap)
            frame.addView(image, FrameLayout.LayoutParams(-1, dp(112)))
            if (description != null) {
                frame.addView(TextView(this).apply {
                    text = Tr.t(description)
                    textSize = 12f
                    gravity = Gravity.CENTER
                    setTextColor(primaryColor())
                }, FrameLayout.LayoutParams(-1, -1))
            }
            previewHost.addView(frame, FrameLayout.LayoutParams(-1, -1))
        }.onFailure { throwable ->
            previewHost.removeAllViews()
            previewHost.addView(TextView(this).apply {
                text = Tr.t("پیش‌نمایش مسیر خورشید")
                gravity = Gravity.CENTER
                textSize = 14f
                setTextColor(primaryColor())
            }, FrameLayout.LayoutParams(-1, -1))
            android.util.Log.e("Widget4x2Configure", "Sun preview rendering failed", throwable)
        }
    }

    private fun zoneForPreview(): TimeZone =
        if (bool(Widget4x2.PREF_IRAN_TIME, false)) TimeZone.getTimeZone("Asia/Tehran") else TimeZone.getDefault()

    private fun persistBool(nativeKey: String, value: Boolean) {
        prefs.edit().putBoolean(nativeKey, value).apply()
    }

    private fun bool(key: String, fallback: Boolean): Boolean = Widget4x2.readBoolean(prefs, key, fallback)

    private fun floatValue(key: String, fallback: Float): Float = Widget4x2.readFloat(prefs, key, fallback)

    private fun doubleValue(key: String, fallback: Double): Double = Widget4x2.readDouble(prefs, key) ?: fallback

    private fun normalizeTextColor(raw: String): String? = runCatching {
        val s = if (raw.startsWith("#")) raw else "#$raw"
        val color = Color.parseColor(s)
        String.format(Locale.US, "#%06X", color and 0xFFFFFF)
    }.getOrNull()

    private fun normalizeBackgroundColor(raw: String): String? = runCatching {
        val s = if (raw.startsWith("#")) raw else "#$raw"
        val color = Color.parseColor(s)
        String.format(Locale.US, "#%08X", color.toLong() and 0xFFFFFFFFL)
    }.getOrNull()

    private fun primaryColor(): Int = resolveColor(android.R.attr.textColorPrimary, if (isNightMode()) Color.WHITE else Color.BLACK)
    private fun secondaryColor(): Int = resolveColor(android.R.attr.textColorSecondary, if (isNightMode()) 0xFFB8B8B8.toInt() else 0xFF5F6368.toInt())
    private fun dividerColor(): Int = (secondaryColor() and 0x00FFFFFF) or 0x40000000

    /** Theme attributes can point at color-state lists or other resource types; never assume every reference is a color. */
    private fun resolveColor(attr: Int, fallback: Int = Color.WHITE): Int = runCatching {
        val tv = android.util.TypedValue()
        if (!theme.resolveAttribute(attr, tv, true)) return@runCatching fallback
        if (tv.type in android.util.TypedValue.TYPE_FIRST_COLOR_INT..android.util.TypedValue.TYPE_LAST_COLOR_INT) return@runCatching tv.data
        val resId = tv.resourceId
        if (resId != 0) {
            runCatching { ContextCompat.getColorStateList(this, resId)?.defaultColor }.getOrNull()?.let { return@runCatching it }
            runCatching {
                if (Build.VERSION.SDK_INT >= 23) resources.getColor(resId, theme)
                else @Suppress("DEPRECATION") resources.getColor(resId)
            }.getOrNull()?.let { return@runCatching it }
        }
        fallback
    }.getOrDefault(fallback)

    private fun isNightMode(): Boolean =
        (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

    private fun lp(top: Int = 0): LinearLayout.LayoutParams = LinearLayout.LayoutParams(-1, -2).apply {
        if (top != 0) setMargins(0, dp(top), 0, 0)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + .5f).toInt()
    private fun format6(v: Double): String = String.format(Locale.US, "%.6f", v)
    private fun format1(v: Double): String = String.format(Locale.US, "%.1f", v)
    private fun persianDigits(value: Int): String = Tr.digits(value.toString())
    private fun persianDigits(value: String): String = Tr.digits(value)

    data class CityItem(val name: String, val countryName: String, val countryCode: String, val lat: Double, val lon: Double, val altitude: Double)
    data class DistrictItem(val name: String, val county: String, val lat: Double, val lon: Double)

}
