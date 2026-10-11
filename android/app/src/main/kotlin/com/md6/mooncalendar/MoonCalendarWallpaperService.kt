package com.md6.mooncalendar

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder

class MoonCalendarWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = EngineImpl()

    private inner class EngineImpl : Engine() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.DEFAULT_BOLD }
        private var visible = false

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            if (visible) draw()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            draw()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
        }

        private fun draw() {
            if (!visible) return
            val canvas = runCatching { surfaceHolder.lockCanvas() }.getOrNull() ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val prefs = applicationContext.getSharedPreferences(Widget4x2.PREFS, MODE_PRIVATE)
                val date = prefs.getString("persian_date", "Mooncalendar") ?: "Mooncalendar"
                val greg = prefs.getString("gregorian", "") ?: ""
                val prayer = prefs.getString("prayer", "") ?: ""
                paint.color = Color.WHITE
                paint.textAlign = Paint.Align.CENTER
                paint.textSize = (canvas.width * 0.075f).coerceAtLeast(34f)
                canvas.drawText(date, canvas.width / 2f, canvas.height * 0.42f, paint)
                paint.color = Color.LTGRAY
                paint.textSize = (canvas.width * 0.035f).coerceAtLeast(18f)
                canvas.drawText(greg, canvas.width / 2f, canvas.height * 0.50f, paint)
                if (prayer.isNotBlank()) canvas.drawText(prayer, canvas.width / 2f, canvas.height * 0.57f, paint)
            } finally {
                surfaceHolder.unlockCanvasAndPost(canvas)
            }
        }
    }
}
