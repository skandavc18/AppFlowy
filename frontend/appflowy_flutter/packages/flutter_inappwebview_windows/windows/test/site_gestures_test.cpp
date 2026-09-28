#include "../in_app_webview/trackpad_touch_queue.h"
#include "../in_app_webview/site_gesture_policy.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace flutter_inappwebview_plugin;
using namespace std::chrono_literals;
using Kind = TrackpadTouchKind;

namespace {
  void check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
  }
  void near(double actual, double expected) {
    check(std::abs(actual - expected) < 0.000001, "timestamp/contact changed");
  }
  struct Harness {
    TrackpadTouchQueue::Clock::time_point now{1000s};
    std::vector<nlohmann::json> sent;
    TrackpadTouchQueue::Completion touchReply;
    TrackpadTouchQueue::PolicyCompletion policyReply;
    std::shared_ptr<TrackpadTouchQueue> queue = std::make_shared<TrackpadTouchQueue>(
      [this](const std::string& json, TrackpadTouchQueue::Completion reply) {
        check(!touchReply && !policyReply, "overlapping CDP calls");
        sent.push_back(nlohmann::json::parse(json)); touchReply = std::move(reply);
      }, [this] { return now; }, 1700000000.0,
      [this](const std::string&, TrackpadTouchQueue::PolicyCompletion reply) {
        check(!touchReply && !policyReply, "overlapping policy and touch");
        policyReply = std::move(reply);
      });
    void at(std::chrono::microseconds time) { now = TrackpadTouchQueue::Clock::time_point(1000s + time); }
    void touch(bool success = true) {
      check(static_cast<bool>(touchReply), "no touch to complete");
      auto reply = std::exchange(touchReply, nullptr); reply(success);
    }
    void policy(std::optional<bool> value) {
      check(static_cast<bool>(policyReply), "no query to complete");
      auto reply = std::exchange(policyReply, nullptr); reply(value);
    }
    void drain() {
      for (int i = 0; touchReply && i < 10; ++i) touch();
      check(!touchReply, "unbounded native work");
    }
    bool pair(Kind kind, int64_t time, double radius, int64_t age = 0) {
      return queue->enqueue(kind, time, 100, 100 - radius, 1, age,
        TrackpadTouchQueue::Contact{100, 100 + radius});
    }
  };

  void twoContactsCoalesceTogether() {
    Harness h;
    check(h.pair(Kind::Start, 9000000000000000LL, 24), "pair rejected");
    for (int i = 1; i <= 1000; ++i) {
      h.at(std::chrono::microseconds(i * 100));
      check(h.pair(Kind::Move, 9000000000000000LL + i * 100, 24 + i * .02), "move rejected");
      check(h.queue->pendingCount() == 1, "unbounded pair queue");
    }
    h.at(110ms);
    h.pair(Kind::End, 9000000000110000LL, 44);
    h.at(150ms); h.drain();
    check(h.sent.size() == 3, "pairs not coalesced");
    check(h.sent[1]["touchPoints"].size() == 2, "lost second contact");
    check(h.sent[1]["touchPoints"][0]["id"] == 0 &&
      h.sent[1]["touchPoints"][1]["id"] == 1, "unstable contact ids");
    near(h.sent[1]["touchPoints"][0]["y"], 56);
    near(h.sent[1]["touchPoints"][1]["y"], 144);
    near(h.sent[1]["timestamp"], 1700000000.1);
    near(h.sent[2]["timestamp"], 1700000000.11);
    check(h.sent[2]["touchPoints"].empty(), "end retained contacts");
  }

  void latePinchKeepsClockAndCancellationFence() {
    Harness h;
    h.queue->enqueue(Kind::Start, 1000000, 100, 100, 1); h.touch();
    h.at(10ms); h.queue->enqueue(Kind::Move, 1010000, 120, 100, 1); h.touch();
    // Arrival delayed 30ms beyond the source sample: must NOT re-pair clocks.
    h.at(60ms); h.pair(Kind::Start, 1010000, 24, 20000);
    h.pair(Kind::Move, 1030000, 48);
    check(h.sent.back()["type"] == "touchCancel", "missing old contact fence");
    check(h.sent.size() == 3, "pair started before cancel ACK");
    h.drain();
    check(h.sent[3]["type"] == "touchStart", "missing paired start");
    near(h.sent[3]["timestamp"], 1700000000.01);
    near(h.sent[4]["timestamp"], 1700000000.03);
  }

  void countCannotChangeOnMove() {
    Harness h;
    h.queue->enqueue(Kind::Start, 1000000, 100, 100, 1); h.touch();
    h.at(10ms);
    check(!h.pair(Kind::Move, 1010000, 30), "changed count without Start");
    h.drain();
    check(h.sent.size() == 2 && h.sent.back()["type"] == "touchCancel", "not cancelled");
  }

  void tinyGestureCannotClick() {
    Harness h;
    h.queue->enqueue(Kind::Start, 0, 100, 100, 1); h.touch();
    h.at(10ms); h.queue->enqueue(Kind::Move, 10000, 101, 100, 1); h.touch();
    h.at(20ms); h.queue->enqueue(Kind::End, 20000, 101, 100, 0); h.touch();
    check(h.sent.back()["type"] == "touchCancel", "tiny drag emulated a tap");
  }

  void querySharesSlotAndNavigationGeneration() {
    Harness h;
    int replies = 0;
    h.queue->queryPolicy("{}", [&](auto value) {
      check(!value, "navigation delivered stale policy"); ++replies;
    });
    check(h.queue->inFlight(), "query did not reserve CDP slot");
    h.queue->queryPolicy("{}", [&](auto value) {
      check(!value, "busy query admitted"); ++replies;
    });
    h.queue->cancel();
    h.pair(Kind::Start, 0, 24);
    check(h.sent.empty(), "touch overlapped query");
    h.policy(true);
    check(replies == 2 && h.sent.size() == 1, "query did not release exactly one slot");
    h.drain();
  }

  void coalescedOutAndBackCannotClick() {
    Harness h;
    h.queue->enqueue(Kind::Start, 0, 100, 100, 1);
    h.at(10ms); h.queue->enqueue(Kind::Move, 10000, 140, 100, 1);
    h.at(20ms); h.queue->enqueue(Kind::Move, 20000, 100, 100, 1);
    h.at(30ms); h.queue->enqueue(Kind::End, 30000, 100, 100, 0);
    h.drain();
    check(h.sent.size() == 3, "unexpected out-and-back dispatch count");
    check(h.sent[1]["touchPoints"][0]["x"] == 100, "latest move not retained");
    check(h.sent.back()["type"] == "touchCancel", "coalescing turned a pan into a tap");
  }

  void staleQueryCannotApproveHistory() {
    Harness h;
    bool called = false;
    h.queue->queryPolicy("{}", [&](auto value) { called = true; check(!value, "stale policy approved"); });
    h.at(251ms); h.policy(false);
    check(called && !h.queue->inFlight(), "stale query slot stranded");
  }

  void queryCloseAndDuplicateCallback() {
    Harness h;
    int count = 0;
    h.queue->queryPolicy("{}", [&](auto value) { check(!value, "closed query returned value"); ++count; });
    auto duplicate = h.policyReply;
    h.queue->close();
    check(h.queue->inFlight(), "close pretended CDP completed");
    h.policy(true); duplicate(false);
    check(count == 1 && !h.queue->inFlight(), "duplicate completed twice");
    check(h.sent.empty(), "close emitted contacts");
  }

  void pairTimeoutNavigationAndClose() {
    for (int mode = 0; mode < 3; ++mode) {
      Harness h;
      h.pair(Kind::Start, 0, 24);
      h.at(10ms); h.pair(Kind::Move, 10000, 48);
      h.at(20ms); h.pair(Kind::End, 20000, 48);
      if (mode == 0) h.at(251ms);
      if (mode == 1) h.queue->cancel();
      if (mode == 2) h.queue->close();
      h.drain();
      check(h.sent.size() == (mode == 2 ? 1u : 2u), "stale pair tail survived");
      if (mode != 2) check(h.sent.back()["type"] == "touchCancel", "missing cancel");
      check(h.queue->pendingCount() == 0, "pending work survived");
    }
  }

  void policyParsingIsStrictAndBounded() {
    check(parseSiteGesturePolicy(R"({"result":{"value":true}})") == true, "true not parsed");
    check(parseSiteGesturePolicy(R"({"result":{"value":false}})") == false, "false not parsed");
    for (const auto* json : { "{", "[]", R"({"result":{"value":"true"}})",
      R"({"result":{"value":true},"exceptionDetails":{}})" }) {
      check(!parseSiteGesturePolicy(json), "invalid response used as policy");
    }
    const auto parameters = nlohmann::json::parse(siteGesturePolicyParameters(100, 200));
    check(parameters["timeout"] == 50 && parameters["returnByValue"] == true,
      "query lost its execution bound");
  }
}

int main() {
  const std::pair<const char*, void(*)()> tests[] = {
    {"atomic pair coalescing and timestamps", twoContactsCoalesceTogether},
    {"late pinch clock and cancel fence", latePinchKeepsClockAndCancellationFence},
    {"contact count requires fenced start", countCannotChangeOnMove},
    {"tiny drag cannot click", tinyGestureCannotClick},
    {"coalesced reversal cannot click", coalescedOutAndBackCannotClick},
    {"query shares slot and navigation generation", querySharesSlotAndNavigationGeneration},
    {"stale query fails closed", staleQueryCannotApproveHistory},
    {"close and duplicate callback", queryCloseAndDuplicateCallback},
    {"pair timeout navigation and close", pairTimeoutNavigationAndClose},
    {"strict bounded policy response", policyParsingIsStrictAndBounded},
  };
  int failures = 0;
  for (const auto& test : tests) {
    try { test.second(); std::cout << "PASS " << test.first << '\n'; }
    catch (const std::exception& error) {
      ++failures; std::cerr << "FAIL " << test.first << ": " << error.what() << '\n';
    }
  }
  return failures == 0 ? 0 : 1;
}