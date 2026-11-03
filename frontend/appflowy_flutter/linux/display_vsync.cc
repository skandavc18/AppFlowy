#include "display_vsync.h"

#include <dlfcn.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>

#include "third_party/flutter_embedder/embedder.h"

// Flutter's Linux embedder gives the engine no vsync source, so the engine
// falls back to a fixed 60 Hz timer however fast the display is: every
// animation and scroll in the app is capped at 60 frames a second, half of
// what a 120 Hz screen shows. GTK 3 adds a second cap of its own: it learns
// the refresh rate only from frame callbacks, which it never requests for
// windows drawn with OpenGL, as the Flutter view is, so its frame clock
// assumes 60 Hz and paints no more often than that either.
//
// FlEngine calls the engine through a procedure table it keeps in its
// instance. Before the engine starts, the table's Initialize is wrapped so the
// engine is created with a vsync callback. The callback answers each request
// at once with the display's next refresh, and FlutterEngineOnVsync holds the
// frame until that time on the engine's own task runner. Nothing waits on the
// GTK main loop, which the embedder blocks while it waits for a frame during
// a resize. Each GTK frame is given the monitor's refresh interval, as a
// frame callback would have, so GTK paints at the display's rate too, and
// the engine's frames start in step with GTK's; eglSwapBuffers still waits for
// the compositor between frames.
//
// FlEngine's layout is private to the engine. It is found through public
// accessors and checked against embedder.h from the same engine revision
// (82bd5b7209295a5b7ff8cae0df96e7870171e3a5, Flutter 3.27.4). GTK's frame
// timings are checked against their public getters before they are written.
// Anything unexpected leaves that part as it was, at 60 Hz.

namespace {

constexpr int64_t kNanosecondsPerMicrosecond = 1000;
constexpr int64_t kSixtyHertz = 16666667;
constexpr char kEngineLibrary[] = "libflutter_linux_gtk.so";
constexpr char kDisableVariable[] = "APPFLOWY_DISPLAY_VSYNC";

struct DisplayVsync {
  FlutterEngineInitializeFnPtr initialize = nullptr;
  FlutterEngineOnVsyncFnPtr on_vsync = nullptr;
  FlutterEngineGetCurrentTimeFnPtr current_time = nullptr;

  std::atomic<int64_t> interval{kSixtyHertz};
  // A time the display refreshed at, on the engine's clock (CLOCK_MONOTONIC,
  // as GDK's), or 0 while unknown.
  std::atomic<int64_t> phase{0};

  // The engine can ask for a frame before Initialize has returned its handle;
  // that request waits here and is answered once the handle exists.
  std::mutex mutex;
  FLUTTER_API_SYMBOL(FlutterEngine) engine = nullptr;
  intptr_t waiting_baton = 0;

  // The engine has at most one request out at a time, so whichever thread
  // answers it has this to itself.
  int64_t last_start = 0;

  // Only the GTK main thread uses these.
  int64_t monitor_interval = kSixtyHertz;
  gint64 monitor_checked = 0;
  bool pace_gtk = true;
};

DisplayVsync* vsync = nullptr;

int64_t FloorDivide(int64_t value, int64_t divisor) {
  int64_t quotient = value / divisor;
  if (value % divisor != 0 && (value < 0) != (divisor < 0)) {
    --quotient;
  }
  return quotient;
}

void Answer(FLUTTER_API_SYMBOL(FlutterEngine) engine, intptr_t baton) {
  const auto now = static_cast<int64_t>(vsync->current_time());
  const int64_t interval = vsync->interval.load(std::memory_order_relaxed);
  int64_t phase = vsync->phase.load(std::memory_order_relaxed);
  if (phase == 0) {
    phase = now;
  }
  // The display's first refresh after now. Two requests within one refresh
  // still get frames a refresh apart, never the same timestamp.
  int64_t start = phase + (FloorDivide(now - phase, interval) + 1) * interval;
  if (start - vsync->last_start < interval / 2) {
    start = vsync->last_start + interval;
  }
  vsync->last_start = start;
  static std::once_flag reported;
  std::call_once(reported, [interval] {
    g_debug("AppFlowy display vsync: engine frames every %.3f ms",
            interval / 1e6);
  });
  vsync->on_vsync(engine, baton, static_cast<uint64_t>(start),
                  static_cast<uint64_t>(start + interval));
}

// Called on the engine's UI thread whenever it wants another frame.
void OnVsyncRequest(void*, intptr_t baton) {
  FLUTTER_API_SYMBOL(FlutterEngine) engine;
  {
    std::lock_guard<std::mutex> lock(vsync->mutex);
    engine = vsync->engine;
    if (engine == nullptr) {
      vsync->waiting_baton = baton;
      return;
    }
  }
  Answer(engine, baton);
}

FlutterEngineResult InitializeWithVsync(
    size_t version,
    const FlutterRendererConfig* config,
    const FlutterProjectArgs* args,
    void* user_data,
    FLUTTER_API_SYMBOL(FlutterEngine) * engine_out) {
  if (args == nullptr || engine_out == nullptr ||
      args->struct_size != sizeof(FlutterProjectArgs) ||
      args->vsync_callback != nullptr) {
    if (args != nullptr && args->struct_size != sizeof(FlutterProjectArgs)) {
      g_warning(
          "AppFlowy: this Flutter engine's project arguments are not the "
          "ones display vsync expects; frames stay at 60 Hz.");
    }
    return vsync->initialize(version, config, args, user_data, engine_out);
  }
  FlutterProjectArgs with_vsync = *args;
  with_vsync.vsync_callback = OnVsyncRequest;
  const FlutterEngineResult result =
      vsync->initialize(version, config, &with_vsync, user_data, engine_out);
  if (result != kSuccess) {
    return result;
  }
  intptr_t waiting;
  {
    std::lock_guard<std::mutex> lock(vsync->mutex);
    vsync->engine = *engine_out;
    waiting = vsync->waiting_baton;
    vsync->waiting_baton = 0;
  }
  if (waiting != 0) {
    Answer(*engine_out, waiting);
  }
  return result;
}

// Until the compositor reports presentations, the monitor's nominal rate.
int64_t MonitorInterval(GtkWidget* window) {
  GdkDisplay* display = gtk_widget_get_display(window);
  GdkWindow* gdk_window = gtk_widget_get_window(window);
  GdkMonitor* monitor =
      gdk_window != nullptr
          ? gdk_display_get_monitor_at_window(display, gdk_window)
          : nullptr;
  if (monitor == nullptr) {
    monitor = gdk_display_get_primary_monitor(display);
  }
  const int millihertz =
      monitor != nullptr ? gdk_monitor_get_refresh_rate(monitor) : 0;
  return millihertz > 0 ? INT64_C(1000000000000) / millihertz : kSixtyHertz;
}

// GdkFrameTimings up to its refresh interval, as GTK 3.24 lays it out in
// gdk/gdkframeclockprivate.h. GTK 3's ABI no longer changes.
struct FrameTimingsPrefix {
  guint ref_count;
  gint64 frame_counter;
  guint64 cookie;
  gint64 frame_time;
  gint64 smoothed_frame_time;
  gint64 drawn_time;
  gint64 presentation_time;
  gint64 refresh_interval;
};

// Gives a frame the interval a frame callback would have reported. GTK's
// frame clock spaces its next frame by it.
bool SetRefreshInterval(GdkFrameTimings* timings, gint64 interval) {
  auto* prefix = reinterpret_cast<FrameTimingsPrefix*>(timings);
  if (prefix->frame_counter != gdk_frame_timings_get_frame_counter(timings) ||
      prefix->frame_time != gdk_frame_timings_get_frame_time(timings) ||
      prefix->presentation_time !=
          gdk_frame_timings_get_presentation_time(timings) ||
      prefix->refresh_interval !=
          gdk_frame_timings_get_refresh_interval(timings)) {
    return false;
  }
  const gint64 previous = prefix->refresh_interval;
  prefix->refresh_interval = interval;
  if (gdk_frame_timings_get_refresh_interval(timings) != interval) {
    prefix->refresh_interval = previous;
    return false;
  }
  return true;
}

void OnAfterPaint(GdkFrameClock* clock, gpointer window) {
  const gint64 frame_time = gdk_frame_clock_get_frame_time(clock);
  // The window may have moved to a monitor with another rate.
  if (frame_time - vsync->monitor_checked >= G_USEC_PER_SEC) {
    vsync->monitor_checked = frame_time;
    vsync->monitor_interval = MonitorInterval(GTK_WIDGET(window));
  }

  gint64 refresh = 0;
  gint64 presentation = 0;
  gdk_frame_clock_get_refresh_info(clock, frame_time, &refresh, &presentation);
  if (presentation != 0 && refresh > 0) {
    // The compositor reported presenting frames: the display's own timing.
    vsync->interval.store(refresh * kNanosecondsPerMicrosecond,
                          std::memory_order_relaxed);
    vsync->phase.store(presentation * kNanosecondsPerMicrosecond,
                       std::memory_order_relaxed);
    return;
  }

  // Otherwise the engine's frames start with GTK's, on its smoothed grid.
  vsync->interval.store(vsync->monitor_interval, std::memory_order_relaxed);
  vsync->phase.store(frame_time * kNanosecondsPerMicrosecond,
                     std::memory_order_relaxed);
  GdkFrameTimings* timings = gdk_frame_clock_get_current_timings(clock);
  if (!vsync->pace_gtk || timings == nullptr ||
      gdk_frame_timings_get_refresh_interval(timings) != 0) {
    return;
  }
  const gint64 interval =
      (vsync->monitor_interval + kNanosecondsPerMicrosecond / 2) /
      kNanosecondsPerMicrosecond;
  if (!SetRefreshInterval(timings, interval)) {
    vsync->pace_gtk = false;
    g_warning(
        "AppFlowy: GTK's frame timings are not laid out as expected; the "
        "window keeps GTK's 60 Hz pacing.");
    return;
  }
  static bool reported = false;
  if (!reported) {
    reported = true;
    g_debug("AppFlowy display vsync: GTK paints every %.3f ms",
            interval / 1e3);
  }
}

void TrackFrameClock(GtkWidget* window) {
  GdkFrameClock* clock = gtk_widget_get_frame_clock(window);
  if (clock != nullptr) {
    g_signal_connect(clock, "after-paint", G_CALLBACK(OnAfterPaint), window);
  }
}

bool InLibrary(const void* address, const void* library_base) {
  Dl_info info;
  return address != nullptr && dladdr(address, &info) != 0 &&
         info.dli_fbase == library_base;
}

const void* EngineLibraryBase() {
  void* library = dlopen(kEngineLibrary, RTLD_LAZY | RTLD_NOLOAD);
  if (library == nullptr) {
    return nullptr;
  }
  void* known = dlsym(library, "fl_engine_new");
  Dl_info info;
  const void* base =
      known != nullptr && dladdr(known, &info) != 0 ? info.dli_fbase : nullptr;
  dlclose(library);
  return base;
}

// The procedure table in [engine], or null when the engine has started or is
// not laid out as in this engine revision:
//
//   GObject parent_instance; GThread* thread; FlDartProject* project;
//   FlRenderer* renderer; FlBinaryMessenger* binary_messenger;
//   FlSettingsHandler* settings_handler;
//   FlTextureRegistrar* texture_registrar; FlTaskRunner* task_runner;
//   FlutterEngineAOTData aot_data; FlutterEngine engine;
//   FlutterEngineProcTable embedder_api; ...
FlutterEngineProcTable* FindProcTable(FlEngine* engine) {
  const void* library_base = EngineLibraryBase();
  if (library_base == nullptr) {
    return nullptr;
  }
  constexpr size_t kPointer = sizeof(void*);
  constexpr size_t kRegistrarAfterMessenger = 2 * kPointer;
  constexpr size_t kHandleAfterMessenger = 5 * kPointer;
  constexpr size_t kTableAfterMessenger = 6 * kPointer;

  GTypeQuery query;
  g_type_query(G_OBJECT_TYPE(engine), &query);
  const void* messenger = fl_engine_get_binary_messenger(engine);
  const void* registrar = fl_engine_get_texture_registrar(engine);
  if (messenger == nullptr || registrar == nullptr) {
    return nullptr;
  }
  auto* bytes = reinterpret_cast<uint8_t*>(engine);
  auto pointer_at = [&](size_t offset) {
    void* value;
    std::memcpy(&value, bytes + offset, kPointer);
    return value;
  };
  for (size_t offset = sizeof(GObject);
       offset + kTableAfterMessenger + sizeof(FlutterEngineProcTable) <=
       query.instance_size;
       offset += kPointer) {
    if (pointer_at(offset) != messenger ||
        pointer_at(offset + kRegistrarAfterMessenger) != registrar) {
      continue;
    }
    if (pointer_at(offset + kHandleAfterMessenger) != nullptr) {
      return nullptr;
    }
    auto* table = reinterpret_cast<FlutterEngineProcTable*>(
        bytes + offset + kTableAfterMessenger);
    if (table->struct_size != sizeof(FlutterEngineProcTable) ||
        !InLibrary(reinterpret_cast<const void*>(table->Initialize),
                   library_base) ||
        !InLibrary(reinterpret_cast<const void*>(table->OnVsync),
                   library_base) ||
        !InLibrary(reinterpret_cast<const void*>(table->GetCurrentTime),
                   library_base)) {
      return nullptr;
    }
    return table;
  }
  return nullptr;
}

}  // namespace

void appflowy_display_vsync_install(FlView* view, GtkWindow* window) {
  if (vsync != nullptr || g_strcmp0(g_getenv(kDisableVariable), "0") == 0) {
    return;
  }
  FlEngine* engine = fl_view_get_engine(view);
  FlutterEngineProcTable* table =
      FL_IS_ENGINE(engine) ? FindProcTable(engine) : nullptr;
  if (table == nullptr) {
    g_warning(
        "AppFlowy: this Flutter engine is not laid out as display vsync "
        "expects; frames stay at 60 Hz.");
    return;
  }
  vsync = new DisplayVsync();
  vsync->initialize = table->Initialize;
  vsync->on_vsync = table->OnVsync;
  vsync->current_time = table->GetCurrentTime;
  vsync->monitor_interval = MonitorInterval(GTK_WIDGET(window));
  vsync->interval.store(vsync->monitor_interval);
  table->Initialize = InitializeWithVsync;
  TrackFrameClock(GTK_WIDGET(window));
}
