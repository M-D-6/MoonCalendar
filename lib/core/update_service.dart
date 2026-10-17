import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'athan/athan_android.dart';
import 'platform_info.dart';
import 'windows_desktop_service.dart';

/// A published release that is newer than this build.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, required this.pageUrl, this.assetName, this.assetUrl, this.assetSize});

  final String version;
  final String notes;
  final String pageUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  /// True when the release has a file for this device (otherwise only the release page can be offered).
  bool get hasAsset => assetUrl != null && assetName != null;
}

/// Looks for a newer GitHub release of the app, downloads its installer / APK and starts it.
/// Only Windows and Android take part; nothing is contacted unless the user turned the check on or asked for it.
class UpdateService {
  UpdateService._();

  static const String repository = 'M-D-6/MoonCalendar';
  static const String _latestUrl = 'https://api.github.com/repos/$repository/releases/latest';

  static bool get isSupported => PlatformInfo.isAndroid || PlatformInfo.isWindows;

  /// 1 when [a] is newer than [b], -1 when older, 0 when equal ("1.1.10" > "1.1.9", a leading "v" is ignored).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[.+\-]')).map((p) => int.tryParse(p) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 4; i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q ? 1 : -1;
    }
    return 0;
  }

  /// The newest release if it is newer than this build, null when up to date. Throws when the check fails.
  static Future<UpdateInfo?> checkLatest() async {
    final response = await http
        .get(Uri.parse(_latestUrl), headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Mooncalendar/$appVersion'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return null; // nothing published yet
    if (response.statusCode != 200) throw HttpException('GitHub answered ${response.statusCode}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty || compareVersions(tag, appVersion) <= 0) return null;

    final wanted = await _wantedAssetNames();
    Map<String, dynamic>? asset;
    for (final name in wanted) {
      for (final a in (json['assets'] as List<dynamic>? ?? const <dynamic>[])) {
        if (a is Map<String, dynamic> && a['name'] == name) asset = a;
      }
      if (asset != null) break;
    }
    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (json['body'] as String? ?? '').trim(),
      pageUrl: json['html_url'] as String? ?? 'https://github.com/$repository/releases/latest',
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: (asset?['size'] as num?)?.toInt(),
    );
  }

  /// Release file names that suit this device, best first.
  static Future<List<String>> _wantedAssetNames() async {
    if (PlatformInfo.isWindows) return const ['MoonCalendar-windows-x64-setup.exe'];
    final abis = await AthanAndroid.supportedAbis();
    return [for (final abi in abis) 'MoonCalendar-android-$abi.apk'];
  }

  static Directory get _folder => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}mooncalendar_update');

  /// Downloads the release file. [onProgress] gets 0..1 (or null when the size is unknown); [cancelled] aborts.
  static Future<File> download(UpdateInfo info, {required void Function(double? progress) onProgress, required bool Function() cancelled}) async {
    final folder = _folder;
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    final target = File('${folder.path}${Platform.pathSeparator}${info.assetName}');
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(info.assetUrl!))..headers['User-Agent'] = 'Mooncalendar/$appVersion');
      if (response.statusCode != 200) throw HttpException('Download failed (${response.statusCode})');
      final total = response.contentLength ?? info.assetSize;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response.stream) {
          if (cancelled()) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress(total == null || total <= 0 ? null : (received / total).clamp(0.0, 1.0).toDouble());
        }
      } finally {
        await sink.close();
      }
      if (info.assetSize != null && received != info.assetSize) throw const HttpException('The downloaded file is incomplete');
      if (target.existsSync()) target.deleteSync();
      return await part.rename(target.path);
    } on _Cancelled {
      if (part.existsSync()) part.deleteSync();
      rethrow;
    } finally {
      client.close();
    }
  }

  static bool isCancelled(Object error) => error is _Cancelled;

  /// Starts the installer and returns. Windows: the app closes itself afterwards, the installer replaces the
  /// files and starts the new version. Android: the system installer opens (the user may first be asked to allow
  /// installs from this app). Returns false when it could not be started.
  static Future<bool> install(File file) async {
    if (PlatformInfo.isWindows) {
      await Process.start(
        file.path,
        const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      // Give the installer a moment to start, then leave so its files are not in use.
      Future<void>.delayed(const Duration(milliseconds: 1500), () => WindowsDesktopService.instance.exitApp());
      return true;
    }
    if (PlatformInfo.isAndroid) return AthanAndroid.installApk(file.path);
    return false;
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
