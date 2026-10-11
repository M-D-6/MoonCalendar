#!/usr/bin/env bash
# Generates the platform folders that are not kept in the repository (linux, macos, ios, web; windows/android
# stay as they are - `flutter create` only fills in missing files) and patches the few things the app needs:
# network access + location permission on macOS / iOS.
set -euo pipefail

flutter create --project-name mooncalendar --org com.md6 \
  --platforms=android,windows,linux,macos,ios,web . >/dev/null

# ---- macOS: the App Sandbox must allow network (http / map tiles) and location --------------------------
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  [ -f "$f" ] || continue
  for key in com.apple.security.network.client com.apple.security.personal-information.location; do
    if ! grep -q "$key" "$f"; then
      sed -i.bak "s#</dict>#\t<key>$key</key>\n\t<true/>\n</dict>#" "$f" && rm -f "$f.bak"
    fi
  done
done

# ---- macOS / iOS: location usage description ------------------------------------------------------------
add_plist_string() { # file key value
  local file="$1" key="$2" value="$3"
  [ -f "$file" ] || return 0
  grep -q "$key" "$file" && return 0
  sed -i.bak "s#</dict>#\t<key>$key</key>\n\t<string>$value</string>\n</dict>#" "$file" && rm -f "$file.bak"
}
MSG="Used to compute prayer times and sun/moon positions for your location."
add_plist_string macos/Runner/Info.plist NSLocationUsageDescription "$MSG"
add_plist_string macos/Runner/Info.plist NSLocationWhenInUseUsageDescription "$MSG"
add_plist_string ios/Runner/Info.plist NSLocationWhenInUseUsageDescription "$MSG"

echo "platform folders ready"
