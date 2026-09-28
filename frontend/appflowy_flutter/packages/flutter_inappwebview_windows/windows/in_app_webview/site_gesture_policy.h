#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_SITE_GESTURE_POLICY_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_SITE_GESTURE_POLICY_H_

#include <cmath>
#include <optional>
#include <string>
#include <nlohmann/json.hpp>

namespace flutter_inappwebview_plugin
{
  // Runs once at gesture start, not per frame. No text, URLs, credentials,
  // listener source, or DOM objects leave Chromium. CDP's command-line helper
  // observes addEventListener registrations without patching site prototypes.
  inline std::string siteGesturePolicyParameters(double x, double y)
  {
    const std::string expression = R"JS((function(x,y) {
      let doc = document, el = doc.elementFromPoint(x,y);
      for (let depth = 0; el && depth < 64; ++depth) {
        const style = doc.defaultView.getComputedStyle(el);
        const action = style.touchAction;
        if (action && action !== 'auto' && action !== 'manipulation') return true;
        if (el !== doc.body && el !== doc.documentElement) {
          if (/^(auto|scroll)$/.test(style.overflowX) &&
              el.scrollWidth > el.clientWidth + 1) return true;
          const handlers = typeof getEventListeners === 'function'
            ? getEventListeners(el) : {};
          if (el.ontouchmove || el.onpointermove || handlers.touchmove ||
              handlers.pointermove) return true;
          if (/^(CANVAS|svg)$/.test(el.tagName) &&
              (el.onpointerdown || el.ontouchstart || handlers.pointerdown ||
               handlers.touchstart)) return true;
        }
        const inner = el.shadowRoot && el.shadowRoot.elementFromPoint(x,y);
        if (inner && inner !== el) { el = inner; continue; }
        if (el.tagName === 'IFRAME') {
          try {
            const child = el.contentDocument;
            if (child) {
              const r = el.getBoundingClientRect();
              x -= r.left + el.clientLeft; y -= r.top + el.clientTop;
              doc = child; el = doc.elementFromPoint(x,y); continue;
            }
          } catch (_) {}
        }
        // The host has already been inspected on entry to an open shadow tree.
        el = el.parentElement;
      }
      return false;
    })( )JS" + nlohmann::json(x).dump() + "," + nlohmann::json(y).dump() + ")";
    return nlohmann::json{ {"expression", expression}, {"returnByValue", true},
      {"includeCommandLineAPI", true}, {"timeout", 50}, {"silent", true} }.dump();
  }

  inline std::optional<bool> parseSiteGesturePolicy(const std::string& payload)
  {
    const auto json = nlohmann::json::parse(payload, nullptr, false);
    if (!json.is_object() || json.contains("exceptionDetails") ||
      !json.contains("result") || !json["result"].is_object()) return std::nullopt;
    const auto& result = json["result"];
    if (!result.contains("value") || !result["value"].is_boolean()) return std::nullopt;
    return result["value"].get<bool>();
  }
}
#endif