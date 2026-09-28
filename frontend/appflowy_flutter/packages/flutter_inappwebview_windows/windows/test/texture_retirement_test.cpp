#include "../custom_platform_view/texture_retirement.h"

#include <cstdlib>
#include <iostream>

using namespace flutter_inappwebview_plugin;

static void Check(bool condition)
{
  if (!condition) std::abort();
}

struct Counts {
  int context_destroyed = 0;
  int bridge_destroyed = 0;
  int texture_destroyed = 0;
  int resource_reads = 0;
  int replies = 0;
};

struct Context {
  Counts& counts;
  explicit Context(Counts& value) : counts(value) {}
  ~Context() { ++counts.context_destroyed; }
};

struct Bridge {
  Counts& counts;
  std::shared_ptr<Context> context;
  bool stopped = false;
  std::shared_ptr<PlatformCallbackTarget<Bridge>> target;
  Bridge(Counts& value, std::shared_ptr<Context> graphics)
    : counts(value), context(std::move(graphics)),
    target(std::make_shared<PlatformCallbackTarget<Bridge>>(this)) {}
  void Shutdown() { target->Detach(); stopped = true; }
  const void* Read()
  {
    if (stopped) return nullptr;
    Check(counts.context_destroyed == 0);
    ++counts.resource_reads;
    return context.get();
  }
  ~Bridge()
  {
    Check(stopped && counts.context_destroyed == 0);
    Check(counts.texture_destroyed == 1);
    ++counts.bridge_destroyed;
  }
};

struct Texture {
  Counts& counts;
  Bridge* bridge; // Mirrors Flutter variant -> raw bridge callback.
  Texture(Counts& value, Bridge* owner) : counts(value), bridge(owner) {}
  const void* Read() const { return bridge->Read(); }
  ~Texture()
  {
    Check(counts.bridge_destroyed == 0);
    ++counts.texture_destroyed;
  }
};

struct Registrar {
  Texture* registered = nullptr; // Mirrors C wrapper's raw variant user_data.
  std::function<void()> completion;
  void Unregister(std::function<void()> done) { completion = std::move(done); }
  void Finish()
  {
    registered = nullptr; // Engine guarantees no further texture callbacks.
    auto done = std::move(completion);
    done();
    done(); // A copied/late completion cannot release or reply twice.
  }
};

static void CheckRetirement(bool explicit_dispose, bool synchronous)
{
  Counts counts;
  auto manager_context = std::make_shared<Context>(counts);
  auto bridge = std::make_unique<Bridge>(counts, manager_context);
  auto texture = std::make_unique<Texture>(counts, bridge.get());
  const auto target = bridge->target;
  const auto stale_capture = [target]() {
    if (auto owner = target->get()) owner->Read();
  };
  Registrar registrar;
  registrar.registered = texture.get();
  Check(registrar.registered->Read() != nullptr);
  stale_capture();
  Check(counts.resource_reads == 2);
  bridge->Shutdown();
  manager_context.reset(); // Manager/graphics owner can die before completion.
  auto events = explicit_dispose ? std::make_shared<TextureLifecycleEvents>() : nullptr;
  std::function<void()> reply;
  if (explicit_dispose) {
    reply = [&counts]() {
      Check(counts.texture_destroyed == 1 && counts.bridge_destroyed == 1);
      Check(counts.context_destroyed == 1);
      ++counts.replies;
    };
  }
  RetireTexture(std::move(bridge), std::move(texture),
    [&registrar, synchronous](std::function<void()> done) {
      registrar.Unregister(std::move(done));
      if (synchronous) registrar.Finish();
    }, std::move(reply), events);
  Check(!bridge && !texture);
  if (!synchronous) {
    Check(counts.bridge_destroyed == 0 && counts.texture_destroyed == 0);
    Check(counts.context_destroyed == 0 && counts.replies == 0);
    // A texture callback already queued at Shutdown is legal until unregister
    // completion: its addresses live, but it must not touch stopped resources.
    Check(registrar.registered->Read() == nullptr);
    stale_capture();
    Check(counts.resource_reads == 2);
    registrar.Finish();
  }
  stale_capture(); // After release: detached target, no bridge dereference.
  Check(counts.resource_reads == 2);
  Check(counts.texture_destroyed == 1 && counts.bridge_destroyed == 1);
  Check(counts.context_destroyed == 1);
  Check(counts.replies == (explicit_dispose ? 1 : 0));
  if (events) Check(*events == TextureLifecycleEvents({3, 4, 5}));
}

int main()
{
  CheckRetirement(true, false);
  CheckRetirement(false, false); // Destruction path: no Dart reply/owner retained.
  CheckRetirement(true, true);
  CheckRetirement(false, true);
  std::cout << "Texture retirement checks passed.\n";
}