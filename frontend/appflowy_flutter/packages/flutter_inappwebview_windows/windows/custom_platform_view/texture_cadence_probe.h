#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <utility>
#include <vector>

namespace flutter_inappwebview_plugin
{
  // Test-only, explicitly armed per texture. The bridge mutex owns all access.
  // No timer, logging, pixel inspection, allocation or clock read when disarmed.
  // Records callback delivery, NOT GPU completion or monitor presentation.
  class TextureCadenceProbe {
  public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    enum class Kind { Arrival, Capture, CapDrop, Notify, GpuCallback, CpuCallback, Resize };
    struct Event {
      Kind kind;
      double milliseconds;
      int64_t sequence;
      double work_milliseconds;
    };
    struct Snapshot {
      std::vector<Event> events;
      double elapsed_ms = 0;
      double limit_ms = 0;
      bool expired = false;
      bool truncated = false;
    };
    static constexpr size_t kMaxEvents = 8192;
    static constexpr auto kMaxDuration = std::chrono::seconds(12);

    void Start(TimePoint now = Clock::now())
    {
      snapshot_ = {};
      snapshot_.events.reserve(kMaxEvents);
      origin_ = now;
      sequence_ = 0;
      active_ = true;
    }

    void Record(Kind kind)
    {
      if (active_) Record(kind, Clock::now());
    }

    // Explicit time overload supports deterministic fake-clock tests.
    void Record(Kind kind, TimePoint now, double work_ms = 0)
    {
      if (!Accept(now)) return;
      if (kind == Kind::Capture) ++sequence_;
      snapshot_.events.push_back({ kind, Milliseconds(now - origin_), sequence_, work_ms });
      if (snapshot_.events.size() == kMaxEvents) {
        snapshot_.truncated = true;
        active_ = false;
        snapshot_.elapsed_ms = Milliseconds(now - origin_);
      }
    }

    std::optional<TimePoint> BeginWork()
    {
      if (!active_) return std::nullopt;
      const auto now = Clock::now();
      return Accept(now) ? std::make_optional(now) : std::nullopt;
    }

    void EndWork(Kind kind, std::optional<TimePoint> start)
    {
      if (!start || !active_) return;
      const auto now = Clock::now();
      Record(kind, now, Milliseconds(now - *start));
    }

    Snapshot Stop(TimePoint now = Clock::now())
    {
      if (active_ && Accept(now)) snapshot_.elapsed_ms = Milliseconds(now - origin_);
      active_ = false;
      auto result = std::move(snapshot_);
      snapshot_ = {};
      return result;
    }

  private:
    template <typename Duration>
    static double Milliseconds(Duration duration)
    {
      return std::chrono::duration<double, std::milli>(duration).count();
    }

    bool Accept(TimePoint now)
    {
      if (!active_) return false;
      if (now - origin_ >= kMaxDuration) {
        snapshot_.expired = true;
        snapshot_.elapsed_ms = Milliseconds(kMaxDuration);
        active_ = false;
        return false;
      }
      return true;
    }

    bool active_ = false;
    TimePoint origin_{};
    int64_t sequence_ = 0;
    Snapshot snapshot_;
  };
}