import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'athan/athan_android.dart';
import 'l10n/l10n.dart';
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
    if (PlatformInfo.isWindows) {
      // A native Arm64 build prefers the Arm64 package; the x64 package also runs there through emulation.
      final arm64 = Platform.version.contains('windows_arm64');
      return arm64 ? const ['MoonCalendar-windows-arm64.zip', 'MoonCalendar-windows-x64.zip'] : const ['MoonCalendar-windows-x64.zip'];
    }
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
    _scanUpdaterFolders();
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

  // ------------------------------------------------------------------------ Windows helper leftovers

  /// Details of an update that failed while the application was closed (the helper rolled back), found at start.
  static String? pendingFailure;

  static bool _cleanupScheduled = false;

  static Iterable<Directory> _updaterFolders() sync* {
    if (!PlatformInfo.isWindows) return;
    try {
      for (final e in Directory.systemTemp.listSync(followLinks: false)) {
        if (e is Directory && e.path.split(Platform.pathSeparator).last.startsWith('mooncalendar-updater-')) yield e;
      }
    } catch (_) {}
  }

  /// Reads a recorded failure, then removes helper folders that are no longer in use (a helper that is still
  /// finishing its work keeps its folder, so younger ones are left and looked at again a little later).
  static void _scanUpdaterFolders() {
    var young = false;
    for (final dir in _updaterFolders().toList()) {
      try {
        final failedFile = File('${dir.path}${Platform.pathSeparator}helper.failed');
        if (pendingFailure == null && failedFile.existsSync()) {
          final logFile = File('${dir.path}${Platform.pathSeparator}update.log');
          final lines = logFile.existsSync() ? logFile.readAsLinesSync() : const <String>[];
          pendingFailure = 'helper: ${failedFile.readAsStringSync().replaceFirst('\uFEFF', '').trim()}\n${lines.skip(lines.length > 12 ? lines.length - 12 : 0).join('\n')}';
        }
        final age = DateTime.now().difference(dir.statSync().modified);
        if (age > const Duration(minutes: 5)) {
          dir.deleteSync(recursive: true);
        } else {
          young = true;
        }
      } catch (_) {}
    }
    if (young && !_cleanupScheduled) {
      _cleanupScheduled = true;
      Timer(const Duration(minutes: 6), () {
        _cleanupScheduled = false;
        _scanUpdaterFolders();
      });
    }
  }

  /// Removes every temporary file of the update system: the download, the helper folders and the failure record.
  /// Used when the user does not retry a failed update.
  static void purge() {
    pendingFailure = null;
    _deleteFolder();
    for (final dir in _updaterFolders().toList()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// The updated application tells the waiting helper that it started properly; without this the helper
  /// would roll the update back.
  static Future<bool> confirmHealthy() async {
    final path = Platform.environment['MOONCALENDAR_UPDATE_HEALTH_FILE'];
    if (path == null || path.isEmpty) return false;
    try {
      await File(path).writeAsString('healthy', flush: true);
      return true;
    } catch (_) {
      return false;
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

  /// Downloads the release file (or returns the one already downloaded). [onProgress] receives bytes received and
  /// total bytes (null when unknown); [cancelled] aborts. Whatever goes wrong, no partial file stays behind.
  static Future<File> download(UpdateInfo info, {required void Function(int receivedBytes, int? totalBytes) onProgress, required bool Function() cancelled}) async {
    _log('download: ${info.assetName} (${info.assetSize} bytes)');
    if (info.sha256 == null || !_isTrustedUrl(info.assetUrl)) throw const HttpException('No published checksum or untrusted address; the file is not downloaded');
    final existing = await readyFile(info);
    if (existing != null) {
      _log('download: reusing the verified file');
      onProgress(existing.lengthSync(), info.assetSize ?? existing.lengthSync());
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
      _log('download: HTTP ${response.statusCode}, length ${response.contentLength}');
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
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      _log('download: received $received of $total bytes');
      if (total != null && total > 0 && received != total) throw HttpException('The downloaded file is incomplete ($received of $total bytes)');
      if (info.assetSize != null && received != info.assetSize) throw HttpException('The downloaded file size does not match GitHub metadata ($received of ${info.assetSize} bytes)');
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
      _log('download: failed (${e.runtimeType})');
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

  /// Starts the update and returns "ok", "permission" (Android: allowing installs from this app is still needed)
  /// or "error:<reason>". Windows: a detached helper safely swaps the verified ZIP and relaunches the app.
  /// Android: the system installer opens (the user may first be asked to allow installs from this app; the
  /// downloaded file is kept, so a second tap does not download again). Returns false when it could not be started.
  static Future<String> install(File file) async {
    _log('install: file ${file.existsSync() ? file.lengthSync() : 'missing'} bytes');
    // Verify again right before starting: the file must still be exactly what GitHub published.
    final expected = _readMeta()?['sha256'] as String?;
    if (expected == null || !file.existsSync()) return 'error:the downloaded file cannot be verified';
    final actual = await _sha256Of(file);
    _log('install: sha256 $actual, expected $expected');
    if (actual != expected) {
      _deleteFolder();
      return 'error:the downloaded file does not match the published checksum and was deleted';
    }
    final result = await _install(file, expected);
    _log('install: result $result');
    return result;
  }

  static Future<String> _install(File file, String expectedHash) async {
    if (PlatformInfo.isWindows) {
      // The helper runs outside the Flutter process. It waits for this process to exit before
      // touching any locked DLL/EXE, stages the complete ZIP beside the install directory,
      // preserves Inno Setup's uninstaller files, swaps directories, and rolls back on failure.
      // Folders of earlier attempts are no longer needed (no helper is running while the app is open).
      for (final old in _updaterFolders().toList()) {
        try {
          old.deleteSync(recursive: true);
        } catch (_) {}
      }
      final tempDir = Directory.systemTemp.createTempSync('mooncalendar-updater-');
      final scriptFile = File('${tempDir.path}${Platform.pathSeparator}update.ps1');
      final logPath = '${tempDir.path}${Platform.pathSeparator}update.log';
      final startedPath = '${tempDir.path}${Platform.pathSeparator}helper.started';
      final readyPath = '${tempDir.path}${Platform.pathSeparator}helper.ready';
      final failurePath = '${tempDir.path}${Platform.pathSeparator}helper.failed';
      final appExe = Platform.resolvedExecutable;
      final appPid = pid;
      final archive = file.path;
      final healthPath = '${tempDir.path}${Platform.pathSeparator}helper.healthy';
      final helperExpectedHash = expectedHash.toLowerCase();
      const ps = r"""
param([string]$Archive, [string]$AppExe, [int]$AppPid, [string]$LogPath, [string]$StartedPath, [string]$ReadyPath, [string]$FailurePath, [string]$ExpectedSha256, [string]$HealthPath, [string]$Lang)
$ErrorActionPreference = 'Stop'
# Window texts in the language the application was using when it closed.
$Strings = @{
  fa = @{ title = 'به‌روزرسانی برنامه'; check = 'بررسی فایل به‌روزرسانی…'; extract = 'در حال استخراج فایل‌ها…'; waitClose = 'در انتظار بسته‌شدن برنامه…'; replace = 'در حال جایگزینی نسخه…'; health = 'تست سلامت برنامه…'; result = 'در حال نمایش نتیجه در برنامه…'; done = 'تمام شد.'; failRestoring = 'به‌روزرسانی ناموفق بود؛ نسخهٔ قبلی بازیابی می‌شود…'; failRestored = 'به‌روزرسانی ناموفق بود؛ نسخهٔ قبلی بازیابی شد.'; failManual = 'بازیابی خودکار کامل نشد؛ گزارش موقت به‌روزرسانی را بررسی کنید.'; close = 'بستن'; rtl = $true }
  en = @{ title = 'Updating the app'; check = 'Checking the update file…'; extract = 'Extracting files…'; waitClose = 'Waiting for the app to close…'; replace = 'Replacing the version…'; health = 'App health check…'; result = 'Showing the result in the app…'; done = 'Done.'; failRestoring = 'The update failed; restoring the previous version…'; failRestored = 'The update failed; the previous version was restored.'; failManual = 'Automatic recovery could not be completed; check the temporary update log.'; close = 'Close'; rtl = $false }
  ar = @{ title = 'تحديث التطبيق'; check = 'جارٍ فحص ملف التحديث…'; extract = 'جارٍ استخراج الملفات…'; waitClose = 'في انتظار إغلاق التطبيق…'; replace = 'جارٍ استبدال الإصدار…'; health = 'فحص سلامة التطبيق…'; result = 'جارٍ عرض النتيجة في التطبيق…'; done = 'تم.'; failRestoring = 'فشل التحديث؛ تتم استعادة الإصدار السابق…'; failRestored = 'فشل التحديث؛ تمت استعادة الإصدار السابق.'; failManual = 'تعذّر إكمال الاستعادة التلقائية؛ راجع سجل التحديث المؤقت.'; close = 'إغلاق'; rtl = $true }
}
$T = if ($Strings.ContainsKey($Lang)) { $Strings[$Lang] } else { $Strings['fa'] }
function Write-Log([string]$line) {
  try { Add-Content -LiteralPath $LogPath -Value ((Get-Date -Format o) + ' ' + $line) } catch {}
}
Write-Log 'Script entered.'
# The helper is started from the application folder; as its current directory that folder could not be renamed.
try { Set-Location -LiteralPath $env:SystemRoot; [System.Environment]::CurrentDirectory = $env:SystemRoot } catch { Write-Log ('Could not leave the working directory: ' + $_.Exception.Message) }
$AbortPath = Join-Path (Split-Path -Parent $StartedPath) 'helper.abort'
# Only one helper may run, however many times it was launched.
$script:singleton = New-Object System.Threading.Mutex($false, 'Local\MoonCalendar.UpdateHelper')
if (-not $script:singleton.WaitOne(0)) { Write-Log 'Another helper is already running.'; exit }
if (Test-Path -LiteralPath $AbortPath) { Write-Log 'Aborted before start.'; exit }
function Write-Status([string]$path, [string]$value) {
  $temp = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
  [System.IO.File]::WriteAllText($temp, $value, [System.Text.Encoding]::UTF8)
  try { [System.IO.File]::Move($temp, $path) }
  catch { try { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } catch {}; throw }
}
function Test-ReservedWindowsName([string]$segment) {
  $base = ($segment -split '\.')[0]
  return $base -match '^(?i:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])$'
}
function Get-SafeEntryName([string]$rawName) {
  if ([string]::IsNullOrWhiteSpace($rawName)) { throw 'ZIP contains an empty entry name.' }
  $name = $rawName.Replace('\','/')
  if ($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or $name.Contains(':') -or $name.Contains([char]0)) { throw 'ZIP contains an absolute or invalid path.' }
  $isDirectory = $name.EndsWith('/')
  $trimmed = $name.TrimEnd('/')
  if ([string]::IsNullOrWhiteSpace($trimmed)) { throw 'ZIP contains an invalid root entry.' }
  $segments = $trimmed.Split('/')
  foreach ($segment in $segments) {
    if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') { throw 'ZIP contains a traversal path.' }
    if ($segment.EndsWith('.') -or $segment.EndsWith(' ')) { throw 'ZIP contains a Windows-ambiguous filename.' }
    if ($segment -match '[<>"|?*]' -or $segment -match '[\x00-\x1F]') { throw 'ZIP contains an invalid Windows filename.' }
    if (Test-ReservedWindowsName $segment) { throw 'ZIP contains a reserved Windows filename.' }
  }
  return [pscustomobject]@{ Name = ($segments -join '\'); IsDirectory = $isDirectory }
}
function Get-ArchiveInventory([string]$archivePath) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    if ($zip.Entries.Count -lt 1 -or $zip.Entries.Count -gt 50000) { throw 'ZIP entry count is outside the permitted range.' }
    $seen = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $totalLength = [int64]0
    $hasExe = $false; $hasFlutterDll = $false; $hasAssets = $false
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $zip.Entries) {
      $safe = Get-SafeEntryName $entry.FullName
      $normalized = $safe.Name
      if ($seen.ContainsKey($normalized)) { throw 'ZIP contains duplicate paths that differ only by case or repeat.' }
      $seen.Add($normalized, $(if ($safe.IsDirectory) { 'D' } else { 'F' }))
      # Reject files used as parent directories (e.g. "data" and "data/file.dll").
      $parts = $normalized.Split([char[]]@([char]92))
      for ($i = 1; $i -lt $parts.Length; $i++) {
        $ancestor = ($parts[0..($i - 1)] -join '\')
        if ($seen.ContainsKey($ancestor) -and $seen[$ancestor] -eq 'F') { throw 'ZIP contains a file/directory path collision.' }
      }
      if (-not $safe.IsDirectory) {
        if ($entry.Length -lt 0 -or $entry.Length -gt 1073741824) { throw 'ZIP contains an oversized file.' }
        $totalLength += [int64]$entry.Length
        if ($totalLength -gt 2147483648) { throw 'ZIP expands beyond the 2 GiB safety limit.' }
        if ($normalized -ieq 'mooncalendar.exe') { $hasExe = $true }
        if ($normalized -ieq 'flutter_windows.dll') { $hasFlutterDll = $true }
        if ($normalized -match '(?i)^data\\flutter_assets\\') { $hasAssets = $true }
      }
      $entries.Add([pscustomobject]@{ Name = $normalized; IsDirectory = $safe.IsDirectory })
    }
    # Also reject a parent added after its child in the archive.
    foreach ($item in $entries) {
      $parts = $item.Name.Split([char[]]@([char]92))
      for ($i = 1; $i -lt $parts.Length; $i++) {
        $ancestor = ($parts[0..($i - 1)] -join '\')
        if ($seen.ContainsKey($ancestor) -and $seen[$ancestor] -eq 'F') { throw 'ZIP contains a file/directory path collision.' }
      }
    }
    if (-not $hasExe -or -not $hasFlutterDll -or -not $hasAssets) { throw 'ZIP is missing required Flutter Windows runtime files.' }
    return ,$entries.ToArray()
  } finally { $zip.Dispose() }
}
function Expand-SafeArchive([string]$archivePath, [string]$destination, [object[]]$inventory) {
  $root = [System.IO.Path]::GetFullPath($destination).TrimEnd([char]92) + '\'
  $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    $entryMap = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($candidate in $zip.Entries) {
      $candidateSafe = Get-SafeEntryName $candidate.FullName
      if (-not $candidateSafe.IsDirectory) { $entryMap.Add($candidateSafe.Name, $candidate) }
    }
    foreach ($item in $inventory) {
      $target = [System.IO.Path]::GetFullPath((Join-Path $destination $item.Name))
      if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'ZIP entry resolves outside staging directory.' }
      if ($item.IsDirectory) {
        [System.IO.Directory]::CreateDirectory($target) | Out-Null
      } else {
        $parent = [System.IO.Path]::GetDirectoryName($target)
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        if (-not $entryMap.ContainsKey($item.Name)) { throw 'Validated ZIP entry could not be found during extraction.' }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entryMap[$item.Name], $target, $false)
      }
    }
  } finally { $zip.Dispose() }
}
$form = $null
try {
  Write-Status $StartedPath 'started'
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $form = New-Object System.Windows.Forms.Form
  # Follow the Windows app theme (dark / light).
  $dark = $false
  try { $dark = ((Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop) -eq 0) } catch {}
  $back = if ($dark) { [System.Drawing.Color]::FromArgb(32,32,32) } else { [System.Drawing.Color]::FromArgb(243,243,243) }
  $fore = if ($dark) { [System.Drawing.Color]::FromArgb(245,245,245) } else { [System.Drawing.Color]::FromArgb(20,20,20) }
  $form.Text = 'MoonCalendar'
  # The window stays invisible while everything goes well; it is shown only when the update failed and the
  # previous version could not be started again.
  $form.StartPosition = 'Manual'
  $form.Location = New-Object System.Drawing.Point(-32000, -32000)
  $form.Opacity = 0
  $form.ShowInTaskbar = $false
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.ControlBox = $true
  $form.ClientSize = New-Object System.Drawing.Size(460,190)
  $form.TopMost = $true
  $form.BackColor = $back; $form.ForeColor = $fore
  if ($T.rtl) { $form.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes; $form.RightToLeftLayout = $true }
  $script:finished = $false
  function Show-Window {
    try {
      $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
      $form.Location = New-Object System.Drawing.Point(($area.X + [int](($area.Width - $form.Width) / 2)), ($area.Y + [int](($area.Height - $form.Height) / 2)))
      $form.ShowInTaskbar = $true
      $form.Opacity = 1
      $form.Visible = $true
      $form.Activate()
    } catch { Write-Log ('Could not show the window: ' + $_.Exception.Message) }
  }
  # Closing the window while the update runs only hides it: the update itself must never be interrupted.
  $form.add_FormClosing({ param($sender, $e) if (-not $script:finished) { $e.Cancel = $true; $sender.Hide() } })
  $title = New-Object System.Windows.Forms.Label
  $title.Text = $T.title
  $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
  $title.AutoSize = $false; $title.TextAlign = 'MiddleCenter'; $title.SetBounds(15,15,430,30); $title.ForeColor = $fore
  $status = New-Object System.Windows.Forms.Label
  $status.Text = $T.check
  $status.Font = New-Object System.Drawing.Font('Segoe UI', 9)
  $status.AutoSize = $false; $status.TextAlign = 'MiddleCenter'; $status.SetBounds(15,52,430,30); $status.ForeColor = $fore
  $bar = New-Object System.Windows.Forms.ProgressBar
  $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 25; $bar.SetBounds(35,100,390,18)
  $closeButton = New-Object System.Windows.Forms.Button
  $closeButton.Text = $T.close
  $closeButton.SetBounds(180,140,100,32)
  $closeButton.FlatStyle = 'System'
  $closeButton.add_Click({ if ($script:finished) { $form.Close() } else { $form.Hide() } })
  $form.Controls.AddRange(@($title,$status,$bar,$closeButton))
  $form.add_Shown({
    $appRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $AppExe))
    $parent = Split-Path -Parent $appRoot
    $leaf = Split-Path -Leaf $appRoot
    $token = [Guid]::NewGuid().ToString('N')
    $stage = Join-Path $parent ('.' + $leaf + '.stage-' + $token)
    $backup = Join-Path $parent ('.' + $leaf + '.backup-' + $token)
    $newRootActive = $false
    $appExited = $false
    $newProcessId = 0
    try {
      Write-Log 'Helper started.'
      if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw 'Downloaded ZIP is missing.' }
      $actualHash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Downloaded ZIP checksum changed before extraction.' }
      if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Expected checksum is invalid.' }
      if (-not (Test-Path -LiteralPath $appRoot -PathType Container)) { throw 'Install directory not found.' }
      $parentProbe = Join-Path $parent ('.mooncalendar-update-probe-' + $token)
      [System.IO.File]::WriteAllText($parentProbe, 'probe')
      Remove-Item -LiteralPath $parentProbe -Force

      $status.Text = $T.extract
      $inventory = Get-ArchiveInventory $Archive
      New-Item -ItemType Directory -Path $stage | Out-Null
      Expand-SafeArchive $Archive $stage $inventory
      $stagedExe = Join-Path $stage 'mooncalendar.exe'
      if (-not (Test-Path -LiteralPath $stagedExe -PathType Leaf) -or (Get-Item -LiteralPath $stagedExe).Length -lt 1024) { throw 'Staged executable is missing or too small.' }
      if (-not (Test-Path -LiteralPath (Join-Path $stage 'flutter_windows.dll') -PathType Leaf)) { throw 'Staged Flutter runtime is missing.' }
      if (-not (Test-Path -LiteralPath (Join-Path $stage 'data\flutter_assets') -PathType Container)) { throw 'Staged Flutter assets are missing.' }

      # Keep Inno Setup uninstall metadata; the updater is only for the app files, not installer registration.
      Get-ChildItem -LiteralPath $appRoot -Force -ErrorAction Stop |
        Where-Object { $_.Name -match '^unins.*\.(exe|dat|msg)$' -and $_ -is [System.IO.FileInfo] } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stage -Force -ErrorAction Stop }

      # Ready is emitted only when download verification, ZIP inventory, extraction and runtime checks pass.
      Write-Status $ReadyPath 'ready'
      if (Test-Path -LiteralPath $AbortPath) { throw 'Update was cancelled by the application.' }
      $status.Text = $T.waitClose
      $deadline = (Get-Date).AddSeconds(45)
      while ((Get-Process -Id $AppPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
      if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) { throw 'MoonCalendar did not exit within 45 seconds.' }
      $appExited = $true

      $status.Text = $T.replace
      # Record transaction intent before changing directory names; all paths are on the same volume.
      Write-Log ('Swap transaction started. backup=' + (Split-Path -Leaf $backup))
      Move-Item -LiteralPath $appRoot -Destination $backup -ErrorAction Stop
      try {
        Move-Item -LiteralPath $stage -Destination $appRoot -ErrorAction Stop
        $newRootActive = $true
      } catch {
        if (-not (Test-Path -LiteralPath $appRoot) -and (Test-Path -LiteralPath $backup)) { Move-Item -LiteralPath $backup -Destination $appRoot -ErrorAction Stop }
        throw
      }

      $status.Text = $T.health
      Write-Log 'Directory swap completed. Starting updated application for health confirmation.'
      $env:MOONCALENDAR_UPDATE_HEALTH_FILE = $HealthPath
      $started = Start-Process -FilePath (Join-Path $appRoot 'mooncalendar.exe') -PassThru -WorkingDirectory $appRoot -ErrorAction Stop
      $newProcessId = $started.Id
      $healthDeadline = (Get-Date).AddSeconds(45)
      $healthy = $false
      while ((Get-Date) -lt $healthDeadline) {
        $started.Refresh()
        if ($started.HasExited) { throw ('Updated application exited before health confirmation, code=' + $started.ExitCode) }
        if (Test-Path -LiteralPath $HealthPath -PathType Leaf) {
          $healthy = ([System.IO.File]::ReadAllText($HealthPath).Trim() -eq 'healthy')
          if ($healthy) {
            # A brief stabilization window catches an immediate crash after the application writes its marker.
            $stableUntil = (Get-Date).AddSeconds(1.5)
            while ((Get-Date) -lt $stableUntil) {
              $started.Refresh()
              if ($started.HasExited) { throw ('Updated application exited immediately after health confirmation, code=' + $started.ExitCode) }
              [System.Windows.Forms.Application]::DoEvents()
              Start-Sleep -Milliseconds 100
            }
            break
          }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
      }
      if (-not $healthy) { throw 'Updated application did not report a healthy startup within 45 seconds.' }
      Write-Log ('Updated application health confirmed and stable. pid=' + $started.Id)
      # The new version is confirmed: the rollback copy and any leftovers of earlier attempts are no longer needed.
      Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ('.' + $leaf + '.backup-*') -or $_.Name -like ('.' + $leaf + '.failed-*') -or $_.Name -like ('.' + $leaf + '.stage-*') } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      $status.Text = $T.done
      $script:finished = $true
      $form.Close()
    } catch {
      $failureType = $_.Exception.GetType().Name
      $failureText = $failureType + ': ' + $_.Exception.Message
      if ($failureText.Length -gt 300) { $failureText = $failureText.Substring(0, 300) }
      Write-Log ('Update failed: ' + $failureText)
      try { Write-Status $FailurePath $failureText } catch { Write-Log 'Could not write failure status.' }
      $status.Text = $T.failRestoring
      if ($newProcessId -ne 0) {
        try {
          $newProc = Get-Process -Id $newProcessId -ErrorAction SilentlyContinue
          if ($null -ne $newProc) {
            Stop-Process -Id $newProcessId -Force -ErrorAction SilentlyContinue
            [void]$newProc.WaitForExit(5000)
          }
        } catch { Write-Log ('Could not stop updated process: ' + $_.Exception.GetType().Name) }
      }
      if ((Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $appRoot)) {
        try {
          $failedRoot = $appRoot + '.failed-' + [Guid]::NewGuid().ToString('N')
          Move-Item -LiteralPath $appRoot -Destination $failedRoot -ErrorAction Stop
          $newRootActive = $false
        } catch { Write-Log ('Could not move failed app directory aside: ' + $_.Exception.GetType().Name) }
      }
      $previousAvailable = $false
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $appRoot)) {
        try {
          Move-Item -LiteralPath $backup -Destination $appRoot -ErrorAction Stop
          $previousAvailable = $true
          Write-Log 'Rollback completed.'
        } catch { Write-Log ('Could not restore rollback directory: ' + $_.Exception.GetType().Name) }
      } elseif ((Test-Path -LiteralPath $appRoot) -and -not (Test-Path -LiteralPath $backup)) {
        # The swap had not started or the old directory was already restored by the nested promotion guard.
        $previousAvailable = $true
      }
      if (Test-Path -LiteralPath $stage) { try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop } catch { Write-Log ('Could not remove staging directory: ' + $_.Exception.GetType().Name) } }
      if ($appExited -and $previousAvailable -and (Test-Path -LiteralPath $AppExe)) {
        try { Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path -Parent $AppExe) -ErrorAction Stop; Write-Log 'Previous application relaunched.' }
        catch { Write-Log ('Previous application relaunch failed: ' + $_.Exception.GetType().Name); $previousAvailable = $false }
      }
      if ($previousAvailable) {
        $status.Text = $T.failRestored
      } else {
        $status.Text = $T.failManual
        Write-Log 'Automatic rollback could not be fully confirmed.'
      }
      $bar.Style = 'Blocks'; $bar.Value = 100
      # With the previous version running again, the application itself reports the failure at its start;
      # the window appears only when even that did not work out, and then it stays until it is closed.
      $script:finished = $true
      if (-not $previousAvailable) { Show-Window } else { $form.Close() }
    } finally {
      try { Remove-Item Env:\MOONCALENDAR_UPDATE_HEALTH_FILE -ErrorAction SilentlyContinue } catch {}
    }
  })
  [void]$form.ShowDialog()
} catch {
  $failureType = $_.Exception.GetType().Name
  Write-Log ('Helper bootstrap failed: ' + $failureType)
  try { Write-Status $FailurePath ('bootstrap:' + $failureType) } catch {}
  try { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('MoonCalendar update helper could not start. Check the updater log in the temporary directory.', 'MoonCalendar Update', 'OK', 'Error') | Out-Null } catch {}
} finally {
  if ($null -ne $form) { try { $form.Dispose() } catch {} }
}
""";
      final started = File(startedPath);
      final ready = File(readyPath);
      final failed = File(failurePath);
      String readStatus(File f) {
        try { return f.readAsStringSync().replaceFirst('﻿', '').trim(); } catch (_) { return ''; }
      }
      Future<bool> waitStarted(Duration limit) async {
        final deadline = DateTime.now().add(limit);
        while (readStatus(started) != 'started' && readStatus(failed).isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        return readStatus(started) == 'started' && readStatus(failed).isEmpty;
      }

      Future<void> abortHelper() async {
        try { File('${tempDir.path}${Platform.pathSeparator}helper.abort').writeAsStringSync('abort'); } catch (_) {}
      }

      Future<String> describeFailure() async {
        // Collected for the technical report: what exists in the helper folder and whether PowerShell itself works.
        try {
          _log('install: helper folder holds ${[for (final e in tempDir.listSync()) e.path.split(Platform.pathSeparator).last]}');
          final logFile = File(logPath);
          if (logFile.existsSync()) {
            final lines = logFile.readAsLinesSync();
            _log('install: helper log\n${lines.skip(lines.length > 12 ? lines.length - 12 : 0).join('\n')}');
          }
        } catch (_) {}
        try {
          final probe = await Process.run(
            'powershell.exe',
            ['-NoProfile', '-NonInteractive', '-Command', r'$PSVersionTable.PSVersion.ToString() + " " + $ExecutionContext.SessionState.LanguageMode'],
          ).timeout(const Duration(seconds: 25));
          _log('install: PowerShell probe exit ${probe.exitCode}: ${'${probe.stdout}'.trim()} ${'${probe.stderr}'.trim()}');
        } catch (e) {
          _log('install: PowerShell probe failed (${e.runtimeType}: $e)');
        }
        return 'error:helper_initialization_failed';
      }

      final psArgs = <String>[
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', scriptFile.path,
        archive, appExe, appPid.toString(), logPath, startedPath, readyPath, failurePath, helperExpectedHash, healthPath, L10n.lang.code,
      ];
      try {
        await scriptFile.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(ps)], flush: true);
      } catch (e) {
        _log('install: could not write the helper script (${e.runtimeType}: $e)');
        return 'error:${e.runtimeType}';
      }
      // Starting a hidden, fully independent PowerShell is the fragile step, so several ways are tried one after
      // another; the helper itself refuses to run twice.
      var launched = false;
      try {
        final r = await Process.run('cmd.exe', ['/d', '/c', 'start', '', '/min', 'powershell.exe', ...psArgs], workingDirectory: tempDir.path).timeout(const Duration(seconds: 20));
        _log('install: launch 1 (start) exit ${r.exitCode} ${'${r.stderr}'.trim()}');
        launched = await waitStarted(const Duration(seconds: 25));
      } catch (e) {
        _log('install: launch 1 failed (${e.runtimeType}: $e)');
      }
      if (!launched && readStatus(failed).isEmpty) {
        try {
          await Process.start('powershell.exe', psArgs, mode: ProcessStartMode.detachedWithStdio, workingDirectory: tempDir.path);
          _log('install: launch 2 (detached with pipes) created');
          launched = await waitStarted(const Duration(seconds: 20));
        } catch (e) {
          _log('install: launch 2 failed (${e.runtimeType}: $e)');
        }
      }
      if (!launched && readStatus(failed).isEmpty) {
        try {
          final process = await Process.start('powershell.exe', psArgs, workingDirectory: tempDir.path);
          unawaited(process.stdout.drain<void>());
          unawaited(process.stderr.drain<void>());
          _log('install: launch 3 (attached) created');
          launched = await waitStarted(const Duration(seconds: 20));
        } catch (e) {
          _log('install: launch 3 failed (${e.runtimeType}: $e)');
        }
      }
      if (!launched) {
        _log('install: helper did not initialize');
        await abortHelper();
        return describeFailure();
      }
      final readyDeadline = DateTime.now().add(const Duration(seconds: 120));
      while (readStatus(ready) != 'ready' && readStatus(failed).isEmpty && DateTime.now().isBefore(readyDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (readStatus(ready) != 'ready' || readStatus(failed).isNotEmpty) {
        _log('install: helper preparation failed (${readStatus(failed)})');
        await abortHelper();
        await describeFailure();
        return 'error:helper_preparation_failed';
      }
      // The helper waits for this process to disappear; if a clean shutdown (widget windows, tray) hangs, end it.
      Future<void>.delayed(const Duration(seconds: 6), () => exit(0));
      await WindowsDesktopService.instance.exitApp();
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
