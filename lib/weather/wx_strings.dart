import 'package:flutter/widgets.dart';

import '../core/l10n/l10n.dart';

/// Weather-page words. Persian is the source language; [tr] turns it into the app language.
class AppLocalizations {
  const AppLocalizations();

  /// For the few words whose Persian spelling already means something else in the shared dictionary.
  static String _by(String fa, String en, String ar) => switch (L10n.lang) {
        AppLanguage.fa => fa,
        AppLanguage.en => en,
        AppLanguage.ar => ar,
      };

  static AppLocalizations of(BuildContext context) {
    L10n.watch(context);
    return const AppLocalizations();
  }

  String get appName => 'MDWeather';
  String get home => tr('هوا');
  String get cities => tr('شهرها');
  String get settings => tr('تنظیمات');
  String get about => tr('داده و حریم خصوصی');
  String get now => tr('اکنون');
  String get stationObservation => tr('مشاهده‌ی ایستگاه');
  String get useGps => tr('موقعیت فعلی');
  String get searchCity => tr('جست‌وجوی شهر');
  String get refresh => tr('تازه‌سازی');
  String get refreshing => tr('در حال تازه‌سازی…');
  String get offline => tr('آفلاین • آخرین داده نمایش داده می‌شود');
  String get details => tr('جزئیات');
  String get feelsLike => tr('دمای حس‌شده');
  String get humidity => tr('رطوبت');
  String get pressure => tr('فشار');
  String get wind => _by('باد', 'Wind', 'الرياح');
  String get visibility => tr('دید');
  String get uv => 'UV';
  String get airQuality => tr('کیفیت هوا');
  String get sunrise => tr('طلوع');
  String get moonPhase => tr('فاز ماه');
  String get sunset => tr('غروب');
  String get daylight => tr('طول روز');
  String get precipitation => tr('بارش');
  String get probability => tr('احتمال');
  String get high => tr('بیشینه');
  String get low => tr('کمینه');
  String get confidence => tr('اعتماد');
  String get models => tr('مدل‌ها');
  String get forecastWindow => tr('افق پیش‌بینی');
  String get theme => tr('تم');
  String get system => tr('سیستم');
  String get light => tr('روشن');
  String get dark => tr('تیره');
  String get language => tr('زبان');
  String get persian => 'فارسی';
  String get english => 'English';
  String get calendar => tr('تقویم');
  String get gregorian => tr('میلادی');
  String get jalali => tr('شمسی');
  String get both => tr('هر دو');
  String get units => tr('واحدها');
  String get animation => tr('انیمیشن');
  String get reducedMotion => tr('کاهش حرکت و مصرف باتری');
  String get haptics => tr('بازخورد لمسی');
  String get notifications => tr('اعلان‌ها');
  String get desktopWidget => tr('حالت ویجت دسکتاپ');
  String get viewScenery => tr('تماشای منظره (پنهان کردن اطلاعات)');
  String get showInfo => tr('نمایش اطلاعات');
  String get consensusLabel => tr('برآیند');
  String get lastFetch => tr('آخرین دریافت');
  String get noDataAtTime => tr('برای این زمان داده ندارد');
  String get sourceUpdated => tr('به‌روزرسانی');
  String get dataSources => tr('منابع داده');
  String get transparency => tr('شفافیت');
  String get noTracking => tr('بدون ردیابی و تبلیغات');
  String get requestsDirect => tr('درخواست‌ها مستقیم از دستگاه شما به سرویس‌ها ارسال می‌شوند.');
  String get locationLogs => tr('سرویس‌ها ممکن است IP و مختصات را در لاگ خود نگه‌داری کنند.');
  String get noMinuteRadar => tr('رادار دقیقه‌ای در این نسخه ادعا نمی‌شود.');
  String get learnedReady => tr('ساختار ثبت پیش‌بینی و مشاهده برای وزن‌دهی آینده آماده است.');
  String get sourceOpenMeteo => 'Open-Meteo';
  String get sourceMetNorway => 'MET Norway';
  String get licenseCcBy => 'CC BY 4.0';
  String get licenseMit => 'MIT';
  String get cityLimit => tr('شهر');
  String get add => tr('افزودن');
  String get remove => tr('حذف');
  String get makeCurrent => tr('شهر فعلی');
  String get noCities => tr('هنوز شهری اضافه نشده.');
  String get save => tr('ذخیره');
  String get cancel => tr('لغو');
  String get close => tr('بستن');
  String get error => tr('خطا');
  String get tryAgain => tr('تلاش دوباره');
  String get forecastUnavailable => tr('پیش‌بینی فعلاً در دسترس نیست.');
  String get selectedTime => tr('زمان انتخاب‌شده');
  String get today => tr('امروز');
  String get yesterday => tr('دیروز');
  String get sourceCount => tr('منبع');
  String consensusOf(int n) {
    final d = L10n.digits(n);
    return _by('برآیند $d منبع', 'Consensus of $d sources', 'حصيلة $d مصادر');
  }
  String get recommendationGood => tr('برای فعالیت بیرون مناسب');
  String get recommendationCaution => tr('احتیاط برای فعالیت طولانی');
  String get recommendationBad => tr('قرارگیری طولانی در بیرون را کاهش دهید');
  String get morningSummary => tr('خلاصه صبح');
  String get rainAlert => tr('شروع بارش');
  String get airAlert => tr('هوای ناسالم');
  String get compact => tr('حالت جمع‌وجور');
  String get privacy => tr('حریم خصوصی');

  String condition(String name) => switch (name) {
        'clear' => tr('صاف'),
        'partlyCloudy' => tr('نیمه‌ابری'),
        'cloudy' => tr('ابری'),
        'fog' => _by('مه', 'Fog', 'ضباب'),
        'drizzle' => tr('نم‌نم باران'),
        'rain' => tr('باران'),
        'snow' => tr('برف'),
        'thunderstorm' => tr('رعدوبرق'),
        _ => name,
      };


  // ---- date explorer
  String get goToDate => tr('برو به تاریخ');
  String get noData => tr('داده‌ای نیست');
  String get noDataForDate => tr('برای این تاریخ پیش‌بینی یا داده‌ای نداریم؛ منظره، فصل و حالت ماه را می‌بینید.');
  String get timeOfDay => tr('ساعت');
  String get goButton => tr('برو');
  String get yearLabel => tr('سال');
  String get monthLabel => _by('ماه', 'Month', 'الشهر');
  String get dayLabel => tr('روز');
  String get cancelButton => tr('انصراف');
  String seasonName(String name) => switch (name) {
        'winter' => tr('زمستان'),
        'spring' => tr('بهار'),
        'summer' => tr('تابستان'),
        _ => tr('پاییز'),
      };

  String moonPhaseName(String name) => switch (name) {
        'new' => tr('ماه نو'),
        'waxingCrescent' => tr('هلال افزایشی'),
        'firstQuarter' => tr('تربیع اول'),
        'waxingGibbous' => tr('محدب افزایشی'),
        'full' => tr('ماه کامل'),
        'waningGibbous' => tr('محدب کاهشی'),
        'lastQuarter' => tr('تربیع آخر'),
        'waningCrescent' => tr('هلال کاهشی'),
        _ => name,
      };

  String confidenceLabel(String name) => switch (name) {
        'high' => tr('بالا'),
        'medium' => tr('متوسط'),
        _ => tr('کم'),
      };
}
