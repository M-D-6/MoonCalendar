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
/// Downloads use an interruption-safe, integrity-checked flow:
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

  /// Compares semantic versions, ignoring build metadata (for example, `1.1.7+12` equals `v1.1.7`).
  /// A stable release sorts after its pre-releases; numeric pre-release identifiers sort numerically.
  static int compareVersions(String a, String b) {
    ({List<int> core, List<String> pre}) parse(String input) {
      var value = input.trim().replaceFirst(RegExp(r'^[vV]'), '');
      value = value.split('+').first; // SemVer build metadata does not affect precedence.
      final dash = value.indexOf('-');
      final coreText = dash < 0 ? value : value.substring(0, dash);
      final preText = dash < 0 ? '' : value.substring(dash + 1);
      final core = coreText.split('.').map((part) => int.tryParse(part) ?? 0).toList();
      final pre = preText.isEmpty ? <String>[] : preText.split('.');
      return (core: core, pre: pre);
    }

    final x = parse(a), y = parse(b);
    final coreLength = x.core.length > y.core.length ? x.core.length : y.core.length;
    for (var i = 0; i < coreLength; i++) {
      final p = i < x.core.length ? x.core[i] : 0;
      final q = i < y.core.length ? y.core[i] : 0;
      if (p != q) return p > q ? 1 : -1;
    }

    if (x.pre.isEmpty && y.pre.isEmpty) return 0;
    if (x.pre.isEmpty) return 1;
    if (y.pre.isEmpty) return -1;
    final preLength = x.pre.length > y.pre.length ? x.pre.length : y.pre.length;
    for (var i = 0; i < preLength; i++) {
      if (i >= x.pre.length) return -1;
      if (i >= y.pre.length) return 1;
      final p = x.pre[i], q = y.pre[i];
      if (p == q) continue;
      final pn = int.tryParse(p), qn = int.tryParse(q);
      if (pn != null && qn != null) return pn > qn ? 1 : -1;
      if (pn != null) return -1; // Numeric identifiers have lower precedence than non-numeric ones.
      if (qn != null) return 1;
      return p.compareTo(q) > 0 ? 1 : -1;
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
    if (PlatformInfo.isWindows) return const ['MoonCalendar-windows-x64.zip'];
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

  /// Starts the updater and returns "ok", "permission" (Android: allowing installs from this app is still needed)
  /// or an error string with a reason suffix. Windows: a detached helper stages the portable ZIP, swaps the app directory with
  /// a rollback copy, and relaunches the app. Android: the system installer opens (the user may first be asked to allow installs from this app; the
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
      final launcherLogPath = '${file.parent.path}${Platform.pathSeparator}update-launcher.log';
      String psLiteral(String value) => "'${value.replaceAll("'", "''")}'";

      // Detached updater: stage and validate first, keep a complete rollback directory, then promote.
      final script = r'''
$ErrorActionPreference = 'Stop'
$mooncalendarProcessId = __PARENT_PID__
$zipPath = __ZIP_PATH__
$launcherLogPath = __LAUNCHER_LOG_PATH__
$installDir = __INSTALL_DIR__
$exeName = 'mooncalendar.exe'
$parentDir = Split-Path -Parent $installDir
$leaf = Split-Path -Leaf $installDir
$token = [Guid]::NewGuid().ToString('N')
$stageDir = Join-Path $parentDir ('.' + $leaf + '.stage-' + $token)
$backupDir = Join-Path $parentDir ('.' + $leaf + '.backup-' + $token)
$promoted = $false
function Log([string]$message) { try { Add-Content -LiteralPath $launcherLogPath -Value ((Get-Date -Format o) + ' ' + $message) } catch { } }
try {
  Log "Waiting for MoonCalendar PID $mooncalendarProcessId to exit. Install=$installDir"
  try { $parent = [System.Diagnostics.Process]::GetProcessById($mooncalendarProcessId); if (-not $parent.WaitForExit(120000)) { throw 'Timed out waiting for MoonCalendar to exit.' } } catch [System.ArgumentException] { }
  Start-Sleep -Milliseconds 400
  if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Portable ZIP not found: $zipPath" }
  if (-not (Test-Path -LiteralPath $installDir -PathType Container)) { throw "Install directory not found: $installDir" }

  # Reject ZIP path traversal before extracting anything.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $rootFull = [System.IO.Path]::GetFullPath($stageDir + [System.IO.Path]::DirectorySeparatorChar)
    foreach ($entry in $archive.Entries) {
      if ([string]::IsNullOrWhiteSpace($entry.FullName)) { continue }
      $destination = [System.IO.Path]::GetFullPath((Join-Path $stageDir ($entry.FullName -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
      if (-not $destination.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe path in update archive: $($entry.FullName)" }
    }
  } finally { $archive.Dispose() }
  New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $stageDir)
  if (-not (Test-Path -LiteralPath (Join-Path $stageDir $exeName) -PathType Leaf)) { throw 'Portable ZIP is missing mooncalendar.exe at its root.' }
  if (-not (Test-Path -LiteralPath (Join-Path $stageDir 'flutter_windows.dll') -PathType Leaf)) { throw 'Update bundle is missing flutter_windows.dll; installation was not changed.' }

  # Persist recovery metadata and register a per-user RunOnce recovery before touching the current install.
  # If Windows shuts down between directory renames, recovery runs at the next sign-in even if the app cannot launch.
  $recoveryRoot = Join-Path $env:LOCALAPPDATA 'MoonCalendar\Updater'
  New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
  $statePath = Join-Path $recoveryRoot ('transaction-' + $token + '.json')
  $recoveryScript = Join-Path $recoveryRoot 'recover-update.ps1'
  $state = [ordered]@{ installDir = $installDir; backupDir = $backupDir; stageDir = $stageDir; status = 'pending' }
  $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  @'
param([Parameter(Mandatory=$true)][string]$StateFile)
$ErrorActionPreference = 'Stop'
try {
  if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) { exit 0 }
  $s = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
  if ($s.status -eq 'committed') {
    if (Test-Path -LiteralPath $s.backupDir) { Remove-Item -LiteralPath $s.backupDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $s.stageDir) { Remove-Item -LiteralPath $s.stageDir -Recurse -Force -ErrorAction SilentlyContinue }
  } elseif (Test-Path -LiteralPath $s.backupDir) {
    if (Test-Path -LiteralPath $s.installDir) {
      $failed = $s.installDir + '.recovery-failed-' + [Guid]::NewGuid().ToString('N')
      Move-Item -LiteralPath $s.installDir -Destination $failed
    }
    Move-Item -LiteralPath $s.backupDir -Destination $s.installDir
    if ($failed -and (Test-Path -LiteralPath $failed)) { Remove-Item -LiteralPath $failed -Recurse -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $s.stageDir) { Remove-Item -LiteralPath $s.stageDir -Recurse -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
} catch { Add-Content -LiteralPath ($StateFile + '.log') -Value ((Get-Date -Format o) + ' recovery failed: ' + $_.ToString()) }
'@ | Set-Content -LiteralPath $recoveryScript -Encoding UTF8
  $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  $runOnceName = '!MoonCalendarUpdateRecovery'
  $runOnceCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $recoveryScript + '" -StateFile "' + $statePath + '"'
  New-Item -Path $runOnce -Force | Out-Null
  Set-ItemProperty -Path $runOnce -Name $runOnceName -Value $runOnceCommand -Force

  # Both directories are siblings, so renames stay on the same volume. Keep old files until new app survives startup.
  Log "Staging validated. Moving current installation to rollback directory $backupDir"
  Move-Item -LiteralPath $installDir -Destination $backupDir
  try { Move-Item -LiteralPath $stageDir -Destination $installDir; $promoted = $true }
  catch { if (-not (Test-Path -LiteralPath $installDir) -and (Test-Path -LiteralPath $backupDir)) { Move-Item -LiteralPath $backupDir -Destination $installDir }; throw }

  $newExe = Join-Path $installDir $exeName
  if (-not (Test-Path -LiteralPath $newExe -PathType Leaf)) { throw 'Promoted update is missing the app executable.' }
  Log "Starting updated app: $newExe"
  $newProcess = Start-Process -FilePath $newExe -WorkingDirectory $installDir -PassThru
  Start-Sleep -Seconds 12
  $newProcess.Refresh()
  if ($newProcess.HasExited) { throw "Updated app exited during startup (exit code $($newProcess.ExitCode)); rolling back." }
  Log "Updated app survived startup; removing rollback copy. PID=$($newProcess.Id)"
  $state.status = 'committed'
  $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name '!MoonCalendarUpdateRecovery' -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $backupDir -Recurse -Force
  Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
  try { Remove-Item -LiteralPath $zipPath -Force } catch { }
  try { Remove-Item -LiteralPath (Join-Path (Split-Path -Parent $zipPath) 'update.json') -Force } catch { }
  Log 'Update completed successfully.'
} catch {
  Log ("FAILED: " + $_.ToString())
  if ($promoted -and (Test-Path -LiteralPath $installDir)) {
    try {
      $failedDir = Join-Path $parentDir ('.' + $leaf + '.failed-' + $token)
      Move-Item -LiteralPath $installDir -Destination $failedDir
      if (Test-Path -LiteralPath $backupDir) { Move-Item -LiteralPath $backupDir -Destination $installDir }
      Remove-Item -LiteralPath $failedDir -Recurse -Force -ErrorAction SilentlyContinue
      Log 'Rollback completed; previous installation restored.'
      $oldExe = Join-Path $installDir $exeName
      if (Test-Path -LiteralPath $oldExe) { Start-Process -FilePath $oldExe -WorkingDirectory $installDir }
    } catch { Log ("ROLLBACK FAILED: " + $_.ToString()) }
  } elseif ((Test-Path -LiteralPath $backupDir) -and -not (Test-Path -LiteralPath $installDir)) {
    try { Move-Item -LiteralPath $backupDir -Destination $installDir; Log 'Recovered installation directory from rollback copy.' } catch { Log ("RECOVERY FAILED: " + $_.ToString()) }
  }
  try { if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}
'''
      .replaceAll('__PARENT_PID__', pid.toString())
      .replaceAll('__ZIP_PATH__', psLiteral(file.path))
      .replaceAll('__LAUNCHER_LOG_PATH__', psLiteral(launcherLogPath))
      .replaceAll('__INSTALL_DIR__', psLiteral(File(Platform.resolvedExecutable).parent.path));
      final bytes = <int>[for (final unit in script.codeUnits) ...[unit & 0xFF, unit >> 8]];
      try {
        await Process.start('powershell.exe', ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', base64Encode(bytes)], mode: ProcessStartMode.detached);
        _log('install: queued portable ZIP updater for PID $pid; log $launcherLogPath');
      } catch (e) {
        _log('install: could not start update launcher ${e.runtimeType}: $e');
        return 'error:could not start update launcher: $e';
      }
      Future<void>.delayed(const Duration(milliseconds: 500), () => WindowsDesktopService.instance.exitApp());
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
