import 'package:flutter/material.dart';
import '../core/settings.dart';

/// Vazirmatn is used for the whole app. If the font is bundled (see
/// assets/fonts/README.md) it is used everywhere; otherwise Flutter falls back
/// to a system-installed Vazirmatn and then to Segoe UI / Tahoma.
const String appFontFamily = 'Vazirmatn';

ThemeData buildTheme({
  required bool dark,
  required ThemeModeChoice choice,
  required bool gradient,
  required bool bold,
  required int systemSeedColor,
}) {
  final Color seed = switch (choice) {
    // System is the only default palette: its seed comes from the OS accent.
    ThemeModeChoice.system => Color(systemSeedColor),
    ThemeModeChoice.aqua => const Color(0xFF00838F),
    ThemeModeChoice.modern => const Color(0xFF607D8B),
    ThemeModeChoice.light => const Color(0xFF00796B),
    ThemeModeChoice.dark => const Color(0xFF3E4042),
    ThemeModeChoice.black => const Color(0xFF000000),
    ThemeModeChoice.custom => Color(AppSettings.customThemeColorValue),
  };

  // Keep Material 3's accent colors, but keep page/surface colors mostly
  // neutral. The OS/app accent should coordinate the UI, not flood it.
  var scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  );

  final Color neutralBackground = dark
      ? const Color(0xFF151718)
      : const Color(0xFFF7F8F8);
  final Color background = Color.lerp(neutralBackground, seed, dark ? 0.025 : 0.018)!;
  final Color surface = Color.lerp(neutralBackground, seed, dark ? 0.040 : 0.022)!;
  final Color surfaceLow = Color.lerp(background, seed, dark ? 0.018 : 0.010)!;
  final Color surfaceHigh = Color.lerp(surface, seed, dark ? 0.055 : 0.030)!;
  final Color surfaceHighest = Color.lerp(surfaceHigh, seed, dark ? 0.070 : 0.040)!;

  scheme = scheme.copyWith(
    surface: surface,
    surfaceContainerLowest: dark ? const Color(0xFF101212) : const Color(0xFFFCFCFC),
    surfaceContainerLow: surfaceLow,
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: surfaceHighest,
    surfaceTint: Colors.transparent,
  );

  if (choice == ThemeModeChoice.black && dark) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: const Color(0xFF070808),
      surfaceContainerHighest: const Color(0xFF0D0E0E),
    );
  }

  final baseText = ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
  ).textTheme.apply(fontFamily: appFontFamily);

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    fontFamilyFallback: const ['Vazirmatn', 'Vazir', 'Segoe UI', 'Tahoma', 'Arial'],
    textTheme: bold ? _bolden(baseText) : baseText,
    scaffoldBackgroundColor: background,
    // Modern motion: ink sparkle ripples + smooth shared-axis style route transitions.
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
    }),
    // Every block on every page lives in its own soft, rounded tonal card (same look as the calendar page).
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.all(8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 18),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      minExtendedWidth: 220,
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      elevation: 0,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: .92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? .10 : .5), width: .8),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      // Transparent pane: the rows (GlassMenuItem) draw the frosted glass.
      color: scheme.surfaceContainerHigh.withValues(alpha: .35),
      surfaceTintColor: Colors.transparent,
      menuPadding: EdgeInsets.zero,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? .10 : .5), width: .8),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface.withValues(alpha: .93),
      modalBackgroundColor: scheme.surface.withValues(alpha: .93),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: scheme.outlineVariant),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

TextTheme _bolden(TextTheme theme) {
  FontWeight? nextWeight(FontWeight? weight) {
    if (weight == null) return null;
    final int index = FontWeight.values.indexOf(weight);
    if (index < 0) return weight;
    return FontWeight.values[(index + 1).clamp(0, FontWeight.values.length - 1).toInt()];
  }

  TextStyle? bold(TextStyle? style) => style?.copyWith(fontWeight: nextWeight(style.fontWeight));

  return theme.copyWith(
    displayLarge: bold(theme.displayLarge),
    displayMedium: bold(theme.displayMedium),
    displaySmall: bold(theme.displaySmall),
    headlineLarge: bold(theme.headlineLarge),
    headlineMedium: bold(theme.headlineMedium),
    headlineSmall: bold(theme.headlineSmall),
    titleLarge: bold(theme.titleLarge),
    titleMedium: bold(theme.titleMedium),
    titleSmall: bold(theme.titleSmall),
    bodyLarge: bold(theme.bodyLarge),
    bodyMedium: bold(theme.bodyMedium),
    bodySmall: bold(theme.bodySmall),
    labelLarge: bold(theme.labelLarge),
    labelMedium: bold(theme.labelMedium),
    labelSmall: bold(theme.labelSmall),
  );
}
