#include "include/appflowy_linux_webview/appflowy_linux_webview_plugin.h"

#include <dlfcn.h>
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <type_traits>
#include <vector>

// A WebKitGTK view drawn into a Flutter texture.
//
// Flutter has no platform views on Linux, so the web view lives in a
// GtkOffscreenWindow: each repaint is copied into an FlPixelBufferTexture and
// Flutter forwards pointer input over the method channel. While a view has
// Flutter's focus, key presses reaching the application window go to it
// instead. Because the texture is an ordinary Flutter widget, Flutter's menus
// and dialogs draw above it.
//
// WebKitGTK is opened with dlopen rather than linked, so AppFlowy builds
// without its development headers and still starts where it is missing. WebKit
// objects are therefore handled through opaque pointers.

namespace {

// Values from the stable WebKitGTK API: WebKitUserContentInjectedFrames,
// WebKitUserScriptInjectionTime, WebKitPolicyDecisionType and
// WebKitHardwareAccelerationPolicy.
constexpr int kInjectAllFrames = 0;
constexpr int kInjectAtDocumentStart = 0;
constexpr int kNewWindowAction = 1;
constexpr int kHardwareAccelerationAlways = 1;
constexpr int kHardwareAccelerationNever = 2;

// WebKit composites on the GPU and passes each frame to this process as a GL
// texture, which an offscreen window cannot draw, unless frames come in
// shared memory instead. WebKit reads this once, when its first view starts.
constexpr char kSharedMemoryFrames[] = "WEBKIT_DMABUF_RENDERER_FORCE_SHM";

// Whether frames will arrive in shared memory, so GPU rendering is safe.
bool PrepareSharedMemoryFrames() {
  static const bool shared = [] {
    const gchar* value = g_getenv(kSharedMemoryFrames);
    if (value == nullptr) {
      return g_setenv(kSharedMemoryFrames, "1", FALSE) != FALSE;
    }
    return g_strcmp0(value, "0") != 0;
  }();
  return shared;
}

// Copies a frame right after GDK has finished painting the offscreen window:
// every damage event of that paint is in, and nothing waits on a timer.
constexpr gint kCapturePriority = GDK_PRIORITY_REDRAW + 10;

constexpr GdkRGBA kTransparent = {0, 0, 0, 0};

constexpr char kMessageHandler[] = "appflowyLinuxWebView";

// Pages post strings to this handler for Dart; see
// LinuxWebViewController.messages.
constexpr char kPageMessageHandler[] = "appflowyLinuxWebViewMessage";

// Reports the CSS cursor under the pointer, which Flutter then shows: the
// view is only a picture, so nothing else would change the cursor.
constexpr char kCursorScript[] = R"JS((() => {
  const handler = window.webkit?.messageHandlers?.appflowyLinuxWebView;
  if (!handler || window.__appflowyLinuxWebViewCursor) {
    return;
  }
  window.__appflowyLinuxWebViewCursor = true;
  const textInput =
    /^(?:text|search|email|url|tel|password|number|date|datetime-local|month|time|week)$/i;
  const report = (event) => {
    const target = event.target;
    if (!(target instanceof Element)) {
      return;
    }
    let cursor = getComputedStyle(target).cursor || 'auto';
    // Image cursors end with the keyword to fall back on.
    cursor = cursor.split(',').pop().trim();
    if (cursor === 'auto') {
      if (target.isContentEditable || target.tagName === 'TEXTAREA' ||
          (target.tagName === 'INPUT' && textInput.test(target.type))) {
        cursor = 'text';
      } else {
        cursor = target.closest('a[href]') ? 'pointer' : 'default';
      }
    }
    handler.postMessage(cursor);
  };
  addEventListener('mousemove', report, { capture: true, passive: true });
  addEventListener('mouseover', report, { capture: true, passive: true });
})();)JS";

struct WebKitApi {
  GType (*web_view_get_type)();
  void (*web_view_load_uri)(gpointer view, const gchar* uri);
  void (*web_view_reload)(gpointer view);
  // WebKitGTK 2.40 replaced run_javascript with evaluate_javascript, so each
  // is optional; one of them is enough.
  void (*web_view_evaluate_javascript)(gpointer view,
                                       const gchar* script,
                                       gssize length,
                                       const gchar* world_name,
                                       const gchar* source_uri,
                                       GCancellable* cancellable,
                                       GAsyncReadyCallback callback,
                                       gpointer user_data);
  void (*web_view_run_javascript)(gpointer view,
                                  const gchar* script,
                                  GCancellable* cancellable,
                                  GAsyncReadyCallback callback,
                                  gpointer user_data);
  guint (*get_major_version)();
  guint (*get_minor_version)();
  void (*web_view_terminate_web_process)(gpointer view);
  void (*web_view_set_background_color)(gpointer view, const GdkRGBA* rgba);
  gpointer (*web_view_get_settings)(gpointer view);
  void (*settings_set_javascript_can_access_clipboard)(gpointer settings,
                                                       gboolean enabled);
  void (*settings_set_enable_developer_extras)(gpointer settings,
                                               gboolean enabled);
  void (*settings_set_enable_write_console_messages_to_stdout)(
      gpointer settings,
      gboolean enabled);
  void (*settings_set_hardware_acceleration_policy)(gpointer settings,
                                                    int policy);
  gpointer (*user_content_manager_new)();
  void (*user_content_manager_add_script)(gpointer manager, gpointer script);
  void (*user_content_manager_remove_all_scripts)(gpointer manager);
  gboolean (*user_content_manager_register_script_message_handler)(
      gpointer manager,
      const gchar* name);
  gpointer (*user_script_new)(const gchar* source,
                              int injected_frames,
                              int injection_time,
                              const gchar* const* allow_list,
                              const gchar* const* block_list);
  void (*user_script_unref)(gpointer script);
  gpointer (*javascript_result_get_js_value)(gpointer result);
  gchar* (*jsc_value_to_string)(gpointer value);
  gpointer (*navigation_policy_decision_get_navigation_action)(
      gpointer decision);
  gpointer (*navigation_action_get_request)(gpointer action);
  const gchar* (*uri_request_get_uri)(gpointer request);
  void (*policy_decision_ignore)(gpointer decision);
  gboolean (*file_chooser_request_get_select_multiple)(gpointer request);
  GtkFileFilter* (*file_chooser_request_get_mime_types_filter)(
      gpointer request);
  void (*file_chooser_request_select_files)(gpointer request,
                                            const gchar* const* files);
  void (*file_chooser_request_cancel)(gpointer request);
  void (*option_menu_close)(gpointer menu);
};

bool IsLoaded(const char* library) {
  void* handle = dlopen(library, RTLD_LAZY | RTLD_NOLOAD);
  if (handle == nullptr) {
    return false;
  }
  dlclose(handle);
  return true;
}

const WebKitApi* LoadWebKit() {
  static bool attempted = false;
  static bool available = false;
  static WebKitApi api = {};
  if (attempted) {
    return available ? &api : nullptr;
  }
  attempted = true;

  // libsoup aborts a process that loads both of its major versions, and the
  // two WebKitGTK API versions each bring their own.
  struct Candidate {
    const char* library;
    const char* conflicting_soup;
  };
  const Candidate candidates[] = {
      {"libwebkit2gtk-4.1.so.0", "libsoup-2.4.so.1"},
      {"libwebkit2gtk-4.0.so.37", "libsoup-3.0.so.0"},
  };
  void* handle = nullptr;
  for (const Candidate& candidate : candidates) {
    if (IsLoaded(candidate.conflicting_soup)) {
      continue;
    }
    handle = dlopen(candidate.library, RTLD_NOW | RTLD_LOCAL);
    if (handle != nullptr) {
      break;
    }
  }
  if (handle == nullptr) {
    g_message("AppFlowy web view: WebKitGTK is not available.");
    return nullptr;
  }

  bool missing = false;
  auto resolve = [&](auto& function, const char* symbol) {
    void* address = dlsym(handle, symbol);
    if (address == nullptr) {
      g_warning("AppFlowy web view: WebKitGTK lacks %s.", symbol);
      missing = true;
    }
    function = reinterpret_cast<std::remove_reference_t<decltype(function)>>(
        address);
  };
  resolve(api.web_view_get_type, "webkit_web_view_get_type");
  resolve(api.web_view_load_uri, "webkit_web_view_load_uri");
  resolve(api.web_view_reload, "webkit_web_view_reload");
  resolve(api.web_view_get_settings, "webkit_web_view_get_settings");
  resolve(api.settings_set_javascript_can_access_clipboard,
          "webkit_settings_set_javascript_can_access_clipboard");
  resolve(api.settings_set_enable_developer_extras,
          "webkit_settings_set_enable_developer_extras");
  resolve(api.settings_set_enable_write_console_messages_to_stdout,
          "webkit_settings_set_enable_write_console_messages_to_stdout");
  resolve(api.settings_set_hardware_acceleration_policy,
          "webkit_settings_set_hardware_acceleration_policy");
  resolve(api.user_content_manager_new, "webkit_user_content_manager_new");
  resolve(api.user_content_manager_add_script,
          "webkit_user_content_manager_add_script");
  resolve(api.user_content_manager_remove_all_scripts,
          "webkit_user_content_manager_remove_all_scripts");
  resolve(api.user_content_manager_register_script_message_handler,
          "webkit_user_content_manager_register_script_message_handler");
  resolve(api.user_script_new, "webkit_user_script_new");
  resolve(api.user_script_unref, "webkit_user_script_unref");
  resolve(api.javascript_result_get_js_value,
          "webkit_javascript_result_get_js_value");
  resolve(api.jsc_value_to_string, "jsc_value_to_string");
  resolve(api.navigation_policy_decision_get_navigation_action,
          "webkit_navigation_policy_decision_get_navigation_action");
  resolve(api.navigation_action_get_request,
          "webkit_navigation_action_get_request");
  resolve(api.uri_request_get_uri, "webkit_uri_request_get_uri");
  resolve(api.policy_decision_ignore, "webkit_policy_decision_ignore");
  resolve(api.file_chooser_request_get_select_multiple,
          "webkit_file_chooser_request_get_select_multiple");
  resolve(api.file_chooser_request_get_mime_types_filter,
          "webkit_file_chooser_request_get_mime_types_filter");
  resolve(api.file_chooser_request_select_files,
          "webkit_file_chooser_request_select_files");
  resolve(api.file_chooser_request_cancel,
          "webkit_file_chooser_request_cancel");
  resolve(api.option_menu_close, "webkit_option_menu_close");
  if (missing) {
    dlclose(handle);
    return nullptr;
  }
  api.web_view_evaluate_javascript =
      reinterpret_cast<decltype(api.web_view_evaluate_javascript)>(
          dlsym(handle, "webkit_web_view_evaluate_javascript"));
  api.web_view_run_javascript =
      reinterpret_cast<decltype(api.web_view_run_javascript)>(
          dlsym(handle, "webkit_web_view_run_javascript"));
  api.get_major_version = reinterpret_cast<decltype(api.get_major_version)>(
      dlsym(handle, "webkit_get_major_version"));
  api.get_minor_version = reinterpret_cast<decltype(api.get_minor_version)>(
      dlsym(handle, "webkit_get_minor_version"));
  api.web_view_terminate_web_process =
      reinterpret_cast<decltype(api.web_view_terminate_web_process)>(
          dlsym(handle, "webkit_web_view_terminate_web_process"));
  api.web_view_set_background_color =
      reinterpret_cast<decltype(api.web_view_set_background_color)>(
          dlsym(handle, "webkit_web_view_set_background_color"));
  available = true;
  return &api;
}

// One published picture of a view, in the RGBA layout Flutter uploads: each
// element holds a pixel's four bytes in memory order.
struct Frame {
  Frame() = default;
  Frame(const Frame&) = delete;
  Frame& operator=(const Frame&) = delete;
  ~Frame() {
    if (stale != nullptr) {
      cairo_region_destroy(stale);
    }
  }

  std::vector<uint32_t> pixels;
  uint32_t width = 0;
  uint32_t height = 0;
  // Once replaced, what the view has repainted since, in logical pixels.
  cairo_region_t* stale = nullptr;
};

std::shared_ptr<Frame> BlankFrame() {
  auto frame = std::make_shared<Frame>();
  frame->width = 1;
  frame->height = 1;
  frame->pixels.assign(1, 0);
  return frame;
}

}  // namespace

// ---------------------------------------------------------------------------
// Texture

G_DECLARE_FINAL_TYPE(WebViewTexture,
                     webview_texture,
                     APPFLOWY,
                     WEBVIEW_TEXTURE,
                     FlPixelBufferTexture)

struct _WebViewTexture {
  FlPixelBufferTexture parent_instance;
  // Published frames never change: the raster thread keeps the one it was
  // handed while the main thread prepares the next.
  std::mutex* mutex;
  std::shared_ptr<Frame>* current;
  std::shared_ptr<Frame>* lent;
};

G_DEFINE_TYPE(WebViewTexture,
              webview_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean webview_texture_copy_pixels(FlPixelBufferTexture* texture,
                                            const uint8_t** out_buffer,
                                            uint32_t* width,
                                            uint32_t* height,
                                            GError**) {
  WebViewTexture* self = APPFLOWY_WEBVIEW_TEXTURE(texture);
  std::lock_guard<std::mutex> lock(*self->mutex);
  *self->lent = *self->current;
  *out_buffer = reinterpret_cast<const uint8_t*>((*self->lent)->pixels.data());
  *width = (*self->lent)->width;
  *height = (*self->lent)->height;
  return TRUE;
}

static void webview_texture_finalize(GObject* object) {
  WebViewTexture* self = APPFLOWY_WEBVIEW_TEXTURE(object);
  delete self->lent;
  delete self->current;
  delete self->mutex;
  G_OBJECT_CLASS(webview_texture_parent_class)->finalize(object);
}

static void webview_texture_class_init(WebViewTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      webview_texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = webview_texture_finalize;
}

static void webview_texture_init(WebViewTexture* self) {
  self->mutex = new std::mutex();
  self->current = new std::shared_ptr<Frame>(BlankFrame());
  self->lent = new std::shared_ptr<Frame>();
}

static std::shared_ptr<Frame> webview_texture_latest(WebViewTexture* self) {
  std::lock_guard<std::mutex> lock(*self->mutex);
  return *self->current;
}

static void webview_texture_publish(WebViewTexture* self,
                                    std::shared_ptr<Frame> frame) {
  std::lock_guard<std::mutex> lock(*self->mutex);
  *self->current = std::move(frame);
}

// ---------------------------------------------------------------------------
// Plugin

struct WebView;

struct _AppflowyLinuxWebviewPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  FlTextureRegistrar* textures;
  FlView* flutter_view;
  // The application window, whose key presses go to a focused web view.
  GtkWidget* toplevel;
  std::map<std::string, WebView*>* views;
  WebView* focused;
};

typedef struct _AppflowyLinuxWebviewPlugin AppflowyLinuxWebviewPlugin;
typedef struct {
  GObjectClass parent_class;
} AppflowyLinuxWebviewPluginClass;

G_DEFINE_TYPE(AppflowyLinuxWebviewPlugin,
              appflowy_linux_webview_plugin,
              g_object_get_type())

#define APPFLOWY_LINUX_WEBVIEW_PLUGIN(obj)                        \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                              \
                              appflowy_linux_webview_plugin_get_type(), \
                              AppflowyLinuxWebviewPlugin))

struct WebView {
  AppflowyLinuxWebviewPlugin* plugin = nullptr;
  std::string id;
  std::string origin;
  GtkWidget* offscreen = nullptr;
  GtkWidget* view = nullptr;
  gpointer content_manager = nullptr;
  WebViewTexture* texture = nullptr;
  int width = 0;
  int height = 0;
  int scale = 1;
  // Where the view sits in the Flutter view, for native coordinates.
  double x = 0;
  double y = 0;
  // Area repainted since the last copy, in logical pixels.
  cairo_region_t* damage = nullptr;
  // Replaced frames to draw the next ones into, once Flutter is done with
  // them; each knows what it has missed.
  std::vector<std::shared_ptr<Frame>> spare;
  guint capture_source = 0;
  bool active = true;
  // Set once the web process has been ended outright; see EndWebProcess.
  bool ended = false;
  std::string cursor;
};

namespace {

FlMethodResponse* Success(FlValue* value = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

FlMethodResponse* Failure(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

FlValue* Lookup(FlValue* args, const char* key, FlValueType type) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == type ? value
                                                              : nullptr;
}

const gchar* StringArg(FlValue* args, const char* key) {
  FlValue* value = Lookup(args, key, FL_VALUE_TYPE_STRING);
  return value != nullptr ? fl_value_get_string(value) : nullptr;
}

int64_t IntArg(FlValue* args, const char* key, int64_t fallback) {
  FlValue* value = Lookup(args, key, FL_VALUE_TYPE_INT);
  return value != nullptr ? fl_value_get_int(value) : fallback;
}

double DoubleArg(FlValue* args, const char* key, double fallback) {
  FlValue* value = Lookup(args, key, FL_VALUE_TYPE_FLOAT);
  if (value != nullptr) {
    return fl_value_get_float(value);
  }
  FlValue* integer = Lookup(args, key, FL_VALUE_TYPE_INT);
  return integer != nullptr ? static_cast<double>(fl_value_get_int(integer))
                            : fallback;
}

bool BoolArg(FlValue* args, const char* key, bool fallback) {
  FlValue* value = Lookup(args, key, FL_VALUE_TYPE_BOOL);
  return value != nullptr ? fl_value_get_bool(value) : fallback;
}

int SizeArg(FlValue* args, const char* key, int fallback) {
  const int64_t size = IntArg(args, key, fallback);
  return static_cast<int>(std::min<int64_t>(std::max<int64_t>(size, 1), 16384));
}

WebView* FindView(AppflowyLinuxWebviewPlugin* self, const gchar* id) {
  if (id == nullptr || self->views == nullptr) {
    return nullptr;
  }
  auto found = self->views->find(id);
  return found != self->views->end() ? found->second : nullptr;
}

GdkSeat* DefaultSeat() {
  return gdk_display_get_default_seat(gdk_display_get_default());
}

// WebKitGTK scales a mouse's smooth scroll by a step that depends on the
// view's size, but takes any other device's deltas as exact pixels, 40 to
// the step. Pixel-exact scrolls therefore come from this touchpad-like
// device, a private instance of the backend's own device type.
GdkDevice* PreciseScrollDevice(GdkSeat* seat) {
  static GdkDevice* device = nullptr;
  GdkDevice* pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;
  if (device == nullptr && pointer != nullptr) {
    device = GDK_DEVICE(g_object_new(
        G_OBJECT_TYPE(pointer), "name", "AppFlowy web view scrolling", "type",
        GDK_DEVICE_TYPE_SLAVE, "input-source", GDK_SOURCE_TOUCHPAD,
        "input-mode", GDK_MODE_SCREEN, "has-cursor", FALSE, "display",
        gdk_seat_get_display(seat), "seat", seat, nullptr));
  }
  return device;
}

// Focus goes to the web view alone: telling the offscreen toplevel makes GTK
// query the pointer on a window with no native counterpart, which X11
// answers with a fatal BadWindow.
void SendFocus(WebView* view, bool in) {
  GdkWindow* window = gtk_widget_get_window(view->view);
  if (window == nullptr) {
    return;
  }
  if (in) {
    gtk_widget_grab_focus(view->view);
  }
  GdkEvent* event = gdk_event_new(GDK_FOCUS_CHANGE);
  event->focus_change.window = GDK_WINDOW(g_object_ref(window));
  event->focus_change.send_event = TRUE;
  event->focus_change.in = in;
  GdkSeat* seat = DefaultSeat();
  if (seat != nullptr && gdk_seat_get_keyboard(seat) != nullptr) {
    gdk_event_set_device(event, gdk_seat_get_keyboard(seat));
  }
  gtk_widget_send_focus_change(view->view, event);
  gdk_event_free(event);
}

void SetFocused(AppflowyLinuxWebviewPlugin* self, WebView* view, bool focused) {
  if (focused) {
    if (self->focused == view) {
      return;
    }
    if (self->focused != nullptr) {
      SendFocus(self->focused, false);
    }
    self->focused = view;
    // An inactive window passes the focus on when it is activated again.
    if (self->toplevel == nullptr ||
        gtk_window_is_active(GTK_WINDOW(self->toplevel))) {
      SendFocus(view, true);
    }
  } else if (self->focused == view) {
    self->focused = nullptr;
    SendFocus(view, false);
  }
}

// Cairo keeps native-endian premultiplied ARGB; Flutter takes RGBA bytes.
inline uint32_t ToRgba(uint32_t argb) {
#if G_BYTE_ORDER == G_LITTLE_ENDIAN
  return (argb & 0xff00ff00u) | ((argb >> 16) & 0xffu) | ((argb & 0xffu) << 16);
#else
  return (argb << 8) | (argb >> 24);
#endif
}

// Copies a rectangle of device pixels out of an ARGB32 image.
void CopyPixels(const uint8_t* data,
                int stride,
                const cairo_rectangle_int_t& rect,
                Frame* frame) {
  for (int y = rect.y; y < rect.y + rect.height; ++y) {
    const uint8_t* in = data + static_cast<size_t>(y) * stride +
                        static_cast<size_t>(rect.x) * 4;
    uint32_t* out =
        frame->pixels.data() + static_cast<size_t>(y) * frame->width + rect.x;
    for (int x = 0; x < rect.width; ++x) {
      uint32_t argb;
      std::memcpy(&argb, in + static_cast<size_t>(x) * 4, sizeof(argb));
      out[x] = ToRgba(argb);
    }
  }
}

// Frames Flutter may still be uploading, beyond the current one, that are
// kept to be drawn into again.
constexpr size_t kSpareFrames = 2;

gboolean CaptureFrame(gpointer user_data) {
  auto* view = static_cast<WebView*>(user_data);
  view->capture_source = 0;
  GdkWindow* window = gtk_widget_get_window(view->offscreen);
  cairo_surface_t* source =
      gtk_offscreen_window_get_surface(GTK_OFFSCREEN_WINDOW(view->offscreen));
  if (window == nullptr || source == nullptr) {
    return G_SOURCE_REMOVE;
  }
  double scale_x = 1;
  double scale_y = 1;
  cairo_surface_get_device_scale(source, &scale_x, &scale_y);
  const int scale = std::max(1, static_cast<int>(std::lround(scale_x)));
  const int logical_width = std::max(1, gdk_window_get_width(window));
  const int logical_height = std::max(1, gdk_window_get_height(window));
  const auto width = static_cast<uint32_t>(logical_width * scale);
  const auto height = static_cast<uint32_t>(logical_height * scale);
  const cairo_rectangle_int_t all = {0, 0, logical_width, logical_height};

  // What changed since the last capture; everything when that is unknown.
  cairo_region_t* damage = view->damage != nullptr
                               ? view->damage
                               : cairo_region_create_rectangle(&all);
  view->damage = nullptr;

  // Spare frames miss this change too. One Flutter has let go of needs only
  // what it missed redrawn; a new one needs everything.
  std::shared_ptr<Frame> frame;
  for (auto it = view->spare.begin(); it != view->spare.end();) {
    if ((*it)->width != width || (*it)->height != height) {
      it = view->spare.erase(it);
      continue;
    }
    cairo_region_union((*it)->stale, damage);
    if (frame == nullptr && it->use_count() == 1) {
      frame = std::move(*it);
      it = view->spare.erase(it);
    } else {
      ++it;
    }
  }
  cairo_region_t* area;
  if (frame != nullptr) {
    area = frame->stale;
    frame->stale = nullptr;
  } else {
    frame = std::make_shared<Frame>();
    frame->width = width;
    frame->height = height;
    frame->pixels.resize(static_cast<size_t>(width) * height);
    area = cairo_region_create_rectangle(&all);
  }
  cairo_region_intersect_rectangle(area, &all);

  // The offscreen window draws into an image surface (see OnCreateSurface),
  // which is read directly; anything else is copied into one first.
  cairo_surface_t* image = source;
  cairo_surface_t* scratch = nullptr;
  if (cairo_surface_get_type(source) != CAIRO_SURFACE_TYPE_IMAGE ||
      cairo_image_surface_get_format(source) != CAIRO_FORMAT_ARGB32) {
    scratch = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
                                         static_cast<int>(width),
                                         static_cast<int>(height));
    cairo_surface_set_device_scale(scratch, scale, scale);
    cairo_t* cr = cairo_create(scratch);
    gdk_cairo_region(cr, area);
    cairo_clip(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_surface(cr, source, 0, 0);
    cairo_paint(cr);
    cairo_destroy(cr);
    image = scratch;
  }
  cairo_surface_flush(image);
  const uint8_t* data = cairo_image_surface_get_data(image);
  const int stride = cairo_image_surface_get_stride(image);
  const int image_width =
      std::min(static_cast<int>(width), cairo_image_surface_get_width(image));
  const int image_height = std::min(static_cast<int>(height),
                                    cairo_image_surface_get_height(image));
  const int rectangles = cairo_region_num_rectangles(area);
  for (int i = 0; data != nullptr && i < rectangles; ++i) {
    cairo_rectangle_int_t rect;
    cairo_region_get_rectangle(area, i, &rect);
    const int x0 = std::min(std::max(rect.x * scale, 0), image_width);
    const int y0 = std::min(std::max(rect.y * scale, 0), image_height);
    const int x1 =
        std::min(std::max((rect.x + rect.width) * scale, 0), image_width);
    const int y1 =
        std::min(std::max((rect.y + rect.height) * scale, 0), image_height);
    if (x1 > x0 && y1 > y0) {
      CopyPixels(data, stride, {x0, y0, x1 - x0, y1 - y0}, frame.get());
    }
  }
  if (scratch != nullptr) {
    cairo_surface_destroy(scratch);
  }
  cairo_region_destroy(area);

  std::shared_ptr<Frame> previous = webview_texture_latest(view->texture);
  webview_texture_publish(view->texture, frame);
  // The frame just replaced lacks this change.
  if (previous != frame && previous->width == width &&
      previous->height == height) {
    previous->stale = damage;
    damage = nullptr;
    view->spare.push_back(std::move(previous));
    if (view->spare.size() > kSpareFrames) {
      view->spare.erase(view->spare.begin());
    }
  }
  if (damage != nullptr) {
    cairo_region_destroy(damage);
  }
  fl_texture_registrar_mark_texture_frame_available(
      view->plugin->textures, FL_TEXTURE(view->texture));
  return G_SOURCE_REMOVE;
}

void ScheduleCapture(WebView* view) {
  if (view->capture_source == 0 && view->active) {
    view->capture_source =
        g_idle_add_full(kCapturePriority, CaptureFrame, view, nullptr);
  }
}

gboolean OnDamage(GtkWidget*, GdkEvent* event, gpointer user_data) {
  auto* view = static_cast<WebView*>(user_data);
  if (view->damage == nullptr) {
    view->damage = cairo_region_create();
  }
  const GdkRectangle& area = event->expose.area;
  cairo_rectangle_int_t rect = {area.x, area.y, area.width, area.height};
  cairo_region_union_rectangle(view->damage, &rect);
  ScheduleCapture(view);
  return FALSE;
}

// An image surface keeps every copy in memory; the default would mirror the
// application window, which on X11 means a server round trip per frame.
cairo_surface_t* OnCreateSurface(GdkWindow* window,
                                 gint width,
                                 gint height,
                                 gpointer) {
  const int scale = std::max(1, gdk_window_get_scale_factor(window));
  cairo_surface_t* surface = cairo_image_surface_create(
      CAIRO_FORMAT_ARGB32, std::max(1, width) * scale,
      std::max(1, height) * scale);
  cairo_surface_set_device_scale(surface, scale, scale);
  return surface;
}

// Where the Flutter view starts inside the application window.
void FlutterViewOrigin(AppflowyLinuxWebviewPlugin* self, int* x, int* y) {
  *x = 0;
  *y = 0;
  if (self->flutter_view != nullptr && self->toplevel != nullptr) {
    gtk_widget_translate_coordinates(GTK_WIDGET(self->flutter_view),
                                     self->toplevel, 0, 0, x, y);
  }
}

// Native coordinates (input methods, root positions) go through the
// embedder: the application window, at the texture's place in it.
void OnToEmbedder(GdkWindow*,
                  gdouble offscreen_x,
                  gdouble offscreen_y,
                  gpointer embedder_x,
                  gpointer embedder_y,
                  gpointer user_data) {
  auto* view = static_cast<WebView*>(user_data);
  int origin_x;
  int origin_y;
  FlutterViewOrigin(view->plugin, &origin_x, &origin_y);
  *static_cast<gdouble*>(embedder_x) = offscreen_x + view->x + origin_x;
  *static_cast<gdouble*>(embedder_y) = offscreen_y + view->y + origin_y;
}

void OnFromEmbedder(GdkWindow*,
                    gdouble embedder_x,
                    gdouble embedder_y,
                    gpointer offscreen_x,
                    gpointer offscreen_y,
                    gpointer user_data) {
  auto* view = static_cast<WebView*>(user_data);
  int origin_x;
  int origin_y;
  FlutterViewOrigin(view->plugin, &origin_x, &origin_y);
  *static_cast<gdouble*>(offscreen_x) = embedder_x - view->x - origin_x;
  *static_cast<gdouble*>(offscreen_y) = embedder_y - view->y - origin_y;
}

gboolean OnDecidePolicy(GtkWidget*,
                        gpointer decision,
                        int decision_type,
                        gpointer user_data) {
  if (decision_type != kNewWindowAction) {
    return FALSE;
  }
  const WebKitApi* api = LoadWebKit();
  auto* view = static_cast<WebView*>(user_data);
  gpointer action =
      api->navigation_policy_decision_get_navigation_action(decision);
  gpointer request =
      action != nullptr ? api->navigation_action_get_request(action) : nullptr;
  const gchar* uri =
      request != nullptr ? api->uri_request_get_uri(request) : nullptr;
  // Links in a document open in the browser; the page never needs a window
  // of its own.
  if (uri != nullptr && !g_str_has_prefix(uri, view->origin.c_str()) &&
      (g_str_has_prefix(uri, "https://") || g_str_has_prefix(uri, "http://") ||
       g_str_has_prefix(uri, "mailto:"))) {
    g_autoptr(GError) error = nullptr;
    if (!g_app_info_launch_default_for_uri(uri, nullptr, &error)) {
      g_warning("AppFlowy web view: cannot open %s: %s", uri,
                error != nullptr ? error->message : "unknown error");
    }
  }
  api->policy_decision_ignore(decision);
  return TRUE;
}

void OnWebProcessTerminated(GtkWidget* web_view, int, gpointer) {
  g_warning("AppFlowy web view: the web process stopped; reloading.");
  LoadWebKit()->web_view_reload(web_view);
}

// A view's web process is its own (its data is ephemeral) and, once the view
// is going, has nothing left to save. Ending it outright skips the shutdown
// WebKit would run instead, which crashes in some GPU drivers (NVIDIA's EGL,
// from WebKit's GPU worker threads).
void EndWebProcess(WebView* view) {
  const WebKitApi* api = LoadWebKit();
  if (view->ended || api == nullptr ||
      api->web_view_terminate_web_process == nullptr) {
    return;
  }
  view->ended = true;
  // Not a crash to recover from.
  g_signal_handlers_disconnect_by_func(
      view->view, reinterpret_cast<gpointer>(OnWebProcessTerminated), view);
  api->web_view_terminate_web_process(view->view);
}

// Native menus and tooltips would be parented to the offscreen window, which
// Wayland cannot place; the page draws its own.
gboolean OnContextMenu(GtkWidget*, gpointer, GdkEvent*, gpointer, gpointer) {
  return TRUE;
}

gboolean OnQueryTooltip(GtkWidget* widget,
                        gint,
                        gint,
                        gboolean,
                        GtkTooltip*,
                        gpointer) {
  g_signal_stop_emission_by_name(widget, "query-tooltip");
  return FALSE;
}

gboolean OnShowOptionMenu(GtkWidget*,
                          gpointer menu,
                          GdkEvent*,
                          GdkRectangle*,
                          gpointer) {
  g_idle_add_full(
      G_PRIORITY_DEFAULT_IDLE,
      [](gpointer data) -> gboolean {
        LoadWebKit()->option_menu_close(data);
        return G_SOURCE_REMOVE;
      },
      g_object_ref(menu), g_object_unref);
  return TRUE;
}

void OnFileChooserResponse(GtkNativeDialog* dialog, gint response, gpointer) {
  const WebKitApi* api = LoadWebKit();
  gpointer request = g_object_get_data(G_OBJECT(dialog), "request");
  if (response == GTK_RESPONSE_ACCEPT) {
    GSList* names = gtk_file_chooser_get_filenames(GTK_FILE_CHOOSER(dialog));
    std::vector<const gchar*> files;
    for (GSList* item = names; item != nullptr; item = item->next) {
      files.push_back(static_cast<const gchar*>(item->data));
    }
    files.push_back(nullptr);
    api->file_chooser_request_select_files(request, files.data());
    g_slist_free_full(names, g_free);
  } else {
    api->file_chooser_request_cancel(request);
  }
  g_object_unref(dialog);
}

// WebKit drops an offscreen parent, so its own chooser would float free of
// AppFlowy.
gboolean OnRunFileChooser(GtkWidget*, gpointer request, gpointer user_data) {
  const WebKitApi* api = LoadWebKit();
  auto* view = static_cast<WebView*>(user_data);
  const bool multiple = api->file_chooser_request_get_select_multiple(request);
  GtkWindow* parent = view->plugin->toplevel != nullptr
                          ? GTK_WINDOW(view->plugin->toplevel)
                          : nullptr;
  GtkFileChooserNative* dialog = gtk_file_chooser_native_new(
      multiple ? "Select Files" : "Select File", parent,
      GTK_FILE_CHOOSER_ACTION_OPEN, nullptr, nullptr);
  gtk_native_dialog_set_modal(GTK_NATIVE_DIALOG(dialog), TRUE);
  gtk_file_chooser_set_select_multiple(GTK_FILE_CHOOSER(dialog), multiple);
  GtkFileFilter* filter =
      api->file_chooser_request_get_mime_types_filter(request);
  if (filter != nullptr) {
    gtk_file_chooser_set_filter(GTK_FILE_CHOOSER(dialog), filter);
  }
  g_object_set_data_full(G_OBJECT(dialog), "request", g_object_ref(request),
                         g_object_unref);
  g_signal_connect(dialog, "response", G_CALLBACK(OnFileChooserResponse),
                   nullptr);
  gtk_native_dialog_show(GTK_NATIVE_DIALOG(dialog));
  return TRUE;
}

void OnScriptMessage(gpointer, gpointer result, gpointer user_data) {
  const WebKitApi* api = LoadWebKit();
  auto* view = static_cast<WebView*>(user_data);
  gpointer value = api->javascript_result_get_js_value(result);
  g_autofree gchar* cursor =
      value != nullptr ? api->jsc_value_to_string(value) : nullptr;
  if (cursor == nullptr || view->cursor == cursor) {
    return;
  }
  view->cursor = cursor;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(view->id.c_str()));
  fl_value_set_string_take(args, "cursor", fl_value_new_string(cursor));
  fl_method_channel_invoke_method(view->plugin->channel, "cursor", args,
                                  nullptr, nullptr, nullptr);
}

void OnPageMessage(gpointer, gpointer result, gpointer user_data) {
  const WebKitApi* api = LoadWebKit();
  auto* view = static_cast<WebView*>(user_data);
  gpointer value = api->javascript_result_get_js_value(result);
  g_autofree gchar* message =
      value != nullptr ? api->jsc_value_to_string(value) : nullptr;
  if (message == nullptr) {
    return;
  }
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(view->id.c_str()));
  fl_value_set_string_take(args, "message", fl_value_new_string(message));
  fl_method_channel_invoke_method(view->plugin->channel, "message", args,
                                  nullptr, nullptr, nullptr);
}

gboolean OnKey(GtkWidget*, GdkEventKey* event, gpointer user_data) {
  auto* self = static_cast<AppflowyLinuxWebviewPlugin*>(user_data);
  WebView* view = self->focused;
  GdkWindow* window =
      view != nullptr ? gtk_widget_get_window(view->view) : nullptr;
  if (window == nullptr) {
    return FALSE;
  }
  GdkEvent* copy = gdk_event_copy(reinterpret_cast<GdkEvent*>(event));
  g_clear_object(&copy->key.window);
  copy->key.window = GDK_WINDOW(g_object_ref(window));
  gtk_main_do_event(copy);
  gdk_event_free(copy);
  // Releases reach Flutter as well, so a key it saw pressed is never left
  // down; it ignores releases of keys it did not see.
  return event->type == GDK_KEY_PRESS;
}

// The caret follows the application window's focus.
gboolean OnToplevelFocus(GtkWidget*, GdkEventFocus* event, gpointer user_data) {
  auto* self = static_cast<AppflowyLinuxWebviewPlugin*>(user_data);
  if (self->focused != nullptr) {
    SendFocus(self->focused, event->in);
  }
  return FALSE;
}

// The application is quitting: ends every view's web process; see
// EndWebProcess. Handles both the window's destroy and the application's
// shutdown, whichever comes first.
void OnQuit(gpointer, gpointer user_data) {
  auto* self = static_cast<AppflowyLinuxWebviewPlugin*>(user_data);
  if (self->views == nullptr) {
    return;
  }
  for (auto& entry : *self->views) {
    EndWebProcess(entry.second);
  }
}

void EnsureToplevel(AppflowyLinuxWebviewPlugin* self) {
  if (self->toplevel != nullptr || self->flutter_view == nullptr) {
    return;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(self->flutter_view));
  if (!GTK_IS_WINDOW(toplevel)) {
    return;
  }
  self->toplevel = toplevel;
  const auto flags = static_cast<GConnectFlags>(0);
  g_signal_connect_object(toplevel, "key-press-event", G_CALLBACK(OnKey), self,
                          flags);
  g_signal_connect_object(toplevel, "key-release-event", G_CALLBACK(OnKey),
                          self, flags);
  g_signal_connect_object(toplevel, "focus-in-event",
                          G_CALLBACK(OnToplevelFocus), self, flags);
  g_signal_connect_object(toplevel, "focus-out-event",
                          G_CALLBACK(OnToplevelFocus), self, flags);
  // Quitting with views open: their web processes would otherwise shut
  // themselves down once this process is gone.
  g_signal_connect_object(toplevel, "destroy", G_CALLBACK(OnQuit), self, flags);
  GtkApplication* application = gtk_window_get_application(GTK_WINDOW(toplevel));
  if (application != nullptr) {
    g_signal_connect_object(application, "shutdown", G_CALLBACK(OnQuit), self,
                            flags);
  }
}

void AddUserScripts(gpointer manager, FlValue* sources) {
  const WebKitApi* api = LoadWebKit();
  auto add = [&](const gchar* source) {
    gpointer script = api->user_script_new(source, kInjectAllFrames,
                                           kInjectAtDocumentStart, nullptr,
                                           nullptr);
    api->user_content_manager_add_script(manager, script);
    api->user_script_unref(script);
  };
  add(kCursorScript);
  for (size_t i = 0; sources != nullptr && i < fl_value_get_length(sources);
       ++i) {
    FlValue* source = fl_value_get_list_value(sources, i);
    if (fl_value_get_type(source) == FL_VALUE_TYPE_STRING) {
      add(fl_value_get_string(source));
    }
  }
}

// An offscreen window learns a new scale only when its surface is remade,
// which a size change does.
void RefreshScale(WebView* view) {
  const int scale = std::max(1, gtk_widget_get_scale_factor(view->offscreen));
  if (scale == view->scale) {
    return;
  }
  view->scale = scale;
  GdkWindow* window = gtk_widget_get_window(view->offscreen);
  if (window != nullptr) {
    const int width = gdk_window_get_width(window);
    const int height = gdk_window_get_height(window);
    gdk_window_resize(window, width + 1, height);
    gdk_window_resize(window, width, height);
  }
  g_object_notify(G_OBJECT(view->view), "scale-factor");
  gtk_widget_queue_draw(view->offscreen);
}

void ApplyGeometry(WebView* view, int width, int height, double x, double y) {
  view->x = x;
  view->y = y;
  if (width != view->width || height != view->height) {
    view->width = width;
    view->height = height;
    gtk_widget_set_size_request(view->view, width, height);
  }
}

FlMethodResponse* CreateView(AppflowyLinuxWebviewPlugin* self, FlValue* args) {
  const WebKitApi* api = LoadWebKit();
  if (api == nullptr || self->flutter_view == nullptr) {
    return Failure("unsupported", "WebKitGTK 4.1 is not installed.");
  }
  const gchar* id = StringArg(args, "id");
  const gchar* url = StringArg(args, "url");
  const gchar* origin = StringArg(args, "origin");
  if (id == nullptr || url == nullptr || origin == nullptr) {
    return Failure("bad_arguments", "id, url and origin are required.");
  }
  if (FindView(self, id) != nullptr) {
    return Failure("exists", "A web view with this id already exists.");
  }
  EnsureToplevel(self);

  auto* view = new WebView();
  view->plugin = self;
  view->id = id;
  view->origin = origin;

  gpointer manager = api->user_content_manager_new();
  AddUserScripts(manager, Lookup(args, "userScripts", FL_VALUE_TYPE_LIST));
  api->user_content_manager_register_script_message_handler(manager,
                                                            kMessageHandler);
  g_autofree gchar* message_signal =
      g_strdup_printf("script-message-received::%s", kMessageHandler);
  g_signal_connect(manager, message_signal, G_CALLBACK(OnScriptMessage), view);
  api->user_content_manager_register_script_message_handler(
      manager, kPageMessageHandler);
  g_autofree gchar* page_signal =
      g_strdup_printf("script-message-received::%s", kPageMessageHandler);
  g_signal_connect(manager, page_signal, G_CALLBACK(OnPageMessage), view);
  view->content_manager = manager;
  // Website data stays in memory: the page's origin changes with every launch,
  // so nothing written to disk would ever be read again.
  view->view = GTK_WIDGET(g_object_new(api->web_view_get_type(),
                                       "user-content-manager", manager,
                                       "is-ephemeral", TRUE, nullptr));
  // Before the page draws anything, the surface behind the texture shows
  // rather than WebKit's white.
  if (api->web_view_set_background_color != nullptr) {
    api->web_view_set_background_color(view->view, &kTransparent);
  }

  gpointer settings = api->web_view_get_settings(view->view);
  api->settings_set_javascript_can_access_clipboard(settings, TRUE);
  // For debugging: the inspector, and the page's console on stdout.
  const bool devtools = g_getenv("APPFLOWY_WEBVIEW_DEVTOOLS") != nullptr;
  api->settings_set_enable_developer_extras(settings, devtools);
  api->settings_set_enable_write_console_messages_to_stdout(settings,
                                                            devtools);
  // An offscreen window has no GL surface, so the GPU's frames must come in
  // shared memory, which WebKitGTK offers from 2.44; otherwise WebKit renders
  // on the CPU.
  const bool gpu = PrepareSharedMemoryFrames() &&
                   api->get_major_version != nullptr &&
                   api->get_minor_version != nullptr &&
                   (api->get_major_version() > 2 ||
                    (api->get_major_version() == 2 &&
                     api->get_minor_version() >= 44));
  api->settings_set_hardware_acceleration_policy(
      settings, gpu ? kHardwareAccelerationAlways : kHardwareAccelerationNever);

  view->offscreen = gtk_offscreen_window_new();
  // WebKit leaves part of the view unpainted until its next frame whenever
  // the view's size changes. That part stays transparent, so the surface
  // behind the texture shows there instead of the theme's window colour,
  // which is near black in dark themes.
  gtk_widget_set_app_paintable(view->offscreen, TRUE);
  gtk_container_add(GTK_CONTAINER(view->offscreen), view->view);
  ApplyGeometry(view, SizeArg(args, "width", 800), SizeArg(args, "height", 600),
                DoubleArg(args, "x", 0), DoubleArg(args, "y", 0));

  // The embedder, set before anything is drawn, gives the surface the
  // application window's scale and a place for native coordinates.
  gtk_widget_realize(view->offscreen);
  GdkWindow* offscreen_window = gtk_widget_get_window(view->offscreen);
  // GDK clears each repaint to this before anything draws; the default is
  // opaque black.
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gdk_window_set_background_rgba(offscreen_window, &kTransparent);
  G_GNUC_END_IGNORE_DEPRECATIONS
  g_signal_connect(offscreen_window, "create-surface",
                   G_CALLBACK(OnCreateSurface), nullptr);
  GdkWindow* embedder = self->toplevel != nullptr
                            ? gtk_widget_get_window(self->toplevel)
                            : nullptr;
  if (embedder != nullptr) {
    gdk_offscreen_window_set_embedder(offscreen_window, embedder);
    g_signal_connect(offscreen_window, "to-embedder", G_CALLBACK(OnToEmbedder),
                     view);
    g_signal_connect(offscreen_window, "from-embedder",
                     G_CALLBACK(OnFromEmbedder), view);
  }

  g_signal_connect(view->offscreen, "damage-event", G_CALLBACK(OnDamage),
                   view);
  g_signal_connect(view->view, "decide-policy", G_CALLBACK(OnDecidePolicy),
                   view);
  g_signal_connect(view->view, "web-process-terminated",
                   G_CALLBACK(OnWebProcessTerminated), view);
  g_signal_connect(view->view, "context-menu", G_CALLBACK(OnContextMenu),
                   view);
  g_signal_connect(view->view, "query-tooltip", G_CALLBACK(OnQueryTooltip),
                   view);
  g_signal_connect(view->view, "show-option-menu",
                   G_CALLBACK(OnShowOptionMenu), view);
  g_signal_connect(view->view, "run-file-chooser",
                   G_CALLBACK(OnRunFileChooser), view);
  gtk_widget_show_all(view->offscreen);

  // WebKit read the scale before the view had a window to take it from.
  view->scale = std::max(1, gtk_widget_get_scale_factor(view->offscreen));
  g_object_notify(G_OBJECT(view->view), "scale-factor");

  view->texture = APPFLOWY_WEBVIEW_TEXTURE(
      g_object_new(webview_texture_get_type(), nullptr));
  fl_texture_registrar_register_texture(self->textures,
                                        FL_TEXTURE(view->texture));
  (*self->views)[view->id] = view;
  api->web_view_load_uri(view->view, url);
  return Success(
      fl_value_new_int(fl_texture_get_id(FL_TEXTURE(view->texture))));
}

void DestroyView(AppflowyLinuxWebviewPlugin* self, WebView* view) {
  if (self->focused == view) {
    self->focused = nullptr;
  }
  if (view->capture_source != 0) {
    g_source_remove(view->capture_source);
    view->capture_source = 0;
  }
  g_clear_pointer(&view->damage, cairo_region_destroy);
  g_signal_handlers_disconnect_by_data(view->content_manager, view);
  g_signal_handlers_disconnect_by_data(view->view, view);
  g_signal_handlers_disconnect_by_data(view->offscreen, view);
  GdkWindow* offscreen_window = gtk_widget_get_window(view->offscreen);
  if (offscreen_window != nullptr) {
    g_signal_handlers_disconnect_by_data(offscreen_window, view);
  }
  if (self->textures != nullptr) {
    fl_texture_registrar_unregister_texture(self->textures,
                                            FL_TEXTURE(view->texture));
  }
  g_object_unref(view->texture);
  EndWebProcess(view);
  gtk_widget_destroy(view->offscreen);
  g_object_unref(view->content_manager);
  delete view;
}

FlMethodResponse* SendPointer(WebView* view, FlValue* args) {
  GdkWindow* window = gtk_widget_get_window(view->view);
  const gchar* kind = StringArg(args, "kind");
  if (window == nullptr || kind == nullptr) {
    return Success();
  }
  const double x = DoubleArg(args, "x", 0);
  const double y = DoubleArg(args, "y", 0);
  int root_x = 0;
  int root_y = 0;
  gdk_window_get_root_coords(window, static_cast<int>(x), static_cast<int>(y),
                             &root_x, &root_y);
  const auto time = static_cast<guint32>(IntArg(args, "time", 0));
  // Flutter reports the buttons; the keyboard state comes from GDK because
  // key presses for a focused view never reach Flutter.
  const auto state =
      static_cast<guint>(IntArg(args, "buttons", 0)) |
      gdk_keymap_get_modifier_state(
          gdk_keymap_get_for_display(gdk_display_get_default()));

  GdkEvent* event;
  if (strcmp(kind, "down") == 0 || strcmp(kind, "up") == 0) {
    event = gdk_event_new(strcmp(kind, "down") == 0 ? GDK_BUTTON_PRESS
                                                     : GDK_BUTTON_RELEASE);
    event->button.time = time;
    event->button.x = x;
    event->button.y = y;
    event->button.x_root = root_x + (x - std::floor(x));
    event->button.y_root = root_y + (y - std::floor(y));
    event->button.state = state;
    event->button.button = static_cast<guint>(IntArg(args, "button", 1));
  } else if (strcmp(kind, "move") == 0) {
    event = gdk_event_new(GDK_MOTION_NOTIFY);
    event->motion.time = time;
    event->motion.x = x;
    event->motion.y = y;
    event->motion.x_root = root_x + (x - std::floor(x));
    event->motion.y_root = root_y + (y - std::floor(y));
    event->motion.state = state;
  } else if (strcmp(kind, "enter") == 0 || strcmp(kind, "leave") == 0) {
    event = gdk_event_new(strcmp(kind, "enter") == 0 ? GDK_ENTER_NOTIFY
                                                      : GDK_LEAVE_NOTIFY);
    event->crossing.time = time;
    event->crossing.x = x;
    event->crossing.y = y;
    event->crossing.x_root = root_x;
    event->crossing.y_root = root_y;
    event->crossing.mode = GDK_CROSSING_NORMAL;
    event->crossing.detail = GDK_NOTIFY_NONLINEAR;
    event->crossing.state = state;
  } else if (strcmp(kind, "scroll") == 0) {
    event = gdk_event_new(GDK_SCROLL);
    event->scroll.time = time;
    event->scroll.x = x;
    event->scroll.y = y;
    event->scroll.x_root = root_x;
    event->scroll.y_root = root_y;
    event->scroll.state = state;
    event->scroll.direction = GDK_SCROLL_SMOOTH;
    event->scroll.delta_x = DoubleArg(args, "dx", 0);
    event->scroll.delta_y = DoubleArg(args, "dy", 0);
  } else {
    return Failure("bad_arguments", "Unknown pointer event.");
  }
  // Every event type keeps its window and send_event in the same place.
  event->any.window = GDK_WINDOW(g_object_ref(window));
  event->any.send_event = TRUE;
  GdkSeat* seat = DefaultSeat();
  if (seat != nullptr && gdk_seat_get_pointer(seat) != nullptr) {
    gdk_event_set_device(event, gdk_seat_get_pointer(seat));
  }
  if (event->type == GDK_SCROLL && BoolArg(args, "precise", false)) {
    GdkDevice* precise = PreciseScrollDevice(seat);
    if (precise != nullptr) {
      gdk_event_set_source_device(event, precise);
    }
  }
  gtk_main_do_event(event);
  gdk_event_free(event);
  return Success();
}

// Runs a script in the main frame without waiting for its result.
FlMethodResponse* Evaluate(WebView* view, FlValue* args) {
  const WebKitApi* api = LoadWebKit();
  const gchar* source = StringArg(args, "source");
  if (source == nullptr) {
    return Failure("bad_arguments", "source is required.");
  }
  if (api->web_view_evaluate_javascript != nullptr) {
    api->web_view_evaluate_javascript(view->view, source, -1, nullptr, nullptr,
                                      nullptr, nullptr, nullptr);
  } else if (api->web_view_run_javascript != nullptr) {
    api->web_view_run_javascript(view->view, source, nullptr, nullptr,
                                 nullptr);
  } else {
    return Failure("unsupported", "This WebKitGTK cannot run scripts.");
  }
  return Success();
}

void HandleMethodCall(FlMethodChannel*,
                      FlMethodCall* method_call,
                      gpointer user_data) {
  auto* self = static_cast<AppflowyLinuxWebviewPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "isSupported") == 0) {
    response = Success(fl_value_new_bool(LoadWebKit() != nullptr &&
                                         self->flutter_view != nullptr));
  } else if (strcmp(method, "create") == 0) {
    response = CreateView(self, args);
  } else if (strcmp(method, "disposeAll") == 0) {
    // A restarted Dart isolate no longer knows the views it made.
    auto views = *self->views;
    self->views->clear();
    for (auto& entry : views) {
      DestroyView(self, entry.second);
    }
    response = Success();
  } else {
    WebView* view = FindView(self, StringArg(args, "id"));
    if (view == nullptr) {
      response = Success();
    } else if (strcmp(method, "pointer") == 0) {
      response = SendPointer(view, args);
    } else if (strcmp(method, "evaluate") == 0) {
      response = Evaluate(view, args);
    } else if (strcmp(method, "geometry") == 0) {
      RefreshScale(view);
      ApplyGeometry(view, SizeArg(args, "width", view->width),
                    SizeArg(args, "height", view->height),
                    DoubleArg(args, "x", view->x),
                    DoubleArg(args, "y", view->y));
      response = Success();
    } else if (strcmp(method, "focus") == 0) {
      SetFocused(self, view, BoolArg(args, "focused", false));
      response = Success();
    } else if (strcmp(method, "active") == 0) {
      view->active = BoolArg(args, "active", true);
      if (view->active) {
        ScheduleCapture(view);
      }
      response = Success();
    } else if (strcmp(method, "setUserScripts") == 0) {
      LoadWebKit()->user_content_manager_remove_all_scripts(
          view->content_manager);
      AddUserScripts(view->content_manager,
                     Lookup(args, "userScripts", FL_VALUE_TYPE_LIST));
      response = Success();
    } else if (strcmp(method, "dispose") == 0) {
      self->views->erase(view->id);
      DestroyView(self, view);
      response = Success();
    } else {
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
  }
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

static void appflowy_linux_webview_plugin_dispose(GObject* object) {
  auto* self = APPFLOWY_LINUX_WEBVIEW_PLUGIN(object);
  if (self->views != nullptr) {
    auto* views = self->views;
    self->views = nullptr;
    for (auto& entry : *views) {
      DestroyView(self, entry.second);
    }
    delete views;
  }
  self->focused = nullptr;
  g_clear_object(&self->channel);
  g_clear_object(&self->textures);
  G_OBJECT_CLASS(appflowy_linux_webview_plugin_parent_class)->dispose(object);
}

static void appflowy_linux_webview_plugin_class_init(
    AppflowyLinuxWebviewPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = appflowy_linux_webview_plugin_dispose;
}

static void appflowy_linux_webview_plugin_init(
    AppflowyLinuxWebviewPlugin* self) {
  self->channel = nullptr;
  self->textures = nullptr;
  self->flutter_view = nullptr;
  self->toplevel = nullptr;
  self->views = new std::map<std::string, WebView*>();
  self->focused = nullptr;
}

void appflowy_linux_webview_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  // Before anything starts WebKit, which reads the setting only once.
  PrepareSharedMemoryFrames();
  AppflowyLinuxWebviewPlugin* plugin = APPFLOWY_LINUX_WEBVIEW_PLUGIN(
      g_object_new(appflowy_linux_webview_plugin_get_type(), nullptr));
  plugin->textures = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));
  plugin->flutter_view = fl_plugin_registrar_get_view(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "appflowy_linux_webview", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, HandleMethodCall, g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
