package com.md6.mooncalendar

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.IntentCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/** Flutter <-> native bridge for athan scheduling, permissions and sound picking. */
class AthanChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "com.md6.Mooncalendar/athan"
        private const val REQ_NOTIFICATION = 7101
        private const val REQ_RINGTONE = 7102
        private const val REQ_AUDIO_FILE = 7103
    }

    private var pending: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler(this)
    }

    private fun status(): Map<String, Any> = mapOf(
        "notifications" to notificationsEnabled(),
        "exactAlarms" to AthanScheduler.canScheduleExact(activity),
        "sdk" to Build.VERSION.SDK_INT,
    )

    private fun notificationsEnabled(): Boolean {
        val enabled = androidx.core.app.NotificationManagerCompat.from(activity).areNotificationsEnabled()
        if (!enabled) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val list = call.argument<List<Map<String, Any?>>>("alarms").orEmpty()
                val alarms = list.mapNotNull {
                    runCatching {
                        AthanAlarm(
                            prayer = it["prayer"] as String,
                            at = (it["at"] as Number).toLong(),
                            title = it["title"] as String,
                            body = it["body"] as String,
                        )
                    }.getOrNull()
                }
                val sound = call.argument<String>("soundUri")?.takeIf { it.isNotBlank() }
                val vibration = call.argument<Boolean>("vibration") ?: true
                val soundChanged = sound != null && sound != AthanStore.soundUri(activity)
                val vibrationChanged = vibration != AthanStore.vibration(activity)
                if (soundChanged || vibrationChanged) {
                    AthanNotifier.invalidateChannel(activity)
                }
                AthanStore.save(activity, alarms, sound, vibration)
                if (alarms.isEmpty()) {
                    AthanScheduler.cancel(activity)
                } else {
                    AthanScheduler.reschedule(activity)
                }
                result.success(status() + mapOf("count" to alarms.size))
            }

            "cancelAll" -> {
                AthanStore.save(activity, emptyList(), null, AthanStore.vibration(activity))
                AthanScheduler.cancel(activity)
                result.success(null)
            }

            "status" -> result.success(status())

            "syncDateNotification" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val lockScreen = call.argument<Boolean>("lockScreen") ?: true
                val largeDayNumber = call.argument<Boolean>("largeDayNumber") ?: true
                val rtl = call.argument<Boolean>("rtl") ?: true
                val list = call.argument<List<Map<String, Any?>>>("notifications").orEmpty()
                val payloads = list.mapNotNull { item ->
                    val date = item["date"]?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    val title = item["title"]?.toString().orEmpty()
                    val body = item["body"]?.toString().orEmpty()
                    mapOf("date" to date, "title" to title, "body" to body, "day" to (item["day"]?.toString().orEmpty()), "latin" to (item["latin"]?.toString().orEmpty()), "styles" to (item["styles"]?.toString().orEmpty()))
                }
                DateNotificationStore.sync(activity, enabled, lockScreen, largeDayNumber, payloads, rtl)
                result.success(null)
            }

            "syncAppIcon" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val table = call.argument<String>("table").orEmpty()
                AppIconManager.sync(activity, enabled, table, call.argument<Boolean>("latin") ?: false)
                result.success(null)
            }

            "setNotificationTemperature" -> {
                DateNotificationStore.setTemperature(activity, call.argument<String>("text").orEmpty())
                result.success(null)
            }

            "openUrl" -> {
                val url = call.argument<String>("url")
                result.success(
                    try {
                        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        true
                    } catch (_: Exception) {
                        false
                    }
                )
            }
            "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "updateDir" -> result.success(File(activity.cacheDir, "mooncalendar_update").apply { mkdirs() }.absolutePath)
            "installApk" -> {
                val path = call.argument<String>("path")
                result.success(if (path == null) "error:no file" else installApk(File(path)))
            }
            "cancelDateNotification" -> {
                DateNotificationStore.cancel(activity)
                result.success(null)
            }

            "preview" -> {
                val alarm = AthanAlarm(
                    prayer = call.argument<String>("prayer") ?: "fajr",
                    at = System.currentTimeMillis(),
                    title = call.argument<String>("title") ?: "اذان",
                    body = call.argument<String>("body") ?: "",
                )
                AthanNotifier.show(
                    activity,
                    alarm,
                    call.argument<String>("soundUri"),
                    call.argument<Boolean>("vibration"),
                )
                result.success(null)
            }

            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    result.success(notificationsEnabled())
                } else if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(notificationsEnabled())
                } else if (pending != null) {
                    result.error("busy", "Another request is in progress", null)
                } else {
                    pending = result
                    activity.requestPermissions(
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATION,
                    )
                }
            }

            "openNotificationSettings" -> {
                launch(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName),
                )
                result.success(null)
            }

            "openExactAlarmSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    launch(
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            .setData(Uri.parse("package:${activity.packageName}")),
                    )
                }
                result.success(null)
            }

            "openBatterySettings" -> {
                launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                result.success(null)
            }

            "pickRingtone" -> {
                if (pending != null) return result.error("busy", "Another request is in progress", null)
                pending = result
                val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                    .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALL)
                    .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                    .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                    .putExtra(
                        RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                        Settings.System.DEFAULT_NOTIFICATION_URI,
                    )
                if (!startForResult(intent, REQ_RINGTONE)) finishPending(null)
            }

            "pickAudioFile" -> {
                if (pending != null) return result.error("busy", "Another request is in progress", null)
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("audio/*")
                if (!startForResult(intent, REQ_AUDIO_FILE)) finishPending(null)
            }

            "reverseGeocode" -> {
                val lat = call.argument<Double>("latitude")
                val lon = call.argument<Double>("longitude")
                if (lat == null || lon == null) return result.success(null)

                val locale = runCatching {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                        activity.resources.configuration.locales[0]
                    } else {
                        @Suppress("DEPRECATION") activity.resources.configuration.locale
                    }
                }.getOrDefault(Locale("fa"))
                val geocoder = Geocoder(activity, locale)

                fun emit(address: android.location.Address?) {
                    val out = address?.let {
                        mapOf(
                            "city" to listOf(it.locality, it.subAdminArea, it.adminArea).firstOrNull { v -> !v.isNullOrBlank() },
                            "country" to it.countryName,
                            "countryCode" to it.countryCode,
                        )
                    }
                    activity.runOnUiThread { result.success(out) }
                }

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    geocoder.getFromLocation(lat, lon, 1) { addresses ->
                        emit(addresses.firstOrNull())
                    }
                } else {
                    Thread {
                        val address = runCatching {
                            @Suppress("DEPRECATION") geocoder.getFromLocation(lat, lon, 1)?.firstOrNull()
                        }.getOrNull()
                        emit(address)
                    }.start()
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun launch(intent: Intent) {
        runCatching { activity.startActivity(intent) }.onFailure {
            runCatching {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:${activity.packageName}")),
                )
            }
        }
    }

    private fun startForResult(intent: Intent, code: Int): Boolean =
        runCatching { activity.startActivityForResult(intent, code) }.isSuccess

    private fun finishPending(value: Any?) {
        val r = pending
        pending = null
        r?.success(value)
    }

    fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQ_NOTIFICATION) return false
        finishPending(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        return true
    }

    @Suppress("UNUSED_PARAMETER")
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQ_RINGTONE -> {
                val uri = if (resultCode == Activity.RESULT_OK && data != null) {
                    IntentCompat.getParcelableExtra(
                        data, RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java,
                    )
                } else null
                if (uri == null) {
                    finishPending(null)
                } else {
                    val title = runCatching {
                        RingtoneManager.getRingtone(activity, uri)?.getTitle(activity)
                    }.getOrNull().orEmpty()
                    finishPending(mapOf("uri" to uri.toString(), "name" to title))
                }
                return true
            }

            REQ_AUDIO_FILE -> {
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                if (uri == null) {
                    finishPending(null)
                } else {
                    val copied = runCatching { copyAudio(uri) }.getOrNull()
                    finishPending(copied)
                }
                return true
            }
        }
        return false
    }

    private fun displayName(uri: Uri): String? = runCatching {
        activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
    }.getOrNull()

    /** Copies a picked document into durable app storage and exposes it through FileProvider. */
    private fun copyAudio(uri: Uri): Map<String, String>? {
        val name = displayName(uri) ?: "athan"
        val safe = name.replace(Regex("[^\\p{L}\\p{N}._-]"), "_")
        val dir = (activity.getExternalFilesDir(Environment.DIRECTORY_ALARMS)
            ?: File(activity.filesDir, "Alarms")).apply { mkdirs() }
        val out = File(dir, safe)
        activity.contentResolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        val shared = FileProvider.getUriForFile(activity, "${activity.packageName}.provider", out)
        return mapOf("uri" to shared.toString(), "name" to name)
    }

    /**
     * Opens the system package installer for a downloaded update. Returns "ok", "permission" (the user still has to
     * allow installs from this app; its settings page is opened) or "error:<reason>".
     */
    private fun installApk(file: File): String {
        if (!file.exists()) return "error:the downloaded file is missing (${file.path})"
        var stage = "start"
        return try {
            stage = "permission check"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
                activity.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return "permission"
            }
            stage = "file provider"
            val uri = FileProvider.getUriForFile(activity, activity.packageName + ".provider", file)
            stage = "start installer"
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            // Some installers only honour the grant when the URI also travels as clip data.
            intent.clipData = android.content.ClipData.newRawUri("", uri)
            activity.startActivity(intent)
            "ok"
        } catch (e: Exception) {
            "error:[$stage] ${e.javaClass.simpleName}: ${e.message} | sdk=${Build.VERSION.SDK_INT} " +
                "size=${file.length()} path=${file.path} authority=${activity.packageName}.provider"
        }
    }
}
