# MoonCalendar 1.1.8

## Highlights

- Windows in-app updates start their helper reliably: it is launched from a neutral working directory (a helper that runs inside the install folder cannot rename it), through several launch methods, and refuses to run twice. The updated app confirms a healthy start, otherwise the previous version is restored automatically.
- The updater window is hidden while an update goes well. It appears only when the update failed and the previous version could not be started again; it follows the Windows theme and the app language. A successful update is reported inside the app.
- A failed download or installation offers "Try again", which reuses the downloaded file when its SHA-256 still matches. If the user does not retry, every temporary update file is deleted; after a successful update the rollback copy and helper folders are removed too.
- Update failures show a technical report (selectable and copyable) to make problems easy to diagnose.
- "Install the latest version again" in Settings downloads and installs the newest published release even when it is the version already installed.
- Memory and CPU: while the Windows window is hidden in the tray or minimized, the current page is removed from the widget tree (no painting, animation or timers), image and renderer caches are emptied and the working set is trimmed. After moving to another page, the previous page's leftovers are released a few seconds later. The astronomy screen releases its decoded images when closed.
- The About page shows the real application version (it was a fixed text). Provider and location User-Agents now use the same version constant.
- Android temperature notification: plain notification, status icon without a frame, repeated identical updates are skipped.
- Weather scene: removed falling leaves, fireflies and water glints; the river animation was halved.

## Upgrade notes

- Version 1.1.7 contains the old Windows updater, which cannot update itself reliably. Install 1.1.8 once with the Setup installer; later updates then run in-app.
- App preferences and user data remain outside the Windows application-bundle replacement process.

## Validation status

- A Flutter/Dart SDK was not available in the authoring environment, so `flutter analyze` and runtime tests were **not** run on this source package. The PowerShell helper script was parse-checked only. Run the analysis, a Windows build and the update scenarios (success, failed swap, killed helper) before publishing.
