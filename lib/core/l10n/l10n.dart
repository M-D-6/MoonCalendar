import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'strings_ar.dart';
import 'strings_en.dart';

/// App languages. Persian is the source language of every string in the code base; English and Arabic are
/// looked up in dictionaries keyed by the Persian text (see [tr]).
enum AppLanguage {
  fa('fa', 'فارسی', TextDirection.rtl),
  en('en', 'English', TextDirection.ltr),
  ar('ar', 'العربية', TextDirection.rtl);

  const AppLanguage(this.code, this.nativeName, this.direction);
  final String code;
  final String nativeName;
  final TextDirection direction;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.fa);

  /// Persian is the default language on first start (the user can switch in the settings).
  static AppLanguage fromDevice() => AppLanguage.fa;
}

/// Current language + numerals; [revision] changes on every switch so widgets/painters can rebuild.
class L10n {
  L10n._();

  static AppLanguage lang = AppLanguage.fa;
  static bool localDigits = true;

  /// "Latin digits for Gregorian dates": Gregorian numbers are tagged with [latinMark] (an invisible
  /// character) so the numeral conversion of [translate] leaves them as 0-9.
  static bool gregorianLatin = false;
  static const String latinMark = '\u2060';

  static void setGregorianLatin(bool value) {
    if (value == gregorianLatin) return;
    gregorianLatin = value;
    _cache.clear();
    revision.value++;
  }

  /// [text] (a number or a string of numbers) shielded from the numeral conversion when the setting is on.
  static String latin(Object text) => gregorianLatin ? markLatin(text) : text.toString();

  /// [text] with every number as 0-9, shielded from the numeral conversion regardless of the setting.
  static String markLatin(Object text) {
    final s = latinDigits(text.toString());
    return s.replaceAllMapped(RegExp(r'[0-9]+'), (m) => '$latinMark${m[0]}');
  }
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get rtl => lang.direction == TextDirection.rtl;
  static bool get isPersian => lang == AppLanguage.fa;
  static TextDirection get direction => lang.direction;
  /// Material's chevron icons mirror themselves in right-to-left layouts, so no language check is needed here.
  static IconData get chevron => Icons.chevron_right;
  static IconData get chevronBack => Icons.chevron_left;

  /// The desktop-widget window always stays Persian / right-to-left.
  static bool persianOnly = false;

  static void set(AppLanguage value, {bool? digits}) {
    if (persianOnly) return;
    final changed = value != lang || (digits != null && digits != localDigits);
    lang = value;
    if (digits != null) localDigits = digits;
    if (changed) {
      _cache.clear();
      revision.value++;
    }
  }

  /// Make [context] rebuild when the language changes.
  static void watch(BuildContext context) => context.dependOnInheritedWidgetOfExactType<L10nScope>();

  static final Map<String, String> _cache = <String, String>{};
  static List<_Template>? _templates;
  static AppLanguage? _templatesFor;

  static Map<String, String> get _dict => lang == AppLanguage.en ? enStrings : arStrings;
  static Map<String, String> get _tplDict => lang == AppLanguage.en ? enTemplates : arTemplates;

  static List<_Template> _compiledTemplates() {
    if (_templates != null && _templatesFor == lang) return _templates!;
    final out = <_Template>[];
    _tplDict.forEach((key, value) => out.add(_Template.compile(key, value)));
    // Longer (more specific) keys first.
    out.sort((a, b) => b.literalLength.compareTo(a.literalLength));
    _templatesFor = lang;
    return _templates = out;
  }

  static final RegExp _hasLetters = RegExp(r'[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF]');
  static final RegExp _separators = RegExp(r'(\s*[،,•·|/]\s*|\n| – | - | — )');

  static String translate(String fa) {
    final hit = _cache[fa];
    if (hit != null) return hit;
    // Persian keeps its own words but its numerals still follow the digit setting (Latin dates -> ۰-۹).
    final result = _digits(lang == AppLanguage.fa ? fa : _translateText(fa, 0));
    if (_cache.length > 6000) _cache.clear();
    return _cache[fa] = result;
  }

  /// City names (Persian -> app language) registered from cities.json once it has been loaded.
  static final Map<String, String> _extraEn = <String, String>{};
  static final Map<String, String> _extraAr = <String, String>{};

  static void registerNames({required Map<String, String> en, required Map<String, String> ar}) {
    _extraEn.addAll(en);
    _extraAr.addAll(ar);
    _cache.clear();
  }

  static String? _lookup(String fa) {
    final exact = _dict[fa] ?? (lang == AppLanguage.en ? _extraEn[fa] : _extraAr[fa]);
    if (exact != null) return exact;
    for (final t in _compiledTemplates()) {
      final r = t.apply(fa, (s) => _translateText(s, 1));
      if (r != null) return r;
    }
    return null;
  }

  static String _translateText(String fa, int depth) {
    if (!_hasLetters.hasMatch(fa)) return fa;
    final direct = _lookup(fa);
    if (direct != null) return direct;
    final trimmed = fa.trim();
    if (trimmed != fa && trimmed.isNotEmpty) {
      final inner = _lookup(trimmed);
      if (inner != null) return fa.replaceFirst(trimmed, inner);
    }
    if (depth > 2) return fa;
    // Multi-line text is translated line by line below (the tokenizer would join the lines with spaces).
    final tokens = fa.contains('\n') ? null : _tokenTranslate(fa);
    if (tokens != null) return tokens;
    // Joined lists such as "شنبه، یکشنبه" or "a • b": translate piece by piece.
    final parts = fa.split(_separators);
    if (parts.length < 2) return fa;
    final seps = _separators.allMatches(fa).map((m) => m.group(0)!).toList();
    var any = false;
    final out = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      var t = p;
      if (_hasLetters.hasMatch(p)) {
        final r = _lookup(p) ?? (p.trim() == p ? null : _lookup(p.trim())) ?? _tokenTranslate(p);
        if (r != null) {
          t = r;
          any = true;
        }
      }
      out.write(t);
      if (i < seps.length) {
        var s = seps[i];
        if (lang == AppLanguage.en) s = s.replaceAll('،', ',');
        out.write(s);
      }
    }
    return any ? out.toString() : fa;
  }

  /// [text] as a unit with its own direction (so a Latin date inside a Persian line, or the other way round,
  /// is not scrambled by the bidirectional algorithm).
  static String isolate(String text) => rtl ? '\u2067$text\u2069' : '\u2066$text\u2069';

  /// Like [isolate] but with the classic embedding controls (RLE / LRE ... PDF), which even old text engines
  /// (Windows toasts) honour; isolates are ignored there and the line comes out scrambled.
  static String embed(String text) => rtl ? '\u202B$text\u202C' : '\u202A$text\u202C';

  /// Every Persian / Arabic-Indic digit of [text] as 0-9.
  static String latinDigits(String text) {
    final buf = StringBuffer();
    for (final c in text.runes) {
      final ch = String.fromCharCode(c);
      var d = _fa.indexOf(ch);
      if (d < 0) d = _arD.indexOf(ch);
      buf.write(d < 0 ? ch : '$d');
    }
    return buf.toString();
  }

  static final RegExp _edgePunct = RegExp(r'^([«»(\[“"\u2066]*)(.*?)([»)\]”":؛،.\u2069!؟?]*)$', dotAll: true);

  /// "شنبه ۵ فروردین ۱۴۰۵" or "🐎 اسب «یونت ئیل»": every Persian word/phrase is a known name (numbers, symbols
  /// and punctuation pass through) -> translate phrase by phrase. All-or-nothing, so a sentence that is not in
  /// the dictionary is never half translated.
  static String? _tokenTranslate(String fa) {
    final words = fa.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2 || words.length > 12) return null;
    final out = <String>[];
    var any = false;
    var i = 0;
    while (i < words.length) {
      final w = words[i];
      if (!_hasLetters.hasMatch(w)) {
        out.add(w);
        i++;
        continue;
      }
      var matched = false;
      for (var n = (words.length - i).clamp(1, 4); n >= 1 && !matched; n--) {
        final phrase = words.sublist(i, i + n).join(' ');
        final whole = _dict[phrase];
        if (whole != null) {
          out.add(whole);
          i += n;
          matched = true;
          any = true;
          break;
        }
        final m = _edgePunct.firstMatch(phrase);
        if (m == null) continue;
        final core = m.group(2)!;
        final hit = core.isEmpty ? null : _dict[core];
        if (hit != null) {
          out.add('${m.group(1)}$hit${m.group(3)}');
          i += n;
          matched = true;
          any = true;
        }
      }
      if (!matched) return null;
    }
    return any ? out.join(' ') : null;
  }

  static const String _fa = '۰۱۲۳۴۵۶۷۸۹';
  static const String _arD = '٠١٢٣٤٥٦٧٨٩';

  /// Numerals follow the language: English = 0-9, Persian and Arabic = ۰-۹ (Arabic-Indic digits are never
  /// used); with "Persian digits" off everything is 0-9.
  static String _digits(String s) {
    final persianDigits = lang != AppLanguage.en && localDigits;
    final buf = StringBuffer();
    var keepLatin = false;
    for (final c in s.runes) {
      final ch = String.fromCharCode(c);
      if (ch == latinMark) {
        keepLatin = true;
        continue;
      }
      var d = _fa.indexOf(ch);
      if (d < 0) d = _arD.indexOf(ch);
      if (d < 0 && c >= 0x30 && c <= 0x39) d = c - 0x30;
      if (d < 0) {
        keepLatin = false;
        buf.write(ch);
      } else {
        buf.write(persianDigits && !keepLatin ? _fa[d] : '$d');
      }
    }
    return buf.toString();
  }

  /// Digits only (for numbers formatted by code rather than looked up).
  static String digits(Object value) => _digits(value.toString());
}

class _Template {
  _Template(this.regex, this.order, this.value, this.literalLength);
  final RegExp regex;
  final List<int> order;
  final String value;
  final int literalLength;

  static final RegExp _slot = RegExp(r'\{(\d)([na]?)\}');

  factory _Template.compile(String key, String value) {
    final order = <int>[];
    final buf = StringBuffer('^');
    var last = 0;
    var literal = 0;
    for (final m in _slot.allMatches(key)) {
      final lit = key.substring(last, m.start);
      literal += lit.length;
      buf.write(RegExp.escape(lit));
      buf.write(switch (m.group(2)) {
        'n' => r'([0-9۰-۹٠-٩:.,٫/+−~%\-\s]+?)',
        'a' => '(.+?)',
        // Plain slots never swallow a list separator, so "اذان صبح، طلوع، ..." is not read as one "اذان {1}".
        _ => r'([^،•\n]+?)',
      });
      order.add(int.parse(m.group(1)!));
      last = m.end;
    }
    final tail = key.substring(last);
    literal += tail.length;
    buf.write(RegExp.escape(tail));
    buf.write(r'$');
    return _Template(RegExp(buf.toString(), dotAll: true), order, value, literal);
  }

  String? apply(String input, String Function(String) inner) {
    final m = regex.firstMatch(input);
    if (m == null) return null;
    var out = value;
    for (var i = 0; i < order.length; i++) {
      out = out.replaceAll('{${order[i]}}', inner(m.group(i + 1)!));
    }
    return out;
  }
}

/// Translate a Persian source string into the current language.
String tr(String fa) => L10n.translate(fa);

/// Placed above the Navigator: widgets that call [L10n.watch] / use the shadow Text rebuild on a switch.
class L10nScope extends InheritedNotifier<ValueNotifier<int>> {
  const L10nScope({super.key, required ValueNotifier<int> notifier, required super.child}) : super(notifier: notifier);
}
