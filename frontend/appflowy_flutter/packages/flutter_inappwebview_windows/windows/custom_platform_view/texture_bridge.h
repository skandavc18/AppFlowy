#pragma once

#include <windows.graphics.capture.h>
#include <wrl.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>

#include "graphics_context.h"
#include "texture_cadence_probe.h"
#include "texture_retirement.h"

namespace flutter_inappwebview_plugin
{
  typedef struct {
    size_t width;
    size_t height;
  } Size;

  class TextureBridge {
  public:
    typedef std::function<void()> FrameAvailableCallback;
    typedef std::function<void(Size size)> SurfaceSizeChangedCallback;
    typedef std::chrono::duration<double, std::milli> FrameDuration;

    TextureBridge(GraphicsContext* graphics_context,
      ABI::Windows::UI::Composition::IVisual* visual);
    virtual ~TextureBridge();

    bool Start();
    void Stop();
    // Permanent teardown on the owning platform thread, before unregister.
    void Shutdown();

    void SetOnFrameAvailable(FrameAvailableCallback callback)
    {
      frame_available_ = std::move(callback);
    }

    void SetOnSurfaceSizeChanged(SurfaceSizeChangedCallback callback)
    {
      surface_size_changed_ = std::move(callback);
    }

    void NotifySurfaceSizeChanged();
    void SetFpsLimit(std::optional<int> max_fps);

    void StartCadenceProbe();
    TextureCadenceProbe::Snapshot StopCadenceProbe();

  protected:
    bool is_running_ = false;
    TextureCadenceProbe cadence_probe_;

    // Copy GPU references, not the manager's lifetime. Shutdown removes factory
    // access before this copy can be retired on a different thread.
    GraphicsContext graphics_context_;
    std::shared_ptr<PlatformCallbackTarget<TextureBridge>> capture_callback_target_;
    std::mutex mutex_;
    std::optional<FrameDuration> frame_duration_ = std::nullopt;

    FrameAvailableCallback frame_available_;
    SurfaceSizeChangedCallback surface_size_changed_;
    std::atomic<bool> needs_update_ = false;
    winrt::com_ptr<ID3D11Texture2D> last_frame_;
    std::optional<std::chrono::high_resolution_clock::time_point>
      last_frame_timestamp_;

    winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>
      capture_item_;
    winrt::com_ptr<ABI::Windows::Graphics::Capture::IDirect3D11CaptureFramePool>
      frame_pool_;
    winrt::com_ptr<ABI::Windows::Graphics::Capture::IGraphicsCaptureSession>
      capture_session_;

    EventRegistrationToken on_closed_token_ = {};
    EventRegistrationToken on_frame_arrived_token_ = {};

    virtual void StopInternal();
    void OnFrameArrived();
    bool ShouldDropFrame();

    // corresponds to DXGI_FORMAT_B8G8R8A8_UNORM
    static constexpr auto kPixelFormat = ABI::Windows::Graphics::DirectX::
      DirectXPixelFormat::DirectXPixelFormat_B8G8R8A8UIntNormalized;
  };
}