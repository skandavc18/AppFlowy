#include "../utils/log.h"
#include "custom_platform_view.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_result_functions.h>

#ifdef HAVE_FLUTTER_D3D_TEXTURE
#include "texture_bridge_gpu.h"
#else
#include "texture_bridge_fallback.h"
#endif

namespace flutter_inappwebview_plugin
{
  constexpr auto kErrorInvalidArgs = "invalidArguments";

  constexpr auto kMethodSetSize = "setSize";
  constexpr auto kMethodSetPosition = "setPosition";
  constexpr auto kMethodSetCursorPos = "setCursorPos";
  constexpr auto kMethodSetPointerUpdate = "setPointerUpdate";
  constexpr auto kMethodSetPointerButton = "setPointerButton";
  constexpr auto kMethodSetScrollDelta = "setScrollDelta";
  constexpr auto kMethodSetZoomScale = "setZoomScale";
  constexpr auto kMethodSetFpsLimit = "setFpsLimit";
  constexpr auto kMethodNavigateHistory = "navigateHistory";
  constexpr auto kMethodGetHistoryState = "getHistoryState";

  constexpr auto kEventType = "type";
  constexpr auto kEventValue = "value";

  static std::optional<int64_t> GetTimestampFromArg(const flutter::EncodableValue& value)
  {
    // StandardMessageCodec chooses int32 or int64 by magnitude. A fresh engine
    // and a long-running one must both preserve every original microsecond.
    if (const auto narrowValue = std::get_if<int32_t>(&value)) return *narrowValue;
    if (const auto wideValue = std::get_if<int64_t>(&value)) return *wideValue;
    return std::nullopt;
  }

  static const std::optional<std::pair<double, double>> GetPointFromArgs(
    const flutter::EncodableValue* args)
  {
    const flutter::EncodableList* list =
      std::get_if<flutter::EncodableList>(args);
    if (!list || list->size() != 2) {
      return std::nullopt;
    }
    const auto x = std::get_if<double>(&(*list)[0]);
    const auto y = std::get_if<double>(&(*list)[1]);
    if (!x || !y) {
      return std::nullopt;
    }
    return std::make_pair(*x, *y);
  }

  static const std::optional<std::tuple<double, double, double>>
    GetPointAndScaleFactorFromArgs(const flutter::EncodableValue* args)
  {
    const flutter::EncodableList* list =
      std::get_if<flutter::EncodableList>(args);
    if (!list || list->size() != 3) {
      return std::nullopt;
    }
    const auto x = std::get_if<double>(&(*list)[0]);
    const auto y = std::get_if<double>(&(*list)[1]);
    const auto z = std::get_if<double>(&(*list)[2]);
    if (!x || !y || !z) {
      return std::nullopt;
    }
    return std::make_tuple(*x, *y, *z);
  }

  static const std::string& GetCursorName(const HCURSOR cursor)
  {
    // The cursor names correspond to the Flutter Engine names:
    // in shell/platform/windows/flutter_window_win32.cc
    static const std::string kDefaultCursorName = "basic";
    static const std::pair<std::string, const wchar_t*> mappings[] = {
        {"allScroll", IDC_SIZEALL},
        {kDefaultCursorName, IDC_ARROW},
        {"click", IDC_HAND},
        {"forbidden", IDC_NO},
        {"help", IDC_HELP},
        {"move", IDC_SIZEALL},
        {"none", nullptr},
        {"noDrop", IDC_NO},
        {"precise", IDC_CROSS},
        {"progress", IDC_APPSTARTING},
        {"text", IDC_IBEAM},
        {"resizeColumn", IDC_SIZEWE},
        {"resizeDown", IDC_SIZENS},
        {"resizeDownLeft", IDC_SIZENESW},
        {"resizeDownRight", IDC_SIZENWSE},
        {"resizeLeft", IDC_SIZEWE},
        {"resizeLeftRight", IDC_SIZEWE},
        {"resizeRight", IDC_SIZEWE},
        {"resizeRow", IDC_SIZENS},
        {"resizeUp", IDC_SIZENS},
        {"resizeUpDown", IDC_SIZENS},
        {"resizeUpLeft", IDC_SIZENWSE},
        {"resizeUpRight", IDC_SIZENESW},
        {"resizeUpLeftDownRight", IDC_SIZENWSE},
        {"resizeUpRightDownLeft", IDC_SIZENESW},
        {"wait", IDC_WAIT},
    };

    static std::map<HCURSOR, std::string> cursors;
    static bool initialized = false;

    if (!initialized) {
      initialized = true;
      for (const auto& pair : mappings) {
        HCURSOR cursor_handle = LoadCursor(nullptr, pair.second);
        if (cursor_handle) {
          cursors[cursor_handle] = pair.first;
        }
      }
    }

    const auto it = cursors.find(cursor);
    if (it != cursors.end()) {
      return it->second;
    }
    return kDefaultCursorName;
  }

  CustomPlatformView::CustomPlatformView(flutter::BinaryMessenger* messenger,
    flutter::TextureRegistrar* texture_registrar,
    GraphicsContext* graphics_context,
    HWND hwnd,
    std::shared_ptr<flutter_inappwebview_plugin::InAppWebView> webView)
    : hwnd_(hwnd), view(std::move(webView)), texture_registrar_(texture_registrar)
  {
#ifdef HAVE_FLUTTER_D3D_TEXTURE
    texture_bridge_ =
      std::make_unique<TextureBridgeGpu>(graphics_context, view->surface());

    flutter_texture_ =
      std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
        kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
        [bridge = static_cast<TextureBridgeGpu*>(texture_bridge_.get())](
          size_t width,
          size_t height) -> const FlutterDesktopGpuSurfaceDescriptor*
        {
          return bridge->GetSurfaceDescriptor(width, height);
        }));
#else
    texture_bridge_ = std::make_unique<TextureBridgeFallback>(
      graphics_context, view->surface());

    flutter_texture_ =
      std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
        [bridge = static_cast<TextureBridgeFallback*>(texture_bridge_.get())](
          size_t width, size_t height) -> const FlutterDesktopPixelBuffer*
        {
          return bridge->CopyPixelBuffer(width, height);
        }));
#endif

    texture_id_ = texture_registrar->RegisterTexture(flutter_texture_.get());
    texture_bridge_->SetOnFrameAvailable(
      [this]() { texture_registrar_->MarkTextureFrameAvailable(texture_id_); });
    // texture_bridge_->SetOnSurfaceSizeChanged([this](Size size) {
    //  view->SetSurfaceSize(size.width, size.height);
    //});

    const auto method_channel_name = "com.pichillilorenzo/custom_platform_view_" + std::to_string(texture_id_);
    method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, method_channel_name,
        &flutter::StandardMethodCodec::GetInstance());
    method_channel_->SetMethodCallHandler([this](const auto& call, auto result)
      {
        HandleMethodCall(call, std::move(result));
      });

    const auto event_channel_name = "com.pichillilorenzo/custom_platform_view_" + std::to_string(texture_id_) + "_events";
    event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, event_channel_name,
        &flutter::StandardMethodCodec::GetInstance());

    auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [this](const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
          events)
        {
          event_sink_ = std::move(events);
          RegisterEventHandlers();
          return nullptr;
        },
        [this](const flutter::EncodableValue* arguments)
        {
          return nullptr;
        });

    event_channel_->SetStreamHandler(std::move(handler));
  }

  void CustomPlatformView::UnregisterMethodCallHandler() const
  {
    if (method_channel_) {
      method_channel_->SetMethodCallHandler(nullptr);
      if (view && view->channelDelegate) {
        view->channelDelegate->UnregisterMethodCallHandler();
      }
    }
  }

  CustomPlatformView::~CustomPlatformView()
  {
    debugLog("dealloc CustomPlatformView");
    Dispose();
  }

  void CustomPlatformView::DetachViewCallbacks()
  {
    if (view) {
      view->onSurfaceSizeChanged(nullptr);
      view->onCursorChanged(nullptr);
    }
    if (history_handlers_registered_ && view && view->webView) {
      view->webView->remove_HistoryChanged(history_changed_token_);
      view->webView->remove_NavigationStarting(navigation_starting_token_);
      view->webView->remove_NavigationCompleted(navigation_completed_token_);
    }
    history_handlers_registered_ = false;
  }

  std::shared_ptr<InAppWebView> CustomPlatformView::DetachView()
  {
    if (view) view->cancelTrackpadGesture();
    DetachViewCallbacks();
    return std::exchange(view, nullptr);
  }

  void CustomPlatformView::Dispose(std::function<void(HRESULT)> completion)
  {
    // The manager removes ownership before calling Dispose; the destructor's
    // second call must not acknowledge an unregister which is still pending.
    if (disposed_) return;
    disposed_ = true;
    UnregisterMethodCallHandler();
    if (event_channel_) event_channel_->SetStreamHandler(nullptr);
    event_sink_ = nullptr;
    DetachViewCallbacks();
    RecordTextureLifecycle(lifecycle_events_, 0); // owner callbacks detached
    texture_bridge_->Shutdown();
    RecordTextureLifecycle(lifecycle_events_, 1); // capture shutdown returned
    // Close on the platform thread even if an outstanding history reply holds
    // a shared renderer. Never retain a WebView/COM apartment in the raster ack.
    const auto close_result = view ? view->Dispose() : S_OK;
    view.reset();
    RecordTextureLifecycle(lifecycle_events_, 2); // controller dispose returned
    RetireTexture(std::move(texture_bridge_), std::move(flutter_texture_),
      [registrar = texture_registrar_, id = texture_id_](std::function<void()> done) {
        registrar->UnregisterTexture(id, std::move(done));
      },
      [completion = std::move(completion), close_result]() {
        if (completion) completion(close_result);
      }, lifecycle_events_);
  }

  void CustomPlatformView::RegisterEventHandlers()
  {
    if (!view) {
      return;
    }

    view->onSurfaceSizeChanged([this](size_t width, size_t height)
      {
        texture_bridge_->NotifySurfaceSizeChanged();
      });

    view->onCursorChanged([this](const HCURSOR cursor)
      {
        const auto& name = GetCursorName(cursor);
        const auto event = flutter::EncodableValue(
          flutter::EncodableMap { {
              flutter::EncodableValue(kEventType),
                flutter::EncodableValue("cursorChanged")
            },
          { flutter::EncodableValue(kEventValue), name }});
        EmitEvent(event);
      });

    if (!history_handlers_registered_ && view->webView) {
      history_handlers_registered_ = true;
      view->webView->add_HistoryChanged(
        Microsoft::WRL::Callback<ICoreWebView2HistoryChangedEventHandler>(
          [this](ICoreWebView2*, IUnknown*) -> HRESULT {
            EmitEvent(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue(kEventType), flutter::EncodableValue("historyChanged")}}));
            return S_OK;
          }).Get(), &history_changed_token_);
      view->webView->add_NavigationStarting(
        Microsoft::WRL::Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs*) -> HRESULT {
            EmitEvent(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue(kEventType), flutter::EncodableValue("navigationStarting")}}));
            return S_OK;
          }).Get(), &navigation_starting_token_);
      view->webView->add_NavigationCompleted(
        Microsoft::WRL::Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs*) -> HRESULT {
            EmitEvent(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue(kEventType), flutter::EncodableValue("navigationCompleted")}}));
            return S_OK;
          }).Get(), &navigation_completed_token_);
    }
  }

  void CustomPlatformView::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    const auto& method_name = method_call.method_name();

    if (method_name == "_getSiteGestureDiagnostics") {
      const auto token = std::get_if<std::string>(method_call.arguments());
      if (!token || *token != "offline-fixture-v1" || !view || !view->webViewController) {
        return result->Error(kErrorInvalidArgs);
      }
      double zoom = 1.0;
      POINT cursor{};
      CURSORINFO info{};
      info.cbSize = sizeof(info);
      if (FAILED(view->webViewController->get_ZoomFactor(&zoom)) ||
        !GetPhysicalCursorPos(&cursor) || !GetCursorInfo(&info)) {
        return result->Error("fixtureDiagnosticsUnavailable");
      }
      return result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("zoomFactor"), flutter::EncodableValue(zoom)},
        {flutter::EncodableValue("idle"), flutter::EncodableValue(view->isTrackpadInputIdle())},
        {flutter::EncodableValue("cursorX"), flutter::EncodableValue(static_cast<int32_t>(cursor.x))},
        {flutter::EncodableValue("cursorY"), flutter::EncodableValue(static_cast<int32_t>(cursor.y))},
        {flutter::EncodableValue("cursorVisible"), flutter::EncodableValue((info.flags & CURSOR_SHOWING) != 0)} }));
    }

    if (method_name == "_startTextureLifecycleProbe") {
      const auto token = std::get_if<std::string>(method_call.arguments());
      if (!token || *token != "offline-fixture-v1") return result->Error(kErrorInvalidArgs);
      lifecycle_events_ = std::make_shared<TextureLifecycleEvents>();
      lifecycle_events_->reserve(6);
      return result->Success();
    }

    // Private fixture protocol: no production caller, per-view explicit opt-in,
    // 12-second/8192-event bound. Never streams events across the Dart channel.
    if (method_name == "_startTextureCadenceProbe") {
      const auto token = std::get_if<std::string>(method_call.arguments());
      if (!token || *token != "offline-fixture-v1") return result->Error(kErrorInvalidArgs);
      texture_bridge_->StartCadenceProbe();
      return result->Success();
    }
    if (method_name == "_stopTextureCadenceProbe") {
      const auto snapshot = texture_bridge_->StopCadenceProbe();
      flutter::EncodableList events;
      events.reserve(snapshot.events.size());
      for (const auto& event : snapshot.events) {
        events.emplace_back(flutter::EncodableList{
          flutter::EncodableValue(static_cast<int32_t>(event.kind)),
          flutter::EncodableValue(event.milliseconds),
          flutter::EncodableValue(event.sequence),
          flutter::EncodableValue(event.work_milliseconds) });
      }
#ifdef HAVE_FLUTTER_D3D_TEXTURE
      const char* backend = "dxgi_shared_handle";
#else
      const char* backend = "cpu_pixel_buffer";
#endif
      return result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("schema"), flutter::EncodableValue(1)},
        {flutter::EncodableValue("backend"), flutter::EncodableValue(backend)},
        {flutter::EncodableValue("elapsed_ms"), flutter::EncodableValue(snapshot.elapsed_ms)},
        {flutter::EncodableValue("limit_ms"), flutter::EncodableValue(snapshot.limit_ms)},
        {flutter::EncodableValue("expired"), flutter::EncodableValue(snapshot.expired)},
        {flutter::EncodableValue("truncated"), flutter::EncodableValue(snapshot.truncated)},
        {flutter::EncodableValue("events"), flutter::EncodableValue(std::move(events))} }));
    }

    if (method_name == kMethodGetHistoryState) {
      if (!view) return result->Error(kErrorInvalidArgs);
      // Keep the reply and renderer alive, never a raw CustomPlatformView
      // pointer, while Chromium answers. No URLs/content cross this channel.
      auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
      auto renderer = view;
      renderer->getCopyBackForwardList([reply, renderer](std::unique_ptr<WebHistory> history) {
        flutter::EncodableMap state = {
          {flutter::EncodableValue("back"), flutter::EncodableValue(renderer->canGoBack())},
          {flutter::EncodableValue("forward"), flutter::EncodableValue(renderer->canGoForward())},
          {flutter::EncodableValue("loading"), flutter::EncodableValue(renderer->isLoading())}
        };
        if (history && history->currentIndex && history->list) {
          const auto index = *history->currentIndex;
          const auto& entries = *history->list;
          const auto addKey = [&](const char* name, int64_t at) {
            if (at >= 0 && at < static_cast<int64_t>(entries.size()) && entries[at]->entryId) {
              state[flutter::EncodableValue(name)] = flutter::EncodableValue(*entries[at]->entryId);
            }
          };
          addKey("current", index);
          addKey("previous", index - 1);
          addKey("next", index + 1);
        }
        reply->Success(flutter::EncodableValue(state));
      });
      return;
    }

    // A bookmark owns its website history; never fall through to workspace
    // navigation when the renderer has no previous/next entry.
    if (method_name.compare(kMethodNavigateHistory) == 0) {
      const auto forward = std::get_if<bool>(method_call.arguments());
      if (!forward || !view) return result->Error(kErrorInvalidArgs);
      const bool available = *forward ? view->canGoForward() : view->canGoBack();
      if (available) {
        if (*forward) view->goForward();
        else view->goBack();
      }
      return result->Success(flutter::EncodableValue(available));
    }

    if (method_name == "querySiteGesturePolicy" || method_name == "querySiteGesturePolicyState") {
      const auto point = GetPointFromArgs(method_call.arguments());
      if (!point || !view) return result->Error(kErrorInvalidArgs);
      auto reply = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
      view->querySiteGesturePolicy(point->first, point->second,
        [reply, detailed = method_name == "querySiteGesturePolicyState"](TrackpadTouchQueue::PolicyResult policy) {
          if (!detailed) {
            if (policy.valid && policy.website) return reply->Success(flutter::EncodableValue(*policy.website));
            return reply->Success();
          }
          reply->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("status"), flutter::EncodableValue(
              !policy.valid ? "invalidated" : !policy.website ? "indeterminate" :
              *policy.website ? "site" : "browser")},
            {flutter::EncodableValue("epoch"), flutter::EncodableValue(static_cast<int64_t>(policy.epoch))} }));
        });
      return;
    }
    if (method_name == "siteGestureFallbackReady") {
      if (!method_call.arguments()) return result->Error(kErrorInvalidArgs);
      const auto epoch = GetTimestampFromArg(*method_call.arguments());
      if (!epoch || *epoch < 0 || !view) return result->Error(kErrorInvalidArgs);
      const auto ready = view->siteGestureFallbackReady(static_cast<uint64_t>(*epoch));
      if (ready) return result->Success(flutter::EncodableValue(*ready));
      return result->Success(); // Invalidated, not merely busy.
    }
    if (method_name == "cancelTrackpadGesture") {
      if (view) view->cancelTrackpadGesture();
      return result->Success();
    }

    // setCursorPos: [double x, double y]
    if (method_name.compare(kMethodSetCursorPos) == 0) {
      const auto point = GetPointFromArgs(method_call.arguments());
      if (point && view) {
        view->setCursorPos(point->first, point->second);
        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }

    // setPointerUpdate:
    // [int pointer, int event, double x, double y, double size, double pressure]
    // Trackpad only appends [int originalTimestampMicros, int knownInputAgeMicros]
    // and optionally [double secondX, double secondY] for an atomic contact pair.
    // Epoch-fenced recovery additionally appends [int inputEpoch] (9/11 values).
    if (method_name.compare(kMethodSetPointerUpdate) == 0) {
      const flutter::EncodableList* list =
        std::get_if<flutter::EncodableList>(method_call.arguments());
      if (!list || (list->size() != 6 && list->size() != 8 && list->size() != 9 &&
        list->size() != 10 && list->size() != 11)) {
        return result->Error(kErrorInvalidArgs);
      }

      const auto pointer = std::get_if<int32_t>(&(*list)[0]);
      const auto event = std::get_if<int32_t>(&(*list)[1]);
      const auto x = std::get_if<double>(&(*list)[2]);
      const auto y = std::get_if<double>(&(*list)[3]);
      const auto size = std::get_if<double>(&(*list)[4]);
      const auto pressure = std::get_if<double>(&(*list)[5]);
      std::optional<int64_t> sourceMicros;
      int64_t inputAgeMicros = 0;
      if (list->size() >= 8) {
        sourceMicros = GetTimestampFromArg((*list)[6]);
        const auto age = GetTimestampFromArg((*list)[7]);
        if (!sourceMicros || !age) return result->Error(kErrorInvalidArgs);
        inputAgeMicros = *age;
      }
      std::optional<std::pair<double, double>> second;
      if (list->size() >= 10) {
        const auto secondX = std::get_if<double>(&(*list)[8]);
        const auto secondY = std::get_if<double>(&(*list)[9]);
        if (!pointer || *pointer != 0x3ffffffe || !secondX || !secondY) {
          return result->Error(kErrorInvalidArgs);
        }
        second = std::make_pair(*secondX, *secondY);
      }
      std::optional<uint64_t> epoch;
      if (list->size() == 9 || list->size() == 11) {
        const auto value = GetTimestampFromArg(list->back());
        if (!pointer || *pointer != 0x3ffffffe || !value || *value < 0) {
          return result->Error(kErrorInvalidArgs);
        }
        epoch = static_cast<uint64_t>(*value);
      }

      if (pointer && event && x && y && size && pressure && view) {
        view->setPointerUpdate(*pointer,
          static_cast<flutter_inappwebview_plugin::InAppWebViewPointerEventKind>(*event),
          *x, *y, *size, *pressure, sourceMicros, inputAgeMicros, second, epoch);
        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }

    // setScrollDelta: [double dx, double dy]
    if (method_name.compare(kMethodSetScrollDelta) == 0) {
      const auto delta = GetPointFromArgs(method_call.arguments());
      if (delta && view) {
        view->setScrollDelta(delta->first, delta->second);
        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }

    // setZoomScale: double relative scale
    if (method_name.compare(kMethodSetZoomScale) == 0) {
      const auto scale = std::get_if<double>(method_call.arguments());
      if (scale && view) {
        view->setZoomScale(*scale);
        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }

    // setPointerButton: {"button": int, "isDown": bool}
    if (method_name.compare(kMethodSetPointerButton) == 0) {
      const auto& map = std::get<flutter::EncodableMap>(*method_call.arguments());

      const auto button = map.find(flutter::EncodableValue("button"));
      const auto isDown = map.find(flutter::EncodableValue("isDown"));
      if (button != map.end() && isDown != map.end()) {
        const auto buttonValue = std::get_if<int32_t>(&button->second);
        const auto isDownValue = std::get_if<bool>(&isDown->second);
        if (buttonValue && isDownValue && view) {
          view->setPointerButtonState(
            static_cast<flutter_inappwebview_plugin::InAppWebViewPointerButton>(*buttonValue), *isDownValue);
          return result->Success();
        }
      }
      return result->Error(kErrorInvalidArgs);
    }

    // setSize: [double width, double height, double scale_factor]
    if (method_name.compare(kMethodSetSize) == 0) {
      auto size = GetPointAndScaleFactorFromArgs(method_call.arguments());
      if (size && view) {
        const auto [width, height, scale_factor] = size.value();

        view->setSurfaceSize(static_cast<size_t>(width),
          static_cast<size_t>(height),
          static_cast<float>(scale_factor));

        texture_bridge_->Start();
        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }
    else if (method_name.compare(kMethodSetPosition) == 0) {
      auto position = GetPointAndScaleFactorFromArgs(method_call.arguments());
      if (position && view) {
        const auto [x, y, scale_factor] = position.value();

        view->setPosition(static_cast<size_t>(x),
          static_cast<size_t>(y),
          static_cast<float>(scale_factor));

        return result->Success();
      }
      return result->Error(kErrorInvalidArgs);
    }
    else if (method_name.compare(kMethodSetFpsLimit) == 0) {
      if (const auto value = std::get_if<int32_t>(method_call.arguments())) {
        texture_bridge_->SetFpsLimit(*value == 0 ? std::nullopt
          : std::make_optional(*value));
        return result->Success();
      }
    }

    result->NotImplemented();
  }
}