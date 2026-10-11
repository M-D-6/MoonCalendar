package com.md6.mooncalendar

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.math.roundToInt
import java.util.concurrent.Executors

class Widget4x2 : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Tr.init(context)
        val pending = goAsync()
        EXECUTOR.execute {
            try { ids.forEach { updateOne(context, manager, it) } }
            finally {
                refreshSecondTicker(context)
                pending.finish()
            }
        }
    }

    override fun onEnabled(context: Context) {
        updateAll(context)
        super.onEnabled(context)
    }

    override fun onDisabled(context: Context) {
        refreshSecondTicker(context)
        super.onDisabled(context)
    }

    override fun onRestored(context: Context, oldWidgetIds: IntArray, newWidgetIds: IntArray) {
        super.onRestored(context, oldWidgetIds, newWidgetIds)
        for (i in minOf(oldWidgetIds.size, newWidgetIds.size) downTo 1) {
            copyWidgetSettings(context, oldWidgetIds[i - 1], newWidgetIds[i - 1])
        }
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // Every configurable option belongs to its widget instance. Deleting one widget must remove
        // only that instance's overrides and must never change another widget.
        appWidgetIds.forEach { id ->
            widgetPrefs(context, id).edit().clear().apply()
        }
        refreshSecondTicker(context)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        EXECUTOR.execute {
            updateOne(context, appWidgetManager, appWidgetId)
            refreshSecondTicker(context)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Tr.init(context)
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_SECOND_TICK -> {
                tickSeconds(context)
            }
            ACTION_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                val pending = goAsync()
                EXECUTOR.execute {
                    try { updateAllNow(context) }
                    finally {
                        refreshSecondTicker(context)
                        pending.finish()
                    }
                }
            }
        }
    }

    private fun updateOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
        try {
            manager.updateAppWidget(widgetId, createRemoteViews(context, widgetId))
        } catch (t: Throwable) {
            Log.e(TAG, "4x2 RemoteViews update failed for widgetId=$widgetId", t)
            runCatching { manager.updateAppWidget(widgetId, createSafeRemoteViews(context, widgetId)) }
                .onFailure { Log.e(TAG, "4x2 safe fallback failed for widgetId=$widgetId", it) }
        }
    }

    companion object {
        const val PREFS = "mooncalendar_widget"
        const val ACTION_REFRESH = "com.md6.Mooncalendar.WIDGET_4X2_REFRESH"

        const val PREF_WIDGET_TEXT_SCALE = "WidgetTextScale"
        const val PREF_SELECTED_WIDGET_TEXT_COLOR = "SelectedWidgetTextColor"
        const val PREF_SELECTED_WIDGET_BACKGROUND_COLOR = "SelectedWidgetBackgroundColor"
        const val PREF_WIDGET_TRANSPARENCY = "WidgetTransparency"
        const val PREF_WIDGETS_PREFER_SYSTEM_COLORS = "PrefersSystemColorInWidgets"
        const val PREF_WIDGET_CLOCK = "WidgetClock"
        const val PREF_WIDGET_IN_24 = "WidgetIn24"
        const val PREF_WIDGET_SHOW_SECONDS = "WidgetShowSeconds"
        const val PREF_WIDGET_EDGE_ALIGN = "WidgetEdgeAlign"
        const val PREF_IRAN_TIME = "IranTime"
        const val PREF_LOCAL_NUMERAL = "PersianDigits"
        const val PREF_NUMERICAL_DATE = "numericalDatePreferred"
        const val PREF_CENTER_ALIGN_WIDGETS = "CenterAlignWidgets"
        const val PREF_WHAT_TO_SHOW_WIDGETS = "what_to_show"
        /** Which prayer times the widget shows (comma separated keys from [PRAYER_TIME_KEYS]). */
        const val PREF_WIDGET_PRAYER_TIMES = "WidgetPrayerTimes"
        /** Every time the widget can show, in day order (imsak included). */
        val PRAYER_TIME_KEYS = arrayOf("imsak", "fajr", "sunrise", "dhuhr", "asr", "sunset", "maghrib", "isha", "midnight")
        val PRAYER_TIME_LABELS = arrayOf("امساک", "اذان صبح", "طلوع", "اذان ظهر", "اذان عصر", "غروب", "اذان مغرب", "اذان عشاء", "نیمه‌شب")
        private val PRAYER_TIME_SHORT_LABELS = arrayOf("امساک", "صبح", "طلوع", "ظهر", "عصر", "غروب", "مغرب", "عشاء", "نیمه‌شب")
        /** Shown until the user picks their own: imsak, asr and isha are off by default. */
        val DEFAULT_PRAYER_KEYS: Set<String> = setOf("fajr", "sunrise", "dhuhr", "sunset", "maghrib", "midnight")

        /** Content-dialog key for official holidays; [CONTENT_MARKER] tells "new format saved" from the old one. */
        const val CONTENT_HOLIDAYS = "holidays"
        const val CONTENT_MARKER = "content_v2"

        @JvmStatic
        fun widgetPrefs(context: Context, widgetId: Int): android.content.SharedPreferences =
            ScopedWidgetPreferences(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE), widgetId)

        private fun scopedKey(key: String, widgetId: Int): String = when (key) {
            PREF_WIDGET_TEXT_SCALE -> "${PREF_WIDGET_TEXT_SCALE}${widgetId}"
            else -> "${key}@${widgetId}"
        }

        @JvmStatic
        fun copyWidgetSettings(context: Context, oldWidgetId: Int, newWidgetId: Int) {
            if (oldWidgetId == newWidgetId) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val all = prefs.all
            val edit = prefs.edit()
            for (key in PER_WIDGET_KEYS) {
                val oldKey = scopedKey(key, oldWidgetId)
                val newKey = scopedKey(key, newWidgetId)
                if (!all.containsKey(oldKey)) continue
                when (val value = all[oldKey]) {
                    is String -> edit.putString(newKey, value)
                    is Boolean -> edit.putBoolean(newKey, value)
                    is Int -> edit.putInt(newKey, value)
                    is Long -> edit.putLong(newKey, value)
                    is Float -> edit.putFloat(newKey, value)
                    is Double -> edit.putFloat(newKey, value.toFloat())
                    is Set<*> -> edit.putStringSet(newKey, value.map { it.toString() }.toSet())
                }
            }
            edit.apply()
        }

        @JvmStatic
        fun clearWidgetSettings(context: Context, widgetId: Int) {
            widgetPrefs(context, widgetId).edit().clear().apply()
        }

        @JvmStatic
        fun scopedKeyForWidget(key: String, widgetId: Int): String = scopedKey(key, widgetId)

        @JvmStatic
        fun selectedPrayerKeys(prefs: android.content.SharedPreferences): Set<String> {
            val raw = when (val v = prefs.all[PREF_WIDGET_PRAYER_TIMES]) {
                is Set<*> -> v.mapNotNull { it?.toString()?.trim() }
                is String -> v.split(',').map { it.trim() }
                else -> emptyList()
            }.filter { it in PRAYER_TIME_KEYS }.toSet()
            // Nothing valid stored (default, or an empty selection) => the default selection.
            return if (raw.isEmpty()) DEFAULT_PRAYER_KEYS else raw
        }
        const val PREF_PRAY_TIME_METHOD = "SelectedPrayTimeMethod"
        const val PREF_HIGH_LATITUDES_METHOD = "SelectedHighLatitudesMethod"
        const val PREF_MIDNIGHT_METHOD = "SelectedMidnightMethod"
        const val PREF_ASR_HANAFI = "AsrHanafiJuristic"
        const val PREF_LATITUDE = "Latitude"
        const val PREF_LONGITUDE = "Longitude"
        const val PREF_ALTITUDE = "Altitude"
        const val PREF_HIJRI_OFFSET = "islamic_offset"
        const val PREF_LOCATION = "Location"

        /** Settings that are overridden per Android widget instance. Synchronized date/event data remains global. */
        val PER_WIDGET_KEYS: Set<String> = setOf(
            PREF_WIDGET_TEXT_SCALE,
            PREF_SELECTED_WIDGET_TEXT_COLOR,
            PREF_SELECTED_WIDGET_BACKGROUND_COLOR,
            PREF_WIDGET_TRANSPARENCY,
            PREF_WIDGETS_PREFER_SYSTEM_COLORS,
            PREF_WIDGET_CLOCK,
            PREF_WIDGET_IN_24,
            PREF_WIDGET_SHOW_SECONDS,
            PREF_WIDGET_EDGE_ALIGN,
            PREF_IRAN_TIME,
            PREF_LOCAL_NUMERAL,
            PREF_NUMERICAL_DATE,
            PREF_CENTER_ALIGN_WIDGETS,
            PREF_WHAT_TO_SHOW_WIDGETS,
            PREF_WIDGET_PRAYER_TIMES,
            PREF_PRAY_TIME_METHOD,
            PREF_HIGH_LATITUDES_METHOD,
            PREF_MIDNIGHT_METHOD,
            PREF_ASR_HANAFI,
            PREF_LATITUDE,
            PREF_LONGITUDE,
            PREF_ALTITUDE,
            PREF_HIJRI_OFFSET,
            PREF_LOCATION,
        )

        private const val KEY_DATE = "persian_date"
        private const val KEY_DATE_YEAR = "persian_year"
        private const val KEY_DATE_MONTH = "persian_month"
        private const val KEY_DATE_DAY = "persian_day"
        private const val KEY_GREGORIAN = "gregorian_date"
        private const val KEY_ISLAMIC = "islamic_date"
        private const val KEY_CALENDARS_ORDER = "calendars_order"
        private const val KEY_WEEKDAY = "weekday"
        private const val KEY_HOLIDAY = "holiday"
        private const val KEY_EVENT = "event"
        private const val KEY_IMSAK = "prayer_imsak"
        private const val KEY_SUNRISE = "prayer_sunrise"
        private const val KEY_FAJR = "prayer_fajr"
        private const val KEY_DHUHR = "prayer_dhuhr"
        private const val KEY_ASR = "prayer_asr"
        private const val KEY_SUNSET = "prayer_sunset"
        private const val KEY_MAGHRIB = "prayer_maghrib"
        private const val KEY_ISHA = "prayer_isha"
        private const val KEY_MIDNIGHT = "prayer_midnight"
        private const val KEY_LOCATION = "location"
        private const val KEY_UPDATED = "updated"
        private const val KEY_SYNC_DATE = "widget_sync_date"

        private const val OTHER_CALENDARS_KEY = "other_calendars"
        private const val NON_HOLIDAYS_EVENTS_KEY = "non_holiday_events"
        private const val OWGHAT_KEY = "owghat"
        private const val OWGHAT_LOCATION_KEY = "owghat_location"

        private const val DEFAULT_TEXT_COLOR = Color.WHITE
        private const val DEFAULT_BACKGROUND_COLOR = Color.TRANSPARENT
        private const val DEFAULT_WIDGET_TEXT_SCALE = 1f
        private const val DEFAULT_WIDGET_TRANSPARENCY = 0f
        private const val TAG = "MoonCalendarWidget4x2"
        private const val SECOND_TICK_REQUEST_CODE = 49061
        const val ACTION_SECOND_TICK = "com.md6.Mooncalendar.WIDGET_4X2_SECOND_TICK"

        private val PERSIAN_MONTHS = arrayOf(
            "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
            "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند",
        )
        private val GREGORIAN_MONTHS = arrayOf(
            "ژانویه", "فوریه", "مارس", "آوریل", "مه", "ژوئن",
            "ژوئیه", "اوت", "سپتامبر", "اکتبر", "نوامبر", "دسامبر",
        )
        private val ISLAMIC_MONTHS = arrayOf(
            "محرم", "صفر", "ربیع‌الاول", "ربیع‌الثانی", "جمادی‌الاول", "جمادی‌الثانی",
            "رجب", "شعبان", "رمضان", "شوال", "ذوالقعده", "ذوالحجه",
        )
        private val WEEKDAYS = arrayOf(
            "شنبه", "یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه",
        )

        private val EXECUTOR = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MoonCalendarWidget4x2").apply { isDaemon = true }
        }

        fun updateAll(context: Context) {
            EXECUTOR.execute { updateAllNow(context) }
        }

        private fun updateAllNow(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, Widget4x2::class.java)
            manager.getAppWidgetIds(component).forEach { updateOneStatic(context, manager, it) }
            WidgetMoon.updateAll(context)
            WidgetSunView.updateAll(context)
            WidgetMap.updateAll(context)
            refreshSecondTicker(context)
        }

        fun refresh(context: Context) = updateAll(context)

        fun createRemoteViews(context: Context, widgetId: Int): RemoteViews {
            val prefs = widgetPrefs(context, widgetId)
            val clockEnabled = bool(prefs, PREF_WIDGET_CLOCK, true)
            val layout = if (clockEnabled) R.layout.widget4x2_clock else R.layout.widget4x2
            val views = RemoteViews(context.packageName, layout)

            val scale = readFloat(prefs, PREF_WIDGET_TEXT_SCALE, DEFAULT_WIDGET_TEXT_SCALE)
                .coerceIn(0.65f, 3f)
            val widgetHeightDp = widgetHeightDp(context, widgetId)
            val heightLevel = widgetHeightLevel(widgetHeightDp)
            val compact = heightLevel <= 1
            val medium = heightLevel == 2
            val large = heightLevel == 3
            val clockCap = when { compact -> 36f; medium -> 42f; large -> 46f; else -> 48f }
            val dateCap = when { compact -> 10.5f; medium -> 12f; large -> 13f; else -> 13f }
            val prayerCap = when { compact -> 10.5f; medium -> 12f; large -> 13f; else -> 14f }
            val eventCap = when { compact -> 10f; medium -> 11f; large -> 12f; else -> 13f }
            // Android 12+ is the Persian Calendar dynamic-color path. On older Android versions
            // the Persian Calendar app falls back to the user-selected foreground/background colors.
            val dynamicColors = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                bool(prefs, PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)
            val transparency = readFloat(prefs, PREF_WIDGET_TRANSPARENCY, DEFAULT_WIDGET_TRANSPARENCY)
                .coerceIn(0f, 1f)
            val localDigits = bool(prefs, PREF_LOCAL_NUMERAL, true)
            val showSeconds = bool(prefs, PREF_WIDGET_SHOW_SECONDS, false)
            val edgeAlign = bool(prefs, PREF_WIDGET_EDGE_ALIGN, false)
            val baseClockSp = minOf(48f * scale, clockCap)
            val clockSp = if (clockEnabled) {
                fitClockTextSize(
                    context = context,
                    baseSp = baseClockSp,
                    // half of the widget minus the divider (8dp margins + 1dp), text padding and a generous safety
                    // margin: launchers (e.g. POCO) often give the widget less room than AppWidgetManager reports,
                    // and too little room clips the last digit of the seconds.
                    availableWidthDp = (widgetWidthDp(context, widgetId) / 2f) - 28f,
                    prefs = prefs,
                    showSeconds = showSeconds,
                    localDigits = false, // the seconds clock (Chronometer) always uses Latin digits
                )
            } else baseClockSp
            val showOtherCalendars = isShowing(prefs, OTHER_CALENDARS_KEY)
            // Explicit height policy: level 1 = date/time only; level 2 = prayer times + remaining time;
            // level 3+ = event area, with three event lines added per extra level.
            val showTimes = isShowing(prefs, OWGHAT_KEY) && heightLevel >= 2
            val eventLineCapacity = if (heightLevel >= 3) (heightLevel - 2) * 3 else 0
            val showEvents = isShowing(prefs, NON_HOLIDAYS_EVENTS_KEY)
            val showHolidays = isShowing(prefs, CONTENT_HOLIDAYS)
            val timesPlan = if (showTimes) {
                planPrayerTimes(
                    context, prefs, widgetWidthDp(context, widgetId) - 2f,
                    minOf(14f * scale, prayerCap), localDigits,
                )
            } else null
            // Upstream behavior: each holiday/event occupies one horizontal line and is
            // ellipsized at the end when it does not fit. More widget width naturally reveals
            // more of the same line; increasing the widget text scale must not push the row
            // onto a second line.
            // Now: lines are shown in full (wrapped) as far as the widget height allows; only when there is
            // no room left does each of holiday/event fall back to one ellipsized line (see below).

            applyBackground(context, views, widgetId, dynamicColors, transparency, prefs)
            views.setInt(R.id.widget_layout4x2, "setLayoutDirection", View.LAYOUT_DIRECTION_RTL)
            val centerContent = bool(prefs, PREF_CENTER_ALIGN_WIDGETS, true)
            views.setInt(
                R.id.widget_content_container,
                "setGravity",
                if (centerContent) android.view.Gravity.CENTER_VERTICAL else android.view.Gravity.TOP,
            )

            val dateInfo = DateInfo.fromNow(zoneFor(prefs), hijriOffset(prefs))
            val syncIsCurrent = prefs.getString(KEY_SYNC_DATE, null) == dateInfo.key
            val weekday = (if (syncIsCurrent) prefs.getString(KEY_WEEKDAY, null).orEmpty() else "")
                .ifBlank { dateInfo.weekday }
            // The date text is always formatted here from the raw numbers, never taken from the string the
            // app pre-formatted: that string was built with the switches as they were when the app last
            // synced, so the "numerical date" / "other calendars" settings changed here would be ignored.
            val persianDate = persianDateText(prefs, dateInfo, syncIsCurrent, localDigits, showOtherCalendars)
            val gregorianDate = gregorianDateText(prefs, dateInfo, syncIsCurrent, localDigits, showOtherCalendars)
            val islamicDate = islamicDateText(prefs, dateInfo, syncIsCurrent, localDigits, showOtherCalendars)
            val dateBlock = orderedDateLines(prefs, persianDate, gregorianDate, islamicDate, showOtherCalendars).joinToString("\n")

            // Vertical fit: the reported widget height is the only room there is, so measure the real
            // layout (fonts, wrapping, paddings) and shrink every text by the same factor until it fits.
            // This keeps the last row ("… تا اذان صبح") fully visible on short widgets.
            val holidayForFit = if (syncIsCurrent && showHolidays) prefs.getString(KEY_HOLIDAY, "").orEmpty().trim() else ""
            val eventForFit = if (syncIsCurrent && showEvents) prefs.getString(KEY_EVENT, "").orEmpty().trim() else ""
            val fitResult = verticalFit(
                context = context,
                widthDp = widgetWidthDp(context, widgetId).toFloat(),
                heightDp = widgetHeightDp.toFloat(),
                clockEnabled = clockEnabled,
                showSecondsForFit = showSeconds,
                clockSp = clockSp,
                dateSp = minOf(13f * scale, dateCap),
                prayerSp = minOf(14f * scale, prayerCap),
                eventSp = minOf(13f * scale, eventCap),
                weekday = weekday,
                dateLines = dateBlock,
                timesPlan = timesPlan,
                holidayText = holidayForFit,
                eventText = eventForFit,
                eventLineCapacity = eventLineCapacity,
            )
            val fit = fitResult.factor

            if (clockEnabled) {
                setTextSize(views, R.id.time_header_4x2, fit * clockSp)
                setTextSize(views, R.id.textPlaceholder0_4x2, fit * clockSp)
                setTextSize(views, R.id.clock_chrono_4x2, fit * clockSp)
                setTextSize(views, R.id.clock_text_4x2, fit * clockSp)
                applyClock(views, prefs, showSeconds)
                views.setTextViewText(
                    R.id.textPlaceholder1_4x2,
                    Tr.t(weekday + '\n' + dateBlock),
                )
            } else {
                setTextSize(views, R.id.textPlaceholder0_4x2, fit * minOf(40f * scale, if (compact) 32f else if (medium) 36f else 40f))
                views.setTextViewText(R.id.textPlaceholder0_4x2, Tr.t(weekday))
                views.setTextViewText(
                    R.id.textPlaceholder1_4x2,
                    Tr.t(dateBlock),
                )
            }

            applyDateClockAlignment(views, clockEnabled, edgeAlign)

            setTextSize(views, R.id.textPlaceholder1_4x2, fit * minOf(13f * scale, dateCap))
            setTextSize(views, R.id.textPlaceholder2_4x2, fit * minOf(13f * scale, eventCap))
            setTextSize(views, R.id.event_4x2, fit * minOf(13f * scale, eventCap))
            setTextSize(views, R.id.holiday_4x2, fit * minOf(13f * scale, eventCap))

            applyTextColors(context, views, widgetId, dynamicColors, prefs, clockEnabled)

            if (timesPlan != null) {
                renderPrayerTimes(
                    context, views, prefs, localDigits, timesPlan,
                    prayerSp = fit * timesPlan.sp,
                    remainingMaxSp = fit * minOf(13f * scale, eventCap),
                    // widget width minus the content margins, the refresh arrow (12dp + 3dp gap),
                    // the text style's padding and a small safety margin for launcher insets.
                    remainingAvailableDp = (widgetWidthDp(context, widgetId) - 2f - 15f - 4f - 12f) * 1f,
                )
            } else {
                views.setViewVisibility(R.id.widget4x2_times, View.GONE)
                views.setViewVisibility(R.id.remaining_row_4x2, View.GONE)
            }

            // Holidays and non-holiday events are each optional ("تعطیلات رسمی" / "مناسبت‌های غیر تعطیل" in the content dialog).
            // Stored event titles are used only when Flutter has synced today's date, otherwise they
            // would be yesterday's data after a midnight/date-change broadcast.
            val holidayText = if (syncIsCurrent && showHolidays) prefs.getString(KEY_HOLIDAY, "").orEmpty().trim() else ""
            val eventText = if (syncIsCurrent && showEvents) prefs.getString(KEY_EVENT, "").orEmpty().trim() else ""
            val eventSpFinal = fit * minOf(13f * scale, eventCap)
            val contentWidthDp = widgetWidthDp(context, widgetId) - 2f
            val holidayNeeded = wrappedLineCount(context, holidayText, eventSpFinal, contentWidthDp)
            val eventNeeded = wrappedLineCount(context, eventText, eventSpFinal, contentWidthDp)
            var remainingEventLines = eventLineCapacity
            val holidayMax = minOf(holidayNeeded, remainingEventLines)
            remainingEventLines -= holidayMax
            val eventMax = minOf(eventNeeded, remainingEventLines)
            if (holidayMax > 0) {
                views.setViewVisibility(R.id.holiday_4x2, View.VISIBLE)
                views.setInt(R.id.holiday_4x2, "setMaxLines", holidayMax)
                views.setTextViewText(R.id.holiday_4x2, Tr.t(holidayText))
            } else {
                views.setViewVisibility(R.id.holiday_4x2, View.GONE)
            }
            if (eventMax > 0) {
                views.setViewVisibility(R.id.event_4x2, View.VISIBLE)
                views.setInt(R.id.event_4x2, "setMaxLines", eventMax)
                views.setTextViewText(R.id.event_4x2, Tr.t(eventText))
            } else {
                views.setViewVisibility(R.id.event_4x2, View.GONE)
            }

            setLaunchClick(context, views, widgetId)
            return views
        }

        /** Persian date honouring the widget's own settings (numerical date, calendar-name suffix, digits). */
        /**
         * Date lines in the user's calendar priority order (Settings > calendars priority): the main calendar
         * first, disabled calendars left out. With "other calendars" off only the main calendar is shown.
         */
        private fun orderedDateLines(
            prefs: android.content.SharedPreferences,
            persian: String,
            gregorian: String,
            islamic: String,
            showOthers: Boolean,
        ): List<String> {
            val order = prefs.getString(KEY_CALENDARS_ORDER, null)?.split(',')?.map { it.trim() }
                ?.filter { it == "shamsi" || it == "gregorian" || it == "hijri" }
                ?.distinct().orEmpty().ifEmpty { listOf("shamsi", "gregorian", "hijri") }
            val lines = order.map {
                when (it) {
                    "gregorian" -> gregorian
                    "hijri" -> islamic
                    else -> persian
                }
            }
            return if (showOthers) lines else lines.take(1)
        }

        private fun persianDateText(
            prefs: android.content.SharedPreferences,
            dateInfo: DateInfo,
            syncIsCurrent: Boolean,
            localDigits: Boolean,
            showOtherCalendars: Boolean,
        ): String {
            val synced = if (syncIsCurrent) {
                val y = prefs.getString(KEY_DATE_YEAR, null)?.trim()?.toIntOrNull()
                val m = prefs.getString(KEY_DATE_MONTH, null)?.trim()?.toIntOrNull()
                val d = prefs.getString(KEY_DATE_DAY, null)?.trim()?.toIntOrNull()
                if (y != null && m != null && d != null && m in 1..12 && d in 1..31) PersianDateValue(y, m, d) else null
            } else null
            return (synced ?: dateInfo.persian).format(
                numerical = bool(prefs, PREF_NUMERICAL_DATE, false),
                localDigits = localDigits,
                calendarNameInLinear = showOtherCalendars,
            )
        }

        /** Reads the raw y/m/d the app synced for [prefix] ("gregorian" / "islamic"), if they are for today. */
        private fun syncedDate(prefs: android.content.SharedPreferences, syncIsCurrent: Boolean, prefix: String): IntArray? {
            if (!syncIsCurrent) return null
            val y = prefs.getString("${prefix}_year", null)?.trim()?.toIntOrNull()
            val m = prefs.getString("${prefix}_month", null)?.trim()?.toIntOrNull()
            val d = prefs.getString("${prefix}_day", null)?.trim()?.toIntOrNull()
            return if (y != null && m != null && d != null && m in 1..12 && d in 1..31) intArrayOf(y, m, d) else null
        }

        /** Gregorian date; the numerical-date switch applies to it exactly like it does to the Persian date. */
        private fun gregorianDateText(
            prefs: android.content.SharedPreferences,
            dateInfo: DateInfo,
            syncIsCurrent: Boolean,
            localDigits: Boolean,
            showOtherCalendars: Boolean,
        ): String {
            val numerical = bool(prefs, PREF_NUMERICAL_DATE, false)
            if (!numerical) {
                val synced = if (syncIsCurrent) prefs.getString(KEY_GREGORIAN, null).orEmpty() else ""
                if (synced.isNotBlank()) return synced
            }
            val raw = syncedDate(prefs, syncIsCurrent, "gregorian")
            val value = if (raw != null) GregorianDateValue(raw[0], raw[1], raw[2]) else dateInfo.gregorian
            return value.format(numerical, localDigits, showOtherCalendars)
        }

        /** Hijri date; the numerical-date switch applies to it as well. */
        private fun islamicDateText(
            prefs: android.content.SharedPreferences,
            dateInfo: DateInfo,
            syncIsCurrent: Boolean,
            localDigits: Boolean,
            showOtherCalendars: Boolean,
        ): String {
            val numerical = bool(prefs, PREF_NUMERICAL_DATE, false)
            if (!numerical) {
                val synced = if (syncIsCurrent) prefs.getString(KEY_ISLAMIC, null).orEmpty() else ""
                if (synced.isNotBlank()) return synced
            }
            val raw = syncedDate(prefs, syncIsCurrent, "islamic")
            val value = if (raw != null) IslamicDateValue(raw[0], raw[1], raw[2]) else dateInfo.islamic
            return value.format(numerical, localDigits, showOtherCalendars)
        }

        private fun hijriOffset(prefs: android.content.SharedPreferences): Int =
            double(prefs, PREF_HIJRI_OFFSET)?.toInt()?.coerceIn(-3, 3) ?: 0

        private fun holidayFor(prefs: android.content.SharedPreferences): String =
            if (isShowing(prefs, CONTENT_HOLIDAYS)) prefs.getString(KEY_HOLIDAY, "").orEmpty().trim() else ""

        private fun createSafeRemoteViews(context: Context, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget4x2_safe)
            val prefs = widgetPrefs(context, widgetId)
            val localDigits = bool(prefs, PREF_LOCAL_NUMERAL, true)
            val showSeconds = bool(prefs, PREF_WIDGET_SHOW_SECONDS, false)
            val now = java.util.Calendar.getInstance(zoneFor(prefs))
            val clock = formatClockText(prefs, now, showSeconds)
            val dateInfo = DateInfo.fromNow(zoneFor(prefs), hijriOffset(prefs))
            val date = dateInfo.persian.format(
                numerical = bool(prefs, PREF_NUMERICAL_DATE, false),
                localDigits = localDigits,
                calendarNameInLinear = true,
            )
            val lines = buildString {
                append(dateInfo.weekday)
                append('\n')
                append(date)
                val holiday = holidayFor(prefs)
                val event = prefs.getString(KEY_EVENT, "").orEmpty().trim()
                if (holiday.isNotBlank()) append('\n').append(holiday)
                if (event.isNotBlank()) append('\n').append(event)
            }
            views.setTextViewText(R.id.widget_safe_time, clock)
            views.setTextViewText(R.id.widget_safe_date, Tr.t(lines))
            val eventText = listOf(
                holidayFor(prefs),
                prefs.getString(KEY_EVENT, "").orEmpty().trim(),
            ).filter { it.isNotBlank() }.joinToString("\n")
            views.setTextViewText(R.id.widget_safe_events, Tr.t(eventText))
            val foreground = parseColor(
                colorPref(prefs, PREF_SELECTED_WIDGET_TEXT_COLOR),
                DEFAULT_TEXT_COLOR,
            )
            views.setTextColor(R.id.widget_safe_time, foreground)
            views.setTextColor(R.id.widget_safe_date, foreground)
            views.setTextColor(R.id.widget_safe_events, foreground)
            views.setOnClickPendingIntent(
                R.id.widget_safe_root,
                AstronomyWidgetSupport.launchApp(context, requestCode = widgetId + 20000),
            )
            return views
        }

        private fun updateOneStatic(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                manager.updateAppWidget(widgetId, createRemoteViews(context, widgetId))
            } catch (t: Throwable) {
                Log.e(TAG, "4x2 static update failed for widgetId=$widgetId", t)
                runCatching { manager.updateAppWidget(widgetId, createSafeRemoteViews(context, widgetId)) }
                    .onFailure { Log.e(TAG, "4x2 static fallback failed for widgetId=$widgetId", it) }
            }
        }

        /** How the selected prayer times are laid out: one or two rows, label style, text size. */
        private data class TimesPlan(
            val slots: List<PrayerSlot>,
            val rows: Int,
            val perRow: Int,
            val shortLabels: Boolean,
            val sp: Float,
            val cellWidthDp: Float,
            val sampleLabel: String,
        )

        private fun allPrayerSlots(t: PrayerTimesValue): List<PrayerSlot> {
            val values = intArrayOf(t.imsak, t.fajr, t.sunrise, t.dhuhr, t.asr, t.sunset, t.maghrib, t.isha, t.midnight)
            return PRAYER_TIME_KEYS.indices.map { i ->
                PrayerSlot(PRAYER_TIME_KEYS[i], PRAYER_TIME_LABELS[i], PRAYER_TIME_SHORT_LABELS[i], values[i])
            }
        }

        /**
         * Chooses the most compact arrangement that keeps the text readable: one row with full labels,
         * one row with short labels, or two rows with short labels. The text size is the largest (up to
         * [baseSp]) at which the widest label / time still fits its cell.
         */
        private fun planPrayerTimes(
            context: Context,
            prefs: android.content.SharedPreferences,
            contentWidthDp: Float,
            baseSp: Float,
            localDigits: Boolean,
        ): TimesPlan? {
            val times = currentPrayerTimes(prefs) ?: return null
            val selected = selectedPrayerKeys(prefs)
            val slots = allPrayerSlots(times).filter { it.key in selected }
            if (slots.isEmpty()) return null
            val n = slots.size
            val m = context.resources.displayMetrics
            val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
            }
            fun timeText(v: Int) = if (localDigits) persianDigits(formatTime(v)) else formatTime(v)
            fun fitSp(cellDp: Float, texts: List<String>): Float {
                val availablePx = (cellDp - 3f) * m.density
                var sp = baseSp
                while (sp > 7f) {
                    paint.textSize = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, sp, m)
                    if (texts.maxOf { paint.measureText(it) } <= availablePx) break
                    sp -= 0.25f
                }
                return sp.coerceAtLeast(7f)
            }
            val times1 = slots.map { timeText(it.value) }
            val fullLabels = slots.map { it.label }
            val shortLabels = slots.map { it.shortLabel }
            val longest = { labels: List<String> -> labels.maxByOrNull { it.length } ?: "" }

            val acceptable = 9f
            // 1) one row, full labels
            var cell = contentWidthDp / n
            var sp = fitSp(cell, fullLabels + times1)
            if (sp >= acceptable) return TimesPlan(slots, 1, n, false, sp, cell, longest(fullLabels))
            // 2) one row, short labels
            sp = fitSp(cell, shortLabels + times1)
            if (sp >= acceptable) return TimesPlan(slots, 1, n, true, sp, cell, longest(shortLabels))
            // 3) two rows, short labels (a single time can never need two rows)
            if (n == 1) return TimesPlan(slots, 1, 1, true, sp, cell, longest(shortLabels))
            val perRow = (n + 1) / 2
            cell = contentWidthDp / perRow
            sp = fitSp(cell, shortLabels + times1)
            return TimesPlan(slots, 2, perRow, true, sp, cell, longest(shortLabels))
        }

        private fun renderPrayerTimes(
            context: Context,
            views: RemoteViews,
            prefs: android.content.SharedPreferences,
            localDigits: Boolean,
            plan: TimesPlan,
            prayerSp: Float,
            remainingMaxSp: Float,
            remainingAvailableDp: Float,
        ) {
            val clock = currentMinutes(prefs)
            val slots = plan.slots
            setRefreshClick(context, views)
            // Next time = the smallest positive distance from now (wraps past midnight).
            val nextIndex = slots.indices.minByOrNull { i ->
                val d = slots[i].value - clock
                if (d <= 0) d + 24 * 60 else d
            } ?: 0

            val row1Cells = intArrayOf(
                R.id.textPlaceholder4times_1_4x2, R.id.textPlaceholder4times_2_4x2,
                R.id.textPlaceholder4times_3_4x2, R.id.textPlaceholder4times_4_4x2,
                R.id.textPlaceholder4times_5_4x2, R.id.textPlaceholder4times_6_4x2,
                R.id.textPlaceholder4times_7_4x2, R.id.textPlaceholder4times_8_4x2,
                R.id.textPlaceholder4times_9_4x2,
            )
            val row1Dividers = intArrayOf(
                R.id.times_div_1, R.id.times_div_2, R.id.times_div_3, R.id.times_div_4,
                R.id.times_div_5, R.id.times_div_6, R.id.times_div_7, R.id.times_div_8,
            )
            val row2Cells = intArrayOf(
                R.id.textPlaceholder4times_r2_1_4x2, R.id.textPlaceholder4times_r2_2_4x2,
                R.id.textPlaceholder4times_r2_3_4x2, R.id.textPlaceholder4times_r2_4_4x2,
            )
            val row2Dividers = intArrayOf(R.id.times_div_r2_1, R.id.times_div_r2_2, R.id.times_div_r2_3)

            fun bindRow(cells: IntArray, dividers: IntArray, from: Int, count: Int) {
                cells.forEachIndexed { i, viewId ->
                    if (i < count) {
                        val slot = slots[from + i]
                        val time = if (localDigits) persianDigits(formatTime(slot.value)) else formatTime(slot.value)
                        views.setViewVisibility(viewId, View.VISIBLE)
                        views.setTextViewText(viewId, Tr.t("${if (plan.shortLabels) slot.shortLabel else slot.label}\n$time"))
                        setTextSize(views, viewId, prayerSp)
                        applyPrayerAlpha(context, views, viewId, prefs, from + i == nextIndex)
                    } else {
                        views.setViewVisibility(viewId, View.GONE)
                    }
                }
                // Divider i sits between cell i and cell i + 1.
                dividers.forEachIndexed { i, dividerId ->
                    views.setViewVisibility(dividerId, if (i + 1 < count) View.VISIBLE else View.GONE)
                }
            }
            val firstCount = if (plan.rows == 1) slots.size else plan.perRow
            bindRow(row1Cells, row1Dividers, 0, firstCount)
            if (plan.rows == 2) {
                views.setViewVisibility(R.id.times_row2, View.VISIBLE)
                bindRow(row2Cells, row2Dividers, firstCount, slots.size - firstCount)
            } else {
                views.setViewVisibility(R.id.times_row2, View.GONE)
            }

            val next = slots[nextIndex]
            var delta = next.value - clock
            if (delta <= 0) delta += 24 * 60
            val remaining = remainingTime(delta)
            // Each part is translated on its own (no dependence on one big template matching).
            fun part(x: String) = Tr.t(if (localDigits) persianDigits(x) else x)
            var local = "${part(remaining)} ${Tr.t("تا")} ${part(next.label)}"
            // «مکان اوقات شرعی» in the widget content settings: show the place the times belong to.
            if (isShowing(prefs, OWGHAT_LOCATION_KEY)) {
                val place = prefs.getString(PREF_LOCATION, "").orEmpty().trim()
                if (place.isNotEmpty() && place != "GPS") local += " (${part(place)})"
            }
            views.setTextViewText(R.id.textPlaceholder2_4x2, local)
            fitRemainingText(context, views, local, remainingMaxSp, remainingAvailableDp)
            views.setViewVisibility(R.id.widget4x2_times, View.VISIBLE)
            views.setViewVisibility(R.id.remaining_row_4x2, View.VISIBLE)
        }

        /**
         * The "time left until next prayer" sentence must stay on ONE line together with the refresh
         * arrow. RemoteViews cannot measure text, so the size is chosen here: the largest size (up to
         * [maxSp]) at which the sentence fits into [availableDp]; below 8sp the layout's end-ellipsis
         * takes over, and the arrow (a fixed-size sibling) is still shown.
         */
        private fun fitRemainingText(
            context: Context,
            views: RemoteViews,
            text: String,
            maxSp: Float,
            availableDp: Float,
        ) {
            val metrics = context.resources.displayMetrics
            val availablePx = availableDp * metrics.density
            val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
            }
            var sp = maxSp
            val minSp = 8f
            while (sp > minSp) {
                paint.textSize = android.util.TypedValue.applyDimension(
                    android.util.TypedValue.COMPLEX_UNIT_SP, sp, metrics,
                )
                if (paint.measureText(text) <= availablePx) break
                sp -= 0.25f
            }
            setTextSize(views, R.id.textPlaceholder2_4x2, sp.coerceAtLeast(minSp))
        }

        private fun currentPrayerTimes(prefs: android.content.SharedPreferences): PrayerTimesValue? {
            val hasLocation = double(prefs, PREF_LATITUDE) != null && double(prefs, PREF_LONGITUDE) != null
            if (!hasLocation) {
                val dateInfo = DateInfo.fromNow(zoneFor(prefs))
                if (prefs.getString(KEY_SYNC_DATE, null) == dateInfo.key) {
                    syncedPrayerFallback(prefs)?.let { return it }
                }
            }
            return computePrayerTimes(prefs)
        }

        /** Exact sunrise/sunset for one widget instance, calculated from that widget's own settings. */
        @JvmStatic
        fun sunriseSunsetHours(prefs: android.content.SharedPreferences): Pair<Double, Double>? =
            computePrayerTimes(prefs)?.let { it.sunrise / 60.0 to it.sunset / 60.0 }

        /** Prayer times calculated here from the widget's own location settings (no app sync involved). */
        private fun computePrayerTimes(prefs: android.content.SharedPreferences): PrayerTimesValue? {
            val lat = double(prefs, PREF_LATITUDE) ?: return null
            val lon = double(prefs, PREF_LONGITUDE) ?: return null
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
            val elevation = double(prefs, PREF_ALTITUDE) ?: 0.0
            val now = Calendar.getInstance(zoneFor(prefs))
            val method = prefs.getString(PREF_PRAY_TIME_METHOD, "tehran").orEmpty()
            val asrHanafi = bool(prefs, PREF_ASR_HANAFI, false)
            val highLatitude = prefs.getString(PREF_HIGH_LATITUDES_METHOD, "nightMiddle").orEmpty()
            val midnightMethod = prefs.getString(PREF_MIDNIGHT_METHOD, "").orEmpty()
            return PrayerCalculator.calculate(
                year = now.get(Calendar.YEAR),
                month = now.get(Calendar.MONTH) + 1,
                day = now.get(Calendar.DAY_OF_MONTH),
                latitude = lat,
                longitude = lon,
                elevation = elevation,
                timeZoneHours = zoneFor(prefs).getOffset(now.timeInMillis) / 3600000.0,
                method = method,
                asrHanafi = asrHanafi,
                highLatitude = highLatitude,
                midnightMethod = midnightMethod,
            )
        }

        /**
         * Re-render after a widget-only location/time-zone change. Prayer times are calculated from that
         * widget's scoped settings, so no global prayer-time cache is modified.
         */
        @JvmStatic
        fun resyncPrayerTimes(context: Context, widgetId: Int) {
            // Prayer times are calculated from the widget's own location/methods during rendering.
            // No global prayer-time store is touched, so changing one widget cannot alter another.
            refresh(context)
        }

        private fun syncedPrayerFallback(prefs: android.content.SharedPreferences): PrayerTimesValue? {
            val sunrise = parseMinutes(prefs.getString(KEY_SUNRISE, "")) ?: return null
            val fajr = parseMinutes(prefs.getString(KEY_FAJR, "")) ?: sunrise
            val imsak = parseMinutes(prefs.getString(KEY_IMSAK, "")) ?: ((fajr - 10 + 1440) % 1440)
            val dhuhr = parseMinutes(prefs.getString(KEY_DHUHR, "")) ?: return null
            val asr = parseMinutes(prefs.getString(KEY_ASR, "")) ?: dhuhr
            val sunset = parseMinutes(prefs.getString(KEY_SUNSET, "")) ?: return null
            val maghrib = parseMinutes(prefs.getString(KEY_MAGHRIB, "")) ?: sunset
            val isha = parseMinutes(prefs.getString(KEY_ISHA, "")) ?: maghrib
            val midnight = parseMinutes(prefs.getString(KEY_MIDNIGHT, "")) ?: ((sunset + ((sunrise - sunset + 1440) % 1440) / 2) % 1440)
            return PrayerTimesValue(imsak, fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight)
        }

        private fun currentMinutes(prefs: android.content.SharedPreferences): Int {
            val now = Calendar.getInstance(zoneFor(prefs))
            return now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        }

        private fun zoneFor(prefs: android.content.SharedPreferences): TimeZone =
            if (bool(prefs, PREF_IRAN_TIME, false)) TimeZone.getTimeZone("Asia/Tehran") else TimeZone.getDefault()

        private fun applyPrayerAlpha(
            context: Context,
            views: RemoteViews,
            id: Int,
            prefs: android.content.SharedPreferences,
            isNext: Boolean,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setFloat(id, "setAlpha", if (isNext) 1f else .6f)
                return
            }
            val base = if (bool(prefs, PREF_WIDGETS_PREFER_SYSTEM_COLORS, true)) {
                ContextCompat.getColor(context, R.color.widget_foreground)
            } else {
                parseColor(colorPref(prefs, PREF_SELECTED_WIDGET_TEXT_COLOR), DEFAULT_TEXT_COLOR)
            }
            views.setTextColor(id, if (isNext) base else Color.argb(180, Color.red(base), Color.green(base), Color.blue(base)))
        }

        private fun applyBackground(
            context: Context,
            views: RemoteViews,
            widgetId: Int,
            dynamicColors: Boolean,
            transparency: Float,
            prefs: android.content.SharedPreferences,
        ) {
            if (dynamicColors) {
                views.setImageViewResource(R.id.widget_layout4x2_background, R.drawable.widget_background)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setFloat(R.id.widget_layout4x2_background, "setAlpha", 1f - transparency)
                }
                return
            }

            val color = parseColor(
                colorPref(prefs, PREF_SELECTED_WIDGET_BACKGROUND_COLOR),
                DEFAULT_BACKGROUND_COLOR,
            )
            val alpha = (Color.alpha(color) * (1f - transparency).coerceIn(0f, 1f)).roundToInt()
            val effectiveColor = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
            if (Color.alpha(effectiveColor) == 0) {
                views.setImageViewResource(R.id.widget_layout4x2_background, 0)
            } else {
                views.setImageViewBitmap(
                    R.id.widget_layout4x2_background,
                    createRoundedBackground(context, widgetId, effectiveColor),
                )
            }
        }

        private fun createRoundedBackground(context: Context, widgetId: Int, color: Int): Bitmap {
            val manager = AppWidgetManager.getInstance(context)
            val options = manager.getAppWidgetOptions(widgetId)
            val landscape = context.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
            val widthDp = options.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,
                250,
            )
            val heightDp = options.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,
                110,
            )
            val density = context.resources.displayMetrics.density
            val width = (widthDp * density).toInt().coerceIn(160, 1200)
            val height = (heightDp * density).toInt().coerceIn(80, 600)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
            val radius = 16f * density
            canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)
            return bitmap
        }

        private fun applyTextColors(
            context: Context,
            views: RemoteViews,
            widgetId: Int,
            dynamicColors: Boolean,
            prefs: android.content.SharedPreferences,
            clockEnabled: Boolean,
        ) {
            val ids = listOf(
                R.id.textPlaceholder0_4x2,
                R.id.clock_chrono_4x2,
                R.id.clock_text_4x2,
                R.id.textPlaceholder1_4x2,
                R.id.textPlaceholder2_4x2,
                R.id.textPlaceholder4times_1_4x2,
                R.id.textPlaceholder4times_2_4x2,
                R.id.textPlaceholder4times_3_4x2,
                R.id.textPlaceholder4times_4_4x2,
                R.id.textPlaceholder4times_5_4x2,
                R.id.textPlaceholder4times_6_4x2,
                R.id.textPlaceholder4times_7_4x2,
                R.id.textPlaceholder4times_8_4x2,
                R.id.textPlaceholder4times_9_4x2,
                R.id.textPlaceholder4times_r2_1_4x2,
                R.id.textPlaceholder4times_r2_2_4x2,
                R.id.textPlaceholder4times_r2_3_4x2,
                R.id.textPlaceholder4times_r2_4_4x2,
                R.id.event_4x2,
            )
            val foreground = if (dynamicColors) {
                ContextCompat.getColor(context, R.color.widget_foreground)
            } else {
                parseColor(colorPref(prefs, PREF_SELECTED_WIDGET_TEXT_COLOR), DEFAULT_TEXT_COLOR)
            }
            ids.forEach { views.setTextColor(it, foreground) }
            val holiday = if (dynamicColors) {
                ContextCompat.getColor(context, R.color.remote_view_holiday_color)
            } else {
                Color.rgb(255, 138, 101)
            }
            views.setTextColor(R.id.holiday_4x2, holiday)
            if (clockEnabled && dynamicColors) {
                val accent = ContextCompat.getColor(context, R.color.widget_accent)
                views.setTextColor(R.id.textPlaceholder0_4x2, accent)
                views.setTextColor(R.id.clock_chrono_4x2, accent)
                views.setTextColor(R.id.clock_text_4x2, accent)
            }
        }

        /** Build the clock text explicitly so the widget never flashes the device's Latin-digit
         * TextClock output before the next broadcast. The widget is refreshed by our minute/second
         * ticker, which also guarantees Persian digits remain stable. */
        private fun formatClockText(
            prefs: android.content.SharedPreferences,
            calendar: Calendar,
            showSeconds: Boolean,
        ): String {
            val hour24 = calendar.get(Calendar.HOUR_OF_DAY)
            val hour = if (bool(prefs, PREF_WIDGET_IN_24, false)) {
                String.format(Locale.US, "%02d", hour24)
            } else {
                // always two digits: 05, not 5
                String.format(Locale.US, "%02d", if (hour24 % 12 == 0) 12 else hour24 % 12)
            }
            val minute = String.format(Locale.US, "%02d", calendar.get(Calendar.MINUTE))
            val second = String.format(Locale.US, "%02d", calendar.get(Calendar.SECOND))
            val raw = if (showSeconds) "$hour:$minute:$second" else "$hour:$minute"
            return raw // the clock is always Latin digits, in every mode
        }

        private fun applyDateClockAlignment(views: RemoteViews, clockEnabled: Boolean, edgeAlign: Boolean) {
            // The two halves are placed with physical left/right rules in the layout itself, so nothing
            // here (or in any launcher's RTL handling) can swap them: clock/weekday LEFT, dates RIGHT.
            val centerV = android.view.Gravity.CENTER_VERTICAL
            if (!edgeAlign) {
                views.setInt(R.id.widget_clock_side_container, "setGravity", android.view.Gravity.CENTER)
                views.setInt(R.id.textPlaceholder0_4x2, "setGravity", android.view.Gravity.CENTER)
                views.setInt(R.id.clock_chrono_4x2, "setGravity", android.view.Gravity.CENTER)
                views.setInt(R.id.clock_text_4x2, "setGravity", android.view.Gravity.CENTER)
                views.setInt(R.id.textPlaceholder1_4x2, "setGravity", android.view.Gravity.CENTER)
                return
            }
            // Edge alignment: clock left-aligned (left edge), weekday/date right-aligned (right edge).
            val left = android.view.Gravity.LEFT or centerV
            if (clockEnabled) views.setInt(R.id.widget_clock_side_container, "setGravity", left)
            views.setInt(R.id.textPlaceholder0_4x2, "setGravity", left)
            views.setInt(R.id.clock_chrono_4x2, "setGravity", left)
            views.setInt(R.id.clock_text_4x2, "setGravity", left)
            views.setInt(R.id.textPlaceholder1_4x2, "setGravity", android.view.Gravity.RIGHT or centerV)
        }

        /**
         * Clock rendering. Seconds mode uses a Chronometer whose base is chosen so that its elapsed time equals
         * the wall-clock time of day ("H:MM:SS"). The launcher ticks it every second by itself, so seconds are
         * exact and identical on every launcher (no alarms, no widget-update rate limits, no fonts/locales).
         * It is re-based at each hour boundary (alarm) to keep the hour prefix/padding and the 12/24h wrap right.
         * Latin digits only. Without seconds the clock is plain text refreshed at each minute.
         */
        private fun applyClock(views: RemoteViews, prefs: android.content.SharedPreferences, showSeconds: Boolean) {
            val cal = Calendar.getInstance(zoneFor(prefs))
            if (!showSeconds) {
                // System TextClock: redrawn by the launcher at each minute change, Latin digits, no alarms.
                views.setViewVisibility(R.id.clock_chrono_4x2, View.GONE)
                views.setViewVisibility(R.id.textPlaceholder0_4x2, View.GONE)
                views.setViewVisibility(R.id.clock_text_4x2, View.VISIBLE)
                val pattern = if (bool(prefs, PREF_WIDGET_IN_24, false)) "HH:mm" else "hh:mm"
                views.setCharSequence(R.id.clock_text_4x2, "setFormat12Hour", pattern)
                views.setCharSequence(R.id.clock_text_4x2, "setFormat24Hour", pattern)
                views.setString(R.id.clock_text_4x2, "setTimeZone", zoneFor(prefs).id)
                return
            }
            views.setViewVisibility(R.id.clock_text_4x2, View.GONE)
            val h24 = cal.get(Calendar.HOUR_OF_DAY)
            val elapsedSec: Long
            var format = "%s"
            if (bool(prefs, PREF_WIDGET_IN_24, false)) {
                elapsedSec = h24 * 3600L + cal.get(Calendar.MINUTE) * 60L + cal.get(Calendar.SECOND)
                // Chronometer prints "MM:SS" below one hour and an unpadded hour above it.
                format = when {
                    h24 == 0 -> "00:%s"
                    h24 < 10 -> "0%s"
                    else -> "%s"
                }
            } else {
                val h12 = if (h24 % 12 == 0) 12 else h24 % 12
                elapsedSec = h12 * 3600L + cal.get(Calendar.MINUTE) * 60L + cal.get(Calendar.SECOND)
                // Chronometer prints an unpadded hour; pad 1..9 to 01..09
                format = if (h12 < 10) "0%s" else "%s"
            }
            val base = android.os.SystemClock.elapsedRealtime() - elapsedSec * 1000L - cal.get(Calendar.MILLISECOND)
            views.setViewVisibility(R.id.textPlaceholder0_4x2, View.GONE)
            views.setViewVisibility(R.id.clock_chrono_4x2, View.VISIBLE)
            views.setChronometer(R.id.clock_chrono_4x2, base, format, true)
        }

        @JvmStatic
        fun refreshSecondTicker(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app)
            val ids = manager.getAppWidgetIds(ComponentName(app, Widget4x2::class.java))
            // Only the seconds Chronometer needs an (hourly) re-base; the minute TextClock needs nothing.
            val secondsIds = ids.filter {
                val prefs = widgetPrefs(app, it)
                bool(prefs, PREF_WIDGET_CLOCK, true) && bool(prefs, PREF_WIDGET_SHOW_SECONDS, false)
            }
            val enabled = secondsIds.isNotEmpty()
            val am = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(app, Widget4x2::class.java).setAction(ACTION_SECOND_TICK)
            val pi = PendingIntent.getBroadcast(
                app,
                SECOND_TICK_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (!enabled) {
                am.cancel(pi)
                pi.cancel()
                return
            }
            // Seconds mode: the launcher ticks the Chronometer; we only re-base it at the next full hour.
            // Minute mode: the text is refreshed at the next full minute.
            val now = System.currentTimeMillis()
            val interval = 3_600_000L
            val next = secondsIds.minOf { id ->
                val zoneOffset = zoneFor(widgetPrefs(app, id)).getOffset(now).toLong()
                (((now + zoneOffset) / interval) + 1L) * interval - zoneOffset
            }
            if (AthanScheduler.canScheduleExact(app)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pi)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pi)
            } else {
                @Suppress("DEPRECATION")
                am.set(AlarmManager.RTC_WAKEUP, next, pi)
            }
        }

        @JvmStatic
        fun tickSeconds(context: Context) {
            val app = context.applicationContext
            val manager = AppWidgetManager.getInstance(app)
            val ids = manager.getAppWidgetIds(ComponentName(app, Widget4x2::class.java))
            ids.forEach { id ->
                val prefs = widgetPrefs(app, id)
                if (!bool(prefs, PREF_WIDGET_CLOCK, true) || !bool(prefs, PREF_WIDGET_SHOW_SECONDS, false)) return@forEach
                val partial = RemoteViews(app.packageName, R.layout.widget4x2_clock)
                applyClock(partial, prefs, true)
                runCatching { manager.partiallyUpdateAppWidget(id, partial) }
                    .onFailure { Log.e(TAG, "Clock tick failed for widgetId=$id", it) }
            }
            refreshSecondTicker(app)
        }

        private fun setRefreshClick(context: Context, views: RemoteViews) {
            val intent = Intent(context, Widget4x2::class.java).apply { action = ACTION_REFRESH }
            val pending = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.refresh_wrapper, pending)
        }

        private fun setLaunchClick(context: Context, views: RemoteViews, widgetId: Int) {
            views.setOnClickPendingIntent(
                R.id.widget_layout4x2,
                AstronomyWidgetSupport.launchApp(context, requestCode = widgetId + 10000),
            )
        }

        private fun isShowing(prefs: android.content.SharedPreferences, key: String): Boolean {
            val raw = prefs.all[PREF_WHAT_TO_SHOW_WIDGETS] ?: return true
            val items = when (raw) {
                is Set<*> -> raw.mapNotNull { it?.toString()?.trim() }
                is String -> raw.split(',').map { it.trim() }
                else -> return true
            }
            // A selection saved before the "holidays" item existed has no marker: holidays stay visible.
            if (key == CONTENT_HOLIDAYS && CONTENT_MARKER !in items) return true
            return key in items
        }

        private fun String.lineCount(): Int = split('\n').count { it.isNotBlank() }.coerceAtMost(6)

        private fun setTextOrHide(views: RemoteViews, id: Int, text: String) {
            if (text.isBlank()) {
                views.setViewVisibility(id, View.GONE)
            } else {
                views.setViewVisibility(id, View.VISIBLE)
                views.setTextViewText(id, Tr.t(text.trim()))
            }
        }

        private fun setTextSize(views: RemoteViews, id: Int, sizeSp: Float) {
            views.setTextViewTextSize(id, android.util.TypedValue.COMPLEX_UNIT_SP, sizeSp)
        }

        private fun remainingTime(deltaMinutes: Int): String {
            val h = deltaMinutes / 60
            val m = deltaMinutes % 60
            return when {
                h > 0 && m > 0 -> "$h ساعت و $m دقیقه"
                h > 0 -> "$h ساعت"
                m > 0 -> "$m دقیقه"
                else -> "کمتر از ۱ دقیقه"
            }
        }

        private fun formatTime(minutes: Int): String {
            val h = (minutes / 60).coerceIn(0, 23)
            val m = minutes % 60
            return "%02d:%02d".format(Locale.US, h, m)
        }

        private fun parseMinutes(value: String?): Int? {
            val clean = normalizeDigits(value.orEmpty())
            val parts = clean.split(":")
            if (parts.size != 2) return null
            val h = parts[0].toIntOrNull() ?: return null
            val m = parts[1].take(2).toIntOrNull() ?: return null
            if (h !in 0..23 || m !in 0..59) return null
            return h * 60 + m
        }

        private fun fitClockTextSize(
            context: Context,
            baseSp: Float,
            availableWidthDp: Float,
            prefs: android.content.SharedPreferences,
            showSeconds: Boolean,
            localDigits: Boolean,
        ): Float {
            if (!showSeconds) return baseSp
            val sample = if (bool(prefs, PREF_WIDGET_IN_24, false)) "00:00:00" else "00:00:00"
            val renderedSample = if (localDigits) persianDigits(sample) else sample
            val density = context.resources.displayMetrics.density
            val targetWidthPx = (availableWidthDp.coerceAtLeast(1f) * density).toInt()
            val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
            }
            var size = baseSp
            val minimum = (baseSp * 0.4f).coerceAtLeast(10f)
            while (size > minimum) {
                paint.textSize = android.util.TypedValue.applyDimension(
                    android.util.TypedValue.COMPLEX_UNIT_SP, size, context.resources.displayMetrics,
                )
                if (paint.measureText(renderedSample) * 1.06f <= targetWidthPx) break
                size -= 0.5f
            }
            return size.coerceAtLeast(minimum)
        }

        /** Height in dp of [text] laid out like a TextView of the widget (sans-serif, font padding, 1dp bottom padding). */
        private fun measureTextDp(
            context: Context,
            text: String,
            sizeSp: Float,
            widthDp: Float,
            minLines: Int = 1,
            maxLines: Int = Int.MAX_VALUE,
            lineExtraDp: Float = 0f,
        ): Float {
            if (text.isBlank()) return 0f
            val m = context.resources.displayMetrics
            val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
                textSize = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, sizeSp, m)
            }
            val widthPx = (widthDp * m.density).toInt().coerceAtLeast(1)
            @Suppress("DEPRECATION")
            val layout = android.text.StaticLayout(
                text, paint, widthPx, android.text.Layout.Alignment.ALIGN_CENTER, 1f, lineExtraDp * m.density, true,
            )
            val lines = layout.lineCount.coerceIn(1, maxLines)
            val perLine = (layout.getLineBottom(0) - layout.getLineTop(0)).toFloat()
            val used = layout.getLineTop(lines).toFloat()
            val extra = (minLines - lines).coerceAtLeast(0) * perLine
            return (used + extra) / m.density + 1f // + WidgetTextStyle paddingBottom (1dp)
        }

        /** Largest factor in [0.55, 1] that keeps the explicitly permitted content inside the widget. */
        private data class VerticalFit(val factor: Float)

        private fun verticalFit(
            context: Context,
            widthDp: Float,
            heightDp: Float,
            clockEnabled: Boolean,
            showSecondsForFit: Boolean,
            clockSp: Float,
            dateSp: Float,
            prayerSp: Float,
            eventSp: Float,
            weekday: String,
            dateLines: String,
            timesPlan: TimesPlan?,
            holidayText: String,
            eventText: String,
            eventLineCapacity: Int,
        ): VerticalFit {
            val available = heightDp - 6f
            val contentW = widthDp - 2f
            val halfW = (contentW - 17f) / 2f
            fun total(f: Float): Float {
                val dateText = if (clockEnabled) "$weekday\n$dateLines" else dateLines
                val leftH = if (clockEnabled) {
                    measureTextDp(context, if (showSecondsForFit) "11:01:01" else "11:01", clockSp * f, halfW, maxLines = 1)
                } else {
                    measureTextDp(context, weekday, minOf(40f, clockSp) * f, halfW, maxLines = 1)
                }
                val rightH = measureTextDp(context, dateText, dateSp * f, halfW, minLines = 4, lineExtraDp = 1f)
                var sum = 4f + maxOf(leftH, rightH)
                if (timesPlan != null) {
                    val sample = "${timesPlan.sampleLabel}\n۱۸:۱۱"
                    val slotH = measureTextDp(context, sample, timesPlan.sp * f, timesPlan.cellWidthDp)
                    sum += 4f + timesPlan.rows * slotH
                    sum += measureTextDp(context, "۵ ساعت و ۳۹ دقیقه تا اذان صبح", eventSp * f, contentW, maxLines = 1)
                }
                if (eventLineCapacity > 0) {
                    val holidayLines = minOf(wrappedLineCount(context, holidayText, eventSp * f, contentW), eventLineCapacity)
                    val eventLines = minOf(
                        wrappedLineCount(context, eventText, eventSp * f, contentW),
                        (eventLineCapacity - holidayLines).coerceAtLeast(0),
                    )
                    if (holidayLines > 0) sum += measureTextDp(context, holidayText, eventSp * f, contentW, maxLines = holidayLines)
                    if (eventLines > 0) sum += measureTextDp(context, eventText, eventSp * f, contentW, maxLines = eventLines)
                }
                return sum
            }
            var f = 1f
            while (f > 0.55f && total(f) > available) f -= 0.02f
            return VerticalFit(f.coerceIn(0.55f, 1f))
        }

        /** Number of lines [text] needs when wrapped (not ellipsized) at [sizeSp] in [widthDp]. */
        private fun wrappedLineCount(context: Context, text: String, sizeSp: Float, widthDp: Float): Int {
            if (text.isBlank()) return 0
            val m = context.resources.displayMetrics
            val paint = android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
                textSize = android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP, sizeSp, m)
            }
            @Suppress("DEPRECATION")
            val layout = android.text.StaticLayout(
                text.trim(), paint, (widthDp * m.density).toInt().coerceAtLeast(1),
                android.text.Layout.Alignment.ALIGN_CENTER, 1f, 0f, true,
            )
            return layout.lineCount
        }

        /** Launcher reports resize size in dp. The provider minimum is level 1 and each
         * vertical launcher increment adds one level. Keep the mapping explicit so level 2
         * never leaks event lines and level 3 is the first event-bearing size. */
        private fun widgetHeightLevel(heightDp: Int): Int =
            (((heightDp - 110f) / 40f).roundToInt() + 1).coerceAtLeast(1)

        private fun widgetWidthDp(context: Context, widgetId: Int): Int {
            val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
            val landscape = context.resources.configuration.orientation ==
                android.content.res.Configuration.ORIENTATION_LANDSCAPE
            val key = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            val value = options.getInt(key, 0)
            val other = options.getInt(
                if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0,
            )
            return (value.takeIf { it > 0 } ?: other.takeIf { it > 0 } ?: 250).coerceAtLeast(100)
        }

        private fun widgetHeightDp(context: Context, widgetId: Int): Int {
            val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
            // Portrait: the widget's height is OPTION_APPWIDGET_MAX_HEIGHT; landscape: ..._MIN_HEIGHT.
            val landscape = context.resources.configuration.orientation ==
                android.content.res.Configuration.ORIENTATION_LANDSCAPE
            val max = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            val min = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val primary = if (landscape) min else max
            val other = if (landscape) max else min
            return (primary.takeIf { it > 0 } ?: other.takeIf { it > 0 } ?: 110).coerceAtLeast(80)
        }

        @JvmStatic
        fun readBoolean(prefs: android.content.SharedPreferences, key: String, fallback: Boolean): Boolean =
            bool(prefs, key, fallback)

        @JvmStatic
        fun readFloat(prefs: android.content.SharedPreferences, key: String, fallback: Float): Float =
            float(prefs, key, fallback)

        @JvmStatic
        fun readDouble(prefs: android.content.SharedPreferences, key: String): Double? =
            double(prefs, key)

        @JvmStatic
        fun readColor(prefs: android.content.SharedPreferences, key: String, fallback: Int): Int =
            parseColor(colorPref(prefs, key), fallback)

        private fun bool(prefs: android.content.SharedPreferences, key: String, fallback: Boolean): Boolean =
            when (val value = prefs.all[key]) {
                is Boolean -> value
                is String -> value.equals("true", ignoreCase = true)
                else -> fallback
            }

        private fun float(prefs: android.content.SharedPreferences, key: String, fallback: Float): Float =
            when (val value = prefs.all[key]) {
                is Float -> value
                is Double -> value.toFloat()
                is Number -> value.toFloat()
                is String -> value.toFloatOrNull() ?: fallback
                else -> fallback
            }

        private fun double(prefs: android.content.SharedPreferences, key: String): Double? =
            when (val value = prefs.all[key]) {
                is Number -> value.toDouble()
                is String -> value.toDoubleOrNull()
                else -> null
            }

        private fun parseColor(raw: String?, fallback: Int): Int =
            runCatching { Color.parseColor(raw ?: "") }.getOrDefault(fallback)

        private fun colorPref(prefs: android.content.SharedPreferences, key: String): String? =
            when (val value = prefs.all[key]) {
                is String -> value
                is Number -> String.format(Locale.US, "#%08X", value.toInt())
                else -> null
            }

        private fun normalizeDigits(value: String): String = value
            .replace('۰', '0').replace('۱', '1').replace('۲', '2').replace('۳', '3').replace('۴', '4')
            .replace('۵', '5').replace('۶', '6').replace('۷', '7').replace('۸', '8').replace('۹', '9')
            .replace('٠', '0').replace('١', '1').replace('٢', '2').replace('٣', '3').replace('٤', '4')
            .replace('٥', '5').replace('٦', '6').replace('٧', '7').replace('٨', '8').replace('٩', '9')

        private fun persianDigits(value: String): String = Tr.digits(value)
    }
}

private class ScopedWidgetPreferences(
    private val delegate: android.content.SharedPreferences,
    private val widgetId: Int,
) : android.content.SharedPreferences {
    private fun scoped(key: String): String? = if (Widget4x2.PER_WIDGET_KEYS.contains(key)) Widget4x2.scopedKeyForWidget(key, widgetId) else null
    private fun readKey(key: String): String = scoped(key) ?: key

    override fun getAll(): Map<String, *> {
        val result = delegate.all
            .filterKeys { key -> !Widget4x2.PER_WIDGET_KEYS.any { base -> key == Widget4x2.scopedKeyForWidget(base, widgetId) } }
            .toMutableMap()
        for (key in Widget4x2.PER_WIDGET_KEYS) {
            val scopedKey = Widget4x2.scopedKeyForWidget(key, widgetId)
            delegate.all[scopedKey]?.let { result[key] = it }
        }
        return result
    }
    private fun hasScoped(key: String): Boolean = scoped(key)?.let(delegate::contains) == true
    private fun readDefaultKey(key: String): String = if (hasScoped(key)) readKey(key) else key

    override fun getString(key: String, defValue: String?): String? = delegate.getString(readDefaultKey(key), defValue)
    override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? = delegate.getStringSet(readDefaultKey(key), defValues)
    override fun getInt(key: String, defValue: Int): Int = delegate.getInt(readDefaultKey(key), defValue)
    override fun getLong(key: String, defValue: Long): Long = delegate.getLong(readDefaultKey(key), defValue)
    override fun getFloat(key: String, defValue: Float): Float = delegate.getFloat(readDefaultKey(key), defValue)
    override fun getBoolean(key: String, defValue: Boolean): Boolean = delegate.getBoolean(readDefaultKey(key), defValue)
    override fun contains(key: String): Boolean = if (scoped(key) != null) hasScoped(key) || delegate.contains(key) else delegate.contains(key)
    override fun edit(): android.content.SharedPreferences.Editor = ScopedWidgetEditor(delegate.edit(), widgetId)
    override fun registerOnSharedPreferenceChangeListener(listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener) { delegate.registerOnSharedPreferenceChangeListener(listener) }
    override fun unregisterOnSharedPreferenceChangeListener(listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener) { delegate.unregisterOnSharedPreferenceChangeListener(listener) }
}

private class ScopedWidgetEditor(
    private val delegate: android.content.SharedPreferences.Editor,
    private val widgetId: Int,
) : android.content.SharedPreferences.Editor {
    private fun key(raw: String): String = if (Widget4x2.PER_WIDGET_KEYS.contains(raw)) Widget4x2.scopedKeyForWidget(raw, widgetId) else raw
    override fun putString(key: String, value: String?) = delegate.putString(key(key), value).let { this }
    override fun putStringSet(key: String, values: Set<String>?) = delegate.putStringSet(key(key), values).let { this }
    override fun putInt(key: String, value: Int) = delegate.putInt(key(key), value).let { this }
    override fun putLong(key: String, value: Long) = delegate.putLong(key(key), value).let { this }
    override fun putFloat(key: String, value: Float) = delegate.putFloat(key(key), value).let { this }
    override fun putBoolean(key: String, value: Boolean) = delegate.putBoolean(key(key), value).let { this }
    override fun remove(key: String) = delegate.remove(key(key)).let { this }
    override fun clear(): android.content.SharedPreferences.Editor {
        for (base in Widget4x2.PER_WIDGET_KEYS) delegate.remove(Widget4x2.scopedKeyForWidget(base, widgetId))
        return this
    }
    override fun commit(): Boolean = delegate.commit()
    override fun apply() { delegate.apply() }
}

private data class PrayerSlot(val key: String, val label: String, val shortLabel: String, val value: Int)

private data class PrayerTimesValue(
    val imsak: Int,
    val fajr: Int,
    val sunrise: Int,
    val dhuhr: Int,
    val asr: Int,
    val sunset: Int,
    val maghrib: Int,
    val isha: Int,
    val midnight: Int,
)

private data class PersianDateValue(val year: Int, val month: Int, val day: Int) {
    fun format(numerical: Boolean, localDigits: Boolean, calendarNameInLinear: Boolean = false): String {
        val value = if (numerical) {
            "$year/$month/$day" + if (calendarNameInLinear) " شمسی" else ""
        } else {
            "$day ${WidgetCalendarData.persianMonth(month)} $year"
        }
        return if (localDigits) WidgetCalendarData.persianDigits(value) else value
    }
}

private data class GregorianDateValue(val year: Int, val month: Int, val day: Int) {
    fun format(numerical: Boolean, localDigits: Boolean, nameSuffix: Boolean = false): String {
        val value = if (numerical) {
            "$year/$month/$day" + if (nameSuffix) " میلادی" else ""
        } else {
            "$day ${WidgetCalendarData.gregorianMonth(month)} $year"
        }
        return if (localDigits) WidgetCalendarData.persianDigits(value) else value
    }
}

private data class IslamicDateValue(val year: Int, val month: Int, val day: Int) {
    fun format(numerical: Boolean, localDigits: Boolean, nameSuffix: Boolean = false): String {
        val value = if (numerical) {
            "$year/$month/$day" + if (nameSuffix) " قمری" else ""
        } else {
            "$day ${WidgetCalendarData.islamicMonth(month)} $year"
        }
        return if (localDigits) WidgetCalendarData.persianDigits(value) else value
    }
}

private data class DateInfo(
    val key: String,
    val weekday: String,
    val persian: PersianDateValue,
    val gregorian: GregorianDateValue,
    val islamic: IslamicDateValue,
) {
    companion object {
        fun fromNow(timeZone: TimeZone = TimeZone.getDefault(), hijriOffset: Int = 0): DateInfo {
            val now = Calendar.getInstance(timeZone)
            val y = now.get(Calendar.YEAR)
            val m = now.get(Calendar.MONTH) + 1
            val d = now.get(Calendar.DAY_OF_MONTH)
            val jdn = WidgetCalendarData.gregorianToJdn(y, m, d)
            val p = WidgetCalendarData.persianFromJdn(jdn)
            val i = WidgetCalendarData.islamicFromJdn(jdn + hijriOffset)
            val weekday = WidgetCalendarData.weekday(now.get(Calendar.DAY_OF_WEEK))
            val gregorian = GregorianDateValue(y, m, d)
            val key = "%04d-%02d-%02d".format(Locale.US, y, m, d)
            return DateInfo(key, weekday, p, gregorian, i)
        }
    }
}

private object WidgetCalendarData {
    private val persianMonths = arrayOf(
        "فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور",
        "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند",
    )
    private val gregorianMonths = arrayOf(
        "ژانویه", "فوریه", "مارس", "آوریل", "مه", "ژوئن",
        "ژوئیه", "اوت", "سپتامبر", "اکتبر", "نوامبر", "دسامبر",
    )
    private val islamicMonths = arrayOf(
        "محرم", "صفر", "ربیع‌الاول", "ربیع‌الثانی", "جمادی‌الاول", "جمادی‌الثانی",
        "رجب", "شعبان", "رمضان", "شوال", "ذوالقعده", "ذوالحجه",
    )
    private val weekdays = arrayOf("شنبه", "یکشنبه", "دوشنبه", "سه‌شنبه", "چهارشنبه", "پنجشنبه", "جمعه")
    private val modernPersianLeapYears = intArrayOf(
        1304, 1309, 1313, 1317, 1321, 1325, 1329, 1333, 1337, 1342, 1346, 1350,
        1354, 1358, 1362, 1366, 1370, 1375, 1379, 1383, 1387, 1391, 1395, 1399,
        1403, 1408, 1412, 1416, 1420, 1424, 1428, 1432, 1436, 1441, 1445, 1449,
        1453, 1457, 1461, 1465, 1469, 1474, 1478, 1482, 1486, 1490, 1494, 1498,
    )
    private const val PERSIAN_START_YEAR = 1304
    private const val PERSIAN_START_JDN = 2424231

    private val iranianIslamicMonths = intArrayOf(
        30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29,
        30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 29, 30, 29, 30, 29, 29,
        30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30,
        29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30,
        29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 29, 30, 30,
        29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 29, 30, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30,
        29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30,
        29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 29, 30,
        30, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30,
        29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29, 30, 29,
        29, 30, 29, 30, 29, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30,
        29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30,
        30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 30, 29, 29, 30,
        29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 30, 29, 30, 29,
        29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 29,
        30, 30, 29, 30, 29, 29, 30, 30, 29, 30, 29, 29, 30, 30, 30, 29, 30, 29, 30, 30, 29, 29, 29, 30,
        29, 30, 30, 29, 30, 30, 29, 30, 30, 29, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29,
        29, 30, 29, 30, 29, 30, 29, 30, 30, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29,
        29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 29,
        30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30,
        29, 29, 30, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 30, 29, 30, 30, 29, 30, 29,
        29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29,
        30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30,
        29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30,
        29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30,
        29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29,
        30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30,
        29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29,
        30, 29, 29, 30, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30,
        30, 29, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30,
        30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29,
        29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29,
        30, 29, 30, 29, 29, 29, 30, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30,
        29, 30, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29,
        30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 29, 30, 30, 30, 29, 29,
        30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 30,
        29, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 30,
        29, 30, 29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29,
        29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29,
        30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30,
        29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30,
        29, 30, 30, 29, 30, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29,
        29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29,
        30, 29, 29, 30, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29,
        30, 30, 29, 30, 30, 30, 29, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29,
        29, 30, 30, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29,
        30, 29, 29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30,
        30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 29, 30,
        30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29,
        30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29,
        30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30,
        29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29,
        30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 30,
        29, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 30, 29,
        30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30,
        29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29,
        30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29, 30,
        29, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30,
        30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29,
        30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29, 30, 29, 29,
        30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 30,
        29, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30,
        29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29,
        30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 30, 29, 30, 30, 29, 30,
        29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 29, 30,
        30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 29, 30,
        30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29,
        30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29,
        30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 29,
        30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29,
        30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30,
        29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29,
        30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30,
        29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 29,
        30, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30,
        29, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30, 30, 30, 30, 29, 29, 29, 30, 29, 29, 29, 30, 30, 30,
        30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30, 29, 29, 30, 29, 30, 29, 30, 29, 29,
        30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 30, 29, 29, 30, 30, 30,
        29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30, 29, 30, 30, 30,
        29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30,
        30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 29, 30,
        29, 29, 30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30,
        29, 30, 29, 29, 29, 30, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 29, 29, 30, 30, 29, 30, 30, 29,
        30, 30, 29, 29, 30, 29, 30, 29, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29,
        30, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30,
        29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30,
        29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 30,
        29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 30, 30, 29, 30, 29, 29, 30, 29, 29,
        30, 29, 30, 30, 30, 29, 30, 30, 29, 29, 30, 29, 29, 30, 29, 30, 30, 29, 30, 30, 29, 30, 29, 30,
        29, 29, 30, 29, 30, 29, 30, 30, 29, 30, 30, 29, 29, 30, 30, 29, 29, 30, 29, 30, 30, 29, 30, 29,
        30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 29, 30, 29, 30, 29, 29,
        30, 30, 30, 29, 30, 30, 29, 30, 29, 29, 29, 30, 29, 30, 30, 29, 30, 30, 30, 29, 30, 29, 29, 29,
        30, 29, 30, 29, 30, 30, 30, 29, 30, 29, 30, 29, 30, 29, 29, 30, 29, 30, 29, 30, 30, 30, 29, 29,
    )
    private val iranianMonthStarts: IntArray = IntArray(iranianIslamicMonths.size).also { result ->
        var jd = 0
        iranianIslamicMonths.forEachIndexed { index, length ->
            result[index] = jd
            jd += length
        }
    }
    private const val IRANIAN_ISLAMIC_START_JDN = 2396005
    private const val IRANIAN_ISLAMIC_START_YEAR = 1264

    fun persianMonth(month: Int) = persianMonths[month - 1]
    fun gregorianMonth(month: Int) = gregorianMonths[month - 1]
    fun islamicMonth(month: Int) = islamicMonths[month - 1]
    fun persianDigits(value: String): String = Tr.digits(value)

    fun weekday(androidDayOfWeek: Int): String = weekdays[(androidDayOfWeek + 5) % 7]

    // Same integer JDN transform used by lib/core/calendar_math.dart.
    fun gregorianToJdn(year: Int, month: Int, day: Int): Int {
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        return day + ((153 * m + 2) / 5) + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private fun persianIsLeap(year: Int): Boolean {
        if (year in 1304..1498) return modernPersianLeapYears.contains(year)
        val cycle = intArrayOf(1, 5, 9, 13, 17, 22, 26, 30)
        val mod = ((year - 1) % 33 + 33) % 33
        return cycle.contains(mod)
    }

    private fun persianMonthDaysBefore(month: Int): Int =
        if (month <= 7) (month - 1) * 31 else 186 + (month - 7) * 30

    private fun persianYearLength(year: Int): Int = if (persianIsLeap(year)) 366 else 365

    private fun persianDaysBeforeYear(year: Int): Int {
        var days = 0
        if (year >= PERSIAN_START_YEAR) {
            var y = PERSIAN_START_YEAR
            while (y < year) {
                days += persianYearLength(y)
                y++
            }
        } else {
            var y = PERSIAN_START_YEAR
            while (y > year) {
                y--
                days -= persianYearLength(y)
            }
        }
        return days
    }

    fun persianToJdn(year: Int, month: Int, day: Int): Int =
        PERSIAN_START_JDN + persianDaysBeforeYear(year) + persianMonthDaysBefore(month) + day - 1

    fun persianFromJdn(jdn: Int): PersianDateValue {
        // The supplied Flutter calendar has an exact modern table through 1498 and a
        // deterministic 33-year compatibility fallback outside that range. Keep the same behavior.
        var year = 1404
        var start = persianToJdn(year, 1, 1)
        if (jdn >= start) {
            while (jdn >= start + persianYearLength(year)) {
                start += persianYearLength(year)
                year++
            }
        } else {
            while (jdn < start) {
                year--
                start -= persianYearLength(year)
            }
        }
        val doy = jdn - start + 1
        val month = if (doy <= 186) ((doy - 1) / 31) + 1 else ((doy - 187) / 30) + 7
        val before = persianMonthDaysBefore(month)
        return PersianDateValue(year, month, doy - before)
    }

    private fun islamicMonthLength(year: Int, month: Int): Int {
        if (month !in 1..12) return 0
        val index = year - IRANIAN_ISLAMIC_START_YEAR
        val flat = index * 12 + month - 1
        if (index >= 0 && flat >= 0 && flat < iranianIslamicMonths.size) {
            return iranianIslamicMonths[flat]
        }
        if (month == 12) {
            val leap = ((11 * year + 14) % 30) < 11
            return if (leap) 30 else 29
        }
        return if (month % 2 == 1) 30 else 29
    }

    private fun islamicToJdn(year: Int, month: Int, day: Int): Int {
        val index = year - IRANIAN_ISLAMIC_START_YEAR
        val flat = index * 12 + month - 1
        if (index >= 0 && flat >= 0 && flat < iranianMonthStarts.size) {
            return IRANIAN_ISLAMIC_START_JDN + iranianMonthStarts[flat] + day - 1
        }
        return day + Math.ceil(29.5 * (month - 1)).toInt() +
            (year - 1) * 354 + Math.floor((3 + 11 * year) / 30.0).toInt() + 1948439 - 1
    }

    fun islamicFromJdn(jdn: Int): IslamicDateValue {
        val days = jdn - IRANIAN_ISLAMIC_START_JDN
        val totalEmbeddedDays = iranianMonthStarts.last() + iranianIslamicMonths.last()
        if (days >= 0 && days < totalEmbeddedDays) {
            var lo = 0
            var hi = iranianMonthStarts.lastIndex
            while (lo < hi) {
                val mid = (lo + hi + 1) / 2
                if (iranianMonthStarts[mid] <= days) lo = mid else hi = mid - 1
            }
            val index = lo
            return IslamicDateValue(
                IRANIAN_ISLAMIC_START_YEAR + index / 12,
                index % 12 + 1,
                days - iranianMonthStarts[index] + 1,
            )
        }
        val year = Math.floor((30.0 * (jdn - 1948439) + 10646.0) / 10631.0).toInt()
        val dayOfYear = jdn - islamicToJdn(year, 1, 1) + 1
        val month = minOf(12, Math.floor((dayOfYear - 1) / 29.5).toInt() + 1)
        val day = jdn - islamicToJdn(year, month, 1) + 1
        return IslamicDateValue(year, month, day)
    }
}

private object PrayerCalculator {
    private data class MethodSpec(
        val fajr: Double,
        val isha: Double,
        val maghrib: Double = 0.0,
        val ishaMinutes: Boolean = false,
        val maghribMinutes: Boolean = true,
        val defaultMidnight: String = "sunsetToSunrise",
    )

    private fun methodSpec(name: String): MethodSpec = when (name.lowercase()) {
        "mwl" -> MethodSpec(18.0, 17.0)
        "isna" -> MethodSpec(15.0, 15.0)
        "egypt" -> MethodSpec(19.5, 17.5)
        "makkah" -> MethodSpec(18.5, 90.0, ishaMinutes = true)
        "karachi" -> MethodSpec(18.0, 18.0)
        "jafari" -> MethodSpec(16.0, 14.0, 4.0, defaultMidnight = "sunsetToFajr", maghribMinutes = false)
        "france" -> MethodSpec(12.0, 12.0)
        "russia" -> MethodSpec(16.0, 15.0)
        "singapore" -> MethodSpec(20.0, 18.0)
        else -> MethodSpec(17.7, 14.0, 4.5, defaultMidnight = "sunsetToFajr", maghribMinutes = false)
    }

    fun calculate(
        year: Int,
        month: Int,
        day: Int,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        timeZoneHours: Double,
        method: String,
        asrHanafi: Boolean,
        highLatitude: String,
        midnightMethod: String,
    ): PrayerTimesValue? {
        val spec = methodSpec(method)
        val jdate = julian(year, month, day) - longitude / (15.0 * 24.0)
        val coords = Coordinates(latitude, longitude, max(elevation, 0.0))
        var imsak = sunAngleTime(jdate, 10.0, 5.0 / 24.0, true, coords)
        var fajr = sunAngleTime(jdate, spec.fajr, 5.0 / 24.0, true, coords)
        val riseAngle = 0.833 + 0.0347 * sqrt(coords.elevation)
        var sunrise = sunAngleTime(jdate, riseAngle, 6.0 / 24.0, true, coords)
        var dhuhr = midDay(jdate, 12.0 / 24.0)
        var asr = asrTime(jdate, if (asrHanafi) 2.0 else 1.0, 13.0 / 24.0, coords)
        var sunset = sunAngleTime(jdate, riseAngle, 18.0 / 24.0, false, coords)
        var maghrib = sunAngleTime(jdate, if (spec.maghribMinutes) 0.0 else spec.maghrib, 18.0 / 24.0, false, coords)
        var isha = sunAngleTime(jdate, if (spec.ishaMinutes) 0.0 else spec.isha, 18.0 / 24.0, false, coords)

        val addToAll = timeZoneHours - longitude / 15.0
        imsak += addToAll
        fajr += addToAll
        sunrise += addToAll
        dhuhr += addToAll
        asr += addToAll
        sunset += addToAll
        maghrib += addToAll
        isha += addToAll

        if (!highLatitude.equals("none", true)) {
            val night = timeDiff(sunset, sunrise)
            imsak = adjustHighLatitude(imsak, sunrise, if (highLatitude.equals("angleBased", true)) 10.0 else 10.0, night, true, highLatitude)
            fajr = adjustHighLatitude(fajr, sunrise, spec.fajr, night, true, highLatitude)
            isha = adjustHighLatitude(isha, sunset, spec.isha, night, false, highLatitude)
            if (!spec.maghribMinutes) maghrib = adjustHighLatitude(maghrib, sunset, spec.maghrib, night, false, highLatitude)
        }

        imsak = fajr - 10.0 / 60.0
        if (spec.maghribMinutes) maghrib = sunset + spec.maghrib / 60.0
        if (spec.ishaMinutes) isha = maghrib + spec.isha / 60.0

        val midnightMode = midnightMethod.ifBlank { spec.defaultMidnight }
        val midnight = when (midnightMode.lowercase()) {
            "sunsettofajr" -> sunset + timeDiff(sunset, fajr) / 2.0
            "maghribtosunrise" -> maghrib + timeDiff(maghrib, sunrise) / 2.0
            "maghribtofajr" -> maghrib + timeDiff(maghrib, fajr) / 2.0
            else -> sunset + timeDiff(sunset, sunrise) / 2.0
        }

        val all = listOf(imsak, fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight)
        if (all.any { it.isNaN() || it.isInfinite() }) return null
        return PrayerTimesValue(
            imsak = fixHourToMinutes(imsak),
            fajr = fixHourToMinutes(fajr),
            sunrise = fixHourToMinutes(sunrise),
            dhuhr = fixHourToMinutes(dhuhr),
            asr = fixHourToMinutes(asr),
            sunset = fixHourToMinutes(sunset),
            maghrib = fixHourToMinutes(maghrib),
            isha = fixHourToMinutes(isha),
            midnight = fixHourToMinutes(midnight),
        )
    }

    private data class Coordinates(val latitude: Double, val longitude: Double, val elevation: Double)

    private fun midDay(jd: Double, time: Double): Double = fixHour(12.0 - sunPosition(jd + time).second)

    private fun sunAngleTime(jd: Double, angle: Double, time: Double, beforeNoon: Boolean, c: Coordinates): Double {
        val decl = sunPosition(jd + time).first
        val noon = midDay(jd, time)
        val latRad = Math.toRadians(c.latitude)
        val angleRad = Math.toRadians(angle)
        val cosArg = (-sin(angleRad) - sin(decl) * sin(latRad)) / (cos(decl) * cos(latRad))
        val hourAngle = Math.toDegrees(acos(cosArg.coerceIn(-1.0, 1.0))) / 15.0
        return noon + if (beforeNoon) -hourAngle else hourAngle
    }

    private fun asrTime(jd: Double, factor: Double, time: Double, c: Coordinates): Double {
        val decl = sunPosition(jd + time).first
        val latRad = Math.toRadians(c.latitude)
        val angle = -kotlin.math.atan(1.0 / (factor + tan(kotlin.math.abs(latRad - decl))))
        return sunAngleTime(jd, Math.toDegrees(angle), time, false, c)
    }

    private fun sunPosition(jd: Double): Pair<Double, Double> {
        val d = jd - 2451545.0
        val g = Math.toRadians((357.529 + 0.98560028 * d).mod(360.0))
        val q = Math.toRadians((280.459 + 0.98564736 * d).mod(360.0))
        val l = Math.toRadians((Math.toDegrees(q) + 1.915 * sin(g) + 0.020 * sin(2.0 * g)).mod(360.0))
        val e = Math.toRadians(23.439 - 0.00000036 * d)
        val ra = Math.toDegrees(atan2(cos(e) * sin(l), cos(l))) / 15.0
        val eqt = Math.toDegrees(q) / 15.0 - fixHour(ra)
        val decl = asin(sin(e) * sin(l))
        return decl to eqt
    }

    private fun julian(year: Int, month: Int, day: Int): Double {
        var y = year
        var m = month
        if (m <= 2) {
            y -= 1
            m += 12
        }
        val a = floor(y / 100.0)
        val b = 2 - a + floor(a / 4.0)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + day + b - 1524.5
    }

    private fun adjustHighLatitude(time: Double, base: Double, angle: Double, night: Double, ccw: Boolean, method: String): Double {
        val factor = when {
            method.equals("angleBased", true) -> angle / 60.0
            method.equals("oneSeventh", true) -> 1.0 / 7.0
            else -> 0.5
        }
        val portion = factor * night
        val diff = if (ccw) timeDiff(time, base) else timeDiff(base, time)
        return if (time.isNaN() || diff > portion) base + if (ccw) -portion else portion else time
    }

    private fun timeDiff(a: Double, b: Double): Double = fixHour(b - a)

    private fun fixHour(a: Double): Double {
        val result = a % 24.0
        return if (result < 0) result + 24.0 else result
    }

    private fun fixHourToMinutes(a: Double): Int {
        val minutes = kotlin.math.round(fixHour(a) * 60.0).toInt()
        return minutes % (24 * 60)
    }
}
