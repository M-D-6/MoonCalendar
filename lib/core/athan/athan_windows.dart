import '../platform_info.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'athan_android.dart' show PickedSound;
import 'athan_common.dart';

/// Windows athan + persistent date notification without a native Flutter plugin.
///
/// The athan scheduler still uses Task Scheduler so it is reliable while the
/// window is hidden, but every trigger is gated by a live Flutter-process
/// session marker. Closing the application clears that marker and the task, so
/// an old scheduled trigger cannot start sound after a real process exit.
///
/// The date notification is independent: it is a silent, same-tag toast.
/// While the UI is being used, the watcher refreshes it from lightweight
/// interaction signals; while the UI is hidden/idle, it refreshes only at local
/// midnight and all configured prayer-time refresh points. It is intentionally not
/// removed when the UI exits, matching Android's ongoing date notification
/// behavior as closely as Windows Action Center permits.
class AthanWindows {
  AthanWindows._();

  static bool get isSupported => PlatformInfo.isWindows;

  static Directory? _dir;

  static Directory get dir {
    final cached = _dir;
    if (cached != null) return cached;
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    final d = Directory('$base\\MoonCalendar\\Athan');
    _dir = d;
    return d;
  }

  static String _p(String name) => '${dir.path}\\$name';
  static String get _soundsDir => '${dir.path}\\sounds';
  static String get _dateNotificationFile => _p('date_notifications.json');
  static String get _appInfoFile => _p('app.json');
  static String get _sessionFile => _p('session.json');
  static String get _dateActivityFile => _p('date_activity');

  /// Absolute path of a bundled voice, extracting it from the app assets on
  /// first use (MediaPlayer needs a real file).
  static Future<String?> bundledSoundPath(String key) async {
    final option = athanBundledSound(key);
    if (option == null) return null;
    try {
      await Directory(_soundsDir).create(recursive: true);
      final file = File('$_soundsDir\\${option.assetFile}');
      final data = await rootBundle.load('assets/audio/${option.assetFile}');
      if (!await file.exists() || await file.length() != data.lengthInBytes) {
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ensureScripts() async {
    await dir.create(recursive: true);
    await _writeIfChanged(_p('athan.ps1'), <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_powerShellScript)]);
    await _writeIfChanged(_p('launcher.vbs'), _utf16le(_launcherScript));
  }

  static Future<void> _writeIfChanged(String path, List<int> bytes) async {
    final file = File(path);
    if (await file.exists()) {
      final current = await file.readAsBytes();
      if (current.length == bytes.length) {
        var same = true;
        for (var i = 0; i < bytes.length; i++) {
          if (current[i] != bytes[i]) {
            same = false;
            break;
          }
        }
        if (same) return;
      }
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  // WScript reads Unicode scripts only as UTF-16 with a BOM; this keeps
  // non-ASCII user-profile paths working.
  static Uint8List _utf16le(String text) {
    final units = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n').codeUnits;
    final out = Uint8List(2 + units.length * 2);
    out[0] = 0xFF;
    out[1] = 0xFE;
    for (var i = 0; i < units.length; i++) {
      out[2 + i * 2] = units[i] & 0xFF;
      out[3 + i * 2] = (units[i] >> 8) & 0xFF;
    }
    return out;
  }

  static Future<ProcessResult> _powershell(List<String> args) {
    return Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Sta',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        ...args,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  static Future<void> _writeAppInfo() async {
    await dir.create(recursive: true);
    await File(_appInfoFile).writeAsString(
      jsonEncode(<String, Object?>{'exe': Platform.resolvedExecutable}),
      flush: true,
    );
  }

  static Future<void> _markSessionActive() async {
    await dir.create(recursive: true);
    await File(_sessionFile).writeAsString(
      jsonEncode(<String, Object?>{
        'pid': pid,
        'startedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
        'exe': Platform.resolvedExecutable,
      }),
      flush: true,
    );
  }

  static Future<void> _clearSession() async {
    try {
      final file = File(_sessionFile);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Writes the schedule and (re)arms the Task Scheduler task. Returns false
  /// if PowerShell could not be run.
  static Future<bool> sync({required List<AthanAlarm> alarms, required String? soundPath}) async {
    if (!isSupported) return false;
    try {
      await _ensureScripts();
      await _writeAppInfo();
      if (alarms.isEmpty) {
        await _clearSession();
        final r = await _powershell(<String>['-File', _p('athan.ps1'), '-Mode', 'unregister']);
        return r.exitCode == 0;
      }
      final schedule = <String, Object?>{
        'version': 2,
        'sound': soundPath ?? '',
        'alarms': alarms.map((e) => e.toJson()).toList(),
      };
      await File(_p('schedule.json')).writeAsString(jsonEncode(schedule), flush: true);
      await _markSessionActive();
      final r = await _powershell(<String>['-File', _p('athan.ps1'), '-Mode', 'register']);
      if (r.exitCode != 0) {
        await _clearSession();
      }
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Keeps one silent Action Center notification up to date. This is the
  /// Windows equivalent of Android's ongoing date/prayer-times notification.
  /// A single lightweight watcher reacts to UI activity and scheduled
  /// prayer/midnight refresh points instead of relying on ToastHistory state.
  static Future<bool> syncDateNotification({
    required bool enabled,
    required List<WindowsDateNotification> notifications,
    required List<int> refreshEpochs,
    bool rtl = true,
  }) async {
    if (!isSupported) return false;
    try {
      await _ensureScripts();
      await _writeAppInfo();
      if (!enabled || notifications.isEmpty) {
        // Remove the persisted data first so a running watcher cannot recreate
        // a notification while the task is being stopped.
        try {
          final file = File(_dateNotificationFile);
          if (await file.exists()) await file.delete();
        } catch (_) {}
        await _powershell(<String>['-File', _p('athan.ps1'), '-Mode', 'date_unregister']);
        return false;
      }
      final data = <String, Object?>{
        'version': 4,
        'rtl': rtl,
        'notifications': notifications.map((e) => e.toJson()).toList(),
        'refreshes': refreshEpochs,
      };
      await File(_dateNotificationFile).writeAsString(jsonEncode(data), flush: true);
      final r = await _powershell(<String>['-File', _p('athan.ps1'), '-Mode', 'date_register']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Signals a user interaction to the long-lived Windows date-notification
  /// watcher. The watcher owns the toast itself, so ordinary UI interactions
  /// do not need to spawn PowerShell repeatedly.
  static Future<void> markDateInteraction({bool ensureWatcher = false}) async {
    if (!isSupported) return;
    try {
      await dir.create(recursive: true);
      await File(_dateActivityFile).writeAsString(
        DateTime.now().millisecondsSinceEpoch.toString(),
        flush: true,
      );
      if (ensureWatcher) {
        await _ensureScripts();
        await _powershell(<String>['-File', _p('athan.ps1'), '-Mode', 'date_touch']);
      }
    } catch (_) {}
  }

  /// Removes the athan task/session before process termination. The date
  /// notification is deliberately not removed, so it survives closing the UI.
  static Future<void> shutdown() async {
    if (!isSupported) return;
    try {
      await _clearSession();
      await _ensureScripts();
      await Process.start(
        'wscript.exe',
        <String>['//B', '//Nologo', _p('launcher.vbs'), 'shutdown'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  /// Shows the alarm toast and plays the athan right now (settings preview).
  static Future<void> preview({required String title, required String body, required String? soundPath}) async {
    if (!isSupported) return;
    await _ensureScripts();
    await File(_p('preview.json')).writeAsString(
      jsonEncode(<String, Object?>{'title': title, 'body': body, 'sound': soundPath ?? ''}),
      flush: true,
    );
    await Process.start(
      'wscript.exe',
      <String>['//B', '//Nologo', _p('launcher.vbs'), 'preview'],
      mode: ProcessStartMode.detached,
    );
  }

  /// Shows (replaces) the silent temperature toast. Runs a short hidden script only when the text changed.
  static String? _lastTemperature;
  static Future<void> showTemperature({required String title, required String body, required bool rtl}) async {
    if (!isSupported) return;
    final key = '$rtl|$title|$body';
    if (key == _lastTemperature) return;
    _lastTemperature = key;
    try {
      await _ensureScripts();
      await File(_p('temperature.json')).writeAsString(
        jsonEncode(<String, Object?>{'title': title, 'body': body, 'rtl': rtl, 'at': DateTime.now().millisecondsSinceEpoch}),
        flush: true,
      );
      await Process.start('wscript.exe', <String>['//B', '//Nologo', _p('launcher.vbs'), 'temp_show'], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  static Future<void> clearTemperature() async {
    if (!isSupported || _lastTemperature == null) return;
    _lastTemperature = null;
    try {
      await _ensureScripts();
      await Process.start('wscript.exe', <String>['//B', '//Nologo', _p('launcher.vbs'), 'temp_clear'], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  /// Stops a playing athan and clears its toast.
  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _ensureScripts();
      await Process.start(
        'wscript.exe',
        <String>['//B', '//Nologo', _p('launcher.vbs'), 'stop'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  /// Lets the user pick an audio file with the standard Windows dialog and
  /// keeps a private copy so the scheduled task never depends on the original.
  static Future<PickedSound?> pickAudioFile() async {
    if (!isSupported) return null;
    try {
      await dir.create(recursive: true);
      final script = File(_p('pick.ps1'));
      await script.writeAsBytes(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(_pickScript)], flush: true);
      final r = await _powershell(<String>['-File', script.path]);
      final picked = (r.stdout as String).trim();
      if (picked.isEmpty || !await File(picked).exists()) return null;
      await Directory(_soundsDir).create(recursive: true);
      final name = picked.split('\\').last;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot) : '.mp3';
      final target = File('$_soundsDir\\custom$ext');
      await File(picked).copy(target.path);
      return PickedSound(target.path, name);
    } catch (_) {
      return null;
    }
  }

  static const String _launcherScript = r'''
Option Explicit
Dim shell, fso, folder, mode, ps, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
mode = "tick"
If WScript.Arguments.Count > 0 Then mode = WScript.Arguments(0)
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
cmd = """" & ps & """ -NoProfile -NonInteractive -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\athan.ps1"" -Mode " & mode
shell.Run cmd, 0, False
''';

  static const String _pickScript = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Select athan audio'
$dialog.Filter = 'Audio files|*.mp3;*.wav;*.wma;*.m4a;*.aac|All files|*.*'
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
if ($dialog.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::Out.Write($dialog.FileName)
}
$owner.Dispose()
''';

  static const String _powerShellScript = r'''
param([string]$Mode = 'tick')

$ErrorActionPreference = 'Stop'
$Dir             = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScheduleFile    = Join-Path $Dir 'schedule.json'
$DateScheduleFile= Join-Path $Dir 'date_notifications.json'
$DateActivityFile = Join-Path $Dir 'date_activity'
$AppInfoFile     = Join-Path $Dir 'app.json'
$SessionFile     = Join-Path $Dir 'session.json'
$StateFile       = Join-Path $Dir 'state.json'
$PreviewFile     = Join-Path $Dir 'preview.json'
$TemperatureFile = Join-Path $Dir 'temperature.json'
$PidFile         = Join-Path $Dir 'athan.pid'
$Launcher        = Join-Path $Dir 'launcher.vbs'
$LogFile         = Join-Path $Dir 'athan.log'
$Aumid           = 'MoonCalendar.Athan'
# Each kind of notification has its own app identity, so Windows lists them separately instead of folding
# the calendar, the temperature and the athan into one stack.
$DateAumid       = 'MoonCalendar.Date'
$TempAumid       = 'MoonCalendar.Weather'
$TaskName        = 'MoonCalendarAthan'
$DateTaskName    = 'MoonCalendarDateNotification'
$AppName         = 'Mooncalendar'
$StopLabel       = 'توقف اذان'
$DateTag         = 'date'
$DateGroup       = 'calendar'
$GraceMs         = 15 * 60 * 1000
$LeadMs          = 15 * 1000

function Write-Log([string]$Message) {
    try {
        if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 200KB)) {
            Remove-Item -LiteralPath $LogFile -Force
        }
        $line = ('{0}  [{1}] {2}' -f (Get-Date -Format 's'), $Mode, $Message)
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
}

function Get-NowMs {
    return [int64][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Get-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Log ('bad json ' + $Path + ': ' + $_)
        return $null
    }
}

function Initialize-Toast {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
}

# Windows desktop toasts require a Start-menu shortcut whose AppUserModelID
# matches the ID passed to CreateToastNotifier. Create/update that shortcut at
# first run so unpackaged Flutter builds behave like installed desktop apps.
function Ensure-ToastShortcut {
    $info = Get-JsonFile $AppInfoFile
    $exe = if ($info) { [string]$info.exe } else { '' }
    if ([string]::IsNullOrEmpty($exe) -or -not (Test-Path -LiteralPath $exe)) {
        Write-Log ('toast shortcut skipped: exe missing ' + $exe)
        return
    }

    try {
        if (-not ('LnkAumidHelper' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class LnkAumidHelper
{
    public static void WriteShortcutWithAumid(string lnkPath, string exePath, string appUserModelId)
    {
        var link = (IShellLinkW)new CShellLink();
        var persist = (IPersistFile)link;
        link.SetPath(exePath);
        link.SetWorkingDirectory(Path.GetDirectoryName(exePath) ?? "");
        var store = (IPropertyStore)link;
        SetAumidOnStore(store, appUserModelId);
        persist.Save(lnkPath, true);
        persist.SaveCompleted(lnkPath);
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class CShellLink { }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        int GetPath(IntPtr pszFile, int cch, IntPtr pfd, uint fFlags);
        int GetIDList(out IntPtr ppidl);
        int SetIDList(IntPtr pidl);
        int GetDescription(IntPtr pszName, int cch);
        int SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        int GetWorkingDirectory(IntPtr pszDir, int cch);
        int SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        int GetArguments(IntPtr pszArgs, int cch);
        int SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        int GetHotkey(out short wHotkey);
        int SetHotkey(short wHotkey);
        int GetShowCmd(out int iShowCmd);
        int SetShowCmd(int iShowCmd);
        int GetIconLocation(IntPtr pszIconPath, int cch, out int iIcon);
        int SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        int SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        int Resolve(IntPtr hWnd, uint fFlags);
        int SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, Guid("0000010b-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPersistFile
    {
        int GetClassID(out Guid pClassID);
        int IsDirty();
        int Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, int dwMode);
        int Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, bool fRemember);
        int SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        int GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    private interface IPropertyStore
    {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    private static readonly PROPERTYKEY PKEY_AppUserModel_ID =
        new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPVARIANT
    {
        public ushort vt, w1, w2, w3;
        public IntPtr p;
        public int i1, i2;
    }

    private const ushort VT_LPWSTR = 31;
    [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PROPVARIANT pvar);

    private static void SetAumidOnStore(IPropertyStore store, string appId)
    {
        var pv = new PROPVARIANT
        {
            vt = VT_LPWSTR,
            p = Marshal.StringToCoTaskMemUni(appId),
        };
        try
        {
            var key = PKEY_AppUserModel_ID;
            store.SetValue(ref key, ref pv);
            store.Commit();
        }
        finally
        {
            PropVariantClear(ref pv);
        }
    }
}
'@
        }

        $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        New-Item -ItemType Directory -Path $programs -Force | Out-Null
        $old = Join-Path $programs 'Mooncalendar (اعلان).lnk'
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        $common = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        $folderLink = Join-Path $programs 'Mooncalendar\Mooncalendar.lnk'
        $commonLink = Join-Path $common 'Mooncalendar.lnk'
        $commonFolderLink = Join-Path $common 'Mooncalendar\Mooncalendar.lnk'
        $shortcut = Join-Path $programs 'Mooncalendar.lnk'
        # One Start-menu entry only: the installer's shortcut already carries the notification identity.
        if ((Test-Path -LiteralPath $shortcut) -or (Test-Path -LiteralPath $folderLink) -or (Test-Path -LiteralPath $commonLink) -or (Test-Path -LiteralPath $commonFolderLink)) { return }
        [LnkAumidHelper]::WriteShortcutWithAumid($shortcut, $exe, $Aumid)
        Write-Log ('toast shortcut ready: ' + $shortcut)
    } catch {
        Write-Log ('toast shortcut error: ' + $_)
    }
}

function Register-App {
    $key = 'HKCU:\Software\Classes\AppUserModelId\' + $Aumid
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'DisplayName' -Value $AppName -PropertyType String -Force | Out-Null
    foreach ($extra in @(@($DateAumid, ($AppName + ' - Date')), @($TempAumid, ($AppName + ' - Weather')))) {
        $extraKey = 'HKCU:\Software\Classes\AppUserModelId\' + $extra[0]
        if (-not (Test-Path $extraKey)) { New-Item -Path $extraKey -Force | Out-Null }
        New-ItemProperty -Path $extraKey -Name 'DisplayName' -Value $extra[1] -PropertyType String -Force | Out-Null
    }

    $proto = 'HKCU:\Software\Classes\mooncalendar-athan'
    New-Item -Path $proto -Force | Out-Null
    Set-ItemProperty -Path $proto -Name '(default)' -Value 'URL:Mooncalendar Athan'
    New-ItemProperty -Path $proto -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    $command = $proto + '\shell\open\command'
    New-Item -Path $command -Force | Out-Null
    Set-ItemProperty -Path $command -Name '(default)' -Value ('wscript.exe //B //Nologo "' + $Launcher + '" stop')
    Ensure-ToastShortcut
}

function Get-LastFired {
    $state = Get-JsonFile $StateFile
    if ($state -and $state.lastFiredAt) { return [int64]$state.lastFiredAt }
    return [int64]0
}

function Set-LastFired([int64]$Value) {
    Set-Content -LiteralPath $StateFile -Value ('{"lastFiredAt":' + $Value + '}') -Encoding UTF8
}

function Test-AthanSession {
    $session = Get-JsonFile $SessionFile
    if (-not $session -or -not $session.pid -or -not $session.startedAt) { return $false }
    try {
        $proc = Get-Process -Id ([int]$session.pid) -ErrorAction Stop
        if ($proc.ProcessName -notlike 'mooncalendar*') { return $false }
        if ($session.exe) {
            try {
                $procPath = [System.IO.Path]::GetFullPath([string]$proc.Path)
                $sessionPath = [System.IO.Path]::GetFullPath([string]$session.exe)
                if ($procPath -and $sessionPath -and -not $procPath.Equals($sessionPath, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            } catch { }
        }
        $startedOffset = [DateTimeOffset]$proc.StartTime.ToUniversalTime()
        $started = $startedOffset.ToUnixTimeMilliseconds()
        return ([math]::Abs($started - [int64]$session.startedAt) -le 30000)
    } catch {
        return $false
    }
}

function Get-NextAlarm($Alarms, [int64]$After) {
    return ($Alarms | Where-Object { [int64]$_.at -gt $After } | Sort-Object { [int64]$_.at } | Select-Object -First 1)
}

# Arms the athan task. The scheduled task may exist outside the app process,
# but every trigger is gated by Test-AthanSession, so it can never start audio
# after the user has actually exited the Flutter process.
function Update-Task($Alarms, [int64]$After) {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "' + $Launcher + '" tick')
        $triggers = @(New-ScheduledTaskTrigger -AtLogOn -User $identity)
        $next = Get-NextAlarm $Alarms $After
        if ($next) {
            $when = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$next.at).LocalDateTime
            $triggers += New-ScheduledTaskTrigger -Once -At $when
        }
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description 'Mooncalendar athan' -Force | Out-Null
        if ($next) { Write-Log ('athan armed for ' + $next.prayer + ' at ' + $when.ToString('s')) } else { Write-Log 'athan armed (no upcoming alarm)' }
    } catch {
        Write-Log ('athan task error: ' + $_)
    }
}

function Stop-Athan {
    try {
        if (Test-Path -LiteralPath $PidFile) {
            $old = [int]((Get-Content -LiteralPath $PidFile -Raw).Trim())
            if ($old -ne $PID) {
                $proc = Get-Process -Id $old -ErrorAction SilentlyContinue
                if ($proc -and $proc.ProcessName -like 'powershell*') { Stop-Process -Id $old -Force }
            }
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        }
    } catch { Write-Log ('stop error: ' + $_) }
    try { [Windows.UI.Notifications.ToastNotificationManager]::History.Remove('athan', 'athan') } catch { }
}

function Show-Toast([string]$Title, [string]$Body) {
    $t = [System.Security.SecurityElement]::Escape($Title)
    $b = [System.Security.SecurityElement]::Escape($Body)
    $xml = '<toast scenario="alarm" activationType="protocol" launch="mooncalendar-athan://stop">' +
        '<visual><binding template="ToastGeneric"><text>' + $t + '</text><text>' + $b + '</text></binding></visual>' +
        '<audio silent="true"/>' +
        '<actions><action content="' + $StopLabel + '" arguments="mooncalendar-athan://stop" activationType="protocol"/></actions>' +
        '</toast>'
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification -ArgumentList $doc
    $toast.Tag = 'athan'
    $toast.Group = 'athan'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($Aumid).Show($toast)
}

function New-DateTag {
    return $DateTag
}

function Get-ToastStyle([string]$Tokens, [string]$Default) {
    # Windows toast text styles: no underline exists, so it is ignored here.
    $t = @(); if ($Tokens) { $t = $Tokens.Split(',') }
    $base = $Default
    if ($t -contains 'heading') { $base = 'subtitle' }
    elseif ($t -contains 'bold') { $base = 'base' }
    if ($t -contains 'light') { return ($base + 'Subtle') }
    return $base
}

function Show-DateToast([object[]]$Lines, [object[]]$Styles) {
    # The persisted layout has no artificial row limit. ToastGeneric can still
    # impose its own visual height, so every configured logical row is retained
    # and joined with explicit line breaks instead of being silently dropped.
    try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $DateAumid) } catch { }
    # Older versions posted the calendar toast under the athan identity: clear that leftover once.
    try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $Aumid) } catch { }
    # The temperature toast goes first so the calendar toast lands on top of it.
    try { Invoke-TempShow -Quiet; Start-Sleep -Milliseconds 400 } catch { }
    $dateRtl = $true
    try { $dsched = Get-JsonFile $DateScheduleFile; if ($dsched -and $dsched.rtl -eq $false) { $dateRtl = $false } } catch { }
    # A leading RLM / LRM mark sets the paragraph direction of every row (the toast has no direction switch).
    $dirMark = $(if ($dateRtl) { [string][char]0x200F } else { [string][char]0x200E })
    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        if ($null -eq $line) { continue }
        $text = ([string]$line).Trim()
        if ($text -eq '') { continue }
        [void]$clean.Add(([System.Security.SecurityElement]::Escape($dirMark + $text)))
    }
    if ($clean.Count -eq 0) { return $null }

    # ToastGeneric shows at most three <text> elements: line 1, line 2 and
    # every remaining line grouped together (they share line 3's style).
    $styleFor = @()
    if ($Styles) { $styleFor = @($Styles | ForEach-Object { [string]$_ }) }
    $s1 = ''; $s2 = ''; $s3 = ''
    if ($styleFor.Count -gt 0) { $s1 = $styleFor[0] }
    if ($styleFor.Count -gt 1) { $s2 = $styleFor[1] }
    if ($styleFor.Count -gt 2) { $s3 = $styleFor[2] }

    $title = [string]$clean[0]
    $st1 = Get-ToastStyle $s1 ''
    $textXml = '<text hint-maxLines="2"' + $(if ($st1) { ' hint-style="' + $st1 + '"' } else { '' }) + '>' + $title + '</text>'
    if ($clean.Count -eq 2) {
        $st2 = Get-ToastStyle $s2 ''
        $textXml += '<text hint-maxLines="99"' + $(if ($st2) { ' hint-style="' + $st2 + '"' } else { '' }) + '>' + [string]$clean[1] + '</text>'
    } elseif ($clean.Count -gt 2) {
        $st2 = Get-ToastStyle $s2 ''
        $textXml += '<text hint-maxLines="2"' + $(if ($st2) { ' hint-style="' + $st2 + '"' } else { '' }) + '>' + [string]$clean[1] + '</text>'
        $rest = [string]::Join('&#10;', [object[]]@($clean | Select-Object -Skip 2))
        $st3 = Get-ToastStyle $s3 ''
        $textXml += '<text hint-maxLines="99"' + $(if ($st3) { ' hint-style="' + $st3 + '"' } else { '' }) + '>' + $rest + '</text>'
    }
    # Layout direction chosen in the app: the toast language decides how Windows lays the text out,
    # hint-align keeps the rows on the matching side.
    $lang = $(if ($dateRtl) { 'fa-IR' } else { 'en-US' })
    $align = $(if ($dateRtl) { 'right' } else { 'left' })
    $textXml = $textXml.Replace('<text ', '<text hint-align="' + $align + '" ')
    $xml = '<toast>' +
        '<visual><binding template="ToastGeneric" lang="' + $lang + '">' + $textXml + '</binding></visual>' +
        '<audio silent="true"/>' +
        '</toast>'
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification -ArgumentList $doc
    $toast.Tag = New-DateTag
    $toast.Group = $DateGroup
    $toast.SuppressPopup = $true
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddHours(30)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($DateAumid).Show($toast)
    return $toast
}

function Get-TodaysDateNotification {
    $schedule = Get-JsonFile $DateScheduleFile
    if (-not $schedule) { return $null }
    $items = @($schedule.notifications)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $item = $items | Where-Object { [string]$_.date -eq $today } | Select-Object -First 1
    if (-not $item) {
        $item = $items | Where-Object { [string]$_.date -ge $today } | Sort-Object date | Select-Object -First 1
    }
    return $item
}

function Invoke-DateWatch {
    Initialize-Toast
    Register-App
    # The notification has an intentional lifecycle:
    #   * when the app is being used, every interaction asks the watcher to re-show it;
    #   * while the app is hidden/idle, only prayer-time and midnight refresh points re-show it;
    #   * dismissing it alone does not create a busy polling/recreation loop.
    # This avoids the unreliable ToastHistory "present" check used in v16/v17,
    # where a dismissed notification could remain in history forever.
    Set-Content -LiteralPath $DateWatchPidFile -Value $PID -Force
    $lastActivity = ''
    $lastDateKey = ''
    $lastHourKey = ''
    $refreshIndex = 0
    try {
      while (Test-Path -LiteralPath $DateScheduleFile) {
        $schedule = Get-JsonFile $DateScheduleFile
        if (-not $schedule) { break }

        $item = Get-TodaysDateNotification
        $now = Get-NowMs
        $show = $false

        # 1) Initial/changed date data.
        if ($item) {
            $dateKey = [string]$item.date
            if ($lastDateKey -ne $dateKey) {
                $show = $true
                $lastDateKey = $dateKey
            }
        }

        # 2) Any user interaction in the Flutter process.
        if (Test-Path -LiteralPath $DateActivityFile) {
            try {
                $activity = (Get-Content -LiteralPath $DateActivityFile -Raw).Trim()
                if ($activity -ne '' -and $activity -ne $lastActivity) {
                    $lastActivity = $activity
                    $show = $true
                }
            } catch { }
        }

        # 3) Local top-of-hour refresh. This is deliberately based on the
        # wall clock instead of a 60-minute interval so 10:00, 11:00, 12:00...
        # are the actual refresh boundaries. Hour 00:00 also refreshes with the
        # new date.
        $hourKey = (Get-Date).ToString('yyyy-MM-dd-HH')
        if ($lastHourKey -ne '' -and $hourKey -ne $lastHourKey) {
            $show = $true
        }
        $lastHourKey = $hourKey

        # 4) Prayer-time refresh points, including midnight from the prepared
        # schedule.
        $refreshes = @($schedule.refreshes) | ForEach-Object { [int64]$_ } | Sort-Object
        while ($refreshIndex -lt $refreshes.Count -and $refreshes[$refreshIndex] -le $now) {
            if (($now - $refreshes[$refreshIndex]) -le 120000) { $show = $true }
            $refreshIndex++
        }

        if ($show -and $item) {
            try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $DateAumid) } catch { }
            Show-DateToast ([object[]]$item.lines) ([object[]]$item.styles) | Out-Null
        }

        Start-Sleep -Milliseconds 1000
      }
    } finally {
      try {
        if ((Test-Path -LiteralPath $DateWatchPidFile) -and (((Get-Content -LiteralPath $DateWatchPidFile -Raw).Trim()) -eq [string]$PID)) {
          Remove-Item -LiteralPath $DateWatchPidFile -Force
        }
      } catch { }
    }
    Write-Log 'date watcher stopped: schedule file removed'
}

function Start-Sound([string]$Path) {
    if ([string]::IsNullOrEmpty($Path) -or -not (Test-Path -LiteralPath $Path)) {
        Write-Log ('sound file missing: ' + $Path)
        return
    }
    Add-Type -AssemblyName presentationCore
    $player = New-Object System.Windows.Media.MediaPlayer
    $player.Open((New-Object System.Uri($Path)))
    $player.Volume = 1.0
    $player.Play()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $length = 0.0
    while ($watch.Elapsed.TotalSeconds -lt 600) {
        Start-Sleep -Milliseconds 250
        if ($length -le 0 -and $player.NaturalDuration.HasTimeSpan) {
            $length = $player.NaturalDuration.TimeSpan.TotalSeconds
        }
        if ($length -gt 0 -and $watch.Elapsed.TotalSeconds -ge ($length + 1.5)) { break }
        if ($length -le 0 -and $watch.Elapsed.TotalSeconds -ge 240) { break }
    }
    $player.Stop()
    $player.Close()
}

function Invoke-Athan([string]$Title, [string]$Body, [string]$Sound) {
    Initialize-Toast
    Stop-Athan
    Set-Content -LiteralPath $PidFile -Value $PID
    try {
        Show-Toast $Title $Body
        Start-Sound $Sound
    } finally {
        try {
            if ((Test-Path -LiteralPath $PidFile) -and (((Get-Content -LiteralPath $PidFile -Raw).Trim()) -eq [string]$PID)) {
                Remove-Item -LiteralPath $PidFile -Force
            }
        } catch { }
    }
}

function Invoke-Register {
    Register-App
    $schedule = Get-JsonFile $ScheduleFile
    if (-not $schedule) { Invoke-Unregister; return }
    $alarms = @($schedule.alarms)
    $now = Get-NowMs
    $last = Get-LastFired
    $past = @($alarms | Where-Object { [int64]$_.at -le $now } | ForEach-Object { [int64]$_.at })
    if ($past.Count -gt 0) {
        $newest = [int64](($past | Measure-Object -Maximum).Maximum)
        if ($newest -gt $last) { Set-LastFired $newest }
    }
    Update-Task $alarms $now
}

function Invoke-Unregister {
    Remove-Item -LiteralPath $SessionFile -Force -ErrorAction SilentlyContinue
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    Write-Log 'athan task removed'
}

function Invoke-Shutdown {
    Remove-Item -LiteralPath $SessionFile -Force -ErrorAction SilentlyContinue
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    Stop-Athan
    Write-Log 'shutdown: athan execution disabled'
}

function Stop-DateWatcherProcess {
    try {
        if (Test-Path -LiteralPath $DateWatchPidFile) {
            $old = [int]((Get-Content -LiteralPath $DateWatchPidFile -Raw).Trim())
            if ($old -and $old -ne $PID) {
                Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $DateWatchPidFile -Force -ErrorAction SilentlyContinue
        }
    } catch { Write-Log ('date watcher process stop error: ' + $_) }
}

function Invoke-DateRegister {
    Initialize-Toast
    Register-App
    $schedule = Get-JsonFile $DateScheduleFile
    if (-not $schedule) { Invoke-DateUnregister; return }
    try { Remove-Item -LiteralPath $DateActivityFile -Force -ErrorAction SilentlyContinue } catch { }

    # Always replace an old watcher instance. Register-ScheduledTask -Force does
    # not terminate a currently running instance when MultipleInstances is IgnoreNew.
    try { Stop-ScheduledTask -TaskName $DateTaskName -ErrorAction SilentlyContinue } catch { }
    Stop-DateWatcherProcess
    try { Unregister-ScheduledTask -TaskName $DateTaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }

    # Show immediately so enabling the setting is visible at once.
    $item = Get-TodaysDateNotification
    if ($item) {
        try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $DateAumid) } catch { }
        Show-DateToast ([object[]]$item.lines) ([object[]]$item.styles) | Out-Null
    }
    Invoke-DateEnsureTask
    try {
        Start-ScheduledTask -TaskName $DateTaskName -ErrorAction Stop
    } catch {
        # Fallback for environments where Task Scheduler refuses an immediate
        # start even though registration succeeded. The watcher will still be
        # a scheduled task for logon/daily recovery.
        Write-Log ('date watcher task start error: ' + $_)
        try {
            Start-Process -FilePath 'wscript.exe' -ArgumentList @('//B', '//Nologo', ('"' + $Launcher + '"'), 'date_watch') -WindowStyle Hidden | Out-Null
        } catch { Write-Log ('date watcher fallback start error: ' + $_) }
    }
}

function Invoke-DateEnsureTask {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "' + $Launcher + '" date_watch')
        $triggers = @(
            (New-ScheduledTaskTrigger -AtLogOn -User $identity),
            (New-ScheduledTaskTrigger -Daily -At ([datetime]::Today.AddMinutes(5)))
        )
        # The watcher is intentionally long-lived so it can react to app
        # interaction signals and scheduled prayer/midnight refresh points.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 20 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $DateTaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description 'Mooncalendar silent date notification watcher' -Force | Out-Null
        Write-Log 'date notification watcher task registered'
    } catch {
        Write-Log ('date watcher task error: ' + $_)
    }
}

function Invoke-DateTouch {
    Initialize-Toast
    Register-App
    if (-not (Test-Path -LiteralPath $DateScheduleFile)) { return }

    # A user interaction is a hard refresh, not merely a signal. This bypasses
    # notification-history state entirely: dismissing the toast can never make
    # the next interaction a no-op. The next timer tick while the app is open
    # calls the same mode once per minute.
    try { Set-Content -LiteralPath $DateActivityFile -Value ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force } catch { }
    try {
        $item = Get-TodaysDateNotification
        if ($item) {
            try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $DateAumid) } catch { }
            Show-DateToast ([object[]]$item.lines) ([object[]]$item.styles) | Out-Null
        }
    } catch { Write-Log ('date touch toast error: ' + $_) }

    try {
        $alive = $false
        if (Test-Path -LiteralPath $DateWatchPidFile) {
            $watchPidText = (Get-Content -LiteralPath $DateWatchPidFile -Raw).Trim()
            if ($watchPidText -match '^\d+$') {
                try {
                    $proc = Get-Process -Id ([int]$watchPidText) -ErrorAction Stop
                    $alive = $proc.ProcessName -like 'powershell*'
                } catch { $alive = $false }
            }
        }
        if (-not $alive) {
            Remove-Item -LiteralPath $DateWatchPidFile -Force -ErrorAction SilentlyContinue
            try { Start-ScheduledTask -TaskName $DateTaskName -ErrorAction Stop } catch {
                Start-Process -FilePath 'wscript.exe' -ArgumentList @('//B', '//Nologo', ('"' + $Launcher + '"'), 'date_watch') -WindowStyle Hidden | Out-Null
            }
        }
    } catch { Write-Log ('date touch watcher start error: ' + $_) }
}

function Invoke-DateTick {
    # Kept for compatibility with older scheduled-task registrations.
    $item = Get-TodaysDateNotification
    if ($item) {
        Initialize-Toast
        Register-App
        Show-DateToast ([object[]]$item.lines) ([object[]]$item.styles) | Out-Null
    }
}

function Invoke-DateUnregister {
    try { Remove-Item -LiteralPath $DateScheduleFile -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item -LiteralPath $DateActivityFile -Force -ErrorAction SilentlyContinue } catch { }
    try { Stop-ScheduledTask -TaskName $DateTaskName -ErrorAction SilentlyContinue } catch { }
    Stop-DateWatcherProcess
    try { Unregister-ScheduledTask -TaskName $DateTaskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Initialize-Toast; [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup($DateGroup, $DateAumid) } catch { }
    Write-Log 'date notification watcher task removed'
}

function Invoke-TempShow([switch]$Quiet) {
    $item = Get-JsonFile $TemperatureFile
    if (-not $item) { return }
    # Never repeat an old reading (the app may have been closed for hours).
    if ($item.at -and (((Get-NowMs) - [int64]$item.at) -gt 10800000)) { return }
    if (-not $Quiet) { Register-App }
    Initialize-Toast
    $rtl = ($item.rtl -ne $false)
    $mark = $(if ($rtl) { [string][char]0x200F } else { [string][char]0x200E })
    $t = [System.Security.SecurityElement]::Escape($mark + [string]$item.title)
    $b = [System.Security.SecurityElement]::Escape($mark + [string]$item.body)
    $lang = $(if ($rtl) { 'fa-IR' } else { 'en-US' })
    $align = $(if ($rtl) { 'right' } else { 'left' })
    $xml = '<toast><visual><binding template="ToastGeneric" lang="' + $lang + '">' +
        '<text hint-align="' + $align + '">' + $t + '</text><text hint-align="' + $align + '">' + $b + '</text>' +
        '</binding></visual><audio silent="true"/></toast>'
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification -ArgumentList $doc
    $toast.Tag = 'temperature'
    $toast.Group = 'temperature'
    $toast.SuppressPopup = $true
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddHours(3)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($TempAumid).Show($toast)
}

function Invoke-TempClear {
    try { Remove-Item -LiteralPath $TemperatureFile -Force -ErrorAction SilentlyContinue } catch { }
    try { Initialize-Toast; [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup('temperature', $TempAumid) } catch { }
    try { [Windows.UI.Notifications.ToastNotificationManager]::History.RemoveGroup('temperature', $Aumid) } catch { }
}

function Invoke-Preview {
    $preview = Get-JsonFile $PreviewFile
    if (-not $preview) { return }
    Register-App
    Invoke-Athan ([string]$preview.title) ([string]$preview.body) ([string]$preview.sound)
}

try {
    switch ($Mode) {
        'register'        { Invoke-Register }
        'unregister'      { Invoke-Unregister }
        'shutdown'        { Invoke-Shutdown }
        'date_register'   { Invoke-DateRegister }
        'date_watch'      { Invoke-DateWatch }
        'date_touch'      { Invoke-DateTouch }
        'date_tick'       { Invoke-DateTick }
        'date_unregister' { Invoke-DateUnregister }
        'preview'         { Invoke-Preview }
        'temp_show'       { Invoke-TempShow }
        'temp_clear'      { Invoke-TempClear }
        'stop'            { Initialize-Toast; Stop-Athan }
        default {
            if (-not (Test-AthanSession)) {
                Write-Log 'tick skipped: app session is not active'
                return
            }
            $schedule = Get-JsonFile $ScheduleFile
            if (-not $schedule) { Invoke-Unregister; return }
            $alarms = @($schedule.alarms)
            $last = Get-LastFired
            $now = Get-NowMs
            $horizon = $now + $LeadMs
            $due = @($alarms | Where-Object { [int64]$_.at -gt $last -and [int64]$_.at -le $horizon } | Sort-Object { [int64]$_.at })
            if ($due.Count -gt 0) { Set-LastFired ([int64]$due[$due.Count - 1].at) }
            Update-Task $alarms $horizon
            if ($due.Count -eq 0) { return }
            $fresh = @($due | Where-Object { ($now - [int64]$_.at) -le $GraceMs })
            if ($fresh.Count -eq 0) { Write-Log 'skipped: too late'; return }
            $alarm = $fresh[$fresh.Count - 1]
            $wait = [int64]$alarm.at - (Get-NowMs)
            if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
            if (-not (Test-AthanSession)) {
                Write-Log 'firing aborted: app session ended while waiting'
                return
            }
            Write-Log ('firing ' + $alarm.prayer)
            Invoke-Athan ([string]$alarm.title) ([string]$alarm.body) ([string]$schedule.sound)
        }
    }
} catch {
    Write-Log ('fatal: ' + $_)
    exit 1
}
''';
}
