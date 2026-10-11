package com.md6.mooncalendar

import android.graphics.Color
import android.graphics.Typeface
import android.service.dreams.DreamService
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView

class MoonCalendarDreamService : DreamService() {
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isInteractive = false
        isFullscreen = true
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
        }
        val prefs = getSharedPreferences(Widget4x2.PREFS, MODE_PRIVATE)
        val date = prefs.getString("persian_date", "Mooncalendar") ?: "Mooncalendar"
        val greg = prefs.getString("gregorian", "") ?: ""
        root.addView(text(date, 44f))
        root.addView(text(greg, 22f))
        setContentView(root)
    }

    private fun text(value: String, size: Float) = TextView(this).apply {
        text = value
        setTextColor(Color.WHITE)
        textSize = size
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(16, 10, 16, 10)
    }
}
