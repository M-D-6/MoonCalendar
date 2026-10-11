package com.md6.mooncalendar

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Paint
import android.content.res.ColorStateList
import android.graphics.drawable.GradientDrawable
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.Locale
import kotlin.math.roundToInt

/** Native reconfiguration UI matching the original SunView widget settings. */
class WidgetSunViewConfigureActivity : Activity() {
    private val prefs get() = Widget4x2.widgetPrefs(this, widgetId)
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var dynamicSwitch: Switch
    private lateinit var previewHost: FrameLayout
    private lateinit var previewBackground: ImageView
    private lateinit var previewImage: ImageView
    private var previewTicket = 0
    private val previewExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val requestLocationCode = 7412
    private var textColorDot: WidgetColorPicker.ColorDot? = null
    private var bgColorDot: WidgetColorPicker.ColorDot? = null
    private var textColorRowRef: View? = null
    private var bgColorRowRef: View? = null

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
            WidgetSettingsUi.styleRoot(this@WidgetSunViewConfigureActivity, this)
        }

        previewHost = FrameLayout(this).apply {
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            background = WidgetSettingsUi.roundedBackground(this@WidgetSunViewConfigureActivity, Color.TRANSPARENT, 24f, stroke = false)
            clipToOutline = true
            setPadding(WidgetSettingsUi.dp(this@WidgetSunViewConfigureActivity, 4), WidgetSettingsUi.dp(this@WidgetSunViewConfigureActivity, 4), WidgetSettingsUi.dp(this@WidgetSunViewConfigureActivity, 4), WidgetSettingsUi.dp(this@WidgetSunViewConfigureActivity, 4))
        }
        previewBackground = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        previewImage = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            contentDescription = Tr.t("پیش‌نمایش مسیر طلوع و غروب خورشید")
            setBackgroundColor(Color.TRANSPARENT)
        }
        previewHost.addView(previewBackground, FrameLayout.LayoutParams(-1, -1))
        previewHost.addView(previewImage, FrameLayout.LayoutParams(-1, -1))
        root.addView(previewHost, LinearLayout.LayoutParams(-1, dp(205)).apply {
            leftMargin = dp(2)
            rightMargin = dp(2)
        })

        val settings = WidgetSettingsUi.settingsSurface(this, root)
        WidgetSettingsUi.actionButtons(this, settings, {
            Widget4x2.refresh(this)
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
            finish()
        }, {
            setResult(RESULT_CANCELED)
            finish()
        })
        val (_, content) = WidgetSettingsUi.settingsScroll(this, settings)

        WidgetSettingsUi.sectionHeader(this, content, "نمایش")
        dynamicSwitch = WidgetSettingsUi.switchRow(
            this, content,
            "پیروی از رنگ‌بندی دستگاه در ویجت‌ها",
            "در اندروید ۱۲ و بالاتر رنگ‌های پویا از سیستم گرفته می‌شوند",
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                AstronomyWidgetSupport.bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true),
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S,
        ) { checked ->
            val effective = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && checked
            prefs.edit().putBoolean(Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, effective).apply()
            updateSunColorRows(effective)
            Widget4x2.refresh(applicationContext)
            updatePreview()
        }

        textColorDot = WidgetColorPicker.ColorDot(
            this, Widget4x2.readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_TEXT_COLOR, Color.WHITE),
        )
        bgColorDot = WidgetColorPicker.ColorDot(
            this, Widget4x2.readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_BACKGROUND_COLOR, Color.TRANSPARENT),
        )
        val textColorRow = WidgetSettingsUi.settingRow(
            this, content, "رنگ نوشته‌های ویجت", "رنگ متن و نوشته‌های روی مسیر خورشید",
            textColorDot,
            onClick = { showColorDialog(false) },
        )
        val bgColorRow = WidgetSettingsUi.settingRow(
            this, content, "رنگ پس‌زمینهٔ ویجت", "رنگ زمینه وقتی رنگ‌بندی دستگاه خاموش است",
            bgColorDot,
            onClick = { showColorDialog(true) },
        )
        val transparencyRow = WidgetSettingsUi.settingRow(
            this, content, "شفافیت پس‌زمینهٔ ویجت", transparencySummary(),
            onClick = { showTransparencyDialog() },
        )
        textColorRowRef = textColorRow
        bgColorRowRef = bgColorRow

        fun updateRows(checked: Boolean) {
            textColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            bgColorRow.visibility = if (checked) View.GONE else View.VISIBLE
            updateSunColorRows(checked)
            transparencyRow.findViewById<TextView>(android.R.id.text1)?.text = Tr.t("شفافیت پس‌زمینهٔ ویجت")
            updateTransparencySummary(transparencyRow)
        }
        updateRows(dynamicSwitch.isChecked)

        WidgetSettingsUi.sectionHeader(this, content, "موقعیت")
        WidgetSettingsUi.settingRow(
            this, content, "دریافت مختصات از مکان‌یاب (GPS)", "موقعیت را از GPS دریافت و برای ویجت ذخیره می‌کند",
            onClick = { requestGpsLocation() },
        )
        WidgetSettingsUi.settingRow(
            this, content, "انتخاب شهر", locationSummary(),
            onClick = { showCityDialog() },
        )
        WidgetSettingsUi.settingRow(
            this, content, "مختصات جغرافیایی", coordinatesSummary(),
            onClick = { showCoordinatesDialog() },
        )
        // The sun path always needs location data, so unlike the prayer-times widget it has no
        // "hide prayer times" action.

        // Local listener needs the current rows; replace the initial no-op visibility state with the
        // actual function after all views exist.
        updateRows(dynamicSwitch.isChecked)

        setContentView(root)
        updatePreview()
    }

    private fun updateSunColorRows(checked: Boolean) {
        textColorRowRef?.visibility = if (checked) View.GONE else View.VISIBLE
        bgColorRowRef?.visibility = if (checked) View.GONE else View.VISIBLE
    }

    private fun transparencySummary(): String =
        "${persianDigits((Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f).coerceIn(0f, 1f) * 100f).roundToInt())}٪"

    private fun updateTransparencySummary(row: View) {
        row.findViewById<TextView>(android.R.id.text1)?.let {
            // keep the title itself stable; summary is the second text child
            val container = row as? LinearLayout ?: return@let
            (container.getChildAt(0) as? LinearLayout)?.let { texts ->
                (texts.getChildAt(1) as? TextView)?.text = Tr.t(transparencySummary())
            }
        }
    }

    private fun updatePreview() {
        val ticket = ++previewTicket
        val width = WidgetSettingsUi.dp(this, 320).coerceAtLeast(200)
        val height = WidgetSettingsUi.dp(this, 150).coerceAtLeast(100)
        val app = applicationContext
        previewExecutor.execute {
            if (ticket != previewTicket) return@execute
            val dynamic = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                AstronomyWidgetSupport.bool(prefs, Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
            val transparency = Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f).coerceIn(0f, 1f)
            val backgroundBitmap = if (dynamic) null else {
                val raw = AstronomyWidgetSupport.readColor(prefs, Widget4x2.PREF_SELECTED_WIDGET_BACKGROUND_COLOR, Color.TRANSPARENT)
                val effective = Color.argb(
                    (Color.alpha(raw) * (1f - transparency)).roundToInt().coerceIn(0, 255),
                    Color.red(raw), Color.green(raw), Color.blue(raw),
                )
                AstronomyWidgetSupport.roundedBackground(app, width, height, effective)
            }
            val (bitmap, description) = runCatching {
                AstronomyWidgetSupport.drawSunPath(app, prefs, width, height, System.currentTimeMillis())
            }.getOrElse {
                android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888) to null
            }
            runOnUiThread {
                if (isFinishing || ticket != previewTicket) return@runOnUiThread
                if (dynamic) {
                    previewBackground.setImageResource(R.drawable.widget_background)
                    previewBackground.alpha = 1f - transparency
                } else {
                    previewBackground.setImageBitmap(backgroundBitmap)
                    previewBackground.alpha = 1f
                }
                previewImage.setImageBitmap(bitmap)
                previewImage.contentDescription = Tr.t(description ?: "مسیر طلوع و غروب خورشید")
            }
        }
    }

    private fun hasCoordinates(): Boolean {
        val lat = Widget4x2.readDouble(prefs, Widget4x2.PREF_LATITUDE) ?: Double.NaN
        val lon = Widget4x2.readDouble(prefs, Widget4x2.PREF_LONGITUDE) ?: Double.NaN
        return lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0
    }

    private fun clearLocationAndRefresh() {
        prefs.edit().remove(Widget4x2.PREF_LATITUDE).remove(Widget4x2.PREF_LONGITUDE).remove(Widget4x2.PREF_ALTITUDE).remove(Widget4x2.PREF_LOCATION).apply()
        Widget4x2.refresh(this)
        updatePreview()
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
                result += CityItem(localized(city, "fa", "en"), countryName, code, city.optDouble("latitude", 0.0), city.optDouble("longitude", 0.0), city.optDouble("elevation", 0.0))
            }
        }
        return result.sortedBy { it.name }
    }

    private fun loadProvinces(): List<String> = JSONObject(readAsset("data/districts.json")).keys().asSequence().sorted().toList()

    private fun loadDistricts(province: String): List<DistrictItem> {
        val provinceObj = JSONObject(readAsset("data/districts.json")).optJSONObject(province) ?: return emptyList()
        val result = mutableListOf<DistrictItem>()
        provinceObj.keys().forEach { county ->
            val countyObj = provinceObj.optJSONObject(county) ?: return@forEach
            countyObj.keys().forEach { group ->
                val towns = countyObj.optJSONObject(group) ?: return@forEach
                towns.keys().forEach { town ->
                    val point = towns.optJSONObject(town) ?: return@forEach
                    result += DistrictItem(town, county, point.optDouble("lat"), point.optDouble("long"))
                }
            }
        }
        return result.sortedBy { it.name }
    }

    private fun readAsset(path: String): String = BufferedReader(InputStreamReader(assets.open(path), Charsets.UTF_8)).use { it.readText() }
    private fun localized(json: JSONObject, preferred: String, fallback: String): String = json.optString(preferred).takeIf { it.isNotBlank() } ?: json.optString(fallback)

    private data class CityItem(val name: String, val countryName: String, val countryCode: String, val lat: Double, val lon: Double, val altitude: Double)
    private data class DistrictItem(val name: String, val county: String, val lat: Double, val lon: Double)

    private fun requestGpsLocation() {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), requestLocationCode)
            return
        }
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var listener: android.location.LocationListener? = null
        var done = false
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
        fun finishWith(location: Location?) {
            if (done) return
            done = true
            listener?.let { runCatching { lm.removeUpdates(it) } }
            if (location != null) {
                val city = if (android.location.Geocoder.isPresent()) {
                    runCatching {
                        @Suppress("DEPRECATION")
                        android.location.Geocoder(this, Locale("fa")).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
                    }.getOrNull()?.let { it.locality ?: it.subAdminArea ?: it.adminArea }.orEmpty()
                } else {
                    ""
                }
                saveLocation(location.latitude, location.longitude, 0.0, city.ifBlank { "GPS" })
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
        runCatching {
            var requested = false
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener!!)
                requested = true
            }
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 0L, 0f, listener!!)
                requested = true
            }
            val last = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
                .minByOrNull { it.accuracy }
            if (last != null) finishWith(last) else if (!requested) finishWith(null)
        }.onFailure { finishWith(null) }
        Handler(Looper.getMainLooper()).postDelayed({ finishWith(null) }, 12_000L)
        handle.dialog.setOnDismissListener { listener?.let { runCatching { lm.removeUpdates(it) } } }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestLocationCode && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) requestGpsLocation()
    }

    private fun showTransparencyDialog() {
        val initial = Widget4x2.readFloat(prefs, Widget4x2.PREF_WIDGET_TRANSPARENCY, 0f).coerceIn(0f, 1f)
        WidgetDialogs.slider(
            activity = this,
            title = "شفافیت پس‌زمینهٔ ویجت",
            subtitle = "فقط برای همین ویجت اعمال می‌شود",
            initialPercent = (initial * 100f).roundToInt(),
        ) { percent ->
            val value = percent / 100f
            prefs.edit().putFloat(Widget4x2.PREF_WIDGET_TRANSPARENCY, value).apply()
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
                WidgetDialogs.Field("عرض جغرافیایی", (Widget4x2.readDouble(prefs, Widget4x2.PREF_LATITUDE) ?: 0.0).toString()),
                WidgetDialogs.Field("طول جغرافیایی", (Widget4x2.readDouble(prefs, Widget4x2.PREF_LONGITUDE) ?: 0.0).toString()),
                WidgetDialogs.Field("ارتفاع (متر، اختیاری)", (Widget4x2.readDouble(prefs, Widget4x2.PREF_ALTITUDE) ?: 0.0).toString()),
            ),
        ) { values ->
            val la = parseNumber(values[0])
            val lo = parseNumber(values[1])
            val al = if (values[2].isBlank()) 0.0 else parseNumber(values[2])
            if (la == null || lo == null || al == null || la !in -90.0..90.0 || lo !in -180.0..180.0 || al !in -418.0..8849.0) {
                "مختصات معتبر نیست."
            } else {
                saveLocation(la, lo, al, "")
                null
            }
        }
    }

    private fun saveLocation(lat: Double, lon: Double, altitude: Double, name: String) {
        prefs.edit().putString(Widget4x2.PREF_LATITUDE, lat.toString()).putString(Widget4x2.PREF_LONGITUDE, lon.toString()).putString(Widget4x2.PREF_ALTITUDE, altitude.toString()).putString(Widget4x2.PREF_LOCATION, name).apply()
        Widget4x2.resyncPrayerTimes(applicationContext, widgetId)
        Widget4x2.refresh(this)
        updatePreview()
    }

    private fun coordinatesSummary(): String {
        val lat = Widget4x2.readDouble(prefs, Widget4x2.PREF_LATITUDE) ?: Double.NaN
        val lon = Widget4x2.readDouble(prefs, Widget4x2.PREF_LONGITUDE) ?: Double.NaN
        return if (lat.isFinite() && lon.isFinite()) "${format(lat)}, ${format(lon)}" else "ثبت نشده"
    }
    private fun locationSummary(): String = prefs.getString(Widget4x2.PREF_LOCATION, "")?.takeIf { it.isNotBlank() } ?: coordinatesSummary()


    private fun editField(hint: String, value: Any) = android.widget.EditText(this).apply { this.hint = Tr.t(hint); setText(value.toString()); inputType = android.text.InputType.TYPE_CLASS_TEXT; textDirection = View.TEXT_DIRECTION_LTR; setPadding(dp(4), dp(8), dp(4), dp(8)) }
    private fun parseNumber(raw: String): Double? = raw.trim().replace('۰','0').replace('۱','1').replace('۲','2').replace('۳','3').replace('۴','4').replace('۵','5').replace('۶','6').replace('۷','7').replace('۸','8').replace('۹','9').replace('٫','.').toDoubleOrNull()
    private fun format(value: Double): String = String.format(Locale.US, "%.5f", value).trimEnd('0').trimEnd('.')
    private fun persianDigits(value: Int): String = Tr.digits(value.toString())
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()
    private fun lp(top: Int = 0): LinearLayout.LayoutParams = LinearLayout.LayoutParams(-1, -2).apply { if (top != 0) topMargin = dp(top) }
    private fun sectionHeader(parent: LinearLayout, title: String) { WidgetSettingsUi.sectionHeader(this, parent, title) }
    private fun clickableRow(parent: LinearLayout, title: String, summary: String, onClick: () -> Unit) { WidgetSettingsUi.settingRow(this, parent, title, summary, onClick = onClick) }
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
}
