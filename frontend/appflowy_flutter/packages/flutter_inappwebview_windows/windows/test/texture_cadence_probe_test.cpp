#include "../custom_platform_view/texture_cadence_probe.h"

#include <cstdlib>
#include <iostream>

using Probe = flutter_inappwebview_plugin::TextureCadenceProbe;
using Kind = Probe::Kind;
using namespace std::chrono_literals;

static void Check(bool condition)
{
  if (!condition) {
    std::cerr << "Texture cadence probe assertion failed.\n";
    std::abort();
  }
}

int main()
{
  Probe probe;
  const Probe::TimePoint origin{};
  probe.Record(Kind::Capture, origin);
  Check(probe.Stop(origin).events.empty());
  Check(!probe.BeginWork());

  // Fake-clock latest-frame trace: arrival != capture != notification !=
  // consumption. Two captures before Flutter asks are not two delivered frames.
  probe.Start(origin);
  probe.Record(Kind::Arrival, origin + 1ms);
  probe.Record(Kind::Capture, origin + 1ms);
  probe.Record(Kind::Notify, origin + 1ms);
  probe.Record(Kind::Capture, origin + 17ms);
  probe.Record(Kind::CapDrop, origin + 17ms);
  probe.Record(Kind::GpuCallback, origin + 20ms, 0.25);
  probe.Record(Kind::GpuCallback, origin + 21ms, 0.5);
  probe.Record(Kind::Resize, origin + 22ms);
  auto snapshot = probe.Stop(origin + 25ms);
  Check(snapshot.events.size() == 8);
  Check(snapshot.events[0].sequence == 0);
  Check(snapshot.events[2].sequence == 1);
  Check(snapshot.events[5].sequence == 2);
  Check(snapshot.events[6].sequence == 2); // repeated latest frame, not new FPS
  Check(snapshot.events[5].milliseconds == 20);
  Check(snapshot.events[5].work_milliseconds == 0.25);
  Check(snapshot.elapsed_ms == 25 && !snapshot.expired && !snapshot.truncated);
  probe.Record(Kind::Capture, origin + 26ms);
  Check(probe.Stop(origin + 27ms).events.empty());

  // Restart fences all previous samples/sequence numbers; fractional timing
  // survives (unlike the existing FPS limiter's integer-millisecond cast).
  probe.Start(origin + 1s);
  probe.Record(Kind::Capture, origin + 1s + 16667us);
  snapshot = probe.Stop(origin + 2s);
  Check(snapshot.events.size() == 1 && snapshot.events[0].sequence == 1);
  Check(snapshot.events[0].milliseconds > 16.66 && snapshot.events[0].milliseconds < 16.68);

  // Hard deadline, including no callbacks at all during the interval.
  probe.Start(origin);
  probe.Record(Kind::Capture, origin + Probe::kMaxDuration);
  snapshot = probe.Stop(origin + 30s);
  Check(snapshot.expired && snapshot.events.empty() && snapshot.elapsed_ms == 12000);
  probe.Start(origin);
  snapshot = probe.Stop(origin + 30s);
  Check(snapshot.expired && snapshot.elapsed_ms == 12000);

  // Floods cannot grow storage or continue recording after exhaustion.
  probe.Start(origin);
  for (size_t i = 0; i < Probe::kMaxEvents + 10; ++i) {
    probe.Record(Kind::Capture, origin + 1ms);
  }
  snapshot = probe.Stop(origin + 2ms);
  Check(snapshot.truncated && snapshot.events.size() == Probe::kMaxEvents);
  Check(!snapshot.expired && !probe.BeginWork());
  std::cout << "Texture cadence fake-clock checks passed.\n";
}