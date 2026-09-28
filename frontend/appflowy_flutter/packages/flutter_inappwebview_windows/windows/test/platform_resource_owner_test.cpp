#include "../custom_platform_view/platform_resource_owner.h"

#include <cstdlib>
#include <iostream>
#include <vector>

using namespace flutter_inappwebview_plugin;

static void Check(bool condition)
{
  if (!condition) std::abort();
}

struct Resource {
  std::vector<int>& order;
  int id;
  std::thread::id thread = std::this_thread::get_id();
  Resource(std::vector<int>& events, int value) : order(events), id(value) {}
  ~Resource()
  {
    Check(thread == std::this_thread::get_id());
    order.push_back(id);
  }
};

using Ref = std::shared_ptr<Resource>;
using Owner = PlatformResourceOwner<Ref, Ref, Ref, Ref>;

int main()
{
  std::vector<int> order;
  auto first = Owner::Acquire();
  first->runtime = std::make_shared<Resource>(order, 1);
  first->dispatcher = std::make_shared<Resource>(order, 2);
  first->graphics = std::make_shared<Resource>(order, 3);
  first->composition = std::make_shared<Resource>(order, 4);
  auto second = Owner::Acquire();
  Check(first == second);
  std::weak_ptr<Owner> weak = first;
  first.reset();
  Check(order.empty()); // Closing one manager cannot invalidate another.
  second.reset();
  Check(order == std::vector<int>({4, 3, 2, 1}));
  Check(weak.expired()); // Registry must not postpone release until DLL unload.

  auto replacement = Owner::Acquire();
  Check(!replacement->runtime && !replacement->valid);
  std::thread other([&replacement]() {
    auto independent = Owner::Acquire();
    Check(independent != replacement);
    Check(independent == Owner::Acquire());
  });
  other.join();
  replacement.reset();
  std::cout << "Platform resource owner: shared managers, release order, weak registry, recreation and thread isolation passed.\n";
}