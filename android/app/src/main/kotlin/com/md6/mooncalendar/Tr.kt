package com.md6.mooncalendar

import android.content.Context
import android.view.Gravity
import android.view.View

/**
 * Native-side translation. Mirrors the Dart `tr()` pipeline: the Persian source string is looked up in the
 * generated dictionaries (assets/tr_en.tsv, tr_ar.tsv), then regex templates, then phrase by phrase.
 * The app language / digit setting are read from the Flutter shared preferences, so widgets and their
 * settings pages follow the language chosen in the app.
 */
object Tr {
    private class Template(val regex: Regex, val order: List<Int>, val value: String, val literal: Int)

    private class Dict(val words: HashMap<String, String>, val templates: List<Template>)

    private val dicts = HashMap<String, Dict>()
    private val cache = HashMap<String, String>()
    private var cacheLang = ""

    private const val FA = "۰۱۲۳۴۵۶۷۸۹"
    private const val AR = "٠١٢٣٤٥٦٧٨٩"
    private val hasLetters = Regex("[ء-يٮ-ۓۺ-ۿ]")
    private val separators = Regex("(\\s*[،,•·|/]\\s*|\\n| – | - | — )")
    private val edgePunct = Regex("^([«»(\\[“\"⁦\u2067\u2068]*)(.*?)([»)\\]”\":؛،.⁩!؟?]*)$", RegexOption.DOT_MATCHES_ALL)
    private val slot = Regex("\\{(\\d)([na]?)\\}")

    private var appCtx: Context? = null

    /** Application context (set explicitly, or fetched from the running process). */
    private fun ctx(): Context? {
        appCtx?.let { return it }
        val found = runCatching {
            val at = Class.forName("android.app.ActivityThread")
            at.getMethod("currentApplication").invoke(null) as? Context
        }.getOrNull()
        if (found != null) appCtx = found.applicationContext
        return appCtx
    }

    fun init(context: Context) {
        appCtx = context.applicationContext
    }

    fun isRtl(): Boolean = ctx()?.let { isRtl(it) } ?: true
    fun layoutDir(): Int = if (isRtl()) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
    fun textDir(): Int = if (isRtl()) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
    fun t(text: CharSequence?): String = text?.toString()?.let { s -> ctx()?.let { t(it, s) } ?: s }.orEmpty()
    fun digits(text: CharSequence?): String = text?.toString()?.let { s -> ctx()?.let { digits(it, s) } ?: s }.orEmpty()

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** "fa", "en" or "ar". */
    fun lang(context: Context): String {
        val code = runCatching { prefs(context).getString("flutter.app_language", null) }.getOrNull()
        return if (code == "en" || code == "ar" || code == "fa") code else "fa"
    }

    private fun localDigits(context: Context): Boolean =
        runCatching { prefs(context).getBoolean("flutter.local_digits", true) }.getOrDefault(true)

    fun isRtl(context: Context): Boolean = lang(context) != "en"

    fun layoutDir(context: Context): Int =
        if (isRtl(context)) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR

    /** Text gravity for "start of the line" that follows the layout direction. */
    val START: Int = Gravity.START

    fun t(context: Context, fa: String): String {
        if (fa.isEmpty()) return fa
        val lang = lang(context)
        val digits = localDigits(context)
        val key = "$lang|$digits|"
        synchronized(this) {
            if (cacheLang != key) {
                cache.clear()
                cacheLang = key
            }
            cache[fa]?.let { return it }
            val base = if (lang == "fa") fa else translateText(context, lang, fa, 0)
            val result = convertDigits(base, lang != "en" && digits)
            if (cache.size > 4000) cache.clear()
            cache[fa] = result
            return result
        }
    }

    /** Digits only: Persian digits for fa/ar (when enabled), Latin digits otherwise. */
    fun digits(context: Context, s: String): String =
        convertDigits(s, lang(context) != "en" && localDigits(context))

    /** Invisible marker put before a digit run that must stay 0-9 (Gregorian dates with the "Latin digits" setting). */
    const val LATIN_MARK = '\u2060'

    /** The "Latin digits for Gregorian dates" setting of the app. */
    fun latinGregorian(): Boolean = ctx()?.let { c ->
        runCatching { prefs(c).getBoolean("flutter.latin_gregorian_digits", false) }.getOrDefault(false)
    } ?: false

    private val digitRun = Regex("[0-9\u06F0-\u06F9\u0660-\u0669]+")

    /** [s] with every number as 0-9, shielded from the numeral conversion of [t] / [digits]. */
    fun latin(s: String): String = digitRun.replace(s) { m ->
        val sb = StringBuilder().append(LATIN_MARK)
        for (ch in m.value) {
            var d = FA.indexOf(ch)
            if (d < 0) d = AR.indexOf(ch)
            sb.append(if (d >= 0) ('0' + d) else ch)
        }
        sb.toString()
    }

    /** Isolates a date so it keeps its own direction inside a right-to-left (or left-to-right) text. */
    fun isolate(s: String): String =
        if (isRtl()) "\u2067$s\u2069" else "\u2066$s\u2069"

    private fun convertDigits(s: String, persian: Boolean): String {
        val sb = StringBuilder(s.length)
        var keepLatin = false
        for (ch in s) {
            if (ch == LATIN_MARK) { keepLatin = true; continue }
            var d = FA.indexOf(ch)
            if (d < 0) d = AR.indexOf(ch)
            if (d < 0 && ch in '0'..'9') d = ch - '0'
            if (d < 0) { keepLatin = false; sb.append(ch) } else sb.append(if (persian && !keepLatin) FA[d] else ('0' + d))
        }
        return sb.toString()
    }

    private fun dict(context: Context, lang: String): Dict {
        dicts[lang]?.let { return it }
        val words = HashMap<String, String>(2048)
        val tpl = ArrayList<Template>()
        runCatching {
            context.applicationContext.assets.open("tr_$lang.tsv").bufferedReader(Charsets.UTF_8).useLines { lines ->
                for (line in lines) {
                    val p = line.split('\t')
                    if (p.size < 3) continue
                    val k = unescape(p[1])
                    val v = unescape(p[2])
                    if (p[0] == "D") words[k] = v else if (p[0] == "T") compile(k, v)?.let { tpl.add(it) }
                }
            }
        }
        tpl.sortByDescending { it.literal }
        return Dict(words, tpl).also { dicts[lang] = it }
    }

    private fun unescape(s: String): String {
        if (!s.contains('\\')) return s
        val sb = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '\\' && i + 1 < s.length) {
                when (s[i + 1]) {
                    'n' -> sb.append('\n')
                    't' -> sb.append('\t')
                    else -> sb.append(s[i + 1])
                }
                i += 2
            } else {
                sb.append(c)
                i++
            }
        }
        return sb.toString()
    }

    private fun compile(key: String, value: String): Template? {
        val order = ArrayList<Int>()
        val re = StringBuilder("^")
        var last = 0
        var literal = 0
        for (m in slot.findAll(key)) {
            val lit = key.substring(last, m.range.first)
            literal += lit.length
            re.append(Regex.escape(lit))
            re.append(
                when (m.groupValues[2]) {
                    "n" -> "([0-9۰-۹٠-٩:.,٫/+−~%\\-\\s]+?)"
                    "a" -> "(.+?)"
                    else -> "([^،•\\n]+?)"
                },
            )
            order.add(m.groupValues[1].toInt())
            last = m.range.last + 1
        }
        val tail = key.substring(last)
        literal += tail.length
        re.append(Regex.escape(tail)).append("$")
        return runCatching { Template(Regex(re.toString(), RegexOption.DOT_MATCHES_ALL), order, value, literal) }.getOrNull()
    }

    private fun lookup(context: Context, lang: String, fa: String): String? {
        val d = dict(context, lang)
        d.words[fa]?.let { return it }
        for (t in d.templates) {
            val m = t.regex.matchEntire(fa) ?: continue
            var out = t.value
            for (i in t.order.indices) {
                out = out.replace("{${t.order[i]}}", translateText(context, lang, m.groupValues[i + 1], 1))
            }
            return out
        }
        return null
    }

    private fun translateText(context: Context, lang: String, fa: String, depth: Int): String {
        if (!hasLetters.containsMatchIn(fa)) return fa
        lookup(context, lang, fa)?.let { return it }
        val trimmed = fa.trim()
        if (trimmed != fa && trimmed.isNotEmpty()) {
            lookup(context, lang, trimmed)?.let { return fa.replaceFirst(trimmed, it) }
        }
        if (depth > 2) return fa
        // Multi-line text is translated line by line below (the tokenizer would join the lines with spaces).
        if (!fa.contains('\n')) tokenTranslate(context, lang, fa)?.let { return it }
        val parts = fa.split(separators)
        if (parts.size < 2) return fa
        val seps = separators.findAll(fa).map { it.value }.toList()
        var any = false
        val out = StringBuilder()
        for (i in parts.indices) {
            val p = parts[i]
            var t = p
            if (hasLetters.containsMatchIn(p)) {
                val r = lookup(context, lang, p)
                    ?: (if (p.trim() == p) null else lookup(context, lang, p.trim()))
                    ?: tokenTranslate(context, lang, p)
                if (r != null) {
                    t = r
                    any = true
                }
            }
            out.append(t)
            if (i < seps.size) {
                var s = seps[i]
                if (lang == "en") s = s.replace('،', ',')
                out.append(s)
            }
        }
        return if (any) out.toString() else fa
    }

    private fun tokenTranslate(context: Context, lang: String, fa: String): String? {
        val words = fa.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.size < 2 || words.size > 12) return null
        val d = dict(context, lang)
        val out = ArrayList<String>()
        var any = false
        var i = 0
        while (i < words.size) {
            val w = words[i]
            if (!hasLetters.containsMatchIn(w)) {
                out.add(w)
                i++
                continue
            }
            var matched = false
            var n = minOf(words.size - i, 4)
            while (n >= 1 && !matched) {
                val phrase = words.subList(i, i + n).joinToString(" ")
                val whole = d.words[phrase]
                if (whole != null) {
                    out.add(whole)
                    i += n
                    matched = true
                    any = true
                    break
                }
                val m = edgePunct.matchEntire(phrase)
                if (m != null) {
                    val core = m.groupValues[2]
                    val hit = if (core.isEmpty()) null else d.words[core]
                    if (hit != null) {
                        out.add(m.groupValues[1] + hit + m.groupValues[3])
                        i += n
                        matched = true
                        any = true
                    }
                }
                n--
            }
            if (!matched) return null
        }
        return if (any) out.joinToString(" ") else null
    }
}
