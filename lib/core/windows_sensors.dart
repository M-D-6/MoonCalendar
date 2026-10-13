import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Windows motion sensors (WinRT `Windows.Devices.Sensors`), read through PowerShell.
///
/// Each stream starts one PowerShell process while somebody listens and stops it when the last
/// listener leaves. Values are printed one reading per line, separated by spaces.
class WindowsSensors {
  const WindowsSensors._();

  static String _type(String name) => '[Windows.Devices.Sensors.$name,Windows.Devices.Sensors,ContentType=WindowsRuntime]';

  /// True when the device has a default sensor of that kind (`Compass`, `Accelerometer`, ...).
  static Future<bool> has(String name) async {
    final type = _type(name);
    try {
      final r = await Process.run('powershell', <String>[
        '-NoProfile', '-NonInteractive', '-Command',
        '[void]$type; if ($type::GetDefault()) { "1" } else { "0" }',
      ]).timeout(const Duration(seconds: 10));
      return r.exitCode == 0 && r.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }

  /// [expressions] are PowerShell expressions evaluated on the reading `$r` (for example `$r.HeadingMagneticNorth`).
  static Stream<List<double>> stream(String name, List<String> expressions) {
    final type = _type(name);
    final format = <String>[
      for (var i = 0; i < expressions.length; i++) '{$i:F3}',
    ].join(' ');
    final script = '[void]$type; \$c = $type::GetDefault(); if (-not \$c) { exit 2 }; '
        '\$c.ReportInterval = [Math]::Max(\$c.MinimumReportInterval, 100); '
        'while (\$true) { \$r = \$c.GetCurrentReading(); '
        'if (\$r) { [Console]::Out.WriteLine([string]::Format([Globalization.CultureInfo]::InvariantCulture, "$format", ${expressions.join(', ')})); [Console]::Out.Flush() }; '
        'Start-Sleep -Milliseconds 100 }';
    Process? process;
    late final StreamController<List<double>> controller;
    controller = StreamController<List<double>>.broadcast(
      onListen: () async {
        if (process != null) return;
        try {
          final started = await Process.start('powershell', <String>['-NoProfile', '-NonInteractive', '-Command', script]);
          process = started;
          started.stdout.transform(const SystemEncoding().decoder).transform(const LineSplitter()).listen((line) {
            final values = line.trim().split(' ').map(double.tryParse).toList();
            if (values.length == expressions.length && !values.contains(null) && !controller.isClosed) {
              controller.add(values.cast<double>());
            }
          });
          started.stderr.drain<void>();
        } catch (_) {
          process = null;
        }
      },
      onCancel: () {
        process?.kill();
        process = null;
      },
    );
    return controller.stream;
  }
}
