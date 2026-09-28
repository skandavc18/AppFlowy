#include "../types/pending_window_request.h"
#include <map>
#include <memory>
#include <stdexcept>
#include <vector>

using namespace flutter_inappwebview_plugin;

namespace {
  void check(bool value) { if (!value) throw std::runtime_error("popup lifecycle regression"); }
  using Request = PendingWindowRequest<int*>;
  struct Fixture {
    int opener = 1, other = 2, child = 3;
    int navigations = 0;
    std::vector<int> calls;
    std::map<int, std::unique_ptr<Request>> pending;
    void add(bool adoptSucceeds = true, bool handledSucceeds = true) {
      pending.emplace(7, std::make_unique<Request>(&opener,
        [this, adoptSucceeds](int* target) {
          check(pending.empty()); check(target == &child); calls.push_back(1); return adoptSucceeds;
        },
        [this, handledSucceeds] {
          check(pending.empty()); calls.push_back(2); return handledSucceeds;
        },
        [this] { check(pending.empty()); calls.push_back(3); return true; }));
    }
    // Same take-before-finish contract used by NewWindowRequested's fallback.
    void fallback() {
      auto request = takePendingWindow(pending, 7, &opener);
      if (!request) return;
      request->finish(); ++navigations;
    }
  };
}

int main() {
  {
    Fixture f; f.add();
    check(!takePendingWindow(f.pending, 7, &f.other));
    check(f.calls.empty() && f.pending.size() == 1);
    auto request = takePendingWindow(f.pending, 7, &f.opener);
    check(request && request->finish());
    check(!request->finish());
    f.fallback(); // Late false/null/error/notImplemented must not navigate.
    check(f.navigations == 0 && f.calls == std::vector<int>({2, 3}));
  }
  {
    Fixture f; f.add(); f.fallback(); f.fallback();
    check(f.navigations == 1 && f.calls == std::vector<int>({2, 3}));
  }
  {
    Fixture f; f.add();
    // true does nothing to pending state: a later windowId can still adopt.
    check(f.pending.size() == 1 && f.calls.empty());
    auto request = takePendingWindow(f.pending, 7);
    check(request->finish(&f.child));
    request.reset(); f.fallback();
    check(f.navigations == 0 && f.calls == std::vector<int>({1, 2, 3}));
  }
  {
    Fixture f; f.add(false, false);
    auto request = takePendingWindow(f.pending, 7);
    check(!request->finish(&f.child));
    check(f.calls == std::vector<int>({1, 2, 3})); // Failure still completes.
  }
  {
    Fixture f; f.add();
    auto request = takePendingWindow(f.pending, 7);
    request.reset(); // Owner disposal denies once, never adopts/navigates.
    check(f.calls == std::vector<int>({2, 3}));
  }
}