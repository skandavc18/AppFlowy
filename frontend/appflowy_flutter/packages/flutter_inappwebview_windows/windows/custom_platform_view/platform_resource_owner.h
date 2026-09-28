#pragma once

#include <cassert>
#include <memory>
#include <thread>

namespace flutter_inappwebview_plugin
{
  // Only live platform-thread managers own this group. The registry is weak:
  // no COM object survives until DLL_PROCESS_DETACH. Separate platform threads
  // must never share an apartment or its dispatcher/compositor.
  template <typename Runtime, typename Dispatcher, typename Graphics, typename Composition>
  class PlatformResourceOwner {
  private:
    const std::thread::id thread_ = std::this_thread::get_id();

  public:
    static std::shared_ptr<PlatformResourceOwner> Acquire()
    {
      static thread_local std::weak_ptr<PlatformResourceOwner> current;
      auto owner = current.lock();
      if (!owner) {
        owner = std::make_shared<PlatformResourceOwner>();
        current = owner;
      }
      return owner;
    }

    PlatformResourceOwner() = default;
    PlatformResourceOwner(const PlatformResourceOwner&) = delete;
    PlatformResourceOwner& operator=(const PlatformResourceOwner&) = delete;
    ~PlatformResourceOwner()
    {
      assert(thread_ == std::this_thread::get_id());
    }

    // C++ destroys members in reverse declaration order. Keep COM/composition
    // release before dispatcher release, RoUninitialize and FreeLibrary.
    Runtime runtime{};
    Dispatcher dispatcher{};
    Graphics graphics{};
    Composition composition{};
    bool valid = false;
  };
}