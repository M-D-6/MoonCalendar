# Windows in-app updater design

## Release assets

- `MoonCalendar-windows-x64-setup.exe` is for first-time installation and manual repair/reinstall.
- `MoonCalendar-windows-x64.zip` is the in-app update payload. It contains the contents of Flutter's Windows Release bundle at the archive root.
- In-app installation is allowed only when GitHub release metadata supplies a SHA-256 digest and the download matches it.

## Update sequence

1. Download to a `.part` file, verify length and SHA-256, then rename to the completed ZIP.
2. Start a detached PowerShell helper and close MoonCalendar. The helper waits for the original PID to exit.
3. Validate archive paths before extraction, extract to a unique sibling staging directory, and verify `mooncalendar.exe` and `flutter_windows.dll` exist at its root.
4. Before changing the installation, write recovery metadata under `%LOCALAPPDATA%\MoonCalendar\Updater` and register a per-user `RunOnce` recovery command.
5. Rename the current installation directory to a uniquely named rollback directory and promote the staged directory into the original path. Both directories are siblings, so the rename stays on the same volume.
6. Launch the updated executable. Keep the rollback directory until the new process survives a 12-second startup window. If it exits early or promotion fails, restore the previous directory and try to launch it.
7. Mark the transaction committed, remove the recovery registration, then remove the rollback copy and downloaded archive.

## Failure behavior and limits

- Interrupted/incomplete downloads never become installable ZIPs.
- An invalid checksum, unsafe archive path, or missing required bundle files aborts before the current installation is touched.
- Ordinary extraction/promotion/first-launch failures trigger rollback.
- If Windows shuts down or loses power during the directory swap, the per-user RunOnce recovery checks the transaction at the next sign-in and restores the rollback directory unless the transaction was marked committed.
- The update changes only the application directory. User settings and app data are stored separately and are not part of the ZIP replacement.
- In-app updates assume the installed folder and its parent are writable by the current user. The standard Inno Setup configuration uses a per-user install under `%LOCALAPPDATA%\Programs`; if a user manually moves the app to a protected location, update may fail safely and the release page remains the fallback.
- The first-launch check is a pragmatic crash guard, not a proof that every feature works. Keep manual Windows testing in the release process, including forced process termination and simulated restart between swap steps.

## Windows validation matrix before publishing

- Successful update from the currently installed Setup version.
- Network interruption while downloading; confirm retry works and the current app remains untouched.
- Corrupt ZIP / checksum mismatch; confirm install is refused.
- Stop the helper before the swap, between the two directory renames, after promotion, and during the startup window; verify rollback/recovery.
- Launch the new app and force it to exit during the startup window; verify the old app is restored and relaunched.
- Verify settings, scheduled notifications, tray behavior, shortcuts, and app launch after update.
