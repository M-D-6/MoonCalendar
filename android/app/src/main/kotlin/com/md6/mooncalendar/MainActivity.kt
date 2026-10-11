package com.md6.mooncalendar

import android.Manifest
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewTreeObserver
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity(), SensorEventListener {
    private val methodName = "com.md6.Mooncalendar/platform"
    private val compassName = "com.md6.Mooncalendar/compass"
    private val levelName = "com.md6.Mooncalendar/level"
    private val launchName = "com.md6.Mooncalendar/launch"
    private var compassSink: EventChannel.EventSink? = null
    private var levelSink: EventChannel.EventSink? = null
    private var sensorManager: SensorManager? = null
    private var accelerometer: FloatArray? = null
    private var magnetometer: FloatArray? = null
    private val levelI = FloatArray(16)
    private val levelR = FloatArray(16)
    private val levelOutR = FloatArray(16)
    private val levelLoc = FloatArray(3)
    private var smoothedCompass = 0f
    private var athan: AthanChannel? = null
    private var launchSink: EventChannel.EventSink? = null
    private val widgetExecutor = java.util.concurrent.Executors.newSingleThreadExecutor { r ->
        Thread(r, "MoonCalendarWidgetSync").apply { isDaemon = true }
    }

    // Android 12+: the system splash (animated icon) must be held until Flutter has drawn its first frame - which
    // shows the very same finished icon - and for as long as the animation lasts. Without this the system splash
    // is dismissed as soon as the window draws the launch drawable, the icon is cut mid-animation, a gap appears
    // and the icon "goes and comes back".
    private var splashHeld = false
    private var flutterShown = false
    private var minSplashElapsed = false

    private fun freeSplash() {
        if (!splashHeld) return
        splashHeld = false
        // A blocked pre-draw is not retried by itself: ask for a new frame.
        findViewById<android.view.View>(android.R.id.content)?.invalidate()
    }

    private fun releaseSplashIfReady() {
        if (flutterShown && minSplashElapsed) freeSplash()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= 31 && savedInstanceState == null) {
            splashHeld = true
            val content = findViewById<android.view.View>(android.R.id.content)
            content.viewTreeObserver.addOnPreDrawListener(object : ViewTreeObserver.OnPreDrawListener {
                override fun onPreDraw(): Boolean {
                    if (splashHeld) return false
                    content.viewTreeObserver.removeOnPreDrawListener(this)
                    return true
                }
            })
            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({ minSplashElapsed = true; releaseSplashIfReady() }, 950)
            // Safety net: never keep the splash longer than this, whatever happens.
            handler.postDelayed({ freeSplash() }, 2500)
        }
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterShown = true
        releaseSplashIfReady()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        athan = AthanChannel(this).also { it.register(flutterEngine.dartExecutor.binaryMessenger) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasCompass" -> result.success(hasMagneticSensors() || sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null)
                "startCompass" -> { compassWanted = true; syncSensors(); result.success(null) }
                "stopCompass" -> { compassWanted = false; syncSensors(); result.success(null) }
                "hasLevel" -> result.success(sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null)
                "startLevel" -> { levelWanted = true; syncSensors(); result.success(null) }
                "stopLevel" -> { levelWanted = false; syncSensors(); result.success(null) }
                "getScreenDpi" -> {
                    val dm = resources.displayMetrics
                    result.success(mapOf("xdpi" to dm.xdpi.toDouble(), "ydpi" to dm.ydpi.toDouble()))
                }
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "openLocationSettings" -> { startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); result.success(null) }
                "openLiveWallpaper" -> openWallpaper(result)
                "openDreamSettings" -> { startActivity(Intent(Settings.ACTION_DREAM_SETTINGS)); result.success(null) }
                "openBatterySettings" -> { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(null) }
                "refreshWidgets" -> {
                    val appContext = applicationContext
                    widgetExecutor.execute {
                        runCatching { Widget4x2.updateAll(appContext) }
                        runCatching { WidgetCounter.updateAll(appContext) }
                        runCatching { WidgetMoon.updateAll(appContext) }
                        runCatching { WidgetMap.updateAll(appContext) }
                        runCatching { WidgetSunView.updateAll(appContext) }
                    }
                    result.success(null)
                }
                "refreshCounterWidgets" -> {
                    val appContext = applicationContext
                    widgetExecutor.execute { runCatching { WidgetCounter.updateAll(appContext) } }
                    result.success(null)
                }
                "syncWidgetData" -> { syncWidgetData(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                "counterVibrate" -> {
                    val duration = (call.argument<Number>("duration")?.toLong() ?: 80L).coerceIn(10L, 300L)
                    val amplitude = (call.argument<Number>("amplitude")?.toInt() ?: 180).coerceIn(1, 255)
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                            val vibrator = manager.defaultVibrator
                            if (vibrator.hasVibrator()) {
                                vibrator.vibrate(android.os.VibrationEffect.createOneShot(duration, amplitude))
                            }
                        } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            @Suppress("DEPRECATION")
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
                            if (vibrator.hasVibrator()) {
                                vibrator.vibrate(android.os.VibrationEffect.createOneShot(duration, amplitude))
                            }
                        } else {
                            @Suppress("DEPRECATION")
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
                            vibrator.vibrate(duration)
                        }
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "counterTargetSound" -> {
                    try {
                        val tone = android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION, 100)
                        Thread {
                            try {
                                tone.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 400)
                            } finally {
                                tone.release()
                            }
                        }.start()
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "getLaunchAction" -> result.success(intent?.action ?: "")
                "requestCalendarPermission" -> requestCalendarPermission(result)
                "hasCalendarPermission" -> result.success(checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED)
                "getDeviceCalendarEvents" -> result.success(readCalendarEvents(call.argument<Long>("startMs") ?: 0L, call.argument<Long>("endMs") ?: 0L))
                "getSystemTheme" -> {
                    // Fresh context each call so a night-mode switch or a new Monet palette is seen live.
                    val fresh = createConfigurationContext(android.content.res.Configuration(resources.configuration))
                    val uiMode = fresh.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
                    val dark = uiMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
                    val seed = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                        fresh.resources.getColor(android.R.color.system_accent1_600, fresh.theme)
                    } else {
                        val typed = theme.obtainStyledAttributes(intArrayOf(android.R.attr.colorAccent))
                        try { typed.getColor(0, 0xFF00796B.toInt()) } finally { typed.recycle() }
                    }
                    result.success(mapOf("seedColor" to seed, "dark" to dark, "sdk" to android.os.Build.VERSION.SDK_INT))
                }
                "getDeclination" -> {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    val altitude = call.argument<Double>("altitude") ?: 0.0
                    val time = call.argument<Long>("time") ?: System.currentTimeMillis()
                    if (latitude == null || longitude == null) result.success(0.0) else {
                        val field = GeomagneticField(latitude.toFloat(), longitude.toFloat(), altitude.toFloat(), time)
                        result.success(field.declination.toDouble())
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, compassName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { compassSink = events; compassWanted = true; syncSensors() }
            override fun onCancel(arguments: Any?) { compassSink = null; compassWanted = false; syncSensors() }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, levelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { levelSink = events; levelWanted = true; syncSensors() }
            override fun onCancel(arguments: Any?) { levelSink = null; levelWanted = false; syncSensors() }
        })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, launchName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { launchSink = events; events?.success(intent?.action ?: "") }
            override fun onCancel(arguments: Any?) { launchSink = null }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchSink?.success(intent.action ?: "")
    }

    // The compass and the level share the same accelerometer / magnetometer listener. Each screen only
    // says whether IT wants readings; the listener is unregistered only when neither does, so closing one
    // screen (compass -> level switch) never switches the sensors off under the screen that just opened.
    private var compassWanted = false
    private var levelWanted = false
    private var sensorsOn = false

    private fun syncSensors() {
        val sm = sensorManager ?: return
        val wanted = compassWanted || levelWanted
        if (wanted && !sensorsOn) {
            sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
            sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
            // Devices that report orientation only through the fused rotation-vector sensor.
            if (!hasMagneticSensors()) {
                sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
            }
            sensorsOn = true
        } else if (!wanted && sensorsOn) {
            sm.unregisterListener(this)
            sensorsOn = false
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                accelerometer = event.values.clone()
                updateLevel(event.values)
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                magnetometer = event.values.clone()
                updateCompass()
            }
            Sensor.TYPE_ROTATION_VECTOR -> {
                val rotation = FloatArray(9)
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                val orientation = FloatArray(3)
                SensorManager.getOrientation(rotation, orientation)
                publishHeading(Math.toDegrees(orientation[0].toDouble()).toFloat())
            }
        }
    }

    private fun updateCompass() {
        val gravity = accelerometer ?: return
        val magnetic = magnetometer ?: return
        val rotation = FloatArray(9)
        val inclination = FloatArray(9)
        if (!SensorManager.getRotationMatrix(rotation, inclination, gravity, magnetic)) return
        val orientation = FloatArray(3)
        SensorManager.getOrientation(rotation, orientation)
        publishHeading(Math.toDegrees(orientation[0].toDouble()).toFloat())
    }

    private fun hasMagneticSensors(): Boolean =
        sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null &&
            sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null

    private fun publishHeading(raw: Float) {
        var target = (raw + displayRotationDegrees()) % 360f
        if (target < 0f) target += 360f
        val delta = ((target - smoothedCompass + 540f) % 360f) - 180f
        smoothedCompass += 0.15f * delta
        if (smoothedCompass < 0f) smoothedCompass += 360f
        if (smoothedCompass >= 360f) smoothedCompass -= 360f
        compassSink?.success(smoothedCompass.toDouble())
    }

    private fun updateLevel(values: FloatArray) {
        // Port of the Persian Calendar OrientationProvider: accelerometer only,
        // display-orientation remap, pitch/roll/balance and 0.8° level threshold.
        if (!SensorManager.getRotationMatrix(levelR, levelI, values, floatArrayOf(1f, 1f, 1f))) return
        when (windowManager.defaultDisplay.rotation) {
            android.view.Surface.ROTATION_270 -> SensorManager.remapCoordinateSystem(levelR, SensorManager.AXIS_MINUS_Y, SensorManager.AXIS_X, levelOutR)
            android.view.Surface.ROTATION_180 -> SensorManager.remapCoordinateSystem(levelR, SensorManager.AXIS_MINUS_X, SensorManager.AXIS_MINUS_Y, levelOutR)
            android.view.Surface.ROTATION_90 -> SensorManager.remapCoordinateSystem(levelR, SensorManager.AXIS_Y, SensorManager.AXIS_MINUS_X, levelOutR)
            else -> SensorManager.remapCoordinateSystem(levelR, SensorManager.AXIS_X, SensorManager.AXIS_Y, levelOutR)
        }
        SensorManager.getOrientation(levelOutR, levelLoc)
        val pitch = Math.toDegrees(levelLoc[1].toDouble()).toFloat()
        val roll = -Math.toDegrees(levelLoc[2].toDouble()).toFloat()
        var tmp = kotlin.math.hypot(levelOutR[8], levelOutR[9])
        tmp = if (tmp == 0f) 0f else levelOutR[8] / tmp
        val balance = Math.toDegrees(kotlin.math.asin(tmp.toDouble())).toFloat()
        levelSink?.success(mapOf("pitch" to pitch.toDouble(), "roll" to roll.toDouble(), "balance" to balance.toDouble()))
    }

    private fun displayRotationDegrees(): Float = when (windowManager.defaultDisplay.rotation) {
        android.view.Surface.ROTATION_0 -> 0f
        android.view.Surface.ROTATION_90 -> 90f
        android.view.Surface.ROTATION_180 -> 180f
        android.view.Surface.ROTATION_270 -> 270f
        else -> 0f
    }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED) {
            result.success(true); return
        }
        pendingCalendarResult = result
        requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), CALENDAR_PERMISSION_REQUEST)
    }

    private var pendingCalendarResult: MethodChannel.Result? = null
    private fun readCalendarEvents(startMs: Long, endMs: Long): List<Map<String, Any?>> {
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val output = mutableListOf<Map<String, Any?>>()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().appendPath(startMs.toString()).appendPath(endMs.toString()).build()
        val projection = arrayOf(CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
        contentResolver.query(uri, projection, null, null, CalendarContract.Instances.BEGIN + " ASC")?.use { c ->
            val id = c.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID)
            val title = c.getColumnIndexOrThrow(CalendarContract.Instances.TITLE)
            val begin = c.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN)
            val end = c.getColumnIndexOrThrow(CalendarContract.Instances.END)
            val allDay = c.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY)
            val calendar = c.getColumnIndexOrThrow(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
            while (c.moveToNext()) output += mapOf("id" to c.getLong(id), "title" to (c.getString(title) ?: ""), "startMs" to c.getLong(begin), "endMs" to c.getLong(end), "allDay" to (c.getInt(allDay) != 0), "calendar" to (c.getString(calendar) ?: ""))
        }
        return output
    }

    private fun syncWidgetData(data: Map<*, *>) {
        val p = getSharedPreferences(Widget4x2.PREFS, Context.MODE_PRIVATE).edit()
        val booleanKeys = setOf(
            Widget4x2.PREF_WIDGET_CLOCK,
            Widget4x2.PREF_WIDGET_IN_24,
            Widget4x2.PREF_WIDGET_SHOW_SECONDS,
            Widget4x2.PREF_WIDGET_EDGE_ALIGN,
            Widget4x2.PREF_CENTER_ALIGN_WIDGETS,
            Widget4x2.PREF_IRAN_TIME,
            Widget4x2.PREF_LOCAL_NUMERAL,
            Widget4x2.PREF_NUMERICAL_DATE,
            Widget4x2.PREF_WIDGETS_PREFER_SYSTEM_COLORS,
            Widget4x2.PREF_ASR_HANAFI,
        )
        data.forEach { (k, v) ->
            if (k == null || v == null) return@forEach
            val key = k.toString()
            when {
                key == Widget4x2.PREF_WHAT_TO_SHOW_WIDGETS -> {
                    val values = v.toString().split(',').map(String::trim).filter(String::isNotEmpty).toSet()
                    p.putStringSet(Widget4x2.PREF_WHAT_TO_SHOW_WIDGETS, values)
                }
                key in booleanKeys -> {
                    p.putBoolean(key, v.toString().equals("true", ignoreCase = true))
                }
                key == Widget4x2.PREF_WIDGET_TRANSPARENCY -> {
                    p.putFloat(key, v.toString().toFloatOrNull()?.coerceIn(0f, 1f) ?: 0f)
                }
                else -> p.putString(key, v.toString())
            }
        }
        p.putString("updated", SimpleDateFormat("HH:mm", Locale.US).format(Date()))
        p.apply()
        // Rendering widget RemoteViews (text fitting, prayer times, bitmaps) must never run on the
        // platform/UI thread: it froze the app right after it was opened from a widget.
        val appContext = applicationContext
        widgetExecutor.execute { runCatching { Widget4x2.updateAll(appContext) } }
    }

    private fun openWallpaper(result: MethodChannel.Result) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= 16) {
                val i = Intent(android.app.WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
                    putExtra(android.app.WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, android.content.ComponentName(this@MainActivity, MoonCalendarWallpaperService::class.java))
                }
                startActivity(i)
            } else startActivity(Intent(android.app.WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
            result.success(null)
        } catch (_: Exception) { result.error("WALLPAPER", "Unable to open live wallpaper settings", null) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == CALENDAR_PERMISSION_REQUEST) {
            val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingCalendarResult?.success(ok)
            pendingCalendarResult = null
            return
        }
        if (athan?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (athan?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    override fun onDestroy() { compassWanted = false; levelWanted = false; syncSensors(); widgetExecutor.shutdown(); super.onDestroy() }

    companion object { private const val CALENDAR_PERMISSION_REQUEST = 4102 }
}
