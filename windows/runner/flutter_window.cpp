#include "flutter_window.h"

#include <optional>
#include <vector>
#include <unordered_set>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dwmapi.h>
#include <psapi.h>
#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

COLORREF ArgbToColorRef(int64_t argb) {
  const BYTE r = static_cast<BYTE>((static_cast<uint64_t>(argb) >> 16) & 0xFF);
  const BYTE g = static_cast<BYTE>((static_cast<uint64_t>(argb) >> 8) & 0xFF);
  const BYTE b = static_cast<BYTE>(static_cast<uint64_t>(argb) & 0xFF);
  return RGB(r, g, b);
}

void SetCaptionColors(HWND window, int64_t background, int64_t foreground) {
  if (!window) return;
  const COLORREF bg = ArgbToColorRef(background);
  const COLORREF fg = ArgbToColorRef(foreground);
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &bg, sizeof(bg));
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &fg, sizeof(fg));
  const BYTE r = static_cast<BYTE>((static_cast<uint64_t>(background) >> 16) & 0xFF);
  const BYTE g = static_cast<BYTE>((static_cast<uint64_t>(background) >> 8) & 0xFF);
  const BYTE b = static_cast<BYTE>(static_cast<uint64_t>(background) & 0xFF);
  const bool dark = (0.2126 * r + 0.7152 * g + 0.0722 * b) < 128.0;
  BOOL immersive_dark = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &immersive_dark, sizeof(immersive_dark));
}

// Keep native popup/context menus aligned with the Windows light/dark setting.
// This uses the Windows theme API exposed by uxtheme.dll while avoiding a hard
// link so older Windows builds can simply ignore it.
void SetNativeMenuTheme(bool dark) {
  HMODULE uxtheme = LoadLibraryW(L"uxtheme.dll");
  if (!uxtheme) return;

  using SetPreferredAppModeFn = int(WINAPI*)(int);
  using FlushMenuThemesFn = void(WINAPI*)();

  // PreferredAppMode: 0=Default, 1=AllowDark, 2=ForceDark, 3=ForceLight.
  auto set_preferred_app_mode = reinterpret_cast<SetPreferredAppModeFn>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
  auto flush_menu_themes = reinterpret_cast<FlushMenuThemesFn>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)));

  if (set_preferred_app_mode) {
    set_preferred_app_mode(dark ? 2 : 3);
  }
  if (flush_menu_themes) {
    flush_menu_themes();
  }
  FreeLibrary(uxtheme);
}

flutter::EncodableMap ReadSystemTheme() {
  DWORD argb = 0xFF00796B;
  bool have_accent = false;

  HKEY accent_key = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent",
          0, KEY_READ, &accent_key) == ERROR_SUCCESS) {
    DWORD value = 0;
    DWORD size = sizeof(value);
    DWORD type = 0;
    if (RegQueryValueExW(accent_key, L"AccentColorMenu", nullptr, &type,
                         reinterpret_cast<LPBYTE>(&value), &size) == ERROR_SUCCESS &&
        type == REG_DWORD) {
      // AccentColorMenu is stored by Windows as AABBGGRR.
      const int r = static_cast<int>(value & 0xFF);
      const int g = static_cast<int>((value >> 8) & 0xFF);
      const int b = static_cast<int>((value >> 16) & 0xFF);
      argb = (static_cast<DWORD>(0xFF) << 24) |
             (static_cast<DWORD>(r) << 16) |
             (static_cast<DWORD>(g) << 8) |
             static_cast<DWORD>(b);
      have_accent = true;
    }
    RegCloseKey(accent_key);
  }

  if (!have_accent) {
    DWORD colorization = 0;
    BOOL opaque = FALSE;
    if (SUCCEEDED(DwmGetColorizationColor(&colorization, &opaque))) {
      const int r = static_cast<int>((colorization >> 16) & 0xFF);
      const int g = static_cast<int>((colorization >> 8) & 0xFF);
      const int b = static_cast<int>(colorization & 0xFF);
      argb = (static_cast<DWORD>(0xFF) << 24) |
             (static_cast<DWORD>(r) << 16) |
             (static_cast<DWORD>(g) << 8) |
             static_cast<DWORD>(b);
    }
  }

  bool dark = false;
  HKEY key = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
          0, KEY_READ, &key) == ERROR_SUCCESS) {
    DWORD value = 1;
    DWORD size = sizeof(value);
    DWORD type = 0;
    if (RegQueryValueExW(key, L"AppsUseLightTheme", nullptr, &type,
                         reinterpret_cast<LPBYTE>(&value), &size) == ERROR_SUCCESS &&
        type == REG_DWORD) {
      dark = value == 0;
    }
    RegCloseKey(key);
  }

  return flutter::EncodableMap{
      {flutter::EncodableValue("seedColor"), flutter::EncodableValue(static_cast<int64_t>(argb))},
      {flutter::EncodableValue("dark"), flutter::EncodableValue(dark)},
  };
}

using PlatformChannel = flutter::MethodChannel<flutter::EncodableValue>;

void SetWidgetStayBehind(HWND window, bool stay_behind);

std::unique_ptr<PlatformChannel> CreatePlatformChannel(
    flutter::BinaryMessenger* messenger, HWND target_window) {
  auto channel = std::make_unique<PlatformChannel>(
      messenger, "com.md6.Mooncalendar/platform",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [target_window](const flutter::MethodCall<flutter::EncodableValue>& call,
                      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getSystemTheme") {
          result->Success(flutter::EncodableValue(ReadSystemTheme()));
        } else if (call.method_name() == "trimWorkingSet") {
          EmptyWorkingSet(GetCurrentProcess());
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "setNativeMenuTheme") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "setNativeMenuTheme expects a map");
            return;
          }
          const auto dark_it = arguments->find(flutter::EncodableValue("dark"));
          const auto* dark = dark_it == arguments->end() ? nullptr : std::get_if<bool>(&dark_it->second);
          if (dark == nullptr) {
            result->Error("invalid_arguments", "dark must be a bool");
            return;
          }
          SetNativeMenuTheme(*dark);
          result->Success();
        } else if (call.method_name() == "setTitleBarColors") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "setTitleBarColors expects a map");
            return;
          }
          const auto bg_it = arguments->find(flutter::EncodableValue("background"));
          const auto fg_it = arguments->find(flutter::EncodableValue("foreground"));
          const auto* background = bg_it == arguments->end() ? nullptr : std::get_if<int64_t>(&bg_it->second);
          const auto* foreground = fg_it == arguments->end() ? nullptr : std::get_if<int64_t>(&fg_it->second);
          if (background == nullptr || foreground == nullptr) {
            result->Error("invalid_arguments", "background and foreground are required");
            return;
          }
          SetCaptionColors(target_window, *background, *foreground);
          result->Success();
        } else if (call.method_name() == "setWidgetStayBehind") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "setWidgetStayBehind expects a map");
            return;
          }
          const auto it = arguments->find(flutter::EncodableValue("enabled"));
          const auto* enabled = it == arguments->end() ? nullptr : std::get_if<bool>(&it->second);
          if (enabled == nullptr) {
            result->Error("invalid_arguments", "enabled must be a bool");
            return;
          }
          SetWidgetStayBehind(target_window, *enabled);
          result->Success();
        } else if (call.method_name() == "dismissNativeContextMenu") {
          EndMenu();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}

std::vector<std::unique_ptr<PlatformChannel>> g_child_platform_channels;
std::unordered_set<HWND> g_stay_behind_windows;

void SetWidgetStayBehind(HWND window, bool stay_behind) {
  if (!window) return;
  if (stay_behind) {
    g_stay_behind_windows.insert(window);
    SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else {
    g_stay_behind_windows.erase(window);
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    if (flutter_view_controller != nullptr) {
      RegisterPlugins(flutter_view_controller->engine());
      HWND view = flutter_view_controller->view() ? flutter_view_controller->view()->GetNativeWindow() : nullptr;
      HWND top_level = view ? ::GetAncestor(view, GA_ROOT) : nullptr;
      if (top_level != nullptr) {
        g_child_platform_channels.push_back(
            CreatePlatformChannel(flutter_view_controller->engine()->messenger(), top_level));
      }
    }
  });

  platform_channel_ = CreatePlatformChannel(flutter_controller_->engine()->messenger(), GetHandle());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  // The Dart side owns window visibility.  In particular, desktop widgets are
  // created with hiddenAtLaunch=true and are shown only after window_manager
  // has applied their transparent/frameless configuration.  Showing every
  // engine here caused a brief white native window before the widget painted.
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  g_stay_behind_windows.erase(GetHandle());
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  const bool stay_behind = g_stay_behind_windows.find(hwnd) != g_stay_behind_windows.end();
  if (stay_behind) {
    if (message == WM_MOUSEACTIVATE) {
      SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      return MA_NOACTIVATE;
    }
    if (message == WM_WINDOWPOSCHANGING) {
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      if (pos != nullptr) {
        pos->hwndInsertAfter = HWND_BOTTOM;
        pos->flags |= SWP_NOACTIVATE;
      }
    }
    if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) {
      SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      return 0;
    }
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
