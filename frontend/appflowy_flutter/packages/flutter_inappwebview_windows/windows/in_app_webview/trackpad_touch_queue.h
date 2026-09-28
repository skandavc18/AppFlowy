#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_TRACKPAD_TOUCH_QUEUE_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_TRACKPAD_TOUCH_QUEUE_H_

#include <chrono>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <nlohmann/json.hpp>

namespace flutter_inappwebview_plugin
{
  enum class TrackpadTouchKind { Start, Move, End, Cancel };

  // No HWND, Flutter engine, or WebView2 dependency: the production transport
  // and the offline delayed-callback fixture use this exact queue/serializer.
  // Call on the host thread. A completion owns the queue, never its view.
  class TrackpadTouchQueue : public std::enable_shared_from_this<TrackpadTouchQueue>
  {
  public:
    using Clock = std::chrono::steady_clock;
    using Now = std::function<Clock::time_point()>;
    using Completion = std::function<void(bool)>;
    using Send = std::function<void(const std::string&, Completion)>;
    using PolicyCompletion = std::function<void(std::optional<bool>)>;
    using PolicySend = std::function<void(const std::string&, PolicyCompletion)>;

    struct PolicyResult {
      std::optional<bool> website;
      bool valid;
      uint64_t epoch;
    };
    using PolicyStateCompletion = std::function<void(PolicyResult)>;

    struct Contact { double x; double y; };

    // A delivery deadline, not a gain/velocity/animation setting. In particular,
    // an old touchEnd must not initiate a new fling after a cold renderer stall.
    static constexpr auto maxInputAge = std::chrono::milliseconds(250);

    explicit TrackpadTouchQueue(Send send,
      Now now = [] { return std::chrono::steady_clock::now(); },
      double epochSeconds = std::chrono::duration<double>(
        std::chrono::system_clock::now().time_since_epoch()).count(),
      PolicySend policySend = nullptr)
      : send_(std::move(send)), now_(std::move(now)),
      epochOrigin_(now_()), epochSeconds_(epochSeconds), policySend_(std::move(policySend)) {}

    // Legacy optional-bool helper retained for callers which cannot recover.
    void queryPolicy(const std::string& payload, PolicyCompletion reply)
    {
      queryPolicyState(payload, [reply](PolicyResult result) {
        reply(result.valid ? result.website : std::nullopt);
      });
    }

    // Indeterminate (busy/failed/aged) is NOT invalidated (cancel/navigation/
    // detach/close). Only the former can recover on fresh samples in this epoch.
    void queryPolicyState(const std::string& payload, PolicyStateCompletion reply)
    {
      if (closed_ || inFlight_ || policyFlight_ || cancelPending_ ||
        !pending_.empty() || !policySend_ || contactMayBeActive_) {
        reply({ std::nullopt, !closed_, inputEpoch_ });
        return;
      }
      const auto token = ++token_;
      const auto epoch = inputEpoch_;
      const auto started = now_();
      policyFlight_ = token;
      const auto self = shared_from_this();
      const auto send = policySend_;
      send(payload, [self, token, epoch, started, reply](std::optional<bool> value) {
        if (self->policyFlight_ != token) return;
        self->policyFlight_.reset();
        const bool valid = !self->closed_ && self->inputEpoch_ == epoch;
        const bool fresh = self->now_() - started <= maxInputAge;
        reply({ valid && fresh ? value : std::nullopt, valid, epoch });
        self->sendNext();
      });
    }

    // Host-thread state read only: never issues CDP or releases a slot.
    std::optional<bool> fallbackReady(uint64_t epoch) const
    {
      if (closed_ || inputEpoch_ != epoch) return std::nullopt;
      return !inFlight() && pending_.empty() && !cancelPending_ && !contactMayBeActive_;
    }

    bool enqueue(TrackpadTouchKind kind, int64_t sourceMicros,
      double x, double y, double pressure, int64_t inputAgeMicros = 0,
      std::optional<Contact> second = std::nullopt,
      std::optional<uint64_t> expectedEpoch = std::nullopt)
    {
      // A late recovery Start must not become a fresh gesture on another page.
      // Stale terminal packets must not cancel a newer owner's contact either.
      if (closed_ || (expectedEpoch && *expectedEpoch != inputEpoch_)) return false;
      if (kind == TrackpadTouchKind::Cancel) {
        cancel();
        return true;
      }
      const auto now = now_();
      if (sourceMicros < 0 || inputAgeMicros < 0 ||
        std::chrono::microseconds(inputAgeMicros) > maxInputAge ||
        !std::isfinite(x) || !std::isfinite(y) ||
        (second && (!std::isfinite(second->x) || !std::isfinite(second->y))) ||
        !std::isfinite(pressure) || pressure < 0.0 || pressure > 1.0) {
        cancel();
        return false;
      }

      if (kind == TrackpadTouchKind::Start) {
        // A contact-count transition is a new DOM stream, not a new clock.
        // Preserve the last actual sample time despite channel/callback delay.
        std::optional<Clock::time_point> continuedOrigin;
        if (gesture_ && !gesture_->ended && gesture_->twoContacts != second.has_value()) {
          const auto elapsed = sourceMicros - gesture_->firstSourceMicros;
          const auto allowed = std::chrono::duration_cast<std::chrono::microseconds>(
            now - gesture_->origin + maxInputAge).count();
          if (elapsed < 0 || elapsed > allowed) {
            cancel();
            return false;
          }
          continuedOrigin = gesture_->origin + std::chrono::microseconds(elapsed);
        }
        invalidateGesture();
        // Pair two origins ONCE per gesture. Flutter's timestamp is NOT an
        // epoch or a host steady_clock value. The known age includes the time
        // spent classifying a bookmark's initially undecided history gesture.
        const auto origin = continuedOrigin.value_or(now - std::chrono::microseconds(inputAgeMicros));
        if (lastSentTime_ && origin < *lastSentTime_) {
          sendNext();
          return false;
        }
        gesture_ = Gesture{ ++generation_, sourceMicros, sourceMicros, origin, false,
          second.has_value(), x, y, 0.0 };
      }
      else if (!gesture_ || gesture_->ended) {
        return false; // A cancelled gesture cannot restart itself with a move.
      }

      auto& gesture = *gesture_;
      if (kind == TrackpadTouchKind::Move && gesture.twoContacts != second.has_value()) {
        cancel();
        return false; // A new Start must cancel/fence a change of contact count.
      }
      if (kind == TrackpadTouchKind::Move) {
        const auto dx = x - gesture.startX;
        const auto dy = y - gesture.startY;
        gesture.travelSquared = (std::max)(gesture.travelSquared, dx * dx + dy * dy);
      }
      if (kind == TrackpadTouchKind::End && !gesture.twoContacts && gesture.travelSquared < 64.0) {
        // CSS pixels: also protects zoomed pages and clamped viewport edges.
        // A trackpad gesture is never an emulated tap/click.
        cancel();
        return true;
      }
      if (sourceMicros < gesture.lastSourceMicros ||
        (kind == TrackpadTouchKind::Move && sourceMicros == gesture.lastSourceMicros)) {
        cancel();
        return false; // Never manufacture a new time for an invalid sample.
      }
      const auto elapsedMicros = sourceMicros - gesture.firstSourceMicros;
      // Bounded tolerance for a batch delivered faster than it was generated.
      // Compare in microseconds BEFORE chrono promotes to nanoseconds: an
      // invalid int64 timestamp could overflow during that promotion itself.
      const auto allowedMicros = std::chrono::duration_cast<std::chrono::microseconds>(
        now - gesture.origin + maxInputAge).count();
      if (now < gesture.origin || elapsedMicros > allowedMicros) {
        cancel();
        return false;
      }
      const auto sampleTime = gesture.origin + std::chrono::microseconds(elapsedMicros);
      Event event{ kind, gesture.id, now, sampleTime, epochAt(sampleTime), x, y, pressure, second };
      if (expired(event, now)) {
        cancel();
        return false;
      }
      gesture.lastSourceMicros = sourceMicros;
      gesture.ended = kind == TrackpadTouchKind::End;

      if (!pending_.empty() && pending_.back().kind == TrackpadTouchKind::Move &&
        kind == TrackpadTouchKind::Move && pending_.back().gesture == event.gesture) {
        // Absolute position AND its original time travel together. Keeping the
        // old time here would itself create an artificial velocity spike.
        pending_.back() = event;
      }
      else {
        pending_.push_back(event);
      }
      sendNext();
      return true;
    }

    void cancel()
    {
      if (closed_) return;
      ++inputEpoch_;
      invalidateGesture();
      sendNext();
    }

    void close()
    {
      ++inputEpoch_;
      closed_ = true;
      pending_.clear();
      gesture_.reset();
      cancelPending_ = false;
      send_ = nullptr;
      policySend_ = nullptr;
      // Do not pretend an outstanding call has completed. Its callback may
      // still arrive, but can only release its slot and its shared ownership.
    }

    size_t pendingCount() const { return pending_.size() + (cancelPending_ ? 1 : 0); }
    bool inFlight() const { return inFlight_.has_value() || policyFlight_.has_value(); }
    bool closed() const { return closed_; }

  private:
    struct Gesture {
      uint64_t id;
      int64_t firstSourceMicros;
      int64_t lastSourceMicros;
      Clock::time_point origin;
      bool ended;
      bool twoContacts;
      double startX;
      double startY;
      double travelSquared;
    };

    struct Event {
      TrackpadTouchKind kind;
      uint64_t gesture;
      Clock::time_point arrival;
      Clock::time_point sampleTime;
      double timestamp;
      double x;
      double y;
      double pressure;
      std::optional<Contact> second;

      std::string serialize() const
      {
        const char* type = kind == TrackpadTouchKind::Start ? "touchStart"
          : kind == TrackpadTouchKind::Move ? "touchMove"
          : kind == TrackpadTouchKind::End ? "touchEnd" : "touchCancel";
        auto points = nlohmann::json::array();
        if (kind == TrackpadTouchKind::Start || kind == TrackpadTouchKind::Move) {
          points.push_back({ {"id", 0}, {"x", x}, {"y", y},
            {"radiusX", 1}, {"radiusY", 1}, {"force", pressure} });
          if (second) points.push_back({ {"id", 1}, {"x", second->x}, {"y", second->y},
            {"radiusX", 1}, {"radiusY", 1}, {"force", pressure} });
        }
        return nlohmann::json{ {"type", type}, {"touchPoints", points},
          {"timestamp", timestamp} }.dump();
      }
    };

    struct Flight {
      Event event;
      uint64_t token;
    };

    Send send_;
    Now now_;
    const Clock::time_point epochOrigin_;
    const double epochSeconds_;
    PolicySend policySend_;
    std::optional<uint64_t> policyFlight_;
    std::optional<Gesture> gesture_;
    std::deque<Event> pending_;
    std::optional<Flight> inFlight_;
    std::optional<Clock::time_point> lastSentTime_;
    uint64_t generation_ = 0;
    uint64_t inputEpoch_ = 0;
    uint64_t token_ = 0;
    bool contactMayBeActive_ = false;
    bool dispatchedPair_ = false;
    double dispatchedStartX_ = 0.0;
    double dispatchedStartY_ = 0.0;
    double dispatchedTravelSquared_ = 0.0;
    bool cancelPending_ = false;
    bool closed_ = false;

    double epochAt(Clock::time_point time) const
    {
      return epochSeconds_ + std::chrono::duration<double>(time - epochOrigin_).count();
    }

    static bool expired(const Event& event, Clock::time_point now)
    {
      // Residence catches an old queued start even when newer moves are fresh.
      // Paired sample age catches late host arrival even with zero residence.
      return now - event.arrival > maxInputAge || now - event.sampleTime > maxInputAge;
    }

    void invalidateGesture()
    {
      ++generation_;
      pending_.clear();
      gesture_.reset();
      if (contactMayBeActive_ &&
        (!inFlight_ || inFlight_->event.kind != TrackpadTouchKind::Cancel)) {
        cancelPending_ = true;
      }
    }

    void sendNext()
    {
      if (closed_ || inFlight_ || policyFlight_) return;
      const auto now = now_();
      if (!cancelPending_ && !pending_.empty() && expired(pending_.front(), now)) {
        invalidateGesture();
      }
      if (!cancelPending_ && pending_.empty()) return;

      // The cancel is an ordering fence for the old contact, not a sampled
      // release. Its last dispatched time cannot overtake a new queued start.
      Event event{ TrackpadTouchKind::Cancel, 0, now,
        lastSentTime_.value_or(now), epochAt(lastSentTime_.value_or(now)), 0, 0, 0, std::nullopt };
      if (cancelPending_) {
        cancelPending_ = false;
      }
      else {
        event = pending_.front();
        pending_.pop_front();
      }
      if (event.kind == TrackpadTouchKind::Start) {
        dispatchedPair_ = event.second.has_value();
        dispatchedStartX_ = event.x;
        dispatchedStartY_ = event.y;
        dispatchedTravelSquared_ = 0.0;
      }
      else if (event.kind == TrackpadTouchKind::Move) {
        const auto dx = event.x - dispatchedStartX_;
        const auto dy = event.y - dispatchedStartY_;
        dispatchedTravelSquared_ = (std::max)(dispatchedTravelSquared_, dx * dx + dy * dy);
      }
      else if (event.kind == TrackpadTouchKind::End && !dispatchedPair_ &&
        dispatchedTravelSquared_ < 64.0) {
        // Coalescing may erase an out-and-back excursion. Judge tap safety
        // using what Chromium actually received, not only enqueued movement.
        event.kind = TrackpadTouchKind::Cancel;
      }
      const auto token = ++token_;
      inFlight_ = Flight{ event, token };
      lastSentTime_ = event.sampleTime;
      if (event.kind == TrackpadTouchKind::Start) contactMayBeActive_ = true;
      const auto self = shared_from_this();
      const auto send = send_; // Safe even if an inline callback closes us.
      send(event.serialize(), [self, token](bool success) { self->complete(token, success); });
    }

    void complete(uint64_t token, bool success)
    {
      // A failed API call and its late callback must not free a newer slot.
      if (!inFlight_ || inFlight_->token != token) return;
      const auto event = inFlight_->event;
      inFlight_.reset();
      if (closed_) return;
      const bool terminal = event.kind == TrackpadTouchKind::End ||
        event.kind == TrackpadTouchKind::Cancel;
      if (success && terminal) {
        contactMayBeActive_ = false;
        cancelPending_ = false;
      }
      if (!success) {
        if (event.kind == TrackpadTouchKind::Cancel) {
          // Unknown contact state: fail closed, not an unbounded retry loop or
          // a new contact interleaved with the one Chromium failed to cancel.
          close();
          return;
        }
        invalidateGesture();
      }
      else if (!terminal && expired(event, now_()) && gesture_ &&
        gesture_->id == event.gesture) {
        // A slow in-flight start/move invalidates the whole gesture, including
        // a recently coalesced move/end. Never catch up with a huge old drag.
        invalidateGesture();
      }
      sendNext();
    }
  };
}
#endif // FLUTTER_INAPPWEBVIEW_PLUGIN_TRACKPAD_TOUCH_QUEUE_H_