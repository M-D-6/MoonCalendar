<div align="center">

<img src="docs/readme_icon.png" width="128" alt="Mooncalendar"/>

# Mooncalendar · مون‌کلندر

**A free, open-source Persian (Solar Hijri) calendar, built with Flutter**
**تقویم فارسی رایگان و متن‌باز، توسعه‌داده‌شده با فلاتر**

> **English —** Mooncalendar brings the Solar Hijri, Gregorian and Islamic calendars together with events and holidays, prayer times, astronomy, a world map, a date converter, a tally counter and widgets, in Persian, English and Arabic.
>
> **فارسی —** مون‌کلندر تقویم‌های شمسی، میلادی و قمری را همراه با مناسبت‌ها و تعطیلات، اوقات شرعی، ستاره‌شناسی، نقشهٔ جهان، تبدیل تاریخ، شمارنده و ویجت، به سه زبان فارسی، انگلیسی و عربی در اختیار شما می‌گذارد.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)
[![Languages](https://img.shields.io/badge/languages-فارسی%20·%20English%20·%20العربية-success)](#)

[Source code · کد برنامه](https://github.com/M-D-6/MoonCalendar) ·
[Web version · نسخهٔ وب](https://m-d-6.github.io/MoonCalendar/) ·
[Persian Calendar · تقویم فارسی](https://github.com/persian-calendar/persian-calendar)

</div>

---

## 🧩 Projects used · پروژه‌های استفاده‌شده

| Project · پروژه | License · مجوز | Used for · مورد استفاده |
|---|---|---|
| [Android Persian Calendar](https://github.com/persian-calendar/persian-calendar) | GPLv3 | Calendar logic, events data, prayer times, astronomy and map data, city lists, widget / notification / screen design ideas, season images (Lotta Nieminen, CC BY-NC 4.0) |
| [Flutter & Dart](https://flutter.dev) | BSD-3-Clause | Framework and UI |
| [Vazirmatn](https://github.com/rastikerdar/vazirmatn) | OFL 1.1 | Main font, day number in the notification icon |
| [Noto Sans Symbols](https://fonts.google.com/noto/specimen/Noto+Sans+Symbols) | OFL 1.1 | Zodiac symbols |
| [Material Design Icons](https://github.com/google/material-design-icons) | Apache 2.0 | UI icons |
| [PrayTimes](https://praytimes.org) | LGPLv3 | Prayer-time calculation (ported) |
| [Calendar converter](https://code.google.com/p/mobile-persian-calendar/) (Amir Khosroshahi) | GPLv2+ | Date conversion algorithms |
| [StarCal](https://github.com/ilius/starcal) | AGPLv3 | Events and holidays data |
| [Level](https://github.com/avianey/Level) | GPLv3 | Bubble level |
| [Natural Earth](https://www.naturalearthdata.com) | Public domain | World map and time zones |
| [Tectonic plates](https://github.com/fraxen/tectonicplates) (fraxen) | ODC-By 1.0 | Tectonic plate boundaries |
| Borna Tasvir Resaneh | as in the original project | Athan sound and animation |
| Dart / Flutter packages (`astronomia`, `geolocator`, `window_manager`, `tray_manager`, `desktop_multi_window`, `share_plus`, `shared_preferences`, `timezone`, `qr`, `http`, …) | various | Astronomy, location, windowing, sharing, storage |

**English —** We thank all of the projects listed above and their developers, and we especially wish to express our gratitude to the [Android Persian Calendar](https://github.com/persian-calendar/persian-calendar) project and all of its developers, translators and contributors; without their work this app would not exist.

**فارسی —** از تمامی پروژه‌های یادشده و توسعه‌دهندگان آن‌ها سپاسگزاریم و به‌ویژه از پروژهٔ [تقویم فارسی اندروید (Persian Calendar)](https://github.com/persian-calendar/persian-calendar) و همهٔ توسعه‌دهندگان، مترجمان و مشارکت‌کنندگان آن تشکر و قدردانی می‌کنیم؛ بدون زحمت آن‌ها این برنامه وجود نداشت.

---

## ✨ Features · امکانات

| | English | فارسی |
|---|---|---|
| 📅 | Solar Hijri, Gregorian and Islamic calendars, with a date converter | تقویم شمسی، میلادی و قمری و تبدیل تاریخ |
| 🎉 | Official holidays and events | مناسبت‌ها و تعطیلات رسمی |
| 🕌 | Prayer times (Athan), qibla compass | اوقات شرعی، اذان و قبله‌نما |
| 🌙 | Astronomy: moon phase, zodiac, planets, sun view | ستاره‌شناسی: فاز ماه، برج‌ها، سیارات و مسیر خورشید |
| 🗺️ | World map with day / night | نقشهٔ جهان با شب و روز |
| 🧮 | Tally counter, level tool | شمارنده و تراز |
| 🧩 | Home-screen and desktop widgets | ویجت صفحهٔ اصلی و دسکتاپ |
| 🔔 | Persistent date notification with a day-number icon | اعلان همیشگی تاریخ با آیکون عدد روز |
| 🎨 | Many themes, custom colour, liquid-glass UI | تم‌های متنوع، رنگ دلخواه و ظاهر شیشه‌ای |
| 🌍 | Persian, English and Arabic — RTL / LTR, instantly switchable | فارسی، انگلیسی و عربی با تغییر آنی زبان |

## ⚙️ Requirements · پیش‌نیازها

- Flutter 3.x (Dart 3.9+)
- Android: Android Studio / SDK, min SDK 23
- Windows: Visual Studio 2022 with *Desktop development with C++*, Developer Mode enabled

## 🚀 Build · ساخت

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run -d <device>

flutter build apk --release --split-per-abi   # one smaller APK per CPU architecture
flutter build windows --release
# installer (Inno Setup 6): iscc windows/installer/Mooncalendar.iss
```

---

## 🛠️ Notes · نکات

- The launcher icon can show the current day number (Settings). Icons live in
  `android/app/src/main/res`; the day-number font is `android/app/src/main/assets/fonts/day_icon_font.ttf`.
- Windows tray / day icons are in `assets/day_icons`.
- The Windows installer installs per user (no administrator rights, `%LocalAppData%\Programs`).
- Windows installers are not code-signed, so SmartScreen may warn on first run (*More info → Run anyway*).
- Translations: Flutter side in `lib/core/l10n`, Android widgets in `android/app/src/main/assets/tr_*.tsv`.

## 📄 License · مجوز

Released under the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE).
Because it is derived from the GPLv3 [Persian Calendar](https://github.com/persian-calendar/persian-calendar)
project, derivative works must keep the same license and keep the original copyright notices.
Third-party licenses and attributions are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

برنامه تحت **GPLv3** منتشر شده است؛ چون از پروژهٔ GPLv3 «تقویم فارسی» مشتق شده، آثار مشتق باید همین مجوز و اعلان‌های حق نشر اصلی را حفظ کنند.
