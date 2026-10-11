package com.md6.mooncalendar

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class MoonCalendarTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            label = "Mooncalendar"
            state = Tile.STATE_ACTIVE
            if (Build.VERSION.SDK_INT >= 29) subtitle = getSharedPreferences(Widget4x2.PREFS, MODE_PRIVATE).getString("persian_date", null)
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        startActivityAndCollapse(Intent(this, MainActivity::class.java))
    }
}
