#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_PENDING_WINDOW_REQUEST_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_PENDING_WINDOW_REQUEST_H_

#include <functional>
#include <utility>

namespace flutter_inappwebview_plugin
{
  // The production COM adapter and native fixture share this terminal owner.
  // Callbacks must not throw. Mark terminal BEFORE calling into a reentrant API.
  template<class Target>
  class PendingWindowRequest
  {
  public:
    const void* const owner;
    PendingWindowRequest(const void* owner, std::function<bool(Target)> adopt,
      std::function<bool()> handled, std::function<bool()> complete)
      : owner(owner), adopt_(std::move(adopt)), handled_(std::move(handled)),
      complete_(std::move(complete)) {}
    PendingWindowRequest(const PendingWindowRequest&) = delete;
    PendingWindowRequest& operator=(const PendingWindowRequest&) = delete;
    ~PendingWindowRequest() { finish(); }

    bool finish(Target child = nullptr)
    {
      if (finished_) return false;
      finished_ = true;
      bool success = true;
      if (child) success = adopt_(child);
      const bool handled = handled_();
      const bool completed = complete_(); // Even a failed put must release deferral.
      adopt_ = nullptr;
      handled_ = complete_ = nullptr;
      return success && handled && completed;
    }
  private:
    bool finished_ = false;
    std::function<bool(Target)> adopt_;
    std::function<bool()> handled_;
    std::function<bool()> complete_;
  };

  // Remove BEFORE completing: reentrant/duplicate replies cannot navigate or
  // complete again. An opener controller may only reject its own requests.
  template<class Map, class Key>
  typename Map::mapped_type takePendingWindow(Map& pending, const Key& id,
    const void* owner = nullptr)
  {
    const auto found = pending.find(id);
    if (found == pending.end() || (owner && found->second->owner != owner)) return nullptr;
    auto request = std::move(found->second);
    pending.erase(found);
    return request;
  }
}
#endif