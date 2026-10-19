# MoonCalendar 1.1.7

## Improvements
- Add a temporary Windows update window showing the current installation stage and the result.
- Close and relaunch MoonCalendar around the installer operation, and attempt to relaunch the existing application if the update fails.
- Keep application version metadata aligned at `1.1.7+12`.

## Notes
- The progress indicator is indeterminate; it does not represent a verified percentage from the installer.
- Validate the update flow on Windows with both a same-version reinstall and an upgrade before publishing.
- The source package was checked for archive integrity and version-string consistency, but Windows/Android builds and runtime tests were not run in the source-preparation environment.
