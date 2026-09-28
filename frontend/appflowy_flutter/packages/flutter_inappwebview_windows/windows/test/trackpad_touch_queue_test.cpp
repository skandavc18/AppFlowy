#include "../in_app_webview/trackpad_touch_queue.h"

#include <iostream>
#include <limits>
#include <stdexcept>
#include <vector>

using flutter_inappwebview_plugin::TrackpadTouchKind;
using flutter_inappwebview_plugin::TrackpadTouchQueue;
using Kind = TrackpadTouchKind;
using namespace std::chrono_literals;

namespace
{
  void check(bool condition, const char* message)
  {
    if (!condition) throw std::runtime_error(message);
  }

  void near(double actual, double expected)
  {
    check(std::abs(actual - expected) < 0.000001, "serialized timestamp/position mismatch");
  }

  struct Harness {
    TrackpadTouchQueue::Clock::time_point now{ 1000s };
    std::vector<nlohmann::json> sent;
    std::deque<TrackpadTouchQueue::Completion> replies;
    std::shared_ptr<TrackpadTouchQueue> queue = std::make_shared<TrackpadTouchQueue>(
      [this](const std::string& payload, TrackpadTouchQueue::Completion reply) {
        check(replies.empty(), "more than one native dispatch in flight");
        sent.push_back(nlohmann::json::parse(payload));
        replies.push_back(std::move(reply));
      }, [this] { return now; }, 1700000000.0);

    void at(std::chrono::microseconds elapsed) { now = TrackpadTouchQueue::Clock::time_point(1000s + elapsed); }

    bool add(Kind kind, int64_t micros, double y = 100, int64_t age = 0)
    {
      return queue->enqueue(kind, micros, 75, y, kind == Kind::End ? 0 : 1, age);
    }

    void reply(bool success = true)
    {
      check(!replies.empty(), "no native call to complete");
      auto callback = std::move(replies.front());
      replies.pop_front();
      callback(success);
    }

    void drain()
    {
      for (int i = 0; !replies.empty() && i < 8; ++i) reply();
      check(replies.empty(), "unbounded dispatch/cancellation loop");
    }

    void types(std::initializer_list<const char*> expected)
    {
      check(sent.size() == expected.size(), "unexpected dispatch count");
      size_t i = 0;
      for (const auto* type : expected) check(sent[i++]["type"] == type, "touch order changed");
    }
  };

  void serializedOriginalSequence()
  {
    Harness h;
    // A non-epoch engine origin; differences must be taken before conversion
    // to floating point. Neither native uptime nor wall time equals this.
    constexpr int64_t origin = 9000000000000000LL;
    check(h.add(Kind::Start, origin), "start rejected");
    h.reply();
    const int times[] = { 10000, 20000, 30000 };
    const double positions[] = { 90, 75, 55 };
    for (int i = 0; i < 3; ++i) {
      h.at(std::chrono::microseconds(times[i]));
      check(h.add(Kind::Move, origin + times[i], positions[i]), "move rejected");
      h.reply();
    }
    h.at(35ms);
    check(h.add(Kind::End, origin + 35000, 55), "end rejected");
    h.reply();
    h.types({ "touchStart", "touchMove", "touchMove", "touchMove", "touchEnd" });
    const double allPositions[] = { 100, 90, 75, 55 };
    for (size_t i = 0; i < 4; ++i) {
      const auto& event = h.sent[i];
      check(event["touchPoints"].size() == 1, "missing active contact");
      check(event["touchPoints"][0]["id"] == 0, "contact id changed");
      near(event["touchPoints"][0]["x"], 75);
      near(event["touchPoints"][0]["y"], allPositions[i]);
      near(event["timestamp"], 1700000000.0 + static_cast<double>(i) * 0.01);
    }
    near(h.sent.back()["timestamp"], 1700000000.035);
    check(h.sent.back()["touchPoints"].empty(), "end carried a touch point");
    check(!h.queue->inFlight() && h.queue->pendingCount() == 0, "queue did not drain");
  }

  void delayedCallbacksKeepSampleTimes()
  {
    Harness h;
    h.add(Kind::Start, 1000000);
    h.at(10ms); h.add(Kind::Move, 1010000, 90);
    h.at(20ms); h.add(Kind::Move, 1020000, 75);
    h.at(30ms); h.add(Kind::Move, 1030000, 55);
    h.at(35ms); h.add(Kind::End, 1035000, 55);
    check(h.sent.size() == 1 && h.queue->pendingCount() == 2, "move coalescing failed");
    h.at(80ms); h.reply();
    h.at(81ms); h.reply();
    h.at(82ms); h.reply();
    h.types({ "touchStart", "touchMove", "touchEnd" });
    near(h.sent[1]["touchPoints"][0]["y"], 55);
    const double start = h.sent[0]["timestamp"];
    const double move = h.sent[1]["timestamp"];
    const double end = h.sent[2]["timestamp"];
    near(move - start, 0.03);
    near(end - move, 0.005);
    // Receipt times 80/81ms would compress this interval to 1ms; coalescing
    // positions without original time is NOT a valid velocity sample.
    check(end - move > 0.004, "callback latency replaced gesture timing");
  }

  void deferredClassificationKeepsStartTime()
  {
    Harness h;
    h.at(30ms);
    h.add(Kind::Start, 5000000, 100, 30000);
    h.add(Kind::Move, 5030000, 70);
    h.drain();
    h.types({ "touchStart", "touchMove" });
    near(h.sent[0]["timestamp"], 1700000000.0);
    near(h.sent[1]["timestamp"], 1700000000.03);
  }

  void oldInflightStartCancelsEvenFreshTail()
  {
    Harness h;
    h.add(Kind::Start, 0);
    h.at(240ms); h.add(Kind::Move, 240000, 60);
    h.at(245ms); h.add(Kind::End, 245000, 60);
    h.at(260ms); h.reply(); h.drain();
    h.types({ "touchStart", "touchCancel" });
    check(h.sent.back()["touchPoints"].empty(), "cancel carried points");
    check(!h.add(Kind::Move, 270000, 50), "cancelled gesture restarted");
    check(!h.add(Kind::End, 280000), "cancelled end replayed");
  }

  void coldDelayNeverReplaysEnd()
  {
    Harness h;
    h.add(Kind::Start, 0); h.reply();
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    h.at(20ms); h.add(Kind::End, 20000, 90);
    h.at(2s); h.reply(); h.drain();
    h.types({ "touchStart", "touchMove", "touchCancel" });
    check(h.queue->pendingCount() == 0, "stale end survived");
  }

  void pairedAgeCatchesLateArrival()
  {
    Harness h;
    h.add(Kind::Start, 42000000); h.reply();
    h.at(1s);
    check(!h.add(Kind::Move, 42010000, 90), "late sample treated as fresh arrival");
    h.drain();
    h.types({ "touchStart", "touchCancel" });
  }

  void navigationFenceClearsOldWork()
  {
    Harness h;
    h.add(Kind::Start, 0);
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    h.at(20ms); h.add(Kind::End, 20000, 90);
    h.queue->cancel(); // Called synchronously by native NavigationStarting.
    check(h.queue->pendingCount() == 1, "navigation retained stale work");
    h.at(30ms); h.add(Kind::Start, 30000, 200);
    h.at(40ms); h.add(Kind::Move, 40000, 190);
    h.at(50ms); h.add(Kind::End, 50000, 190);
    check(h.sent.size() == 1, "new gesture interleaved an old call");
    h.drain();
    h.types({ "touchStart", "touchCancel", "touchStart", "touchMove", "touchEnd" });
    near(h.sent[2]["touchPoints"][0]["y"], 200);
    near(h.sent[3]["timestamp"], 1700000000.04);
  }

  void cancelInFlightIsOneFence()
  {
    Harness h;
    h.add(Kind::Start, 0); h.reply();
    h.queue->cancel();
    h.queue->cancel();
    h.at(10ms); h.add(Kind::Start, 10000, 200);
    h.at(20ms); h.add(Kind::Start, 20000, 300);
    h.drain();
    h.types({ "touchStart", "touchCancel", "touchStart" });
    near(h.sent.back()["touchPoints"][0]["y"], 300);
  }

  void newGestureSupersedesOldPendingContacts()
  {
    Harness h;
    h.add(Kind::Start, 0);
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    h.at(20ms); h.add(Kind::End, 20000, 90);
    h.at(30ms); h.add(Kind::Start, 30000, 200);
    h.drain();
    h.types({ "touchStart", "touchCancel", "touchStart" });
  }

  void queuedStartExpiresBehindCancel()
  {
    Harness h;
    h.add(Kind::Start, 0); h.reply();
    h.queue->cancel();
    h.at(10ms); h.add(Kind::Start, 10000, 200);
    h.at(300ms); h.reply();
    h.types({ "touchStart", "touchCancel" });
    check(!h.queue->inFlight() && h.queue->pendingCount() == 0, "old queued start replayed");
  }

  void duplicateCompletionCannotReleaseNewSlot()
  {
    Harness h;
    h.add(Kind::Start, 0);
    auto oldReply = h.replies.front();
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    h.at(20ms); h.add(Kind::End, 20000, 90);
    h.reply();
    oldReply(false);
    check(h.queue->inFlight() && h.sent.size() == 2, "duplicate freed a newer slot");
    h.drain();
    h.types({ "touchStart", "touchMove", "touchEnd" });
  }

  void failureCancelsInsteadOfDrainingMoves()
  {
    Harness h;
    h.add(Kind::Start, 0);
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    h.at(20ms); h.add(Kind::End, 20000, 90);
    h.reply(false); h.drain();
    h.at(30ms); h.add(Kind::Start, 30000, 200); h.reply();
    h.types({ "touchStart", "touchCancel", "touchStart" });
  }

  void cancellationFailureIsBounded()
  {
    Harness h;
    h.add(Kind::Start, 0); h.reply(false); h.reply(false);
    check(h.queue->closed(), "failed cancellation did not fail closed");
    check(!h.add(Kind::Start, 10000), "unknown old contact admitted another start");
    h.types({ "touchStart", "touchCancel" });
  }

  void closePreservesSlotAndOwnsOnlyQueue()
  {
    Harness h;
    h.add(Kind::Start, 0);
    h.at(10ms); h.add(Kind::Move, 10000, 90);
    std::weak_ptr<TrackpadTouchQueue> weak = h.queue;
    h.queue->close();
    check(h.queue->inFlight(), "close falsely completed native work");
    check(h.queue->pendingCount() == 0, "close retained pending events");
    h.queue.reset();
    check(!weak.expired(), "callback lost its queue owner");
    h.reply();
    check(weak.expired(), "callback retained disposed queue");
    h.types({ "touchStart" });
  }

  void invalidSamplesCancel()
  {
    for (const auto time : { -1LL, 999LL, 1000LL, (std::numeric_limits<int64_t>::max)() }) {
      Harness h;
      h.add(Kind::Start, 1000); h.reply();
      check(!h.add(Kind::Move, time, 90), "invalid timestamp accepted");
      h.drain();
      h.types({ "touchStart", "touchCancel" });
    }
    Harness h;
    h.add(Kind::Start, 0); h.reply();
    check(!h.add(Kind::Move, 1000, std::numeric_limits<double>::quiet_NaN()), "NaN accepted");
    h.drain();
    h.types({ "touchStart", "touchCancel" });
  }

  void boundedPendingMoves()
  {
    Harness h;
    h.add(Kind::Start, 0);
    for (int i = 1; i <= 1000; ++i) {
      h.at(std::chrono::microseconds(i * 100));
      h.add(Kind::Move, i * 100, 100.0 - i * 0.01);
      check(h.queue->pendingCount() == 1, "move queue grew with input count");
    }
    h.at(110ms); h.add(Kind::End, 110000, 90); h.drain();
    h.types({ "touchStart", "touchMove", "touchEnd" });
    near(h.sent[1]["timestamp"], 1700000000.1);
    near(h.sent[1]["touchPoints"][0]["y"], 90);
  }

  void freshnessBoundary()
  {
    for (const auto delay : { 250000us, 250001us }) {
      Harness h;
      h.add(Kind::Start, 0);
      h.at(10ms); h.add(Kind::Move, 10000, 90);
      h.at(20ms); h.add(Kind::End, 20000, 90);
      h.at(delay); h.drain();
      if (delay == 250000us) h.types({ "touchStart", "touchMove", "touchEnd" });
      else h.types({ "touchStart", "touchCancel" });
    }
  }

  void staleClassificationNeverStartsContact()
  {
    Harness h;
    h.at(1s);
    check(!h.add(Kind::Start, 8000000, 100, 250001), "stale deferred start accepted");
    check(!h.add(Kind::Move, 8010000, 90), "orphan move accepted");
    h.types({});
  }

  void synchronousCallbacksAreSafe()
  {
    int calls = 0;
    auto queue = std::make_shared<TrackpadTouchQueue>(
      [&calls](const std::string&, TrackpadTouchQueue::Completion done) {
        ++calls;
        done(calls != 1); // Immediate submission error, successful cancel.
      });
    queue->enqueue(Kind::Start, 0, 0, 0, 1);
    check(calls == 2 && !queue->inFlight(), "inline completion stranded queue");
    queue->close();
  }
}

int main()
{
  const std::pair<const char*, void(*)()> tests[] = {
    { "original delta sequence and epoch serialization", serializedOriginalSequence },
    { "delayed callbacks retain coalesced sample times", delayedCallbacksKeepSampleTimes },
    { "deferred classification retains original start", deferredClassificationKeepsStartTime },
    { "old in-flight start cancels fresh tail", oldInflightStartCancelsEvenFreshTail },
    { "cold delay never replays a fling-producing end", coldDelayNeverReplaysEnd },
    { "paired source age catches late arrival", pairedAgeCatchesLateArrival },
    { "native navigation fence discards old work", navigationFenceClearsOldWork },
    { "cancel in flight remains a single fence", cancelInFlightIsOneFence },
    { "new gesture cannot interleave old contacts", newGestureSupersedesOldPendingContacts },
    { "queued start expires behind cancel", queuedStartExpiresBehindCancel },
    { "duplicate callback cannot release another slot", duplicateCompletionCannotReleaseNewSlot },
    { "failed dispatch cancels pending moves", failureCancelsInsteadOfDrainingMoves },
    { "failed cancellation is bounded", cancellationFailureIsBounded },
    { "close and callback lifetime", closePreservesSlotAndOwnsOnlyQueue },
    { "invalid and out-of-order samples", invalidSamplesCancel },
    { "one thousand moves stay bounded", boundedPendingMoves },
    { "exact freshness boundary", freshnessBoundary },
    { "stale classification never creates contact", staleClassificationNeverStartsContact },
    { "inline callbacks and submission failure", synchronousCallbacksAreSafe },
  };
  int passed = 0;
  int failed = 0;
  for (const auto& test : tests) {
    try {
      test.second();
      ++passed;
      std::cout << "PASS " << test.first << '\n';
    }
    catch (const std::exception& error) {
      ++failed;
      std::cerr << "FAIL " << test.first << ": " << error.what() << '\n';
    }
  }
  std::cout << "Native trackpad policy: " << passed << " passed, " << failed << " failed\n";
  return failed == 0 ? 0 : 1;
}