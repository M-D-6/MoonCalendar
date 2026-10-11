import 'platform_info.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class CounterWidgetBridge {
  CounterWidgetBridge._();

  static const MethodChannel _channel = MethodChannel('com.md6.Mooncalendar/platform');
  static Timer? _refreshTimer;

  static void scheduleRefresh() {
    if (!PlatformInfo.isAndroid) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_channel.invokeMethod<void>('refreshCounterWidgets').catchError((_) {}));
    });
  }
}
