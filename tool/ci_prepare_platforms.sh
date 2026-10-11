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

# ---- App icon for the generated platforms (web, macOS, iOS) ---------------------------------------------
# Android and Windows keep their own icons; flutter_launcher_icons only writes the platforms listed below.
cat > flutter_launcher_icons.generated.yaml <<'YAML'
flutter_launcher_icons:
  image_path: "assets/images/branding/mooncalendar_icon.png"
  android: false
  ios: true
  remove_alpha_ios: true
  web:
    generate: true
    image_path: "assets/images/branding/mooncalendar_icon.png"
    background_color: "#4A0E1B"
    theme_color: "#4A0E1B"
  macos:
    generate: true
    image_path: "assets/images/branding/mooncalendar_icon.png"
  windows:
    generate: false
YAML
dart pub global activate flutter_launcher_icons >/dev/null
flutter pub get >/dev/null
dart pub global run flutter_launcher_icons -f flutter_launcher_icons.generated.yaml
rm -f flutter_launcher_icons.generated.yaml

# ---- Rounded corners for web, macOS and Linux (iOS and maskable icons stay square) ----------------------
python3 -m venv "${TMPDIR:-/tmp}/iconvenv"
"${TMPDIR:-/tmp}/iconvenv/bin/pip" install --quiet pillow
"${TMPDIR:-/tmp}/iconvenv/bin/python" tool/round_icons.py

# ---- Web: title and description --------------------------------------------------------------------------
if [ -f web/index.html ]; then
  sed -i.bak -e 's#<title>[^<]*</title>#<title>Mooncalendar</title>#' \
    -e 's#<meta name="description" content="[^"]*">#<meta name="description" content="Mooncalendar - Persian calendar">#' \
    -e 's#apple-mobile-web-app-title" content="[^"]*"#apple-mobile-web-app-title" content="Mooncalendar"#' web/index.html && rm -f web/index.html.bak
fi
if [ -f web/manifest.json ]; then
  sed -i.bak -e 's#"name": "[^"]*"#"name": "Mooncalendar"#' -e 's#"short_name": "[^"]*"#"short_name": "Mooncalendar"#' \
    -e 's#"description": "[^"]*"#"description": "Persian calendar"#' web/manifest.json && rm -f web/manifest.json.bak
fi

# ---- Linux: window icon (the PNG is already bundled as a Flutter asset) ----------------------------------
python3 - <<'PY'
import os
p = 'linux/runner/my_application.cc'
if os.path.exists(p):
    s = open(p).read()
    marker = 'gtk_window_set_default_size(window, 1280, 720);'
    if marker in s and 'gtk_window_set_icon_from_file' not in s:
        s = s.replace(marker, marker + """
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(exe_dir, "data", "flutter_assets", "assets", "images",
                                                   "branding", "mooncalendar_icon_round.png", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }""", 1)
        open(p, 'w').write(s)
PY

echo "platform folders ready"
