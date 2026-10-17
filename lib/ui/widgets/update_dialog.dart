import 'package:flutter/material.dart' hide Text;

import '../../core/app_version.dart';
import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/settings.dart';
import '../../core/update_service.dart';
import 'tr_text.dart';

/// User-facing part of the update system: the "new version" prompt, the download progress and the manual check.
class UpdateUi {
  UpdateUi._();

  static bool _busy = false;

  /// The daily background check: silent unless a version newer than the skipped one exists.
  static Future<void> autoCheck(BuildContext context, AppSettings settings) async {
    if (!UpdateService.isSupported || !settings.autoUpdateCheck || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - settings.lastUpdateCheckMs < const Duration(hours: 24).inMilliseconds) return;
    _busy = true;
    try {
      final info = await UpdateService.checkLatest();
      await settings.setLastUpdateCheck(now);
      if (info == null || info.version == settings.skippedUpdate || !context.mounted) return;
      await _prompt(context, settings, info);
    } catch (_) {
      // Offline or rate limited: try again on the next start.
    } finally {
      _busy = false;
    }
  }

  /// Settings → "Check for updates": always answers, and ignores a skipped version.
  static Future<void> checkNow(BuildContext context, AppSettings settings) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('در حال بررسی به‌روزرسانی…'), duration: Duration(seconds: 2)));
    try {
      final info = await UpdateService.checkLatest();
      await settings.setLastUpdateCheck(DateTime.now().millisecondsSinceEpoch);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (info == null) {
        messenger.showSnackBar(const SnackBar(content: Text('نسخهٔ شما به‌روز است.')));
      } else {
        await _prompt(context, settings, info);
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('بررسی به‌روزرسانی ممکن نشد؛ اتصال اینترنت را بررسی کنید.')));
    } finally {
      _busy = false;
    }
  }

  static String _digits(String s) => toPersianDigits(s);

  static Future<void> _prompt(BuildContext context, AppSettings settings, UpdateInfo info) async {
    final choice = await showDialog<_Choice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نسخهٔ جدید در دسترس است', textDirection: TextDirection.rtl),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('نسخهٔ ${_digits(info.version)} منتشر شده است (نسخهٔ فعلی: ${_digits(appVersion)}).', textDirection: TextDirection.rtl),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('تغییرات این نسخه', style: TextStyle(fontWeight: FontWeight.bold), textDirection: TextDirection.rtl),
                const SizedBox(height: 4),
                PlainText(info.notes.length > 1200 ? '${info.notes.substring(0, 1200)}…' : info.notes),
              ],
              if (!info.hasAsset) ...[
                const SizedBox(height: 12),
                const Text('فایل نصب این نسخه برای دستگاه شما پیدا نشد؛ برای دریافت دستی به صفحهٔ انتشار مراجعه کنید.', textDirection: TextDirection.rtl),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, _Choice.never), child: const Text('دیگر به‌روزرسانی نکن')),
          TextButton(onPressed: () => Navigator.pop(ctx, _Choice.skip), child: const Text('رد کردن این نسخه')),
          TextButton(onPressed: () => Navigator.pop(ctx, _Choice.later), child: const Text('بعداً')),
          if (info.hasAsset) FilledButton(onPressed: () => Navigator.pop(ctx, _Choice.update), child: const Text('به‌روزرسانی')),
        ],
      ),
    );
    switch (choice) {
      case _Choice.update:
        if (context.mounted) await _downloadAndInstall(context, info);
      case _Choice.skip:
        await settings.setSkippedUpdate(info.version);
      case _Choice.never:
        await settings.setAutoUpdateCheck(false);
      case _Choice.later || null:
        break;
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('در حال دریافت به‌روزرسانی', textDirection: TextDirection.rtl),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: value),
            const SizedBox(height: 10),
            PlainText(value == null ? '…' : _digits('${(value * 100).round()}%')),
          ]),
        ),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('انصراف'))],
      ),
    );
    void closeDialog() {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final file = await UpdateService.download(info, onProgress: (v) => progress.value = v, cancelled: () => cancelled);
      closeDialog();
      final ok = await UpdateService.install(file);
      if (!ok) {
        messenger.showSnackBar(const SnackBar(
          content: Text('برای نصب، اجازهٔ «نصب برنامه از این منبع» را بدهید و دوباره به‌روزرسانی را بزنید.'),
          duration: Duration(seconds: 6),
        ));
      }
    } catch (e) {
      closeDialog();
      if (!UpdateService.isCancelled(e)) {
        messenger.showSnackBar(const SnackBar(content: Text('دریافت به‌روزرسانی ناموفق بود؛ دوباره تلاش کنید.')));
      }
    } finally {
      progress.dispose();
    }
  }
}

enum _Choice { update, later, skip, never }
