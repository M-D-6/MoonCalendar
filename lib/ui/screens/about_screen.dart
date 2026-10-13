import '../../core/platform_info.dart';
import '../../core/l10n/l10n.dart';
import '../widgets/tr_text.dart';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

const String kAppRepoUrl = 'https://github.com/M-D-6/MoonCalendar';
const String kOriginRepoUrl = 'https://github.com/persian-calendar/persian-calendar';

/// A third-party project the app builds on: what is shown in «پروژه‌های استفاده‌شده» and in its details dialog.
class _UsedProject {
  final IconData icon;
  final String name;
  final String license;
  final String url;
  final List<String> uses;
  const _UsedProject(this.icon, this.name, this.license, this.url, this.uses);
}

const List<_UsedProject> _kUsedProjects = <_UsedProject>[
  _UsedProject(
    Icons.calendar_month_rounded,
    'تقویم فارسی اندروید (Persian Calendar)',
    'GPLv3',
    kOriginRepoUrl,
    <String>[
      'منطق تقویم‌ها و تبدیل تاریخ (شمسی، میلادی، قمری)',
      'داده‌های مناسبت‌ها و تعطیلات',
      'محاسبهٔ اوقات شرعی و روش‌های آن',
      'محاسبات نجومی و داده‌های نقشه (جهان، مناطق زمانی، صفحات زمین‌ساخت)',
      'فهرست شهرها و مناطق ایران',
      'طراحی و ایدهٔ ویجت‌ها، اعلان و صفحه‌های برنامه',
      'تصاویر فصل‌ها (Lotta Nieminen، CC BY-NC 4.0)',
    ],
  ),
  _UsedProject(
    Icons.flutter_dash,
    'Flutter و Dart',
    'BSD-3-Clause',
    'https://flutter.dev',
    <String>['چارچوب اصلی برنامه و رابط کاربری'],
  ),
  _UsedProject(
    Icons.extension_rounded,
    'بسته‌های متن‌باز Dart و Flutter',
    'مجوزهای متفاوت',
    'https://pub.dev',
    <String>[
      'astronomia: محاسبات نجومی',
      'geolocator: موقعیت مکانی',
      'window_manager، tray_manager، desktop_multi_window و desktop_context_menu: پنجره، تری و ویجت‌های دسکتاپ',
      'share_plus، shared_preferences، timezone، qr و http: اشتراک‌گذاری، ذخیره‌سازی و ابزارهای کمکی',
    ],
  ),
  _UsedProject(
    Icons.font_download_rounded,
    'فونت وزیرمتن (Vazirmatn)',
    'OFL 1.1',
    'https://github.com/rastikerdar/vazirmatn',
    <String>['فونت اصلی برنامه', 'عدد روز در آیکون اعلان'],
  ),
  _UsedProject(
    Icons.public_rounded,
    'Noto Sans Symbols',
    'OFL 1.1',
    'https://fonts.google.com/noto/specimen/Noto+Sans+Symbols',
    <String>['نمادهای برج‌های فلکی'],
  ),
  _UsedProject(
    Icons.interests_rounded,
    'Material Design Icons',
    'Apache 2.0',
    'https://github.com/google/material-design-icons',
    <String>['آیکون‌های رابط کاربری'],
  ),
  _UsedProject(
    Icons.access_time_rounded,
    'PrayTimes',
    'LGPLv3',
    'https://praytimes.org',
    <String>['محاسبهٔ اوقات شرعی (پورت‌شده)'],
  ),
  _UsedProject(
    Icons.swap_horiz_rounded,
    'مبدل تقویم (Amir Khosroshahi)',
    'GPLv2+',
    'https://code.google.com/p/mobile-persian-calendar/',
    <String>['الگوریتم‌های تبدیل تاریخ'],
  ),
  _UsedProject(
    Icons.event_note_rounded,
    'StarCal',
    'AGPLv3',
    'https://github.com/ilius/starcal',
    <String>['داده‌های مناسبت‌ها و تعطیلات'],
  ),
  _UsedProject(
    Icons.explore_rounded,
    'Level',
    'GPLv3',
    'https://github.com/avianey/Level',
    <String>['تراز حبابی'],
  ),
  _UsedProject(
    Icons.map_rounded,
    'Natural Earth',
    'Public Domain',
    'https://www.naturalearthdata.com',
    <String>['نقشهٔ جهان و مناطق زمانی'],
  ),
  _UsedProject(
    Icons.terrain_rounded,
    'Tectonic Plates (fraxen)',
    'ODC-By 1.0',
    'https://github.com/fraxen/tectonicplates',
    <String>['مرز صفحات زمین‌ساخت'],
  ),
  _UsedProject(
    Icons.cloud_outlined,
    'Open-Meteo',
    'CC BY 4.0',
    'https://open-meteo.com',
    <String>['پیش‌بینی آب‌وهوا، کیفیت هوا و جست‌وجوی مکان'],
  ),
  _UsedProject(
    Icons.air_rounded,
    'MET Norway',
    'CC BY 4.0',
    'https://api.met.no',
    <String>['پیش‌بینی آب‌وهوا'],
  ),
  _UsedProject(
    Icons.volume_up_rounded,
    'بُرنا تصویر رسانه',
    'مطابق پروژهٔ مرجع',
    'https://github.com/persian-calendar/persian-calendar',
    <String>['صدا و انیمیشن اذان'],
  ),
];

/// GitHub account and display name of the people thanked in the About screen.
const List<(String, String)> _kDevelopers = <(String, String)>[
  ('ebraminio', 'Ebrahim Byagowi'),
  ('xmha97', 'Muhammadhussein Ammari'),
];

/// Shuffled once per app run, so the order is random but does not change while the screen is rebuilt.
final List<(String, String)> _shuffledDevelopers = List<(String, String)>.of(_kDevelopers)..shuffle();

const List<(IconData, String)> _kFeatures = <(IconData, String)>[
  (Icons.calendar_month_rounded, 'تقویم و تبدیل تاریخ'),
  (Icons.celebration_rounded, 'مناسبت‌ها و تعطیلات'),
  (Icons.mosque_rounded, 'اوقات شرعی و اذان'),
  (Icons.nightlight_round, 'ستاره‌شناسی'),
  (Icons.public_rounded, 'نقشهٔ جهان'),
  (Icons.explore_rounded, 'قطب‌نما و تراز'),
  (Icons.touch_app_rounded, 'شمارنده'),
  (Icons.widgets_rounded, 'ویجت و اعلان'),
  (Icons.translate_rounded, 'فارسی، انگلیسی و عربی'),
];

class AboutScreen extends StatelessWidget {
  final VoidCallback onLicenses, onDevice;
  const AboutScreen({super.key, required this.onLicenses, required this.onDevice});

  void _copy(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('پیوند کپی شد'), duration: const Duration(seconds: 2)));
  }

  void _showProject(BuildContext context, _UsedProject p) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: L10n.direction,
        child: AlertDialog(
          icon: CircleAvatar(
            radius: 26,
            backgroundColor: scheme.primaryContainer,
            child: Icon(p.icon, color: scheme.onPrimaryContainer),
          ),
          title: Text(p.name, textAlign: TextAlign.center),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
                      child: Text(p.license, style: text.labelMedium?.copyWith(color: scheme.onSecondaryContainer)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('چه چیزهایی از این پروژه استفاده شده', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final u in p.uses)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Icon(Icons.circle, size: 6, color: scheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(u, style: text.bodyMedium?.copyWith(height: 1.6))),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_rounded),
                    title: Text(p.url, textDirection: TextDirection.ltr, textAlign: TextAlign.start, style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.copy_rounded, size: 18),
                    onTap: () => _copy(dialogContext, p.url),
                  ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('بستن'))],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12 + MediaQuery.paddingOf(context).top, 12, 24),
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Column(children: [
              // Round icon: soft glow, a thin gradient ring and a clean gap before the artwork.
              Container(
                width: 136,
                height: 136,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [scheme.primary, scheme.tertiary, scheme.secondary, scheme.primary]),
                  boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .30), blurRadius: 30, offset: const Offset(0, 10))],
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surface),
                  child: ClipOval(
                    child: Image.asset('assets/images/branding/mooncalendar_icon.png', fit: BoxFit.cover, filterQuality: FilterQuality.high),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Mooncalendar', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .3)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .7), borderRadius: BorderRadius.circular(20)),
                child: Text('نسخه ۱.۱.۳', style: text.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
              ),
              const SizedBox(height: 16),
              Text(
                'تقویم فارسی رایگان و متن‌باز، توسعه‌داده‌شده با فلاتر',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(height: 1.7),
              ),
            ]),
          ),
        ),
        _sectionTitle(context, 'امکانات برنامه'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _kFeatures)
                  Chip(
                    avatar: Icon(f.$1, size: 18, color: scheme.primary),
                    label: Text(f.$2),
                    side: BorderSide.none,
                    backgroundColor: scheme.primaryContainer.withValues(alpha: .45),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Card(
          child: ListTile(
            leading: const Icon(Icons.code_rounded),
            title: Text('کد برنامه در گیت‌هاب'),
            subtitle: Text(kAppRepoUrl, textDirection: TextDirection.ltr, textAlign: TextAlign.start, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.copy_rounded, size: 18),
            onTap: () => _copy(context, kAppRepoUrl),
          ),
        ),
        _sectionTitle(context, 'پروژه‌های استفاده‌شده'),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text('برای دیدن موارد استفاده‌شده از هر پروژه، روی آن بزنید.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < _kUsedProjects.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: scheme.primaryContainer.withValues(alpha: .7),
                  child: Icon(_kUsedProjects[i].icon, size: 20, color: scheme.onPrimaryContainer),
                ),
                title: Text(_kUsedProjects[i].name),
                subtitle: Text(_kUsedProjects[i].license, style: const TextStyle(fontSize: 12)),
                trailing: Icon(L10n.chevron),
                onTap: () => _showProject(context, _kUsedProjects[i]),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'از تمامی پروژه‌های یادشده و توسعه‌دهندگان آن‌ها سپاسگزاریم و به‌ویژه از پروژهٔ تقویم فارسی اندروید (Persian Calendar) و همهٔ توسعه‌دهندگان، مترجمان و مشارکت‌کنندگان آن تشکر و قدردانی می‌کنیم؛ بدون زحمت آن‌ها این برنامه وجود نداشت.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(height: 1.9, color: scheme.onSurfaceVariant),
          ),
        ),
        _sectionTitle(context, 'با تشکر از (ترتیب تصادفی)'),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text('برای کپی پیوند گیت‌هاب هر فرد، روی نام او بزنید.', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (user, name) in _shuffledDevelopers)
                ActionChip(
                  avatar: const Icon(Icons.person_rounded, size: 18),
                  label: PlainText(name),
                  onPressed: () => _copy(context, 'https://github.com/$user'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Card(child: ListTile(leading: const Icon(Icons.description_outlined), title: Text('مجوزها'), onTap: onLicenses)),
        Card(child: ListTile(leading: const Icon(Icons.memory_outlined), title: Text('اطلاعات دستگاه'), onTap: onDevice)),
      ],
    );
  }
}
class LicensesScreen extends StatelessWidget { const LicensesScreen({super.key}); @override Widget build(BuildContext context)=>ListView(padding:EdgeInsets.fromLTRB(16,16+MediaQuery.paddingOf(context).top,16,16),children:[Text('مجوزها',style:Theme.of(context).textTheme.headlineSmall,textDirection:TextDirection.rtl),const SizedBox(height:16),const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('این برنامه تحت مجوز GPLv3 منتشر شده و از کد و داده‌های پروژهٔ «تقویم فارسی اندروید» (github.com/persian-calendar/persian-calendar) مشتق شده است. هنگام انتشار نسخهٔ مشتق‌شده، همین مجوز و اعلان‌های حق نشر اصلی را حفظ کنید.',textAlign:TextAlign.center,textDirection:TextDirection.rtl)))]); }
class DeviceScreen extends StatelessWidget { const DeviceScreen({super.key}); @override Widget build(BuildContext context){final p=PlatformInfo.name;return ListView(padding:EdgeInsets.fromLTRB(12,12+MediaQuery.paddingOf(context).top,12,12),children:[ListTile(leading:const Icon(Icons.devices_outlined),title:const Text('سیستم‌عامل',textDirection:TextDirection.rtl),trailing:Text(p)),ListTile(leading:const Icon(Icons.monitor_outlined),title:const Text('عرض پنجره',textDirection:TextDirection.rtl),trailing:Text(MediaQuery.sizeOf(context).width.toStringAsFixed(0))),ListTile(leading:const Icon(Icons.height_outlined),title:const Text('ارتفاع پنجره',textDirection:TextDirection.rtl),trailing:Text(MediaQuery.sizeOf(context).height.toStringAsFixed(0))),const ListTile(leading:Icon(Icons.flutter_dash),title:Text('Flutter',textDirection:TextDirection.rtl),subtitle:Text('پلتفرم چندسکویی',textDirection:TextDirection.rtl))]);}}
