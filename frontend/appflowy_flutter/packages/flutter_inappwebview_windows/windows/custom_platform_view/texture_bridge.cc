#include "texture_bridge.h"

#include <windows.foundation.h>

#include <algorithm>
#include <atomic>
#include <cassert>
#include <iostream>

#include "util/direct3d11.interop.h"

namespace flutter_inappwebview_plugin
{
  // Two, so the next frame can be captured while the last one still waits for
  // the platform thread, which scrolling input keeps busy. With one, every
  // such wait cost a frame (measured: 24 fps delivered during wheel scrolling
  // of a page drawing at 111 fps).
  const int kNumBuffers = 2;

  // Windows otherwise captures at most every 1/60 s, below a faster display.
  // In 100 ns units: 1 ms leaves the display's own refresh as the limit.
  constexpr INT64 kMinUpdateInterval = 10000;

  TextureBridge::TextureBridge(GraphicsContext* graphics_context,
    ABI::Windows::UI::Composition::IVisual* visual)
    : graphics_context_(*graphics_context),
    capture_callback_target_(std::make_shared<PlatformCallbackTarget<TextureBridge>>(this))
  {
    capture_item_ =
      graphics_context_.CreateGraphicsCaptureItemFromVisual(visual);
    assert(capture_item_);

    capture_item_->add_Closed(
      Microsoft::WRL::Callback<ABI::Windows::Foundation::ITypedEventHandler<
      ABI::Windows::Graphics::Capture::GraphicsCaptureItem*,
      IInspectable*>>(
        [](ABI::Windows::Graphics::Capture::IGraphicsCaptureItem* item,
          IInspectable* args) -> HRESULT
        {
          std::cerr << "Capture item was closed." << std::endl;
          return S_OK;
        })
      .Get(),
          &on_closed_token_);
  }

  TextureBridge::~TextureBridge()
  {
    Shutdown();
  }

  void TextureBridge::Shutdown()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    // After explicit Shutdown, destruction may occur on the unregister thread.
    // Do not touch the platform-thread target or WinRT objects a second time.
    if (!capture_item_) {
      graphics_context_.DetachFactories();
      return;
    }
    capture_callback_target_->Detach();
    frame_available_ = nullptr;
    surface_size_changed_ = nullptr;
    StopInternal();
    capture_item_->remove_Closed(on_closed_token_);
    capture_item_ = nullptr;
    graphics_context_.DetachFactories();
  }

  bool TextureBridge::Start()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (is_running_ || !capture_item_) {
      return false;
    }

    ABI::Windows::Graphics::SizeInt32 size;
    capture_item_->get_Size(&size);

    frame_pool_ = graphics_context_.CreateCaptureFramePool(
      graphics_context_.device(),
      static_cast<ABI::Windows::Graphics::DirectX::DirectXPixelFormat>(
        kPixelFormat),
      kNumBuffers, size);
    assert(frame_pool_);

    frame_pool_->add_FrameArrived(
      Microsoft::WRL::Callback<ABI::Windows::Foundation::ITypedEventHandler<
      ABI::Windows::Graphics::Capture::Direct3D11CaptureFramePool*,
      IInspectable*>>(
        [target = capture_callback_target_](ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool*
          pool,
          IInspectable* args) -> HRESULT
        {
          if (auto bridge = target->get()) bridge->OnFrameArrived();
          return S_OK;
        })
      .Get(),
          &on_frame_arrived_token_);

    if (FAILED(frame_pool_->CreateCaptureSession(capture_item_.get(),
      capture_session_.put()))) {
      std::cerr << "Creating capture session failed." << std::endl;
      return false;
    }

#if defined(____x_ABI_CWindows_CGraphics_CCapture_CIGraphicsCaptureSession5_INTERFACE_DEFINED__)
    // Windows 11 24H2 and later; older systems keep their 60 fps capture.
    if (auto session5 = capture_session_.try_as<
      ABI::Windows::Graphics::Capture::IGraphicsCaptureSession5>()) {
      ABI::Windows::Foundation::TimeSpan interval{};
      interval.Duration = kMinUpdateInterval;
      session5->put_MinUpdateInterval(interval);
    }
#endif

    if (SUCCEEDED(capture_session_->StartCapture())) {
      is_running_ = true;
      return true;
    }

    return false;
  }

  void TextureBridge::Stop()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    StopInternal();
  }

  void TextureBridge::StopInternal()
  {
    is_running_ = false;
    // Also retire a partially started capture session. Keep all WinRT Close
    // and event unsubscription on the same dispatcher that created the pool.
    if (frame_pool_) {
      frame_pool_->remove_FrameArrived(on_frame_arrived_token_);
    }
    if (capture_session_) {
      auto closable =
        capture_session_.try_as<ABI::Windows::Foundation::IClosable>();
      assert(closable);
      closable->Close();
      capture_session_ = nullptr;
    }
    if (frame_pool_) {
      auto closable = frame_pool_.try_as<ABI::Windows::Foundation::IClosable>();
      if (closable) closable->Close();
      frame_pool_ = nullptr;
    }
  }

  void TextureBridge::OnFrameArrived()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (!is_running_) {
      return;
    }

    cadence_probe_.Record(TextureCadenceProbe::Kind::Arrival);
    bool has_frame = false;

    winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFrame>
      frame;
    auto hr = frame_pool_->TryGetNextFrame(frame.put());
    if (SUCCEEDED(hr) && frame) {
      winrt::com_ptr<
        ABI::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface>
        frame_surface;

      if (SUCCEEDED(frame->get_Surface(frame_surface.put()))) {
        last_frame_ =
          TryGetDXGIInterfaceFromObject<ID3D11Texture2D>(frame_surface);
        if (last_frame_) cadence_probe_.Record(TextureCadenceProbe::Kind::Capture);
        has_frame = !ShouldDropFrame();
        if (!has_frame) cadence_probe_.Record(TextureCadenceProbe::Kind::CapDrop);
      }
    }

    if (needs_update_) {
      cadence_probe_.Record(TextureCadenceProbe::Kind::Resize);
      ABI::Windows::Graphics::SizeInt32 size;
      capture_item_->get_Size(&size);
      frame_pool_->Recreate(
        graphics_context_.device(),
        static_cast<ABI::Windows::Graphics::DirectX::DirectXPixelFormat>(
          kPixelFormat),
        kNumBuffers, size);
      needs_update_ = false;
    }

    if (has_frame && frame_available_) {
      cadence_probe_.Record(TextureCadenceProbe::Kind::Notify);
      frame_available_();
    }
  }

  void TextureBridge::StartCadenceProbe()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    cadence_probe_.Start();
  }

  TextureCadenceProbe::Snapshot TextureBridge::StopCadenceProbe()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    auto snapshot = cadence_probe_.Stop();
    snapshot.limit_ms = frame_duration_ ? frame_duration_->count() : 0;
    return snapshot;
  }

  bool TextureBridge::ShouldDropFrame()
  {
    if (!frame_duration_.has_value()) {
      return false;
    }
    auto now = std::chrono::high_resolution_clock::now();

    bool should_drop_frame = false;
    if (last_frame_timestamp_.has_value()) {
      auto diff = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_frame_timestamp_.value());
      should_drop_frame = diff < frame_duration_.value();
    }

    if (!should_drop_frame) {
      last_frame_timestamp_ = now;
    }
    return should_drop_frame;
  }

  void TextureBridge::NotifySurfaceSizeChanged()
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    needs_update_ = true;
  }

  void TextureBridge::SetFpsLimit(std::optional<int> max_fps)
  {
    const std::lock_guard<std::mutex> lock(mutex_);
    auto value = max_fps.value_or(0);
    if (value != 0) {
      frame_duration_ = FrameDuration(1000.0 / value);
    }
    else {
      frame_duration_.reset();
      last_frame_timestamp_.reset();
    }
  }
}