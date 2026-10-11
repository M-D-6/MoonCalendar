package com.md6.mooncalendar

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** One scheduled athan notification. `at` is an absolute epoch in milliseconds. */
data class AthanAlarm(val prayer: String, val at: Long, val title: String, val body: String)

object AthanStore {
    private const val PREFS = "athan_store"
    private const val KEY_ALARMS = "alarms"
    private const val KEY_SOUND = "sound_uri"
    private const val KEY_VIBRATION = "vibration"
    private const val KEY_LAST_KEY = "last_fired_key"
    private const val KEY_CHANNEL_ID = "channel_id"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun defaultSoundUri(context: Context) =
        "android.resource://${context.packageName}/raw/special"

    fun soundUri(context: Context): String =
        prefs(context).getString(KEY_SOUND, null)?.takeIf { it.isNotEmpty() }
            ?: defaultSoundUri(context)

    fun vibration(context: Context): Boolean = prefs(context).getBoolean(KEY_VIBRATION, true)

    fun save(context: Context, alarms: List<AthanAlarm>, soundUri: String?, vibration: Boolean) {
        val array = JSONArray()
        alarms.forEach {
            array.put(
                JSONObject()
                    .put("prayer", it.prayer)
                    .put("at", it.at)
                    .put("title", it.title)
                    .put("body", it.body),
            )
        }
        val editor = prefs(context).edit()
            .putString(KEY_ALARMS, array.toString())
            .putBoolean(KEY_VIBRATION, vibration)
        if (soundUri == null) {
            editor.remove(KEY_SOUND)
        } else {
            editor.putString(KEY_SOUND, soundUri)
        }
        editor.apply()
    }

    fun loadAlarms(context: Context): List<AthanAlarm> = runCatching {
        val array = JSONArray(prefs(context).getString(KEY_ALARMS, "[]"))
        (0 until array.length()).map {
            val o = array.getJSONObject(it)
            AthanAlarm(
                o.getString("prayer"),
                o.getLong("at"),
                o.getString("title"),
                o.getString("body"),
            )
        }
    }.getOrDefault(emptyList())

    fun hasChannelId(context: Context): Boolean = prefs(context).contains(KEY_CHANNEL_ID)

    fun channelId(context: Context): Int = prefs(context).getInt(KEY_CHANNEL_ID, 3005)

    fun setChannelId(context: Context, value: Int) {
        prefs(context).edit().putInt(KEY_CHANNEL_ID, value).apply()
    }

    fun lastFiredKey(context: Context): String? = prefs(context).getString(KEY_LAST_KEY, null)

    fun setLastFiredKey(context: Context, value: String) {
        prefs(context).edit().putString(KEY_LAST_KEY, value).apply()
    }
}
