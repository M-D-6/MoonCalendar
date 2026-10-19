import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import '../../core/platform_info.dart';

import '../../core/app_version.dart';
import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/settings.dart';
import '../../core/update_service.dart';
import '../../core/l10n/l10n.dart';
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
    } catch (e) {
      messenger.hideCurrentSnackBar();
      UpdateService.log.add('check: failed ${e.runtimeType}: $e');
      if (context.mounted) await _showFailure(context, 'بررسی به‌روزرسانی ممکن نشد؛ اتصال اینترنت را بررسی کنید.');
    } finally {
      _busy = false;
    }
  }

  /// Settings → "Install the latest release again": offers the newest published release even when it is the
  /// version already installed (a repair, and a way to test the whole download and install path).
  static Future<void> reinstallLatest(BuildContext context, AppSettings settings) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('در حال بررسی آخرین نسخه…'), duration: Duration(seconds: 2)));
    try {
      final info = await UpdateService.checkLatest(force: true);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (info == null) {
        await _showFailure(context, 'نسخهٔ منتشرشده‌ای پیدا نشد.');
      } else if (!info.hasAsset) {
        await _showFailure(context, 'فایل نصب این نسخه برای دستگاه شما در صفحهٔ انتشار پیدا نشد.', info);
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('نصب مجدد آخرین نسخه', textDirection: TextDirection.rtl),
            content: PlainText('${tr('آخرین نسخهٔ منتشرشده')}: ${_digits(info.version)}\n${tr('نسخهٔ فعلی')}: ${_digits(appVersion)}\n\n${tr('فایل نصب دریافت و روی نسخهٔ فعلی نصب می‌شود.')}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دریافت و نصب')),
            ],
          ),
        );
        if (ok == true && context.mounted) await _downloadAndInstall(context, info);
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      UpdateService.log.add('check: failed ${e.runtimeType}: $e');
      if (context.mounted) await _showFailure(context, 'بررسی آخرین نسخه ممکن نشد؛ اتصال اینترنت را بررسی کنید.');
    } finally {
      _busy = false;
    }
  }

  /// A failure dialog with the technical trace (selectable and copyable) so that the cause can be reported.
  static Future<void> _showFailure(BuildContext context, String message, [UpdateInfo? info]) {
    final report = UpdateService.report;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خطا', textDirection: TextDirection.rtl),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message, textDirection: TextDirection.rtl),
              const SizedBox(height: 12),
              const Text('جزئیات فنی', style: TextStyle(fontWeight: FontWeight.bold), textDirection: TextDirection.rtl),
              const SizedBox(height: 4),
              Directionality(textDirection: TextDirection.ltr, child: SelectableText(report, style: const TextStyle(fontSize: 11.5))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: report)), child: const Text('کپی جزئیات')),
          TextButton(onPressed: () => UpdateService.openReleasePage(info), child: const Text('صفحهٔ دانلود')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
        ],
      ),
    );
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
          TextButton(onPressed: () => Navigator.pop(ctx, _Choice.page), child: const Text('صفحهٔ دانلود')),
          if (info.hasAsset) FilledButton(onPressed: () => Navigator.pop(ctx, _Choice.update), child: const Text('به‌روزرسانی')),
        ],
      ),
    );
    switch (choice) {
      case _Choice.update:
        if (context.mounted) await _downloadAndInstall(context, info);
      case _Choice.page:
        await UpdateService.openReleasePage(info);
      case _Choice.skip:
        await settings.setSkippedUpdate(info.version);
      case _Choice.never:
        await settings.setAutoUpdateCheck(false);
      case _Choice.later || null:
        break;
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    final progress = ValueNotifier<({int received, int? total})>((received: 0, total: info.assetSize));
    var cancelled = false;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('در حال دریافت به‌روزرسانی', textDirection: TextDirection.rtl),
        content: ValueListenableBuilder<({int received, int? total})>(
          valueListenable: progress,
          builder: (_, value, _) {
            final total = value.total;
            final ratio = total == null || total <= 0 ? null : (value.received / total).clamp(0.0, 1.0).toDouble();
            String size(int bytes) => bytes >= 1024 * 1024
                ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                : '${(bytes / 1024).toStringAsFixed(0)} KB';
            final amount = total == null || total <= 0
                ? size(value.received)
                : '${size(value.received)} از ${size(total)}';
            return Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 10),
              PlainText(ratio == null ? amount : _digits('${(ratio * 100).round()}%  •  $amount')),
            ]);
          },
        ),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('انصراف'))],
      ),
    );
    void closeDialog() {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final file = await UpdateService.download(
        info,
        onProgress: (received, total) => progress.value = (received: received, total: total),
        cancelled: () => cancelled,
      );
      closeDialog();
      if (!context.mounted) return;
      if (PlatformInfo.isWindows) {
        final size = file.lengthSync();
        final ready = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('دانلود کامل شد', textDirection: TextDirection.rtl),
            content: PlainText('''فایل به‌روزرسانی با موفقیت دریافت و اعتبارسنجی شد.\nحجم: ${(size / (1024 * 1024)).toStringAsFixed(1)} MB\nنسخه: ${_digits(info.version)}\n\nبرای جایگزینی فایل‌های برنامه و اجرای مجدد، روی دکمهٔ زیر بزنید.'''),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعداً')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('شروع جایگزینی و اجرای مجدد')),
            ],
          ),
        );
        if (ready != true || !context.mounted) return;
      }
      final answer = await UpdateService.install(file);
      if (answer == 'permission') {
        // Android: the permission to install from this app is still missing (its settings page was opened). The
        // downloaded file is kept, so a second tap installs without downloading again.
        messenger.showSnackBar(SnackBar(
          content: const Text('برای نصب، اجازهٔ «نصب برنامه از این منبع» را بدهید و دوباره به‌روزرسانی را بزنید.'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: tr('صفحهٔ دانلود'), onPressed: () => UpdateService.openReleasePage(info)),
        ));
      } else if (answer != 'ok') {
        if (context.mounted) await _showFailure(context, 'نصب به‌روزرسانی شروع نشد. می‌توانید فایل را از صفحهٔ دانلود بگیرید.', info);
      }
    } catch (e) {
      closeDialog();
      if (!UpdateService.isCancelled(e) && context.mounted) {
        await _showFailure(context, 'دریافت به‌روزرسانی ناموفق بود. می‌توانید فایل را از صفحهٔ دانلود بگیرید.', info);
      }
    } finally {
      progress.dispose();
    }
  }
}

enum _Choice { update, page, later, skip, never }
