import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import '../../core/l10n/l10n.dart';

/// Flutter's own Text: never translated or re-digited (language names, the clock, ...).
typedef PlainText = m.Text;

/// «زبان» in the app language, plus "(Language)" when the app is not English so it can always be found.
String get languageTitle => L10n.lang == AppLanguage.en ? 'Language' : '${tr('زبان')} (Language)';

/// Drop-in replacement for Flutter's Text: the string is translated into the app language, and the
/// hard-coded right-to-left direction used all over the code base is dropped for left-to-right languages.
class Text extends StatelessWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : textSpan = null;

  const Text.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    L10n.watch(context);
    final dir = (textDirection == TextDirection.rtl && !L10n.rtl) ? null : textDirection;
    final span = textSpan;
    if (span != null) {
      return m.Text.rich(
        span,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: dir,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    // The seven-segment LCD font only has Latin digits: its numbers are never translated or re-digited.
    final lcd = style?.fontFamily == 'TallySegment7' || style?.fontFamily == 'Segoe UI'; // Segoe UI = the desktop widget clock (always Latin)
    return m.Text(
      lcd ? data! : tr(data!),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: dir,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null ? null : tr(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
