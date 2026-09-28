#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <utility>
#include <vector>

namespace flutter_inappwebview_plugin
{
  // Access and Detach must both run on the owning platform/dispatcher thread.
  // A queued delegate retains this target, never the raw owner's lifetime.
  template <typename Owner>
  class PlatformCallbackTarget {
  public:
    explicit PlatformCallbackTarget(Owner* owner) : owner_(owner) {}
    Owner* get() const { return owner_; }
    void Detach() { owner_ = nullptr; }
  private:
    Owner* owner_;
  };

  // Allocated only by the private fixture opt-in. No per-frame lifecycle hooks.
  using TextureLifecycleEvents = std::vector<int32_t>;
  inline void RecordTextureLifecycle(
    const std::shared_ptr<TextureLifecycleEvents>& events, int32_t stage)
  {
    if (events) events->push_back(stage);
  }

  // Flutter retains the variant's address and its raw bridge callback until
  // asynchronous unregister completes. All apartment-bound objects/callbacks
  // must already be detached on their owning thread before calling this helper.
  // Completion may run on another thread: retain no owner/manager/registrar here.
  template <typename Bridge, typename Texture, typename Unregister>
  void RetireTexture(std::unique_ptr<Bridge> bridge,
    std::unique_ptr<Texture> texture, Unregister unregister,
    std::function<void()> complete = nullptr,
    std::shared_ptr<TextureLifecycleEvents> events = nullptr)
  {
    struct Pending {
      std::unique_ptr<Bridge> bridge;
      std::unique_ptr<Texture> texture;
      std::function<void()> complete;
      std::shared_ptr<TextureLifecycleEvents> events;
      bool completed = false;

      void Complete()
      {
        // The registrar invokes this once. Also tolerate sequential copies of
        // the completion in deterministic fake-registrar tests.
        if (completed) return;
        completed = true;
        RecordTextureLifecycle(events, 4); // unregister completed
        texture.reset();
        bridge.reset();
        RecordTextureLifecycle(events, 5); // retained resources released
        auto reply = std::move(complete);
        if (reply) reply();
      }
    };
    auto pending = std::make_shared<Pending>();
    pending->bridge = std::move(bridge);
    pending->texture = std::move(texture);
    pending->complete = std::move(complete);
    pending->events = std::move(events);
    RecordTextureLifecycle(pending->events, 3); // unregister requested
    unregister([pending]() { pending->Complete(); });
  }
}