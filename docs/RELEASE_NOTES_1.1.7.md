# MoonCalendar 1.1.7

## Windows updater
- Downloads the portable Windows ZIP and displays percentage plus received and total size.
- Verifies the downloaded asset's expected size and GitHub-published SHA-256 digest before enabling installation.
- Waits for explicit confirmation before replacing application files and restarting MoonCalendar.
- Uses a separate helper process to stage and validate the Windows ZIP before the current process exits.
- Rechecks SHA-256 in the helper, rejects unsafe or duplicate ZIP paths, limits archive expansion, and verifies required Flutter runtime files.
- Confirms the updated application reaches its Windows post-startup initialization point; if that confirmation is missing, attempts to restore and relaunch the previous directory.
- Preserves Inno Setup uninstall metadata during direct replacement; the updater does not update Inno Setup's uninstall log for newly introduced files.
