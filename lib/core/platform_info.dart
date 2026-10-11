import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Safe platform checks for every target (Android, iOS, Windows, Linux, macOS and the web).
///
/// `dart:io`'s `Platform.isX` throws on the web, so [kIsWeb] is always checked first. Use these
/// instead of `Platform.isX` everywhere in the app.
class PlatformInfo {
  PlatformInfo._();

  static const bool isWeb = kIsWeb;
  static final bool isAndroid = !kIsWeb && Platform.isAndroid;
  static final bool isIOS = !kIsWeb && Platform.isIOS;
  static final bool isWindows = !kIsWeb && Platform.isWindows;
  static final bool isLinux = !kIsWeb && Platform.isLinux;
  static final bool isMacOS = !kIsWeb && Platform.isMacOS;

  static final bool isDesktop = isWindows || isLinux || isMacOS;
  static final bool isMobile = isAndroid || isIOS;

  /// Platforms that have the native (Kotlin / C++) services: widgets, notifications, tray, athan.
  static final bool hasNativeServices = isAndroid || isWindows;

  /// Human readable platform name (device info screen).
  static String get name => isWeb
      ? 'web'
      : isAndroid
          ? 'android'
          : isIOS
              ? 'ios'
              : isWindows
                  ? 'windows'
                  : isLinux
                      ? 'linux'
                      : isMacOS
                          ? 'macos'
                          : 'unknown';
}
