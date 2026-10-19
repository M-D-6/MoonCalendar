# MoonCalendar 1.1.7

## Highlights

- Windows in-app updates use the portable ZIP payload rather than launching the Setup installer. The updater validates the download, stages files before replacing the installation, keeps a rollback copy during startup verification, and attempts recovery after an interrupted update.
- Removed the dark overlay after the final weather-forecast point. The timeline still prevents selection or scrolling beyond the last available forecast time, while the complete final-day card remains visible.
- Shortened the current-time marker's fading vertical trail by approximately 50%.
- The weather-scene animation now keeps running on Windows when its window is visible but has lost keyboard/input focus, including when the window is on another monitor. It stops when the scene is disposed or the app's views are hidden/minimized. Mobile lifecycle behavior remains conservative.
- Fixed a Windows desktop-widget startup race: the parent window now authorizes showing a child widget only after its first frame is ready and after checking current global and per-widget visibility. Widget state writes are serialized to avoid an older write overwriting a newer position/visibility update.
- Made Windows system-theme polling resilient to overlapping polls and transient platform/plugin failures.
- Removed an unnecessary timeline-wide rebuild on every horizontal scroll update; selection callbacks and scroll restoration are preserved.
- Android prayer notifications no longer use an explicit shared group key. Date notification row order, collapsed/expanded body behavior, text direction, and styling remain intact.
- Aligned application version metadata to `1.1.7+12` and fixed the two previously reported analyzer findings (an updater documentation warning and an unused weather helper).

## Upgrade notes

- First-time Windows installation and manual repair continue to use the Setup installer. In-app updates use the portable ZIP payload.
- Android's notification shade is controlled by Android and the device manufacturer. The app no longer explicitly groups prayer notifications, but it cannot guarantee that an OS/device will always render separate notification cards or status-bar icons.
- App preferences and user data remain outside the Windows application-bundle replacement process.

## Validation status

- The source archive, patch application, SHA-256 hashes, version metadata, and targeted static checks were verified in the authoring environment.
- A Flutter/Dart SDK was not available in that environment, so `flutter analyze`, `flutter test`, Android/Windows release builds, and runtime tests of multi-window races, the updater, rendering, and notifications were **not** run on this exact source package. Run those checks before publishing.
