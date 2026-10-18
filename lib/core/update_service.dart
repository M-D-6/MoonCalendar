import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'athan/athan_android.dart';
import 'platform_info.dart';
import 'windows_desktop_service.dart';

/// A published release that is newer than this build.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize,
    this.sha256,
  });

  final String version;
  final String notes;
  final String pageUrl;
  final String? assetName;
  final String? assetUrl;
  final int? assetSize;

  /// Lower-case hex digest published by GitHub for the file, when available.
  final String? sha256;

  /// True when the release has a file for this device (otherwise only the release page can be offered).
  bool get hasAsset => assetUrl != null && assetName != null;
}

/// Looks for a newer GitHub release of the app, downloads its installer / APK and starts it.
/// Only Windows and Android take part; nothing is contacted unless the user turned the check on or asked for it.
///
/// Downloads follow the same rules as desktop messengers:
///  * the file is written as `*.part` and only renamed once it is complete and verified, so a download that was
///    cut off (network, app closed) never leaves a usable-looking broken file behind;
///  * a finished download is kept and reused if the install did not happen, instead of downloading again;
///  * it is deleted once the new version runs, when a manual update replaces it, or after [_maxAge].
class UpdateService {
  UpdateService._();

  static const String repository = 'M-D-6/MoonCalendar';
  static const String _latestUrl = 'https://api.github.com/repos/$repository/releases/latest';
  static const Duration _maxAge = Duration(days: 14);

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

  // ------------------------------------------------------------------------------------------ check

  /// The newest release if it is newer than this build, null when up to date. Throws when the check fails.
  /// Technical trace of the last check / download / install, shown when something fails so the cause can be found.
  static final List<String> log = <String>[];

  static void _log(String line) {
    log.add(line);
    if (log.length > 60) log.removeAt(0);
  }

  static String get report => 'Mooncalendar $appVersion | ${PlatformInfo.isAndroid ? 'android' : 'windows'}\n${log.join('\n')}';

  /// [force] also returns the latest release when it is not newer than this version (used for "install again").
  static Future<UpdateInfo?> checkLatest({bool force = false}) async {
    log.clear();
    _log('check: GET $_latestUrl');
    final response = await http
        .get(Uri.parse(_latestUrl), headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Mooncalendar/$appVersion'})
        .timeout(const Duration(seconds: 15));
    _log('check: HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes');
    if (response.statusCode == 404) return null; // nothing published yet
    if (response.statusCode != 200) throw HttpException('GitHub answered ${response.statusCode}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = (json['tag_name'] as String? ?? '').trim();
    _log('check: latest tag "$tag", installed $appVersion');
    if (tag.isEmpty || (!force && compareVersions(tag, appVersion) <= 0)) return null;

    Map<String, dynamic>? asset;
    final assets = (json['assets'] as List<dynamic>? ?? const <dynamic>[]).whereType<Map<String, dynamic>>().toList();
    for (final name in await _wantedAssetNames()) {
      for (final a in assets) {
        if (a['name'] == name) asset = a;
      }
      if (asset != null) break;
    }
    _log('check: wanted ${await _wantedAssetNames()}; release has ${[for (final a in assets) a['name']]}; picked ${asset?['name']}');
    final digest = asset?['digest'] as String?; // "sha256:<hex>"
    final assetUrlRaw = asset?['browser_download_url'] as String?;
    final checksum = digest != null && RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ? digest.substring(7).toLowerCase() : null;
    // Only a file with a published SHA-256 from GitHub's own servers can be installed from inside the app.
    final trusted = asset != null && checksum != null && _isTrustedUrl(assetUrlRaw);
    if (asset != null && !trusted) _log('check: asset rejected (checksum ${checksum == null ? 'missing' : 'ok'}, url $assetUrlRaw)');
    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (json['body'] as String? ?? '').trim(),
      pageUrl: json['html_url'] as String? ?? 'https://github.com/$repository/releases/latest',
      assetName: trusted ? asset['name'] as String? : null,
      assetUrl: trusted ? assetUrlRaw : null,
      assetSize: trusted ? (asset['size'] as num?)?.toInt() : null,
      sha256: trusted ? checksum : null,
    );
  }

  /// Downloads must come over HTTPS from GitHub itself (release assets are served from these hosts).
  static bool _isTrustedUrl(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' || host.endsWith('.githubusercontent.com');
  }

  /// Release file names that suit this device, best first.
  static Future<List<String>> _wantedAssetNames() async {
    if (PlatformInfo.isWindows) return const ['MoonCalendar-windows-x64-setup.exe'];
    final abis = await AthanAndroid.supportedAbis();
    return [for (final abi in abis) 'MoonCalendar-android-$abi.apk'];
  }

  // -------------------------------------------------------------------------------- download folder

  static String? _base;

  /// Android: the folder comes from the native side (inside the app's cache directory, which the package installer
  /// is allowed to read through the app's FileProvider). Windows: a folder in the temp directory.
  static Future<void> _ensureBase() async {
    if (_base != null) return;
    String? dir;
    if (PlatformInfo.isAndroid) dir = await AthanAndroid.updateDir();
    _base = dir ?? '${Directory.systemTemp.path}${Platform.pathSeparator}mooncalendar_update';
  }

  static Directory get _folder => Directory(_base ?? '${Directory.systemTemp.path}${Platform.pathSeparator}mooncalendar_update');
  static File get _metaFile => File('${_folder.path}${Platform.pathSeparator}update.json');

  static void _deleteFolder() {
    try {
      if (_folder.existsSync()) _folder.deleteSync(recursive: true);
    } catch (_) {
      // A file still in use (installer running); it is removed on a later start.
    }
  }

  static Map<String, dynamic>? _readMeta() {
    try {
      return jsonDecode(_metaFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Housekeeping, run at every start: removes unfinished downloads, files of versions that are already
  /// installed, damaged files and anything older than two weeks.
  static Future<void> cleanup() async {
    if (!isSupported) return;
    await _ensureBase();
    try {
      if (!_folder.existsSync()) return;
      for (final entity in _folder.listSync()) {
        if (entity is File && entity.path.endsWith('.part')) entity.deleteSync();
      }
      final meta = _readMeta();
      if (meta == null) return _deleteFolder();
      final name = meta['name'] as String?;
      final version = meta['version'] as String?;
      final size = meta['size'] as int?;
      final at = DateTime.fromMillisecondsSinceEpoch(meta['at'] as int? ?? 0);
      final file = name == null ? null : File('${_folder.path}${Platform.pathSeparator}$name');
      final stale = version == null ||
          compareVersions(version, appVersion) <= 0 ||
          DateTime.now().difference(at) > _maxAge ||
          file == null ||
          !file.existsSync() ||
          (size != null && file.lengthSync() != size);
      if (stale) _deleteFolder();
    } catch (_) {
      _deleteFolder();
    }
  }

  /// A complete, verified download of exactly this release, or null.
  static Future<File?> readyFile(UpdateInfo info) async {
    await _ensureBase();
    try {
      final meta = _readMeta();
      if (meta == null || meta['version'] != info.version || meta['name'] != info.assetName) return null;
      final file = File('${_folder.path}${Platform.pathSeparator}${info.assetName}');
      if (!file.existsSync()) return null;
      final expected = info.assetSize ?? meta['size'] as int?;
      if (expected != null && file.lengthSync() != expected) return null;
      if (info.sha256 != null && await _sha256Of(file) != info.sha256) return null;
      return file;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sha256Of(File file) async => (await sha256.bind(file.openRead()).first).toString();

  /// Downloads the release file (or returns the one already downloaded). [onProgress] gets 0..1 (or null when the
  /// size is unknown); [cancelled] aborts. Whatever goes wrong, no partial file stays behind.
  static Future<File> download(UpdateInfo info, {required void Function(double? progress) onProgress, required bool Function() cancelled}) async {
    _log('download: ${info.assetName} (${info.assetSize} bytes) ${info.assetUrl}');
    if (info.sha256 == null || !_isTrustedUrl(info.assetUrl)) throw const HttpException('No published checksum or untrusted address; the file is not downloaded');
    final existing = await readyFile(info);
    if (existing != null) {
      _log('download: reusing the verified file ${existing.path}');
      onProgress(1);
      return existing;
    }
    _deleteFolder(); // older or damaged downloads
    _folder.createSync(recursive: true);
    final target = File('${_folder.path}${Platform.pathSeparator}${info.assetName}');
    final part = File('${target.path}.part');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.assetUrl!))..headers['User-Agent'] = 'Mooncalendar/$appVersion';
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      _log('download: HTTP ${response.statusCode}, length ${response.contentLength}, folder ${_folder.path}');
      if (response.statusCode != 200) throw HttpException('Download failed (${response.statusCode})');
      final total = response.contentLength ?? info.assetSize;
      var received = 0;
      final sink = part.openWrite();
      try {
        // A connection that stops delivering data for 30 s counts as failed.
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (cancelled()) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress(total == null || total <= 0 ? null : (received / total).clamp(0.0, 1.0).toDouble());
        }
      } finally {
        await sink.close();
      }
      _log('download: received $received of $total bytes');
      if (total != null && total > 0 && received != total) throw HttpException('The downloaded file is incomplete ($received of $total bytes)');
      {
        final actual = await _sha256Of(part);
        _log('download: sha256 $actual, expected ${info.sha256}');
        if (actual != info.sha256) throw const HttpException('The downloaded file is damaged (checksum mismatch)');
      }
      final done = await part.rename(target.path);
      await _metaFile.writeAsString(jsonEncode(<String, dynamic>{
        'version': info.version,
        'name': info.assetName,
        'size': received,
        'sha256': info.sha256,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));
      return done;
    } catch (e) {
      _log('download: failed ${e.runtimeType}: $e');
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  static bool isCancelled(Object error) => error is _Cancelled;

  // ---------------------------------------------------------------------------------------- install

  /// Starts the installer and returns "ok", "permission" (Android: allowing installs from this app is still needed)
  /// or "error:<reason>". Windows: the app closes, a silent setup replaces the files and starts the new
  /// version. Android: the system installer opens (the user may first be asked to allow installs from this app; the
  /// downloaded file is kept, so a second tap does not download again). Returns false when it could not be started.
  static Future<String> install(File file) async {
    _log('install: ${file.path} (${file.existsSync() ? file.lengthSync() : 'missing'} bytes)');
    // Verify again right before starting: the file must still be exactly what GitHub published.
    final expected = _readMeta()?['sha256'] as String?;
    if (expected == null || !file.existsSync()) return 'error:the downloaded file cannot be verified';
    final actual = await _sha256Of(file);
    _log('install: sha256 $actual, expected $expected');
    if (actual != expected) {
      _deleteFolder();
      return 'error:the downloaded file does not match the published checksum and was deleted';
    }
    final result = await _install(file);
    _log('install: result $result');
    return result;
  }

  static Future<String> _install(File file) async {
    if (PlatformInfo.isWindows) {
      final logPath = '${file.parent.path}${Platform.pathSeparator}setup.log';
      final args = ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/LOG=$logPath'];
      try {
        // The setup is started directly and detached from this process. It waits by itself until the running app
        // (its single-instance mutex) is gone, so the app only has to close right after.
        await Process.start(file.path, args, mode: ProcessStartMode.detached);
        _log('install: setup started directly, log $logPath');
      } catch (e) {
        _log('install: direct start failed ${e.runtimeType}: $e; trying the shell');
        try {
          final path = file.path.replaceAll("'", "''");
          final list = args.map((a) => "'${a.replaceAll("'", "''")}'").join(',');
          final script = 'Start-Process -FilePath \'$path\' -ArgumentList $list';
          final bytes = <int>[for (final unit in script.codeUnits) ...[unit & 0xFF, unit >> 8]];
          await Process.start(
            'powershell.exe',
            ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', base64Encode(bytes)],
            mode: ProcessStartMode.detached,
          );
          _log('install: setup started through the shell');
        } catch (e2) {
          return 'error:${e2.runtimeType}: $e2';
        }
      }
      Future<void>.delayed(const Duration(milliseconds: 1500), () => WindowsDesktopService.instance.exitApp());
      return 'ok';
    }
    if (PlatformInfo.isAndroid) return AthanAndroid.installApk(file.path);
    return 'error:unsupported';
  }

  /// Opens the release page of GitHub in the browser (the fallback whenever the in-app update is not possible).
  static Future<void> openReleasePage([UpdateInfo? info]) async {
    final url = info?.pageUrl ?? 'https://github.com/$repository/releases/latest';
    try {
      if (PlatformInfo.isAndroid) {
        await AthanAndroid.openUrl(url);
      } else if (PlatformInfo.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
