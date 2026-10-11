import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:async';
import 'theme_dialog.dart';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'calendar_dialogs.dart' show showCalendarPriorityDialog;
import '../widgets/glass.dart';

import '../../core/athan/athan_android.dart';
import '../../core/athan/athan_common.dart';
import '../../core/athan/athan_service.dart';
import '../../core/calendar_math.dart' show toPersianDigits;
import '../../core/calendar_system.dart';
import '../../core/pray_times.dart';
import '../../core/settings.dart';
import '../../core/platform.dart';
import '../../core/windows_desktop_service.dart';
import 'counter_screen.dart';
import 'location_dialogs.dart';
import 'location_picker.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onMap;
  final VoidCallback? onDesktopWidgets;
  final VoidCallback? onCounterSettings;

  const SettingsScreen({super.key, required this.settings, required this.onMap, this.onDesktopWidgets, this.onCounterSettings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    AthanService.instance.refreshStatus();
    _tabController.addListener(() {
      if (!mounted) return;
      if (tab != _tabController.index) setState(() => tab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  AppSettings get settings => widget.settings;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));
  }

  void _gps() {
    showGpsLocationDialog(context, settings);
  }

  @override
  Widget build(BuildContext context) {
    // The page runs under the glass title bar; PageFrame passes the bar's height as top padding.
    final double barH = MediaQuery.paddingOf(context).top;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Stack(
        children: [
          // The pages scroll underneath the glass tab bar (their top padding leaves room for it).
          Positioned.fill(child: _buildTab(context, tab)),
          // Soft fade just below the glass frame, so the texts melt away elegantly as they slide under it.
          Positioned(
            top: barH + 74,
            left: 0,
            right: 0,
            height: 34,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .92),
                      Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: barH + 4,
            left: 10,
            right: 10,
            child: GlassSurface(
              borderRadius: BorderRadius.circular(28),
              blur: 24,
              opacity: Theme.of(context).brightness == Brightness.dark ? .30 : .40,
              child: Material(
                color: Colors.transparent,
                child: TabBar(
                  tabs: [
                    Tab(icon: const Icon(Icons.palette_outlined), height: 74, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 92), child: Text(tr('رابط و تقویم'), maxLines: 2, textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 12.5, height: 1.15)))),
                    Tab(icon: const Icon(Icons.widgets_outlined), height: 74, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 92), child: Text(tr('اعلان و ویجت'), maxLines: 2, textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 12.5, height: 1.15)))),
                    Tab(icon: const Icon(Icons.location_on_outlined), height: 74, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 92), child: Text(tr('موقعیت و اذان'), maxLines: 2, textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 12.5, height: 1.15)))),
                  ],
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.label,
                  onTap: (value) => setState(() => tab = value),
                  controller: _tabController,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    switch (index) {
      case 0:
        return _interfaceAndCalendar();
      case 1:
        return _notificationAndWidget();
      default:
        return _locationAndAthan();
    }
  }

  Widget _interfaceAndCalendar() => ListView(
        padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 84, 10, 28),
        children: [
          _section('رابط کاربری', [
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('تنظیم پوسته', textDirection: TextDirection.rtl),
              subtitle: Text(themeSummary(settings), textDirection: TextDirection.rtl),
              trailing: Icon(L10n.chevron),
              onTap: () => showThemeDialog(context, settings),
            ),
            ListTile(
              leading: const Icon(Icons.language_outlined),
              title: PlainText(languageTitle),
              subtitle: PlainText(settings.language.nativeName),
              trailing: Icon(L10n.chevron),
              onTap: () => showLanguageDialog(context, settings),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('اولویت نمایش تقویم‌ها', textDirection: TextDirection.rtl),
              subtitle: Text(
                settings.enabledCalendars.map((c) => c.title).join('، '),
                textDirection: TextDirection.rtl,
              ),
              onTap: () => showCalendarPriorityDialog(context, settings),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.filter_2_outlined),
              title: const Text('نمایش تقویم دوم در جدول ماه', textDirection: TextDirection.rtl),
              subtitle: const Text('شمارهٔ روز تقویم دوم، کوچک زیر هر روز', textDirection: TextDirection.rtl),
              value: settings.secondaryCalendarShown,
              onChanged: settings.enabledCalendars.length > 1 ? settings.setSecondaryCalendarShown : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.filter_3_outlined),
              title: const Text('نمایش تقویم سوم در جدول ماه', textDirection: TextDirection.rtl),
              subtitle: const Text('شمارهٔ روز تقویم سوم، کنار تقویم دوم', textDirection: TextDirection.rtl),
              value: settings.thirdCalendarShown,
              onChanged: settings.enabledCalendars.length > 2 ? settings.setThirdCalendarShown : null,
            ),
            ListTile(
              leading: const Icon(Icons.touch_app_outlined),
              title: const Text('تنظیمات شمارنده', textDirection: TextDirection.rtl),
              subtitle: const Text('رنگ، ویبره و دکمهٔ ۱-؛ تنظیمات از همین برنامه', textDirection: TextDirection.rtl),
              onTap: widget.onCounterSettings ?? () { unawaited(showCounterSettingsDialog(context)); },
            ),
            if (PlatformInfo.isWindows)
              ListTile(
                leading: const Icon(Icons.desktop_windows_outlined),
                title: const Text('اندازهٔ پنجره', textDirection: TextDirection.rtl),
                subtitle: const Text(
                  'اندازه در ویندوز ذخیره می‌شود؛ ارتفاع آزاد است و حداقل عرض حالت موبایلی حفظ می‌شود',
                  textDirection: TextDirection.rtl,
                ),
                onTap: () => _windowSizeDialog(context),
              ),
            _switch('طیف رنگی', 'فعال‌کردن پس‌زمینهٔ گرادیانی', settings.gradient, settings.setGradient, Icons.gradient_outlined),
            _switch('تعطیلات به رنگ قرمز', 'نمایش تعطیلات با رنگ قرمز', settings.redHolidays, settings.setRedHolidays, Icons.event_busy_outlined),
            _switch('نوشتار پررنگ', 'افزایش وزن نوشتار رابط', settings.bold, settings.setBold, Icons.format_bold_outlined),
            _switch('رقم‌های فارسی', 'نمایش رقم‌ها به فارسی', settings.localDigits, settings.setLocalDigits, Icons.pin_outlined),
            _switch('نام انگلیسی ماه‌های میلادی', 'در متن فارسی، نام ماه‌های میلادی مثل June و July نمایش داده شود', settings.englishGregorianPersianMonths, settings.setEnglishGregorianPersianMonths, Icons.translate_outlined),
          ]),
          _section('تقویم', [
            _singleSelectInt(
              icon: Icons.view_week_outlined,
              title: 'شروع هفته',
              summary: _weekdayName(settings.weekStart),
              values: List.generate(7, (i) => i),
              current: settings.weekStart,
              label: _weekdayName,
              onChanged: settings.setWeekStart,
            ),
            _weekdayMultiChoice(),
            _switch('شمارهٔ هفته', 'نمایش شمارهٔ هفته در صفحهٔ تقویم', settings.showWeekNumber, settings.setShowWeekNumber, Icons.numbers_outlined),
            _deviceCalendarTile(),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('نوع مناسبت‌ها', textDirection: TextDirection.rtl),
              subtitle: Text(_eventSummary(), textDirection: TextDirection.rtl),
              onTap: _eventsDialog,
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('تنظیم تقویم قمری', textDirection: TextDirection.rtl),
              subtitle: Text('اصلاح تاریخ هجری قمری: ${settings.hijriOffset > 0 ? '+' : ''}${toPersianDigits(settings.hijriOffset)} روز', textDirection: TextDirection.rtl),
              trailing: Icon(L10n.chevron),
              onTap: _hijriOffsetDialog,
            ),
            _switch('اطلاعات نجومی', 'نمایش صورت فلکی، نام سال و اطلاعات نجومی تکمیلی', settings.astronomicalFeatures, settings.setAstronomicalFeatures, Icons.auto_awesome_outlined),
            if (settings.astronomicalFeatures)
              _switch('قمر در عقرب', 'نمایش وضعیت قمر در عقرب', settings.showMoonInScorpio, settings.setShowMoonInScorpio, Icons.brightness_3_outlined),
          ]),
        ],
      );

  Widget _notificationAndWidget() => ListView(
        padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 84, 10, 28),
        children: [
          _section('اعلان', [
            _switch(
              'روشن کردن اعلان',
              PlatformInfo.isWindows ? 'نمایش بی‌صدای تاریخ و اوقات شرعی در اعلان‌های ویندوز' : 'اعلان همیشگی برای تاریخ‌ها',
              settings.notifyDate,
              (value) async {
                if (value && PlatformInfo.isAndroid) {
                  final granted = await AthanAndroid.requestNotificationPermission();
                  if (!granted) {
                    _snack('برای نمایش اعلان همیشگی، دسترسی اعلان را فعال کنید');
                    return;
                  }
                }
                await settings.setNotifyDate(value);
              },
              Icons.notifications_outlined,
            ),
            if (settings.notifyDate)
              _switch('نمایش اعلان در قفل صفحه', 'فقط هنگامی که قفل صفحه فعال باشد', settings.notifyDateLockScreen, settings.setNotifyDateLockScreen, Icons.lock_outline),
            if (settings.notifyDate)
              _switch('عدد بزرگ در نوار اعلان', 'نمایش روز ماه به صورت عددی بزرگ', settings.largeDayNumberNotification, settings.setLargeDayNumberNotification, Icons.format_size_outlined),
              if (PlatformInfo.isAndroid || PlatformInfo.isWindows)
                _switch('آیکون برنامه با عدد روز', PlatformInfo.isAndroid ? 'به‌جای حرف M، عدد روز ماه روی آیکون برنامه نمایش داده می‌شود و هر روز عوض می‌شود' : 'به‌جای حرف M، عدد روز ماه روی آیکون Tray نمایش داده می‌شود', settings.dayNumberAppIcon, settings.setDayNumberAppIcon, Icons.calendar_today_outlined),
            if (settings.notifyDate)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('جهت اعلان', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'auto', label: Text('مطابق زبان')),
                          ButtonSegment(value: 'rtl', label: Text('راست‌چین')),
                          ButtonSegment(value: 'ltr', label: Text('چپ‌چین')),
                        ],
                        selected: {settings.notifyDirection},
                        onSelectionChanged: (v) => settings.setNotifyDirection(v.first),
                      ),
                    ),
                  ],
                ),
              ),
            if (settings.notifyDate) _notificationLayoutEditor(),
          ]),
          _section('ویجت‌ها و پیش‌فرض‌ها', [
            _switch('نمایش تاریخ به‌صورت عددی', 'تاریخ‌ها به صورت سال/ماه/روز نمایش داده می‌شوند و در پایان «شمسی»، «قمری» یا «میلادی» می‌آید', settings.numericalDate, settings.setNumericalDate, Icons.looks_one_outlined),
            _switch('رنگ‌های سیستم در ویجت', 'پیش‌فرض ویجت‌هایی که هنوز سفارشی نشده‌اند؛ تنظیم هر ویجت جداگانه قابل تغییر است', settings.widgetDynamicColors, settings.setWidgetDynamicColors, Icons.color_lens_outlined),
            if (settings.widgetDynamicColors)
              ListTile(
                leading: const Icon(Icons.opacity_outlined),
                title: const Text('شفافیت پس‌زمینهٔ ویجت', textDirection: TextDirection.rtl),
                subtitle: Text('${toPersianDigits((settings.widgetTransparency * 100).round())}٪', textDirection: TextDirection.rtl),
                onTap: _widgetTransparencyDialog,
              ),
            if (!settings.widgetDynamicColors) ...[
              ListTile(
                leading: const Icon(Icons.format_color_text_outlined),
                title: const Text('رنگ متن ویجت', textDirection: TextDirection.rtl),
                subtitle: Text(settings.widgetTextColor, textDirection: TextDirection.ltr),
                trailing: Icon(L10n.chevron),
                onTap: () => _widgetColorDialog(background: false),
              ),
              ListTile(
                leading: const Icon(Icons.format_color_fill_outlined),
                title: const Text('رنگ پس‌زمینهٔ ویجت', textDirection: TextDirection.rtl),
                subtitle: Text(settings.widgetBackgroundColor, textDirection: TextDirection.ltr),
                trailing: Icon(L10n.chevron),
                onTap: () => _widgetColorDialog(background: true),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('محتوای ویجت', textDirection: TextDirection.rtl),
              subtitle: Text(_widgetContentSummary(), textDirection: TextDirection.rtl),
              trailing: Icon(L10n.chevron),
              onTap: _widgetContentDialog,
            ),
            if (settings.widgetWhatToShow.contains('times'))
              ListTile(
                leading: const Icon(Icons.schedule_send_outlined),
                title: const Text('اوقات نمایش‌داده‌شده در ویجت', textDirection: TextDirection.rtl),
                subtitle: Text(_widgetPrayerTimesSummary(), textDirection: TextDirection.rtl),
                trailing: Icon(L10n.chevron),
                onTap: _widgetPrayerTimesDialog,
              ),
            _switch('ساعت در ویجت', 'پیش‌فرض ویجت‌هایی که هنوز سفارشی نشده‌اند', settings.widgetClock, settings.setWidgetClock, Icons.access_time_outlined),
            _switch('۲۴ ساعته', 'نمایش ساعت به‌صورت ۲۴تایی', settings.widgetIn24, settings.setWidgetIn24, Icons.schedule_outlined),
            _switch('نمایش ثانیه در ویجت', 'نمایش ثانیه در ساعت ویجت؛ پیش‌فرض خاموش است', settings.widgetShowSeconds, settings.setWidgetShowSeconds, Icons.timer_outlined),
            _switch('تراز کناری ساعت و تاریخ', 'ساعت چپ‌چین و تاریخ راست‌چین؛ پیش‌فرض وسط‌چین باقی می‌ماند', settings.widgetEdgeAlign, settings.setWidgetEdgeAlign, Icons.format_align_justify_outlined),
            _switch('تراز وسط ویجت', 'چیدمان مرکزی محتوای ویجت‌ها', settings.centerAlignWidgets, settings.setCenterAlignWidgets, Icons.format_align_center_outlined),
            _switch('وقت ایران', 'نمایش ویجت و اعلان برنامه به‌وقت ایران در همه‌جا، مناسب ایرانیان خارج از ایران', settings.iranTime, settings.setIranTime, Icons.access_time_outlined),
            if (PlatformInfo.isWindows)
              ListTile(
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('مدیریت ویجت‌های دسکتاپ', textDirection: TextDirection.rtl),
                subtitle: const Text('افزودن، حذف، جابه‌جایی، تغییر اندازه و تنظیم کامل ویجت‌های دسکتاپ', textDirection: TextDirection.rtl),
                trailing: Icon(L10n.chevron),
                onTap: widget.onDesktopWidgets,
              ),
            if (PlatformInfo.isAndroid) ...[
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('به‌روزرسانی ویجت‌های Android', textDirection: TextDirection.rtl),
                subtitle: const Text('دادهٔ تاریخ، مناسبت، اوقات و ماه در همهٔ اندازه‌های ویجت همگام می‌شود', textDirection: TextDirection.rtl),
                onTap: () async { await PlatformServices.refreshWidgets(); _snack('ویجت‌ها به‌روزرسانی شدند'); },
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper_outlined),
                title: const Text('والپیپر زندهٔ تقویم', textDirection: TextDirection.rtl),
                subtitle: const Text('والپیپر Mooncalendar را در تنظیمات Android فعال کنید', textDirection: TextDirection.rtl),
                onTap: () async { try { await PlatformServices.openLiveWallpaper(); } catch (_) { _snack('بازکردن والپیپر ممکن نشد'); } },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('حالت Screensaver', textDirection: TextDirection.rtl),
                subtitle: const Text('تنظیم Mooncalendar به‌عنوان محافظ صفحهٔ Android', textDirection: TextDirection.rtl),
                onTap: () async { try { await PlatformServices.openDreamSettings(); } catch (_) { _snack('بازکردن تنظیمات محافظ صفحه ممکن نشد'); } },
              ),
            ],
          ]),
          if (PlatformInfo.isWindows)
            _section('ویندوز', [
              _switch('شروع با ویندوز', 'اجرای خودکار برنامه (در ناحیهٔ اعلان) هنگام ورود به ویندوز', settings.startWithWindows, settings.setStartWithWindows, Icons.power_settings_new_rounded),
              _switch('فعال ماندن در پس‌زمینه', 'با بستن پنجره، برنامه به‌جای خروج در پس‌زمینه می‌ماند', settings.runInBackground, settings.setRunInBackground, Icons.energy_savings_leaf_outlined),
              _switch('نمایش آیکون Tray', 'نمایش آیکون Mooncalendar در ناحیهٔ اعلان ویندوز', settings.showTrayIcon, settings.setShowTrayIcon, Icons.notifications_none_outlined),
            ]),
        ],
      );

  bool get _hasLocation => settings.latitude != null && settings.longitude != null;

  Widget _locationAndAthan() {
    final hasLocation = _hasLocation;
    final isJafari = settings.prayerMethod == PrayerMethod.jafari;
    final highLatitude = hasLocation && settings.latitude!.abs() > 48;
    return ListView(
      padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 84, 10, 28),
      children: [
        _section('موقعیت', [
          ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: const Text('انتخاب شهر یا استان', textDirection: TextDirection.rtl),
            subtitle: Text(_locationSummary(), textDirection: TextDirection.rtl),
            trailing: Icon(L10n.chevron),
            onTap: () => showLocationPicker(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.my_location_outlined),
            title: const Text('دریافت مختصات از مکان‌یاب (GPS)', textDirection: TextDirection.rtl),
            subtitle: const Text('استفاده از موقعیت فعلی دستگاه', textDirection: TextDirection.rtl),
            onTap: _gps,
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('انتخاب روی نقشه', textDirection: TextDirection.rtl),
            subtitle: const Text('تنظیم مختصات به‌صورت دستی', textDirection: TextDirection.rtl),
            onTap: widget.onMap,
          ),
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('ورود دستی مختصات', textDirection: TextDirection.rtl),
            subtitle: hasLocation
                ? Text('${settings.latitude!.toStringAsFixed(6)} ، ${settings.longitude!.toStringAsFixed(6)}\nارتفاع: ${settings.elevation.toStringAsFixed(1)} متر', textDirection: TextDirection.ltr)
                : const Text('عرض، طول و ارتفاع جغرافیایی را دستی وارد کنید', textDirection: TextDirection.rtl),
            onTap: _manualCoordinatesDialog,
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('عدم نمایش اوقات', textDirection: TextDirection.rtl),
            subtitle: const Text('پاک‌کردن مکان ذخیره‌شده و غیرفعال‌شدن اوقات شرعی و اذان', textDirection: TextDirection.rtl),
            enabled: hasLocation,
            onTap: () => settings.clearLocation(),
          ),
        ]),
        _section('اذان', [
          if (!hasLocation)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('برای فعال‌شدن اوقات شرعی و اذان، ابتدا مکان خود را تعیین کنید', textDirection: TextDirection.rtl),
            ),
          if (hasLocation)
            _singleSelect<PrayerMethod>(
              icon: Icons.calculate_outlined,
              title: 'شیوهٔ محاسبه',
              summary: _prayerMethodName(settings.prayerMethod),
              values: PrayerMethod.values,
              current: settings.prayerMethod,
              label: _prayerMethodName,
              onChanged: settings.setPrayerMethod,
            ),
          if (highLatitude)
            _singleSelect<HighLatitudeMethod>(
              icon: Icons.public_outlined,
              title: 'شیوهٔ عرض‌های جغرافیایی بالا',
              summary: _highLatitudeName(settings.highLatitudeMethod),
              values: HighLatitudeMethod.values,
              current: settings.highLatitudeMethod,
              label: _highLatitudeName,
              onChanged: settings.setHighLatitudeMethod,
            ),
          if (hasLocation && !isJafari)
            _switch('شیوهٔ محاسبهٔ اذان عصر حنفی', 'استفاده از روش حنفی برای عصر', settings.asrMethod == AsrMethod.hanafi, (v) => settings.setAsrMethod(v ? AsrMethod.hanafi : AsrMethod.standard), Icons.wb_sunny_outlined),
          if (hasLocation)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('فاصلهٔ بین اذان واقعی و اذان برنامه', textDirection: TextDirection.rtl),
              subtitle: Text('چند دقیقه پیش از اذان، هشدار به صدا درآید: ${toPersianDigits(settings.athanGap)} دقیقه', textDirection: TextDirection.rtl),
              onTap: _athanGapDialog,
            ),
          if (hasLocation) _athanAlarmsTile(),
          if (hasLocation) _athanStatusTiles(),
          if (hasLocation && AthanService.isSupported)
            ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('انتخاب اذان', textDirection: TextDirection.rtl),
              subtitle: Text(_athanSoundSummary(), textDirection: TextDirection.rtl),
              trailing: Icon(L10n.chevron),
              onTap: _athanSoundDialog,
            ),
          if (hasLocation && AthanService.isSupported)
            ListTile(
              leading: const Icon(Icons.volume_up_outlined),
              title: const Text('پیش‌نمایش', textDirection: TextDirection.rtl),
              subtitle: const Text('اعلان و صدای اذان را همین حالا مثل زمان واقعی نشان می‌دهد', textDirection: TextDirection.rtl),
              onTap: _athanPreviewDialog,
            ),
          if (hasLocation && PlatformInfo.isWindows)
            ListTile(
              leading: const Icon(Icons.stop_circle_outlined),
              title: const Text('توقف صدای اذان', textDirection: TextDirection.rtl),
              onTap: () => AthanService.instance.stopPlayback(),
            ),
          if (hasLocation && PlatformInfo.isAndroid)
            _switch('لرزش', 'لرزش هنگام اذان (با تغییر آن، کانال اعلان اذان دوباره ساخته می‌شود)', settings.athanVibration, settings.setAthanVibration, Icons.vibration_outlined),
          if (hasLocation && PlatformInfo.isAndroid && settings.athanAlarms.isNotEmpty)
            const ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('برای تنظیم حجم صدای اذان، هنگام زدن دکمهٔ فیزیکی صدای گوشی، در قسمت سه‌نقطهٔ آن پنجره، حجم صدای کانال اعلان (Notification) دستگاه را تغییر دهید.', textDirection: TextDirection.rtl),
            ),
          if (hasLocation)
            _singleSelect<MidnightMethod>(
              icon: Icons.nightlight_outlined,
              title: 'نیمه‌شب',
              summary: _midnightName(settings.midnightMethod ?? _defaultMidnight(settings.prayerMethod)),
              values: MidnightMethod.values,
              current: settings.midnightMethod ?? _defaultMidnight(settings.prayerMethod),
              label: _midnightName,
              onChanged: (value) => settings.setMidnightMethod(value),
            ),
        ]),
      ],
    );
  }

  // --- athan helpers -------------------------------------------------------

  Widget _athanAlarmsTile() => ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('اذان‌ها', textDirection: TextDirection.rtl),
        subtitle: Text(
          settings.athanAlarms.isEmpty ? 'هیچ‌کدام' : AthanPrayer.values.where((p) => settings.athanAlarms.contains(p.key)).map((p) => p.label).join('، '),
          textDirection: TextDirection.rtl,
        ),
        trailing: Icon(L10n.chevron),
        onTap: _athanAlarmsDialog,
      );

  Future<void> _athanAlarmsDialog() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final values = {...settings.athanAlarms};
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('اذان‌ها', textDirection: TextDirection.rtl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final prayer in AthanPrayer.values)
                    CheckboxListTile(
                      value: values.contains(prayer.key),
                      onChanged: (v) => setState(() => v == true ? values.add(prayer.key) : values.remove(prayer.key)),
                      title: Text(prayer.label, textDirection: TextDirection.rtl),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, values), child: const Text('تأیید')),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    await settings.setAthanAlarms(result);
    if (result.isNotEmpty) await _ensureNotificationPermission();
  }

  /// Android 13+ needs an explicit runtime permission before any athan can show.
  Future<bool> _ensureNotificationPermission() async {
    if (!PlatformInfo.isAndroid) return true;
    final granted = await AthanAndroid.requestNotificationPermission();
    await AthanService.instance.refreshStatus();
    if (!granted) {
      _snack('جهت عملکرد صحیح اذان برنامه به دسترسی اعلان نیاز دارد. اگر پنجرهٔ درخواست نمایش داده نمی‌شود، از تنظیمات اعلان‌های برنامه آن را فعال کنید.');
      await AthanAndroid.openNotificationSettings();
    }
    return granted;
  }

  Widget _athanStatusTiles() {
    final next = AthanService.instance.nextAlarm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (settings.athanAlarms.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('اذان بعدی', textDirection: TextDirection.rtl),
            subtitle: Text(next == null ? 'زمانی برای نمایش وجود ندارد' : _nextAthanText(next), textDirection: TextDirection.rtl),
          ),
        if (PlatformInfo.isAndroid)
          ValueListenableBuilder<AndroidAthanStatus?>(
            valueListenable: AthanService.instance.androidStatus,
            builder: (context, status, _) {
              if (status == null || settings.athanAlarms.isEmpty) return const SizedBox.shrink();
              return Column(
                children: [
                  if (!status.notifications)
                    ListTile(
                      leading: Icon(Icons.notifications_off_outlined, color: Theme.of(context).colorScheme.error),
                      title: const Text('اعلان‌های برنامه غیرفعال است', textDirection: TextDirection.rtl),
                      subtitle: const Text('بدون دسترسی اعلان، اذان نمایش داده نمی‌شود. برای فعال‌سازی ضربه بزنید.', textDirection: TextDirection.rtl),
                      onTap: _ensureNotificationPermission,
                    ),
                  if (!status.exactAlarms)
                    ListTile(
                      leading: Icon(Icons.alarm_off_outlined, color: Theme.of(context).colorScheme.error),
                      title: const Text('اجازهٔ زنگ دقیق داده نشده است', textDirection: TextDirection.rtl),
                      subtitle: const Text('برای اینکه اذان دقیقاً سر وقت پخش شود، «آلارم‌ها و یادآورها» را برای برنامه مجاز کنید.', textDirection: TextDirection.rtl),
                      onTap: AthanAndroid.openExactAlarmSettings,
                    ),
                  ListTile(
                    leading: const Icon(Icons.battery_saver_outlined),
                    title: const Text('محدودیت باتری', textDirection: TextDirection.rtl),
                    subtitle: const Text('اگر اذان گاهی پخش نمی‌شود، برنامه را از بهینه‌سازی باتری مستثنا کنید (در برخی گوشی‌ها «شروع خودکار» هم باید فعال باشد).', textDirection: TextDirection.rtl),
                    onTap: AthanAndroid.openBatterySettings,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  String _nextAthanText(AthanAlarm alarm) {
    final at = DateTime.fromMillisecondsSinceEpoch(alarm.epochMs, isUtc: true);
    final shown = settings.iranTime ? at.add(const Duration(minutes: 210)) : at.toLocal();
    final now = settings.iranTime ? DateTime.now().toUtc().add(const Duration(minutes: 210)) : DateTime.now();
    final sameDay = shown.year == now.year && shown.month == now.month && shown.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = shown.year == tomorrow.year && shown.month == tomorrow.month && shown.day == tomorrow.day;
    final clock = '${shown.hour.toString().padLeft(2, '0')}:${shown.minute.toString().padLeft(2, '0')}';
    final day = sameDay ? 'امروز' : (isTomorrow ? 'فردا' : '${toPersianDigits(shown.month)}/${toPersianDigits(shown.day)}');
    final prayer = AthanPrayer.fromKey(alarm.prayer)?.label ?? alarm.prayer;
    return 'اذان $prayer، $day ساعت ${settings.localDigits ? toPersianDigits(clock) : clock}';
  }

  String _athanSoundSummary() {
    if (settings.athanSound == athanCustomSoundKey) {
      final name = settings.athanCustomName;
      return name == null || name.isEmpty ? 'صدای انتخاب‌شده' : name;
    }
    return (athanBundledSound(settings.athanSound) ?? athanBundledSounds.first).label;
  }

  Future<void> _athanSoundDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> pickBundled(AthanSoundOption option) async {
          Navigator.pop(dialogContext);
          await settings.setAthanSound(option.key);
          _snack('صدای اذان تنظیم شد؛ برای شنیدن آن از «پیش‌نمایش» استفاده کنید');
        }

        Future<void> pickCustom(Future<PickedSound?> Function() picker) async {
          Navigator.pop(dialogContext);
          final picked = await picker();
          if (picked == null) return;
          await settings.setAthanSound(athanCustomSoundKey, customUri: picked.uri, customName: picked.name);
          _snack('صدای درخواستی تنظیم شد');
        }

        return AlertDialog(
          title: const Text('انتخاب اذان', textDirection: TextDirection.rtl),
          contentPadding: const EdgeInsets.only(top: 12),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in athanBundledSounds)
                  ListTile(
                    leading: Icon(settings.athanSound == option.key ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    title: Text(option.label, textDirection: TextDirection.rtl),
                    onTap: () => pickBundled(option),
                  ),
                const Divider(),
                if (PlatformInfo.isAndroid)
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('پیش‌فرض دستگاه', textDirection: TextDirection.rtl),
                    subtitle: const Text('انتخاب از زنگ‌ها و اعلان‌های گوشی', textDirection: TextDirection.rtl),
                    onTap: () => pickCustom(AthanService.instance.pickRingtone),
                  ),
                ListTile(
                  leading: const Icon(Icons.audio_file_outlined),
                  title: const Text('بیشتر', textDirection: TextDirection.rtl),
                  subtitle: const Text('انتخاب یک پرونده صوتی، برای نمونه «mp3»', textDirection: TextDirection.rtl),
                  onTap: () => pickCustom(AthanService.instance.pickCustomFile),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو'))],
        );
      },
    );
  }

  Future<void> _athanPreviewDialog() async {
    final prayer = await showDialog<AthanPrayer>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('پیش‌نمایش', textDirection: TextDirection.rtl),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in AthanPrayer.values)
                ListTile(title: Text(p.label, textDirection: TextDirection.rtl), onTap: () => Navigator.pop(dialogContext, p)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو'))],
      ),
    );
    if (prayer == null) return;
    if (!await _ensureNotificationPermission()) return;
    try {
      await AthanService.instance.preview(prayer);
    } catch (_) {
      _snack('نمایش پیش‌نمایش اذان ناموفق بود');
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.fromLTRB(2, 4, 2, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 6),
              child: Text(title, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ...children,
          ],
        ),
      );

  Widget _notificationLayoutEditor() {
    final rows = settings.notificationRows;
    final summary = rows.isEmpty
        ? 'چیدمان خالی است'
        : rows
            .map((row) => row.map((key) => windowsNotificationItemLabels[key] ?? key).join('، '))
            .join('  •  ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.view_agenda_outlined),
        title: Row(
          children: [
            const Expanded(
              child: Text('چیدمان اعلان', textDirection: TextDirection.rtl),
            ),
            IconButton(
              tooltip: tr('بازنشانی'),
              onPressed: settings.resetNotificationRows,
              icon: const Icon(Icons.restore),
            ),
          ],
        ),
        subtitle: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.rtl,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 2, 8, 10),
            child: Text(
              'تعداد خط‌ها نامحدود است. هر خط می‌تواند چند آیتم داشته باشد و خط‌ها و آیتم‌ها قابل جابه‌جایی هستند.',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'هیچ خطی فعال نیست. برای ساختن اعلان، یک خط اضافه کنید.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rows.length,
            onReorderItem: (oldIndex, newIndex) => settings.reorderNotificationRows(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
            itemBuilder: (context, rowIndex) {
              final row = rows[rowIndex];
              final rowSummary = row.isEmpty
                  ? 'بدون آیتم'
                  : row.map((key) => windowsNotificationItemLabels[key] ?? key).join('، ');
              return Card(
                key: ValueKey('notification-row-$rowIndex-${row.join('|')}'),
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: ExpansionTile(
                  initiallyExpanded: rowIndex == 0,
                  leading: ReorderableDragStartListener(
                    index: rowIndex,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rowIndex == 0 ? 'خط ۱' : 'خط ${toPersianDigits(rowIndex + 1)}',
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                      IconButton(
                        tooltip: tr('افزودن آیتم'),
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _editNotificationRow(rowIndex),
                      ),
                      IconButton(
                        tooltip: tr('حذف خط'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => settings.removeNotificationRow(rowIndex),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    rowIndex == 0 ? rowSummary : 'توضیح: $rowSummary',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    style: _notificationLinePreviewStyle(settings.notificationStyleAt(rowIndex)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ظاهر این خط', textDirection: TextDirection.rtl),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            textDirection: L10n.direction,
                            children: [
                              for (final style in notificationLineStyleKeys)
                                FilterChip(
                                  label: Text(notificationLineStyleLabels[style] ?? style),
                                  selected: settings.notificationStyleAt(rowIndex).contains(style),
                                  onSelected: (on) => settings.toggleNotificationRowStyle(rowIndex, style, on),
                                ),
                            ],
                          ),
                          if (PlatformInfo.isWindows) ...[
                            const SizedBox(height: 4),
                            Text(
                              'در ویندوز «زیرخط» پشتیبانی نمی‌شود و فقط سه بخش اول اعلان استایل جدا دارند.',
                              textDirection: TextDirection.rtl,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (row.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: OutlinedButton.icon(
                          onPressed: () => _editNotificationRow(rowIndex),
                          icon: const Icon(Icons.add),
                          label: const Text('انتخاب آیتم‌های این خط'),
                        ),
                      ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: row.length,
                      onReorderItem: (oldItem, newItem) async {
                        final next = settings.notificationRows.map(List<String>.from).toList(growable: true);
                        final items = next[rowIndex];
                        final item = items.removeAt(oldItem);
                        items.insert(newItem, item);
                        await settings.setNotificationRows(next);
                      },
                      itemBuilder: (context, itemIndex) {
                        final key = row[itemIndex];
                        return ListTile(
                          key: ValueKey('notification-item-$rowIndex-$itemIndex-$key'),
                          dense: true,
                          leading: ReorderableDragStartListener(
                            index: itemIndex,
                            child: const Icon(Icons.drag_indicator_outlined),
                          ),
                          title: Text(
                            windowsNotificationItemLabels[key] ?? key,
                            textDirection: TextDirection.rtl,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (rows.length > 1)
                                GlassPopupMenuButton<int>(
                                  tooltip: tr('انتقال به خط دیگر'),
                                  icon: const Icon(Icons.drive_file_move_outline),
                                  itemBuilder: (context) => [
                                    for (var target = 0; target < rows.length; target++)
                                      if (target != rowIndex)
                                        GlassMenuItem<int>(
                                          value: target,
                                          child: Text(
                                            'انتقال به خط ${toPersianDigits(target + 1)}',
                                            textDirection: TextDirection.rtl,
                                          ),
                                        ),
                                  ],
                                  onSelected: (target) => settings.moveNotificationItem(rowIndex, target, key),
                                ),
                              IconButton(
                                tooltip: tr('حذف آیتم'),
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => settings.removeNotificationItem(rowIndex, key),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _editNotificationRow(rowIndex),
                        icon: const Icon(Icons.tune),
                        label: const Text('انتخاب آیتم‌ها'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: settings.addNotificationRow,
            icon: const Icon(Icons.add),
            label: const Text('افزودن خط'),
          ),
        ],
      ),
    );
  }

  TextStyle? _notificationLinePreviewStyle(Set<String> styles) {
    if (styles.isEmpty) return null;
    final base = Theme.of(context).textTheme.bodyMedium;
    return base?.copyWith(
      fontWeight: styles.contains('bold') || styles.contains('heading') ? FontWeight.w700 : null,
      fontSize: styles.contains('heading') ? (base.fontSize ?? 14) * 1.15 : null,
      color: styles.contains('light') ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5) : null,
      decoration: styles.contains('underline') ? TextDecoration.underline : null,
    );
  }

  Future<void> _editNotificationRow(int rowIndex) async {
    if (!mounted || rowIndex < 0 || rowIndex >= settings.notificationRows.length) return;
    final current = List<String>.from(settings.notificationRows[rowIndex]);
    final selected = current.toSet();
    final usedElsewhere = <String, int>{};
    for (var index = 0; index < settings.notificationRows.length; index++) {
      if (index == rowIndex) continue;
      for (final key in settings.notificationRows[index]) {
        usedElsewhere[key] = index;
      }
    }
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'آیتم‌های خط ${toPersianDigits(rowIndex + 1)}',
            textDirection: TextDirection.rtl,
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final key in windowsNotificationItemKeys)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(key),
                      title: Text(
                        windowsNotificationItemLabels[key] ?? key,
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: usedElsewhere.containsKey(key)
                          ? Text(
                              'این آیتم در خط ${toPersianDigits(usedElsewhere[key]! + 1)} فعال است؛ برای جابه‌جایی از گزینهٔ «انتقال به خط دیگر» استفاده کنید.',
                              textDirection: TextDirection.rtl,
                            )
                          : null,
                      onChanged: usedElsewhere.containsKey(key)
                          ? null
                          : (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(key);
                          } else {
                            selected.remove(key);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                final ordered = <String>[
                  ...current.where(selected.contains),
                  ...windowsNotificationItemKeys.where(
                    (key) => selected.contains(key) && !current.contains(key),
                  ),
                ];
                Navigator.pop(dialogContext, ordered);
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      await settings.setNotificationRowItems(rowIndex, result);
    }
  }

  Widget _deviceCalendarTile() => SwitchListTile.adaptive(
        value: settings.showDeviceCalendarEvents,
        onChanged: (value) async {
          if (value && PlatformInfo.isAndroid) {
            final granted = await PlatformServices.requestCalendarPermission();
            if (!granted) {
              _snack('برای نمایش رویدادهای تقویم دستگاه، دسترسی تقویم لازم است');
              return;
            }
          }
          await settings.setShowDeviceCalendarEvents(value);
        },
        secondary: const Icon(Icons.event_available_outlined),
        title: const Text('رویدادهای شخصی', textDirection: TextDirection.rtl),
        subtitle: Text(PlatformInfo.isAndroid ? 'رویدادهای تقویم گوشی با حفظ تقویم‌های برنامه نمایش داده می‌شوند' : 'در Android از تقویم سیستم خوانده می‌شود', textDirection: TextDirection.rtl),
      );

  Widget _switch(String title, String summary, bool value, ValueChanged<bool> onChanged, IconData icon) => SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon),
        title: Text(title, textDirection: TextDirection.rtl),
        subtitle: Text(summary, textDirection: TextDirection.rtl),
      );

  Widget _singleSelect<T>({required IconData icon, required String title, required String summary, required List<T> values, required T current, required String Function(T) label, required Future<void> Function(T) onChanged}) => ListTile(
        leading: Icon(icon),
        title: Text(title, textDirection: TextDirection.rtl),
        subtitle: Text(summary, textDirection: TextDirection.rtl),
        trailing: Icon(L10n.chevron),
        onTap: () async {
          final selected = await _showSingleChoice<T>(title, values, current, label);
          if (selected != null) await onChanged(selected);
        },
      );


  Widget _singleSelectInt({required IconData icon, required String title, required String summary, required List<int> values, required int current, required String Function(int) label, required Future<void> Function(int) onChanged}) => _singleSelect<int>(icon: icon, title: title, summary: summary, values: values, current: current, label: label, onChanged: onChanged);

  Widget _weekdayMultiChoice() => ListTile(
        leading: const Icon(Icons.calendar_view_week_outlined),
        title: const Text('روزهای تعطیل هفته', textDirection: TextDirection.rtl),
        subtitle: Text(settings.weekEnds.isEmpty ? 'هیچ‌کدام' : settings.weekEnds.map(_weekdayName).join('، '), textDirection: TextDirection.rtl),
        trailing: Icon(L10n.chevron),
        onTap: () async {
          final result = await showDialog<Set<int>>(
            context: context,
            builder: (dialogContext) {
              final values = {...settings.weekEnds};
              return StatefulBuilder(
                builder: (context, setState) => AlertDialog(
                  title: const Text('روزهای تعطیل هفته', textDirection: TextDirection.rtl),
                  content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final day in List.generate(7, (i) => i)) CheckboxListTile(value: values.contains(day), onChanged: (v) => setState(() => v == true ? values.add(day) : values.remove(day)), title: Text(_weekdayName(day), textDirection: TextDirection.rtl))])),
                  actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')), FilledButton(onPressed: () => Navigator.pop(dialogContext, values), child: const Text('تأیید'))],
                ),
              );
            },
          );
          if (result != null) await settings.setWeekEnds(result);
        },
      );


  Future<T?> _showSingleChoice<T>(String title, List<T> values, T current, String Function(T) label) => showDialog<T>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title, textDirection: TextDirection.rtl),
          content: SingleChildScrollView(
            child: RadioGroup<T>(
              groupValue: current,
              onChanged: (v) => Navigator.pop(dialogContext, v),
              child: Column(mainAxisSize: MainAxisSize.min, children: [for (final value in values) RadioListTile<T>(value: value, title: Text(label(value), textDirection: TextDirection.rtl))]),
            ),
          ),
        ),
      );

  Future<void> _hijriOffsetDialog() async {
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اصلاح تقویم قمری', textDirection: TextDirection.rtl),
        content: RadioGroup<int>(
          groupValue: settings.hijriOffset,
          onChanged: (v) => Navigator.pop(dialogContext, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in [-2, -1, 0, 1, 2])
                RadioListTile<int>(
                  value: value,
                  title: Text(value == 0 ? 'بدون اصلاح' : '${value > 0 ? '+' : ''}${toPersianDigits(value)} روز', textDirection: TextDirection.rtl),
                ),
            ],
          ),
        ),
      ),
    );
    if (result != null) await settings.setHijriOffset(result);
  }

  Future<void> _widgetColorDialog({required bool background}) async {
    int initial;
    try {
      var raw = background ? settings.widgetBackgroundColor : settings.widgetTextColor;
      if (!raw.startsWith('#')) raw = '#$raw';
      if (raw.length == 7) raw = '#FF${raw.substring(1)}';
      initial = int.parse(raw.substring(1), radix: 16);
    } catch (_) {
      initial = background ? 0x00000000 : 0xFFFFFFFF;
    }

    var alpha = (initial >> 24) & 0xFF;
    var red = (initial >> 16) & 0xFF;
    var green = (initial >> 8) & 0xFF;
    var blue = initial & 0xFF;

    String hex() => background
        ? '#${Color.fromARGB(alpha, red, green, blue).toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}'
        : '#${Color.fromARGB(255, red, green, blue).toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final color = Color.fromARGB(alpha, red, green, blue);
          Widget channel(String label, int value, Color track, ValueChanged<double> onChanged) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(label, style: Theme.of(context).textTheme.bodySmall, textDirection: TextDirection.rtl),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: track,
                      thumbColor: track,
                      overlayColor: track.withValues(alpha: .12),
                    ),
                    child: Directionality(textDirection: TextDirection.ltr, child: Slider(value: value.toDouble(), min: 0, max: 255, onChanged: onChanged)),
                  ),
                ],
              );

          Widget swatch(Color swatchColor, {bool checker = false}) =>
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setStateDialog(() {
                    alpha = swatchColor.a.round();
                    red = swatchColor.r.round();
                    green = swatchColor.g.round();
                    blue = swatchColor.b.round();
                  });
                },
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .7), width: 2),
                    color: checker ? Colors.transparent : swatchColor,
                  ),
                  child: checker
                      ? CustomPaint(painter: const _CheckerboardPainter())
                      : null,
                ),
              );

          return AlertDialog(
            title: Text(background ? 'رنگ پس‌زمینهٔ ویجت' : 'رنگ نوشته‌های ویجت', textDirection: TextDirection.rtl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (background && alpha < 255) const CustomPaint(painter: _CheckerboardPainter()),
                          Container(
                            color: color,
                            alignment: Alignment.center,
                            child: Text(
                              background && alpha == 0 ? 'شفاف' : '',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (background)
                    channel('شفافیت', alpha, Colors.grey, (v) => setStateDialog(() => alpha = v.round())),
                  channel('قرمز', red, const Color(0xFFFF264C), (v) => setStateDialog(() => red = v.round())),
                  channel('سبز', green, const Color(0xFF00C456), (v) => setStateDialog(() => green = v.round())),
                  channel('آبی', blue, const Color(0xFF397DFF), (v) => setStateDialog(() => blue = v.round())),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: background
                        ? [
                            swatch(Colors.transparent, checker: true),
                            swatch(Colors.black),
                            swatch(const Color(0x28FFFFFF)),
                            swatch(const Color(0x78FFFFFF)),
                          ]
                        : [
                            swatch(Colors.black),
                            swatch(Colors.yellow),
                            swatch(const Color(0xFF009187)),
                            swatch(const Color(0xFFF55000)),
                            swatch(Colors.white),
                          ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, hex()), child: const Text('تأیید')),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    if (background) {
      await settings.setWidgetBackgroundColor(result);
    } else {
      await settings.setWidgetTextColor(result);
    }
  }

  Future<void> _widgetTransparencyDialog() async {
    double value = settings.widgetTransparency;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('شفافیت پس‌زمینهٔ ویجت', textDirection: TextDirection.rtl),
          content: Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            label: tr('${(value * 100).round()}٪'),
            onChanged: (v) => setStateDialog(() => value = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, value), child: const Text('تأیید')),
          ],
        ),
      ),
    );
    if (result != null) await settings.setWidgetTransparency(result);
  }

  Future<void> _widgetContentDialog() async {
    const options = <String, String>{
      'other_calendars': 'تقویم‌های دیگر',
      'holidays': 'تعطیلات رسمی',
      'events': 'مناسبت‌های غیرتعطیل',
      'times': 'اوقات شرعی',
      'times_location': 'مکان اوقات شرعی',
    };
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final values = {...settings.widgetWhatToShow};
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('محتوای ویجت', textDirection: TextDirection.rtl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in options.entries)
                    CheckboxListTile(
                      value: values.contains(entry.key),
                      onChanged: (v) => setStateDialog(() => v == true ? values.add(entry.key) : values.remove(entry.key)),
                      title: Text(entry.value, textDirection: TextDirection.rtl),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, values), child: const Text('تأیید')),
            ],
          ),
        );
      },
    );
    if (result != null) await settings.setWidgetWhatToShow(result);
  }

  static const _widgetPrayerTimeLabels = <String, String>{
    'imsak': 'امساک',
    'fajr': 'اذان صبح',
    'sunrise': 'طلوع آفتاب',
    'dhuhr': 'اذان ظهر',
    'asr': 'اذان عصر',
    'sunset': 'غروب آفتاب',
    'maghrib': 'اذان مغرب',
    'isha': 'اذان عشاء',
    'midnight': 'نیمه‌شب شرعی',
  };

  String _widgetPrayerTimesSummary() {
    final selected = settings.widgetPrayerTimes;
    if (selected.length == _widgetPrayerTimeLabels.length) return 'همه';
    return _widgetPrayerTimeLabels.entries.where((e) => selected.contains(e.key)).map((e) => e.value).join('، ');
  }

  Future<void> _widgetPrayerTimesDialog() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final values = {...settings.widgetPrayerTimes};
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('اوقات نمایش‌داده‌شده در ویجت', textDirection: TextDirection.rtl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in _widgetPrayerTimeLabels.entries)
                    CheckboxListTile(
                      value: values.contains(entry.key),
                      onChanged: (v) => setStateDialog(() {
                        if (v == true) {
                          values.add(entry.key);
                        } else if (values.length > 1) {
                          values.remove(entry.key); // at least one time stays selected
                        }
                      }),
                      title: Text(entry.value, textDirection: TextDirection.rtl),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, values), child: const Text('تأیید')),
            ],
          ),
        );
      },
    );
    if (result != null) await settings.setWidgetPrayerTimes(result);
  }

  Future<void> _eventsDialog() async {
    const options = <String, String>{
      'iran_holidays': 'تعطیلات رسمی تنظیم‌شدهٔ مرکز تقویم دانشگاه تهران',
      'iran_others': 'مناسبت‌های تقویم رسمی دانشگاه تهران',
      'afghanistan_holidays': 'رخصتی‌های افغانستان',
      'afghanistan_others': 'سایر مناسبت‌های افغانستان',
      'iran_ancient': 'مناسبت‌های ایران باستان',
      'international': 'مناسبت‌های بین‌المللی',
      'nepal_holidays': 'تعطیلات نپال',
      'nepal_others': 'سایر مناسبت‌های نپال',
    };
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final values = {...settings.enabledEvents};
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('رویدادها', textDirection: TextDirection.rtl),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final entry in options.entries) CheckboxListTile(value: values.contains(entry.key), onChanged: (v) => setState(() => v == true ? values.add(entry.key) : values.remove(entry.key)), title: Text(entry.value, textDirection: TextDirection.rtl))])),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')), FilledButton(onPressed: () => Navigator.pop(dialogContext, values), child: const Text('تأیید'))],
          ),
        );
      },
    );
    if (result != null) await settings.setEvents(result);
  }

  Future<void> _athanGapDialog() async {
    final controller = TextEditingController(text: settings.athanGap.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فاصلهٔ اذان', textDirection: TextDirection.rtl),
        content: TextField(controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(labelText: tr('دقیقه'), border: OutlineInputBorder())),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لغو')), FilledButton(onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text)), child: const Text('تأیید'))],
      ),
    );
    controller.dispose();
    if (value != null) await settings.setAthanGap(value);
  }

  Future<void> _manualCoordinatesDialog() async {
    await showCoordinatesDialog(
      context,
      settings,
      latitude: settings.latitude,
      longitude: settings.longitude,
      elevation: settings.latitude != null ? settings.elevation : 0,
      onOpenMap: widget.onMap,
    );
  }

  Future<void> _windowSizeDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اندازهٔ پنجره', textDirection: TextDirection.rtl),
        content: const Text(
          'اندازهٔ پنجره پس از بستن برنامه ذخیره می‌شود و در اجرای بعدی بازگردانده می‌شود.',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await WindowsDesktopService.instance.applyWindowPreset(mobile: true);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حالت موبایلی'),
          ),
          FilledButton(
            onPressed: () async {
              await WindowsDesktopService.instance.applyWindowPreset(mobile: false);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حالت دسکتاپی'),
          ),
        ],
      ),
    );
  }

  String _weekdayName(int value) => ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'][value.clamp(0, 6).toInt()];
  String _eventSummary() => settings.enabledEvents.isEmpty ? 'هیچ‌کدام' : '${settings.enabledEvents.length} منبع فعال';
  String _widgetContentSummary() {
    const labels = <String, String>{
      'other_calendars': 'تقویم‌های دیگر',
      'holidays': 'تعطیلات رسمی',
      'events': 'مناسبت‌ها',
      'times': 'اوقات شرعی',
      'times_location': 'مکان اوقات',
    };
    final selected = settings.widgetWhatToShow.where(labels.containsKey).map((e) => labels[e]!).toList();
    return selected.isEmpty ? 'هیچ‌کدام' : selected.join('، ');
  }
  String _locationSummary() {
    if (settings.latitude == null) return 'اگر مایلید اوقات نمایش داده شود این بخش را تنظیم کنید';
    final name = settings.locationName;
    if (name != null && name.isNotEmpty) {
      final country = settings.locationCountryName;
      return country != null && country.isNotEmpty ? '$name، $country' : name;
    }
    return '${settings.latitude!.toStringAsFixed(4)} ، ${settings.longitude!.toStringAsFixed(4)}';
  }

  String _prayerMethodName(PrayerMethod method) => switch (method) {
        PrayerMethod.tehran => 'انجمن ژئوفیزیک، دانشگاه تهران',
        PrayerMethod.mwl => 'اتحادیهٔ جهانی اسلام',
        PrayerMethod.karachi => 'دانشگاه علوم اسلامی، کراچی',
        PrayerMethod.isna => 'جامعهٔ اسلامی آمریکای شمالی',
        PrayerMethod.jafari => 'شیعهٔ دوازده امامی، قم',
        PrayerMethod.egypt => 'مرجع عمومی تحقیقات مصر',
        PrayerMethod.makkah => 'دانشگاه ام‌القری، مکه',
        PrayerMethod.france => 'مسلمانان فرانسه',
        PrayerMethod.russia => 'شورای مسلمانان روسیه',
        PrayerMethod.singapore => 'شورای دینی اسلامی سنگاپور',
      };

  String _highLatitudeName(HighLatitudeMethod method) => switch (method) {
        HighLatitudeMethod.none => 'هیچ‌کدام',
        HighLatitudeMethod.angleBased => 'بر پایهٔ زاویه',
        HighLatitudeMethod.oneSeventh => 'یک‌هفتم',
        HighLatitudeMethod.nightMiddle => 'نیمهٔ شب',
      };

  String _midnightName(MidnightMethod method) => switch (method) {
        MidnightMethod.sunsetToSunrise => 'از غروب تا طلوع',
        MidnightMethod.sunsetToFajr => 'از غروب تا صبح',
        MidnightMethod.maghribToSunrise => 'از مغرب تا طلوع',
        MidnightMethod.maghribToFajr => 'از مغرب تا صبح',
      };

  MidnightMethod _defaultMidnight(PrayerMethod method) => method == PrayerMethod.tehran || method == PrayerMethod.jafari ? MidnightMethod.sunsetToFajr : MidnightMethod.sunsetToSunrise;
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFFECECEC);
    final dark = Paint()..color = const Color(0xFFD0D0D0);
    canvas.drawRect(Offset.zero & size, light);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if ((((x / cell).floor() + (y / cell).floor()) & 1) == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) => false;
}
