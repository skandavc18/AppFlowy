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
      graphics_context, webview_->surface());

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
    if (history_handlers_registered_ && view && view->webView) {
      view->webView->remove_HistoryChanged(history_changed_token_);
      view->webView->remove_NavigationStarting(navigation_starting_token_);
      view->webView->remove_NavigationCompleted(navigation_completed_token_);
    }
    event_sink_ = nullptr;
    texture_registrar_->UnregisterTexture(texture_id_, nullptr);
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
    if (method_name.compare(kMethodSetPointerUpdate) == 0) {
      const flutter::EncodableList* list =
        std::get_if<flutter::EncodableList>(method_call.arguments());
      if (!list || list->size() != 6) {
        return result->Error(kErrorInvalidArgs);
      }

      const auto pointer = std::get_if<int32_t>(&(*list)[0]);
      const auto event = std::get_if<int32_t>(&(*list)[1]);
      const auto x = std::get_if<double>(&(*list)[2]);
      const auto y = std::get_if<double>(&(*list)[3]);
      const auto size = std::get_if<double>(&(*list)[4]);
      const auto pressure = std::get_if<double>(&(*list)[5]);

      if (pointer && event && x && y && size && pressure && view) {
        view->setPointerUpdate(*pointer,
          static_cast<flutter_inappwebview_plugin::InAppWebViewPointerEventKind>(*event),
          *x, *y, *size, *pressure);
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