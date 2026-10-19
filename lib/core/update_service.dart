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
param([string]$Archive, [string]$AppExe, [int]$AppPid, [string]$LogPath, [string]$StartedPath, [string]$ReadyPath, [string]$FailurePath, [string]$ExpectedSha256, [string]$HealthPath)
$ErrorActionPreference = 'Stop'
function Write-Log([string]$line) {
  try { Add-Content -LiteralPath $LogPath -Value ((Get-Date -Format o) + ' ' + $line) } catch {}
}
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
  $form.Text = 'MoonCalendar - Update'
  $form.StartPosition = 'CenterScreen'
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.ControlBox = $false
  $form.ClientSize = New-Object System.Drawing.Size(460,170)
  $form.TopMost = $true
  $title = New-Object System.Windows.Forms.Label
  $title.Text = 'در حال جایگزینی فایل‌های MoonCalendar'
  $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
  $title.AutoSize = $false; $title.TextAlign = 'MiddleCenter'; $title.SetBounds(15,15,430,30)
  $status = New-Object System.Windows.Forms.Label
  $status.Text = 'آماده‌سازی…'
  $status.Font = New-Object System.Drawing.Font('Segoe UI', 9)
  $status.AutoSize = $false; $status.TextAlign = 'MiddleCenter'; $status.SetBounds(15,52,430,30)
  $bar = New-Object System.Windows.Forms.ProgressBar
  $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 25; $bar.SetBounds(35,100,390,18)
  $form.Controls.AddRange(@($title,$status,$bar))
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

      $status.Text = 'در حال بررسی و استخراج فایل‌ها…'
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
      $status.Text = 'در انتظار بسته‌شدن برنامه…'
      $deadline = (Get-Date).AddSeconds(45)
      while ((Get-Process -Id $AppPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150 }
      if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) { throw 'MoonCalendar did not exit within 45 seconds.' }
      $appExited = $true

      $status.Text = 'در حال جایگزینی نسخهٔ فعلی…'
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

      $status.Text = 'در حال اجرای آزمایشی نسخهٔ جدید…'
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
            $stableUntil = (Get-Date).AddSeconds(3)
            while ((Get-Date) -lt $stableUntil) {
              $started.Refresh()
              if ($started.HasExited) { throw ('Updated application exited immediately after health confirmation, code=' + $started.ExitCode) }
              [System.Windows.Forms.Application]::DoEvents()
              Start-Sleep -Milliseconds 250
            }
            break
          }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 250
      }
      if (-not $healthy) { throw 'Updated application did not report a healthy startup within 45 seconds.' }
      Write-Log ('Updated application health confirmed and stable. pid=' + $started.Id)
      # Keep exactly one recent rollback directory; older backups are removed best-effort.
      Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.Name -like ('.' + $leaf + '.backup-*') -and $_.FullName -ne $backup) -or $_.Name -like ('.' + $leaf + '.failed-*') } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      $status.Text = 'تمام شد. برنامه با موفقیت اجرا شد.'
      $bar.Style = 'Blocks'; $bar.Value = 100
      Start-Sleep -Seconds 2
    } catch {
      $failureType = $_.Exception.GetType().Name
      Write-Log ('Update failed: ' + $failureType)
      try { Write-Status $FailurePath $failureType } catch { Write-Log 'Could not write failure status.' }
      $status.Text = 'به‌روزرسانی ناموفق بود؛ نسخهٔ قبلی بازیابی می‌شود…'
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
        $status.Text = 'به‌روزرسانی ناموفق بود؛ نسخهٔ قبلی بازیابی شد.'
      } else {
        $status.Text = 'بازیابی خودکار کامل نشد؛ گزارش موقت به‌روزرسانی را بررسی کنید.'
        Write-Log 'Automatic rollback could not be fully confirmed.'
      }
      $bar.Style = 'Blocks'; $bar.Value = 100
      Start-Sleep -Seconds 6
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
      try {
        await scriptFile.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(ps)], flush: true);
        await Process.start(
          'powershell.exe',
          ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA', '-File', scriptFile.path,
            archive, appExe, appPid.toString(), logPath, startedPath, readyPath, failurePath, helperExpectedHash, healthPath],
          mode: ProcessStartMode.detached,
        );
        _log('install: ZIP helper process created');
      } catch (e) {
        _log('install: ZIP helper failed (${e.runtimeType})');
        try { if (tempDir.existsSync()) tempDir.deleteSync(recursive: true); } catch (_) {}
        return 'error:${e.runtimeType}';
      }
      // Never exit until the helper has initialized, verified the ZIP, extracted the staging tree,
      // and checked the install parent. The actual directory rename is still guarded by rollback.
      final started = File(startedPath);
      final ready = File(readyPath);
      final failed = File(failurePath);
      String readStatus(File file) {
        try { return file.readAsStringSync().replaceFirst('\uFEFF', '').trim(); } catch (_) { return ''; }
      }
      final startDeadline = DateTime.now().add(const Duration(seconds: 10));
      while (readStatus(started) != 'started' && readStatus(failed).isEmpty && DateTime.now().isBefore(startDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (readStatus(started) != 'started' || readStatus(failed).isNotEmpty) {
        _log('install: helper did not initialize');
        return 'error:helper_initialization_failed';
      }
      final readyDeadline = DateTime.now().add(const Duration(seconds: 120));
      while (readStatus(ready) != 'ready' && readStatus(failed).isEmpty && DateTime.now().isBefore(readyDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (readStatus(ready) != 'ready' || readStatus(failed).isNotEmpty) {
        _log('install: helper preparation failed');
        return 'error:helper_preparation_failed';
      }
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
