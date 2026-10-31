// Retixel · host del overlay.
//
// Proceso independiente del panel Flutter. Crea una ventana layered del sistema
// (sin bordes, siempre encima, click-through) y dibuja sobre ella un sprite raw
// generado por el panel. No inyecta nada en ningun juego: es una ventana mas de
// Windows compuesta por el escritorio.
//
// Uso:
//   retixel_overlay.exe --config <ruta overlay.ini>
//   retixel_overlay.exe --list-monitors <ruta salida.txt>

#define _WIN32_WINNT 0x0A00
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN

#include <windows.h>

#include <shellapi.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kClassName[] = L"RetixelOverlayWindow";
constexpr wchar_t kMutexName[] = L"Local\\RetixelOverlaySingleInstance";
constexpr UINT_PTR kTimerPoll = 1;   // ADS + visibilidad
constexpr UINT_PTR kTimerWatch = 2;  // config + proceso padre + monitor
constexpr int kHotkeyId = 1;
constexpr int kMaxSpriteSide = 1024;

struct Sprite {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> rgba;  // recto, no premultiplicado

  bool valid() const {
    return width > 0 && height > 0 && width <= kMaxSpriteSide &&
           height <= kMaxSpriteSide &&
           rgba.size() == static_cast<size_t>(width) * height * 4;
  }
};

struct MonitorDesc {
  RECT rect{};
  bool primary = false;
};

struct Config {
  int monitor = 0;
  int offset_x = 0;
  int offset_y = 0;
  double opacity = 1.0;
  std::wstring hotkey = L"F8";
  bool hide_on_ads = true;
  DWORD parent_pid = 0;
  std::wstring sprite = L"crosshair.bin";
  ULONGLONG stamp = 0;
};

struct App {
  HWND hwnd = nullptr;
  HDC mem_dc = nullptr;
  HBITMAP bitmap = nullptr;
  HGDIOBJ old_bitmap = nullptr;
  void* bits = nullptr;
  int canvas_w = 0;
  int canvas_h = 0;

  Sprite sprite;
  Config cfg;
  std::wstring config_path;
  std::wstring base_dir;

  bool visible = true;
  bool manual_hidden = false;
  bool hotkey_ok = false;
  bool hotkey_registered = false;
  bool sprite_ok = false;
  HANDLE parent = nullptr;
  bool parent_checked = false;
};

App g_app;

// ---------------------------------------------------------------- utilidades

std::wstring ExeDir() {
  wchar_t buffer[MAX_PATH * 2] = {};
  DWORD len = GetModuleFileNameW(nullptr, buffer, MAX_PATH * 2);
  std::wstring path(buffer, len);
  size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

std::wstring Join(const std::wstring& dir, const std::wstring& name) {
  if (name.empty()) return dir;
  if (name.size() > 1 && (name[1] == L':' || name[0] == L'\\')) return name;
  if (!dir.empty() && (dir.back() == L'\\' || dir.back() == L'/')) return dir + name;
  return dir + L"\\" + name;
}

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr, 0, nullptr,
                                 nullptr);
  if (size <= 1) return {};
  std::string out(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring ToWide(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, out.data(), size);
  return out;
}

std::wstring Trim(std::wstring value) {
  const wchar_t* space = L" \t\r\n";
  size_t first = value.find_first_not_of(space);
  if (first == std::wstring::npos) return {};
  size_t last = value.find_last_not_of(space);
  return value.substr(first, last - first + 1);
}

std::string Trim(const std::string& value) {
  const char* space = " \t\r\n";
  size_t first = value.find_first_not_of(space);
  if (first == std::string::npos) return {};
  size_t last = value.find_last_not_of(space);
  return value.substr(first, last - first + 1);
}

void Log(const std::string& message) {
  std::wstring path = Join(g_app.base_dir, L"overlay.log");
  std::ofstream out(path, std::ios::app | std::ios::binary);
  if (!out) return;
  SYSTEMTIME now{};
  GetLocalTime(&now);
  char stamp[32] = {};
  std::snprintf(stamp, sizeof(stamp), "%02d:%02d:%02d ", now.wHour, now.wMinute,
                now.wSecond);
  out << stamp << message << "\r\n";
}

// Keep overlay.log small: it is a diagnostic tail, not a journal.
void TrimLog() {
  std::wstring path = Join(g_app.base_dir, L"overlay.log");
  WIN32_FILE_ATTRIBUTE_DATA data{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return;
  const ULONGLONG size = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32) |
                         data.nFileSizeLow;
  if (size < 256 * 1024) return;
  DeleteFileW(path.c_str());
}

ULONGLONG FileStamp(const std::wstring& path) {
  WIN32_FILE_ATTRIBUTE_DATA data{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return 0;
  return (static_cast<ULONGLONG>(data.ftLastWriteTime.dwHighDateTime) << 32) |
         data.ftLastWriteTime.dwLowDateTime;
}

// ------------------------------------------------------------------- config

Config LoadConfig(const std::wstring& path) {
  Config cfg;
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    Log("config: no se pudo abrir overlay.ini");
    return cfg;
  }
  std::stringstream buffer;
  buffer << in.rdbuf();
  std::string text = buffer.str();
  if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
      static_cast<unsigned char>(text[1]) == 0xBB &&
      static_cast<unsigned char>(text[2]) == 0xBF) {
    text.erase(0, 3);
  }

  std::map<std::string, std::string> values;
  std::istringstream lines(text);
  std::string line;
  while (std::getline(lines, line)) {
    line = Trim(line);
    if (line.empty() || line[0] == '#' || line[0] == ';') continue;
    size_t eq = line.find('=');
    if (eq == std::string::npos) continue;
    std::string key = Trim(line.substr(0, eq));
    std::string value = Trim(line.substr(eq + 1));
    values[key] = value;
  }

  auto get_int = [&](const char* key, int fallback) {
    auto it = values.find(key);
    if (it == values.end()) return fallback;
    try {
      return std::stoi(it->second);
    } catch (...) {
      return fallback;
    }
  };
  auto get_double = [&](const char* key, double fallback) {
    auto it = values.find(key);
    if (it == values.end()) return fallback;
    try {
      return std::stod(it->second);
    } catch (...) {
      return fallback;
    }
  };

  cfg.monitor = std::max(0, get_int("monitor", 0));
  cfg.offset_x = get_int("offset_x", 0);
  cfg.offset_y = get_int("offset_y", 0);
  cfg.opacity = std::clamp(get_double("opacity", 1.0), 0.05, 1.0);
  cfg.hide_on_ads = get_int("hide_on_ads", 1) != 0;
  cfg.parent_pid = static_cast<DWORD>(std::max(0, get_int("parent_pid", 0)));

  if (auto it = values.find("hotkey"); it != values.end()) cfg.hotkey = ToWide(it->second);
  if (auto it = values.find("sprite"); it != values.end()) cfg.sprite = ToWide(it->second);
  cfg.stamp = FileStamp(path);
  return cfg;
}

bool ParseHotkey(const std::wstring& text, UINT* modifiers, UINT* key) {
  std::wstring value = text;
  std::transform(value.begin(), value.end(), value.begin(), towlower);

  UINT mods = 0;
  std::wstring token;
  std::wstringstream stream(value);
  std::vector<std::wstring> parts;
  while (std::getline(stream, token, L'+')) {
    token = Trim(token);
    if (!token.empty()) parts.push_back(token);
  }
  if (parts.empty()) return false;

  auto parse_key = [](const std::wstring& part, UINT* out) {
    static const std::map<std::wstring, UINT> named = {
        {L"f1", VK_F1},   {L"f2", VK_F2},   {L"f3", VK_F3},   {L"f4", VK_F4},
        {L"f5", VK_F5},   {L"f6", VK_F6},   {L"f7", VK_F7},   {L"f8", VK_F8},
        {L"f9", VK_F9},   {L"f10", VK_F10}, {L"f11", VK_F11}, {L"f12", VK_F12},
        {L"insert", VK_INSERT}, {L"home", VK_HOME}, {L"end", VK_END},
        {L"pageup", VK_PRIOR},  {L"pagedown", VK_NEXT},
        {L"pause", VK_PAUSE},   {L"scrolllock", VK_SCROLL},
        {L"num0", VK_NUMPAD0},  {L"num1", VK_NUMPAD1}, {L"num2", VK_NUMPAD2},
        {L"num3", VK_NUMPAD3},  {L"num4", VK_NUMPAD4}, {L"num5", VK_NUMPAD5},
        {L"num6", VK_NUMPAD6},  {L"num7", VK_NUMPAD7}, {L"num8", VK_NUMPAD8},
        {L"num9", VK_NUMPAD9},
    };
    auto it = named.find(part);
    if (it != named.end()) {
      *out = it->second;
      return true;
    }
    if (part.size() == 1) {
      SHORT scan = VkKeyScanW(static_cast<wchar_t>(part[0]));
      if (scan != -1) {
        *out = static_cast<UINT>(scan & 0xFF);
        return true;
      }
    }
    return false;
  };

  for (const auto& part : parts) {
    if (part == L"ctrl" || part == L"control") {
      mods |= MOD_CONTROL;
    } else if (part == L"alt") {
      mods |= MOD_ALT;
    } else if (part == L"shift") {
      mods |= MOD_SHIFT;
    } else if (part == L"win" || part == L"super") {
      mods |= MOD_WIN;
    } else if (!parse_key(part, key)) {
      return false;
    }
  }

  *modifiers = mods;
  return *key != 0;
}

// ----------------------------------------------------------------- monitors

BOOL CALLBACK CollectMonitor(HMONITOR handle, HDC, LPRECT, LPARAM data) {
  auto* list = reinterpret_cast<std::vector<MonitorDesc>*>(data);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(handle, &info)) return TRUE;
  MonitorDesc desc;
  desc.rect = info.rcMonitor;
  desc.primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  list->push_back(desc);
  return TRUE;
}

std::vector<MonitorDesc> EnumMonitors() {
  std::vector<MonitorDesc> list;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor, reinterpret_cast<LPARAM>(&list));
  std::stable_sort(list.begin(), list.end(), [](const MonitorDesc& a, const MonitorDesc& b) {
    if (a.primary != b.primary) return a.primary;
    if (a.rect.top != b.rect.top) return a.rect.top < b.rect.top;
    return a.rect.left < b.rect.left;
  });
  return list;
}

// ------------------------------------------------------------------- sprite

void LoadSprite() {
  g_app.sprite = Sprite{};
  g_app.sprite_ok = false;

  std::wstring path = Join(g_app.base_dir, g_app.cfg.sprite);
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    Log("sprite: no existe " + ToUtf8(path));
    return;
  }
  std::stringstream buffer;
  buffer << in.rdbuf();
  const std::string data = buffer.str();
  if (data.size() < 12 || data.compare(0, 4, "CXSP") != 0) {
    Log("sprite: cabecera invalida");
    return;
  }
  const auto* raw = reinterpret_cast<const unsigned char*>(data.data());
  uint32_t width = 0;
  uint32_t height = 0;
  std::memcpy(&width, raw + 4, 4);
  std::memcpy(&height, raw + 8, 4);
  if (width == 0 || height == 0 || width > kMaxSpriteSide || height > kMaxSpriteSide) {
    Log("sprite: dimensiones fuera de rango");
    return;
  }
  const size_t expected = 12 + static_cast<size_t>(width) * height * 4;
  if (data.size() < expected) {
    Log("sprite: datos incompletos");
    return;
  }

  g_app.sprite.width = static_cast<int>(width);
  g_app.sprite.height = static_cast<int>(height);
  g_app.sprite.rgba.assign(raw + 12, raw + expected);
  g_app.sprite_ok = true;
}

// ------------------------------------------------------------------ canvas

bool EnsureCanvas(int width, int height) {
  if (g_app.canvas_w == width && g_app.canvas_h == height && g_app.mem_dc != nullptr) {
    return true;
  }
  if (g_app.bitmap != nullptr) {
    if (g_app.mem_dc != nullptr) SelectObject(g_app.mem_dc, g_app.old_bitmap);
    DeleteObject(g_app.bitmap);
    g_app.bitmap = nullptr;
    g_app.bits = nullptr;
  }
  if (g_app.mem_dc == nullptr) g_app.mem_dc = CreateCompatibleDC(nullptr);
  if (g_app.mem_dc == nullptr) return false;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;  // top-down
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  g_app.bitmap = CreateDIBSection(g_app.mem_dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (g_app.bitmap == nullptr || bits == nullptr) {
    Log("canvas: CreateDIBSection fallo");
    return false;
  }
  g_app.bits = bits;
  g_app.old_bitmap = SelectObject(g_app.mem_dc, g_app.bitmap);
  g_app.canvas_w = width;
  g_app.canvas_h = height;
  return true;
}

void ComposeAndUpload(const RECT& monitor) {
  const int width = monitor.right - monitor.left;
  const int height = monitor.bottom - monitor.top;
  if (width <= 0 || height <= 0) return;
  if (!EnsureCanvas(width, height)) return;

  auto* pixels = static_cast<uint32_t*>(g_app.bits);
  std::fill(pixels, pixels + static_cast<size_t>(width) * height, 0u);
  if (!g_app.sprite_ok) return;

  // Offsets are configured in logical pixels; the monitor may be scaled.
  UINT dpi = 96;
  if (g_app.hwnd != nullptr) {
    dpi = GetDpiForWindow(g_app.hwnd);
    if (dpi == 0) dpi = 96;
  }
  const double scale = static_cast<double>(dpi) / 96.0;

  const int sprite_w = g_app.sprite.width;
  const int sprite_h = g_app.sprite.height;
  const int origin_x =
      (width - sprite_w) / 2 + static_cast<int>(g_app.cfg.offset_x * scale);
  const int origin_y =
      (height - sprite_h) / 2 + static_cast<int>(g_app.cfg.offset_y * scale);
  const double opacity = g_app.cfg.opacity;

  for (int y = 0; y < sprite_h; ++y) {
    const int dy = origin_y + y;
    if (dy < 0 || dy >= height) continue;
    const uint8_t* src = g_app.sprite.rgba.data() + static_cast<size_t>(y) * sprite_w * 4;
    uint32_t* dst = pixels + static_cast<size_t>(dy) * width;
    for (int x = 0; x < sprite_w; ++x) {
      const int dx = origin_x + x;
      if (dx < 0 || dx >= width) continue;
      const uint8_t* p = src + static_cast<size_t>(x) * 4;
      uint32_t alpha = p[3];
      if (alpha == 0) continue;
      alpha = static_cast<uint32_t>(alpha * opacity + 0.5);
      if (alpha == 0) continue;
      const uint8_t r = static_cast<uint8_t>((p[0] * alpha + 127) / 255);
      const uint8_t g = static_cast<uint8_t>((p[1] * alpha + 127) / 255);
      const uint8_t b = static_cast<uint8_t>((p[2] * alpha + 127) / 255);
      dst[dx] = (alpha << 24) | (static_cast<uint32_t>(r) << 16) |
                (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
    }
  }

  HDC screen = GetDC(nullptr);
  POINT destination{monitor.left, monitor.top};
  SIZE size{width, height};
  POINT source{0, 0};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 255;
  blend.AlphaFormat = AC_SRC_ALPHA;
  UpdateLayeredWindow(g_app.hwnd, screen, &destination, &size, g_app.mem_dc, &source, 0,
                      &blend, ULW_ALPHA);
  ReleaseDC(nullptr, screen);
}

RECT CurrentMonitorRect() {
  std::vector<MonitorDesc> monitors = EnumMonitors();
  if (monitors.empty()) {
    RECT fallback{0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    return fallback;
  }
  int index = g_app.cfg.monitor;
  if (index < 0 || index >= static_cast<int>(monitors.size())) index = 0;
  return monitors[static_cast<size_t>(index)].rect;
}

void ApplyLayout() {
  RECT monitor = CurrentMonitorRect();
  SetWindowPos(g_app.hwnd, HWND_TOPMOST, monitor.left, monitor.top,
               monitor.right - monitor.left, monitor.bottom - monitor.top,
               SWP_NOACTIVATE | (g_app.visible ? SWP_SHOWWINDOW : 0));
  ComposeAndUpload(monitor);
}

void SetVisible(bool visible) {
  if (g_app.visible == visible) return;
  g_app.visible = visible;
  ShowWindow(g_app.hwnd, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
}

void UpdateVisibility() {
  bool show = true;
  if (g_app.manual_hidden) {
    show = false;
  } else if (g_app.cfg.hide_on_ads) {
    // Right mouse button pressed counts as aiming down sights. Games that
    // bind ADS to another key can simply disable this option.
    const bool right_down = (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
    if (right_down) show = false;
  }
  SetVisible(show);
}

// ------------------------------------------------------------------- hotkey

void UnregisterHotkey() {
  if (g_app.hotkey_registered) {
    UnregisterHotKey(g_app.hwnd, kHotkeyId);
    g_app.hotkey_registered = false;
  }
}

void RegisterConfiguredHotkey() {
  UnregisterHotkey();
  g_app.hotkey_ok = false;
  UINT modifiers = 0;
  UINT key = 0;
  if (!ParseHotkey(g_app.cfg.hotkey, &modifiers, &key)) {
    Log("hotkey: formato invalido '" + ToUtf8(g_app.cfg.hotkey) + "'");
    return;
  }
  if (!RegisterHotKey(g_app.hwnd, kHotkeyId, modifiers | MOD_NOREPEAT, key)) {
    Log("hotkey: FAILED '" + ToUtf8(g_app.cfg.hotkey) + "' (ocupado por otro programa)");
    return;
  }
  g_app.hotkey_registered = true;
  g_app.hotkey_ok = true;
  Log("hotkey: ok '" + ToUtf8(g_app.cfg.hotkey) + "'");
}

// ------------------------------------------------------------------- carga

void ReloadConfig() {
  Config next = LoadConfig(g_app.config_path);
  g_app.cfg = next;
  LoadSprite();
  RegisterConfiguredHotkey();
  ApplyLayout();
  Log("config: recargada (monitor=" + std::to_string(next.monitor) +
      " sprite=" + std::to_string(g_app.sprite.width) + "x" +
      std::to_string(g_app.sprite.height) + ")");
}

bool ParentAlive() {
  if (g_app.cfg.parent_pid == 0) return true;
  if (g_app.parent == nullptr) {
    g_app.parent = OpenProcess(SYNCHRONIZE, FALSE, g_app.cfg.parent_pid);
    if (g_app.parent == nullptr) return false;
  }
  return WaitForSingleObject(g_app.parent, 0) != WAIT_OBJECT_0;
}

// ------------------------------------------------------------------ window

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_HOTKEY:
      if (wparam == kHotkeyId) {
        g_app.manual_hidden = !g_app.manual_hidden;
        UpdateVisibility();
      }
      return 0;
    case WM_TIMER:
      if (wparam == kTimerPoll) {
        UpdateVisibility();
      } else if (wparam == kTimerWatch) {
        static ULONGLONG last_config = 0;
        static ULONGLONG last_parent = 0;
        const ULONGLONG now = GetTickCount64();
        if (now - last_config > 300) {
          last_config = now;
          const ULONGLONG stamp = FileStamp(g_app.config_path);
          if (stamp != 0 && stamp != g_app.cfg.stamp) ReloadConfig();
        }
        if (now - last_parent > 1000) {
          last_parent = now;
          if (!ParentAlive()) {
            Log("padre cerrado: saliendo");
            PostMessageW(hwnd, WM_CLOSE, 0, 0);
          }
        }
      }
      return 0;
    case WM_DISPLAYCHANGE:
      ApplyLayout();
      return 0;
    case WM_CLOSE:
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
    default:
      return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

void EnableDpiAwareness() {
  using SetContextFn = BOOL(WINAPI*)(void*);
  auto user32 = GetModuleHandleW(L"user32.dll");
  if (user32 != nullptr) {
    auto set_context =
        reinterpret_cast<SetContextFn>(GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
    if (set_context != nullptr && set_context(reinterpret_cast<void*>(-4))) return;
  }
  SetProcessDPIAware();
}

int ListMonitors(const std::wstring& output_path) {
  std::ofstream out(output_path, std::ios::binary | std::ios::trunc);
  if (!out) return 1;
  std::vector<MonitorDesc> monitors = EnumMonitors();
  for (size_t i = 0; i < monitors.size(); ++i) {
    const RECT& r = monitors[i].rect;
    out << i << ";" << r.left << ";" << r.top << ";" << (r.right - r.left) << ";"
        << (r.bottom - r.top) << ";" << (monitors[i].primary ? 1 : 0) << "\n";
  }
  return 0;
}

int Run(const std::wstring& config_path) {
  g_app.config_path = config_path;
  size_t slash = config_path.find_last_of(L"\\/");
  g_app.base_dir = slash == std::wstring::npos ? ExeDir() : config_path.substr(0, slash);

  EnableDpiAwareness();
  TrimLog();

  HANDLE mutex = CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex == nullptr || GetLastError() == ERROR_ALREADY_EXISTS) {
    Log("instancia duplicada: saliendo");
    return 0;
  }

  g_app.cfg = LoadConfig(config_path);
  LoadSprite();

  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = nullptr;
  if (RegisterClassExW(&wc) == 0) {
    Log("RegisterClassEx fallo");
    return 1;
  }

  RECT monitor = CurrentMonitorRect();
  g_app.hwnd = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          WS_EX_TOPMOST,
      kClassName, L"Retixel Overlay", WS_POPUP, monitor.left, monitor.top,
      monitor.right - monitor.left, monitor.bottom - monitor.top, nullptr, nullptr,
      wc.hInstance, nullptr);
  if (g_app.hwnd == nullptr) {
    Log("CreateWindowEx fallo");
    return 1;
  }

  RegisterConfiguredHotkey();
  ApplyLayout();
  ShowWindow(g_app.hwnd, SW_SHOWNOACTIVATE);
  SetTimer(g_app.hwnd, kTimerPoll, 30, nullptr);
  SetTimer(g_app.hwnd, kTimerWatch, 250, nullptr);
  Log("overlay: iniciado en monitor rect " + std::to_string(monitor.left) + "," +
      std::to_string(monitor.top) + " " +
      std::to_string(monitor.right - monitor.left) + "x" +
      std::to_string(monitor.bottom - monitor.top));

  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  KillTimer(g_app.hwnd, kTimerPoll);
  KillTimer(g_app.hwnd, kTimerWatch);
  UnregisterHotkey();
  if (g_app.parent != nullptr) CloseHandle(g_app.parent);
  if (g_app.bitmap != nullptr) {
    SelectObject(g_app.mem_dc, g_app.old_bitmap);
    DeleteObject(g_app.bitmap);
  }
  if (g_app.mem_dc != nullptr) DeleteDC(g_app.mem_dc);
  ReleaseMutex(mutex);
  CloseHandle(mutex);
  return 0;
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::wstring config;
  std::wstring monitors_out;

  for (int i = 1; argv != nullptr && i < argc; ++i) {
    std::wstring arg = argv[i];
    if (arg == L"--config" && i + 1 < argc) {
      config = argv[++i];
    } else if (arg == L"--list-monitors" && i + 1 < argc) {
      monitors_out = argv[++i];
    }
  }
  if (argv != nullptr) LocalFree(argv);

  if (!monitors_out.empty()) {
    EnableDpiAwareness();
    return ListMonitors(monitors_out);
  }
  if (config.empty()) {
    MessageBoxW(nullptr, L"Falta --config <overlay.ini>", L"Retixel",
                MB_OK | MB_ICONERROR);
    return 2;
  }
  return Run(config);
}
