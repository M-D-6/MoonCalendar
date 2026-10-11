package com.md6.mooncalendar

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import java.util.Calendar

/**
 * Switches the launcher icon between the default "M" icon and one of 31
 * day-number icons (activity-aliases), so the icon always shows today's
 * solar-hijri day. The date -> day table is supplied by Flutter (so the
 * app's own calendar, offsets included, stays the single source of truth).
 */
object AppIconManager {
    private const val PREFS = "mooncalendar_app_icon"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_TABLE = "table"
    private const val PKG = "com.md6.mooncalendar"

    private fun alias(context: Context, suffix: String) = ComponentName(context, "$PKG.$suffix")

    fun sync(context: Context, enabled: Boolean, table: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putString(KEY_TABLE, table)
            .apply()
        refresh(context)
    }

    private fun todayKey(): String {
        val c = Calendar.getInstance()
        return "%04d-%02d-%02d".format(c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
    }

    private fun todayDay(table: String): Int? {
        val key = todayKey()
        for (part in table.split(',')) {
            val i = part.indexOf(':')
            if (i > 0 && part.substring(0, i) == key) return part.substring(i + 1).toIntOrNull()
        }
        return null
    }

    /**
     * Switching the enabled launcher alias makes many launchers / OEM ROMs
     * finish the task that was started from the old alias, i.e. the app closes
     * under the user's fingers. So the switch is never performed while one of
     * our activities is visible; it is applied as soon as the app goes to the
     * background (see [AppVisibility]) or from the midnight alarm.
     */
    fun refresh(context: Context) {
        if (AppVisibility.isForeground) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_ENABLED, false)
        val day = if (enabled) todayDay(prefs.getString(KEY_TABLE, "").orEmpty())?.takeIf { it in 1..31 } else null
        val target = if (day != null) "LauncherDay%02d".format(day) else "LauncherDefault"
        val pm = context.packageManager
        // Enable the new alias first, then disable the others, so the launcher entry never disappears.
        val all = listOf("LauncherDefault") + (1..31).map { "LauncherDay%02d".format(it) }
        val targetComponent = alias(context, target)
        if (pm.getComponentEnabledSetting(targetComponent) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            pm.setComponentEnabledSetting(targetComponent, PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        }
        for (name in all) {
            if (name == target) continue
            val c = alias(context, name)
            val state = pm.getComponentEnabledSetting(c)
            val isEnabled = state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "LauncherDefault")
            if (isEnabled) pm.setComponentEnabledSetting(c, PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        }
    }
}
