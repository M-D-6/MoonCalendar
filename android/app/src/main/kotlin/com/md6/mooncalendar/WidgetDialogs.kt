package com.md6.mooncalendar

import android.app.Activity
import android.app.Dialog
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The one dialog style used by every widget settings screen (same card as [WidgetColorPicker]):
 * rounded surface, title + subtitle, separate rounded rows, accent coloured controls and pill buttons.
 * Used for transparency, content, prayer times, city lists, coordinates and GPS.
 */
object WidgetDialogs {

    class Handle(val dialog: Dialog, private val messageView: TextView?) {
        fun dismiss() = dialog.dismiss()
        fun setMessage(text: String) { messageView?.text = Tr.t(text) }
    }

    class Field(val label: String, val initial: String, val ltr: Boolean = true, val numeric: Boolean = false)

    /** A themed switch row shown above the fields of [form]. */
    class Toggle(val title: String, val summary: String?, val initial: Boolean, val onChanged: (Boolean) -> Unit)

    private fun ui(activity: Activity, value: Int): Int = WidgetSettingsUi.dp(activity, value)

    private fun surface(activity: Activity): Int =
        if (isDark(activity)) 0xFF1F2024.toInt() else 0xFFFAFAFB.toInt()

    private fun isDark(activity: Activity): Boolean =
        (activity.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

    /** A faint accent wash used for selected rows / chips. */
    private fun tint(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    private fun rowBackground(activity: Activity, selected: Boolean) =
        WidgetSettingsUi.roundedBackground(
            activity,
            if (selected) tint(WidgetSettingsUi.accentColor(activity), 34) else tint(WidgetSettingsUi.primaryColor(activity), 14),
            16f,
            stroke = false,
        )

    private fun persianDigits(value: Int): String = Tr.digits(value.toString())

    // ------------------------------------------------------------------------------- the card

    /**
     * Generic card dialog. [onPositive] returns true when the dialog may close (false keeps it open,
     * e.g. after validation failed). A null [positiveText] / [negativeText] hides that button.
     */
    fun show(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        body: View? = null,
        message: String? = null,
        positiveText: String? = "تأیید",
        negativeText: String? = "انصراف",
        neutralText: String? = null,
        onNeutral: (() -> Unit)? = null,
        tallList: Boolean = false,
        surfaceOverride: Int? = null,
        onPositive: (() -> Boolean)? = null,
    ): Handle {
        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            background = WidgetSettingsUi.roundedBackground(activity, surfaceOverride ?: surface(activity), 28f, stroke = true)
            clipToOutline = true
        }
        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(ui(activity, 22), ui(activity, 18), ui(activity, 22), ui(activity, 6))
        }
        header.addView(TextView(activity).apply {
            text = Tr.t(title)
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.START
            setTextColor(WidgetSettingsUi.primaryColor(activity))
        }, LinearLayout.LayoutParams(-1, -2))
        if (!subtitle.isNullOrBlank()) header.addView(TextView(activity).apply {
            text = Tr.t(subtitle)
            textSize = 12f
            gravity = Gravity.START
            setPadding(0, ui(activity, 3), 0, 0)
            setTextColor(WidgetSettingsUi.secondaryColor(activity))
        }, LinearLayout.LayoutParams(-1, -2))
        card.addView(header, LinearLayout.LayoutParams(-1, -2))

        var messageView: TextView? = null
        if (message != null) {
            messageView = TextView(activity).apply {
                text = Tr.t(message)
                textSize = 14f
                gravity = Gravity.START
                setLineSpacing(0f, 1.15f)
                setPadding(ui(activity, 22), ui(activity, 8), ui(activity, 22), ui(activity, 8))
                setTextColor(WidgetSettingsUi.primaryColor(activity))
            }
            card.addView(messageView, LinearLayout.LayoutParams(-1, -2))
        }
        if (body != null) {
            if (body is ListView) {
                card.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
            } else {
                val scroll = ScrollView(activity).apply {
                    isVerticalScrollBarEnabled = false
                    overScrollMode = View.OVER_SCROLL_NEVER
                    addView(body, ViewGroup.LayoutParams(-1, -2))
                }
                // weight 1 lets the body shrink and scroll while the buttons below always stay visible
                card.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            }
        }

        val dialog = Dialog(activity)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        if (neutralText != null) {
            val neutral = WidgetSettingsUi.button(activity, neutralText, false).apply {
                setOnClickListener { onNeutral?.invoke(); dialog.dismiss() }
            }
            card.addView(neutral, LinearLayout.LayoutParams(-1, ui(activity, 46)).apply {
                setMargins(ui(activity, 22), ui(activity, 8), ui(activity, 22), 0)
            })
        }

        val actions = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = Tr.layoutDir()
            gravity = Gravity.CENTER
            setPadding(ui(activity, 16), ui(activity, 10), ui(activity, 16), ui(activity, 16))
        }
        if (positiveText != null) {
            val ok = WidgetSettingsUi.button(activity, positiveText, true).apply {
                setOnClickListener { if (onPositive?.invoke() != false) dialog.dismiss() }
            }
            actions.addView(ok, LinearLayout.LayoutParams(0, ui(activity, 48), 1f).apply {
                setMargins(ui(activity, 6), 0, ui(activity, 6), 0)
            })
        }
        if (negativeText != null) {
            val cancel = WidgetSettingsUi.button(activity, negativeText, false).apply {
                setOnClickListener { dialog.dismiss() }
            }
            actions.addView(cancel, LinearLayout.LayoutParams(0, ui(activity, 48), 1f).apply {
                setMargins(ui(activity, 6), 0, ui(activity, 6), 0)
            })
        }
        card.addView(actions, LinearLayout.LayoutParams(-1, -2))

        dialog.setContentView(card)
        dialog.setCanceledOnTouchOutside(true)
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setDimAmount(0.55f)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            val metrics = activity.resources.displayMetrics
            val width = min(metrics.widthPixels - ui(activity, 24) * 2, ui(activity, 400))
            val height = if (tallList || body is ListView) (metrics.heightPixels * 0.78f).roundToInt() else ViewGroup.LayoutParams.WRAP_CONTENT
            setLayout(width, height)
        }
        dialog.show()
        return Handle(dialog, messageView)
    }

    fun message(activity: Activity, title: String, text: String, buttonText: String = "باشه") {
        show(activity, title, message = text, positiveText = buttonText, negativeText = null)
    }

    // ------------------------------------------------------------------------ multiple choice

    /** Separate rounded rows with a check box each; at least [minSelected] rows must stay checked. */
    fun multiChoice(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        labels: List<String>,
        checked: BooleanArray,
        minSelected: Int = 0,
        minMessage: String? = null,
        onConfirm: (BooleanArray) -> Unit,
    ): Handle {
        val state = checked.copyOf()
        val accent = WidgetSettingsUi.accentColor(activity)
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(ui(activity, 16), ui(activity, 6), ui(activity, 16), ui(activity, 4))
        }
        labels.forEachIndexed { index, label ->
            val box = CheckBox(activity).apply {
                isChecked = state[index]
                isClickable = false
                isFocusable = false
                buttonTintList = ColorStateList.valueOf(accent)
            }
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = Tr.layoutDir()
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui(activity, 52)
                setPadding(ui(activity, 14), ui(activity, 4), ui(activity, 8), ui(activity, 4))
                background = rowBackground(activity, state[index])
                isClickable = true
                isFocusable = true
            }
            row.addView(TextView(activity).apply {
                text = Tr.t(label)
                textSize = 15f
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.primaryColor(activity))
            }, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(box, LinearLayout.LayoutParams(-2, -2))
            row.setOnClickListener {
                state[index] = !state[index]
                box.isChecked = state[index]
                row.background = rowBackground(activity, state[index])
            }
            body.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = ui(activity, 6) })
        }
        return show(activity, title, subtitle, body, onPositive = {
            if (state.count { it } < minSelected) {
                Toast.makeText(activity, Tr.t(minMessage ?: "حداقل یک مورد باید انتخاب شود"), Toast.LENGTH_SHORT).show()
                false
            } else {
                onConfirm(state)
                true
            }
        })
    }

    // -------------------------------------------------------------------------- single choice

    /** Long scrollable list of tappable rows (cities, provinces, districts). Picking a row closes the dialog. */
    fun list(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        labels: List<String>,
        neutralText: String? = null,
        onNeutral: (() -> Unit)? = null,
        onPick: (Int) -> Unit,
    ): Handle {
        val list = ListView(activity).apply {
            divider = null
            dividerHeight = ui(activity, 6)
            selector = ColorDrawable(Color.TRANSPARENT)
            isVerticalScrollBarEnabled = false
            setPadding(ui(activity, 16), ui(activity, 6), ui(activity, 16), ui(activity, 6))
            clipToPadding = false
            layoutDirection = Tr.layoutDir()
        }
        lateinit var handle: Handle
        list.adapter = object : ArrayAdapter<String>(activity, 0, labels) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val row = (convertView as? TextView) ?: TextView(activity).apply {
                    textSize = 15f
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    minimumHeight = ui(activity, 50)
                    setPadding(ui(activity, 16), ui(activity, 8), ui(activity, 16), ui(activity, 8))
                    setTextColor(WidgetSettingsUi.primaryColor(activity))
                    background = rowBackground(activity, false)
                }
                row.text = Tr.t(getItem(position))
                return row
            }
        }
        list.setOnItemClickListener { _, _, position, _ ->
            handle.dismiss()
            onPick(position)
        }
        handle = show(
            activity, title, subtitle, list,
            positiveText = null, negativeText = "انصراف",
            neutralText = neutralText, onNeutral = onNeutral, tallList = true,
        )
        return handle
    }

    class Choice(val title: String, val summary: String? = null)

    /** Radio-style rows (title + optional summary); picking a row closes the dialog and calls [onPick]. */
    fun singleChoice(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        choices: List<Choice>,
        selected: Int,
        neutralText: String? = null,
        onNeutral: (() -> Unit)? = null,
        onPick: (Int) -> Unit,
    ): Handle {
        val accent = WidgetSettingsUi.accentColor(activity)
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(ui(activity, 16), ui(activity, 6), ui(activity, 16), ui(activity, 4))
        }
        lateinit var handle: Handle
        choices.forEachIndexed { index, choice ->
            val radio = android.widget.RadioButton(activity).apply {
                isChecked = index == selected
                isClickable = false
                isFocusable = false
                buttonTintList = ColorStateList.valueOf(accent)
            }
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = Tr.layoutDir()
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui(activity, 54)
                setPadding(ui(activity, 14), ui(activity, 6), ui(activity, 8), ui(activity, 6))
                background = rowBackground(activity, index == selected)
                isClickable = true
                isFocusable = true
            }
            val texts = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            texts.addView(TextView(activity).apply {
                text = Tr.t(choice.title)
                textSize = 15f
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.primaryColor(activity))
            }, LinearLayout.LayoutParams(-1, -2))
            if (!choice.summary.isNullOrBlank()) texts.addView(TextView(activity).apply {
                text = Tr.t(choice.summary)
                textSize = 12f
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.secondaryColor(activity))
            }, LinearLayout.LayoutParams(-1, -2))
            row.addView(texts, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(radio, LinearLayout.LayoutParams(-2, -2))
            row.setOnClickListener {
                handle.dismiss()
                onPick(index)
            }
            body.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = ui(activity, 6) })
        }
        handle = show(
            activity, title, subtitle, body,
            positiveText = null, negativeText = "انصراف",
            neutralText = neutralText, onNeutral = onNeutral,
        )
        return handle
    }

    // ------------------------------------------------------------------------------- slider

    fun slider(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        initialPercent: Int,
        valueText: (Int) -> String = { "${persianDigits(it)}٪" },
        onConfirm: (Int) -> Unit,
    ): Handle {
        val accent = WidgetSettingsUi.accentColor(activity)
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            setPadding(ui(activity, 22), ui(activity, 8), ui(activity, 22), ui(activity, 6))
        }
        val value = TextView(activity).apply {
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(accent)
        }
        body.addView(value, LinearLayout.LayoutParams(-1, -2))
        val seek = SeekBar(activity).apply {
            max = 100
            progress = initialPercent.coerceIn(0, 100)
            progressTintList = ColorStateList.valueOf(accent)
            thumbTintList = ColorStateList.valueOf(accent)
            progressBackgroundTintList = ColorStateList.valueOf(tint(WidgetSettingsUi.primaryColor(activity), 60))
        }
        body.addView(seek, LinearLayout.LayoutParams(-1, ui(activity, 40)).apply { topMargin = ui(activity, 6) })
        val chips = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            gravity = Gravity.CENTER
        }
        listOf(0, 25, 50, 75, 100).forEach { preset ->
            chips.addView(TextView(activity).apply {
                text = persianDigits(preset)
                textSize = 13f
                gravity = Gravity.CENTER
                setTextColor(WidgetSettingsUi.primaryColor(activity))
                background = rowBackground(activity, false)
                isClickable = true
                isFocusable = true
                setOnClickListener { seek.progress = preset }
            }, LinearLayout.LayoutParams(0, ui(activity, 38), 1f).apply {
                setMargins(ui(activity, 3), ui(activity, 4), ui(activity, 3), 0)
            })
        }
        body.addView(chips, LinearLayout.LayoutParams(-1, -2).apply { topMargin = ui(activity, 6) })
        fun refresh() { value.text = valueText(seek.progress) }
        refresh()
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar?, progress: Int, fromUser: Boolean) = refresh()
            override fun onStartTrackingTouch(bar: SeekBar?) = Unit
            override fun onStopTrackingTouch(bar: SeekBar?) = Unit
        })
        return show(activity, title, subtitle, body, onPositive = {
            onConfirm(seek.progress)
            true
        })
    }

    // --------------------------------------------------------------------------------- form

    /**
     * Labelled, outlined text fields. [onSave] gets the values in order and returns an error message to
     * show inside the dialog (keeping it open) or null when everything was accepted.
     */
    fun form(
        activity: Activity,
        title: String,
        subtitle: String? = null,
        fields: List<Field>,
        positiveText: String = "ذخیره",
        message: String? = null,
        toggle: Toggle? = null,
        onSave: (List<String>) -> String?,
    ): Handle {
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutDirection = Tr.layoutDir()
            setPadding(ui(activity, 22), ui(activity, 6), ui(activity, 22), ui(activity, 4))
        }
        if (toggle != null) {
            val accent = WidgetSettingsUi.accentColor(activity)
            val sw = android.widget.Switch(activity).apply {
                isChecked = toggle.initial
                thumbTintList = ColorStateList.valueOf(accent)
                trackTintList = ColorStateList.valueOf(tint(accent, 110))
            }
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = Tr.layoutDir()
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = ui(activity, 56)
                setPadding(ui(activity, 14), ui(activity, 6), ui(activity, 10), ui(activity, 6))
                background = rowBackground(activity, false)
                isClickable = true
                isFocusable = true
                setOnClickListener { sw.isChecked = !sw.isChecked }
            }
            val texts = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
            texts.addView(TextView(activity).apply {
                text = Tr.t(toggle.title)
                textSize = 14f
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.primaryColor(activity))
            }, LinearLayout.LayoutParams(-1, -2))
            if (!toggle.summary.isNullOrBlank()) texts.addView(TextView(activity).apply {
                text = Tr.t(toggle.summary)
                textSize = 11.5f
                gravity = Gravity.START
                setTextColor(WidgetSettingsUi.secondaryColor(activity))
            }, LinearLayout.LayoutParams(-1, -2))
            row.addView(texts, LinearLayout.LayoutParams(0, -2, 1f))
            row.addView(sw, LinearLayout.LayoutParams(-2, -2))
            sw.setOnCheckedChangeListener { _, value -> toggle.onChanged(value) }
            body.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = ui(activity, 4) })
        }
        val edits = fields.map { field ->
            body.addView(TextView(activity).apply {
                text = Tr.t(field.label)
                textSize = 13f
                gravity = Gravity.START
                setPadding(ui(activity, 2), ui(activity, 10), ui(activity, 2), ui(activity, 4))
                setTextColor(WidgetSettingsUi.secondaryColor(activity))
            }, LinearLayout.LayoutParams(-1, -2))
            EditText(activity).apply {
                setText(field.initial)
                setSingleLine(true)
                textSize = 15f
                inputType = if (field.numeric) InputType.TYPE_CLASS_NUMBER
                else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                imeOptions = EditorInfo.IME_ACTION_NEXT
                if (field.ltr) {
                    textDirection = View.TEXT_DIRECTION_LTR
                    gravity = Gravity.CENTER_VERTICAL or Gravity.END
                } else {
                    gravity = Gravity.CENTER_VERTICAL or Gravity.START
                }
                setTextColor(WidgetSettingsUi.primaryColor(activity))
                setPadding(ui(activity, 14), ui(activity, 10), ui(activity, 14), ui(activity, 10))
                background = WidgetSettingsUi.roundedBackground(activity, Color.TRANSPARENT, 14f, stroke = true)
                body.addView(this, LinearLayout.LayoutParams(-1, ui(activity, 48)))
            }
        }
        val error = TextView(activity).apply {
            textSize = 12.5f
            gravity = Gravity.START
            visibility = View.GONE
            setPadding(ui(activity, 2), ui(activity, 10), ui(activity, 2), 0)
            setTextColor(0xFFE5484D.toInt())
        }
        body.addView(error, LinearLayout.LayoutParams(-1, -2))
        return show(activity, title, subtitle, body, message = message, positiveText = positiveText, onPositive = {
            val problem = onSave(edits.map { it.text.toString() })
            if (problem != null) {
                error.text = Tr.t(problem)
                error.visibility = View.VISIBLE
                false
            } else true
        })
    }
}
