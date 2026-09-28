#include "../in_app_webview/trackpad_touch_queue.h"
#include "../in_app_webview/site_gesture_policy.h"
#include <stdexcept>
#include <vector>

using namespace flutter_inappwebview_plugin;
using namespace std::chrono_literals;
using Kind = TrackpadTouchKind;
namespace {
  void check(bool value) { if (!value) throw std::runtime_error("unknown recovery regression"); }
  struct Fixture {
    TrackpadTouchQueue::Clock::time_point now{1000s};
    TrackpadTouchQueue::PolicyCompletion policy;
    TrackpadTouchQueue::Completion touch;
    std::vector<nlohmann::json> sent;
    TrackpadTouchQueue::PolicyResult result{std::nullopt, false, 0};
    std::shared_ptr<TrackpadTouchQueue> queue = std::make_shared<TrackpadTouchQueue>(
      [this](const std::string& json, auto reply) {
        check(!policy && !touch); sent.push_back(nlohmann::json::parse(json)); touch = reply;
      }, [this] { return now; }, 1700000000.0,
      [this](const std::string&, auto reply) { check(!policy && !touch); policy = reply; });
    void query() { queue->queryPolicyState("{}", [this](auto value) { result = value; }); }
    void completePolicy(std::optional<bool> value) { auto reply = std::exchange(policy, nullptr); reply(value); }
    void ack() { auto reply = std::exchange(touch, nullptr); reply(true); }
    bool sample(Kind kind, int64_t time, double y, uint64_t epoch) {
      return queue->enqueue(kind, time, 100, y, 1, 0, std::nullopt, epoch);
    }
  };
}
int main() {
  {
    Fixture f; f.query();
    const auto duplicate = f.policy;
    f.now += 600ms; // Dart's 150ms deadline cannot clear this actual slot.
    for (int i = 0; i < 1000; ++i) {
      f.query(); // Busy returns immediately; it does not issue another CDP call.
      check(f.result.valid && !f.result.website);
      check(f.queue->fallbackReady(f.result.epoch) == false);
      check(f.queue->inFlight() && f.queue->pendingCount() == 0);
    }
    f.completePolicy(false); // Aged result cannot authorize browser/history.
    check(f.result.valid && !f.result.website);
    check(f.queue->fallbackReady(f.result.epoch) == true);
    check(f.sample(Kind::Start, 8000000, 100, f.result.epoch));
    duplicate(true); // Must not free the new touch slot.
    check(f.queue->inFlight()); f.ack();
    f.now += 10ms; check(f.sample(Kind::Move, 8010000, 80, f.result.epoch)); f.ack();
    f.now += 10ms; check(f.sample(Kind::End, 8020000, 80, f.result.epoch)); f.ack();
    check(f.sent.size() == 3 && f.sent.back()["type"] == "touchEnd");
    check(std::abs(f.sent.front()["timestamp"].get<double>() - 1700000000.6) < .000001);
  }
  for (bool closed : {false, true}) {
    Fixture f; f.query();
    if (closed) f.queue->close(); else f.queue->cancel();
    f.completePolicy(std::nullopt);
    check(!f.result.valid && !f.queue->fallbackReady(f.result.epoch));
    check(!f.sample(Kind::Start, 0, 100, f.result.epoch));
    check(f.sent.empty());
  }
  {
    Fixture f; f.query(); f.completePolicy(std::nullopt);
    const auto oldEpoch = f.result.epoch;
    check(f.queue->fallbackReady(oldEpoch) == true);
    f.queue->cancel(); // Navigation AFTER readiness but BEFORE Dart Start.
    check(!f.sample(Kind::Start, 0, 100, oldEpoch));
    f.query(); f.completePolicy(std::nullopt);
    check(f.sample(Kind::Start, 0, 100, f.result.epoch)); f.ack();
    check(!f.sample(Kind::Cancel, 0, 100, oldEpoch));
    f.now += 10ms; check(f.sample(Kind::Move, 10000, 80, f.result.epoch)); f.ack();
    check(f.sent.size() == 2); // Stale cancel did not cancel the new page.
  }
  check(nlohmann::json::parse(siteGesturePolicyParameters(20, 30))["timeout"] == 50);
}