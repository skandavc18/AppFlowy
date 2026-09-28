#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_JAVASCRIPT_HANDLER_RESPONSE_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_JAVASCRIPT_HANDLER_RESPONSE_H_

#include <flutter/encodable_value.h>
#include <memory>
#include <optional>
#include <string>
#include <utility>

namespace flutter_inappwebview_plugin
{
  // A method-channel response can outlive its native view. Check a separately
  // owned token BEFORE invoking code that captures the view's raw address.
  template <typename Callback>
  auto withLiveJavaScriptOwner(std::weak_ptr<bool> alive, Callback callback)
  {
    return [alive, callback](auto&&... args) {
      const auto owner = alive.lock();
      if (!owner || !*owner) return;
      callback(std::forward<decltype(args)>(args)...);
    };
  }

  inline std::string javaScriptHandlerResponse(
    const std::optional<const flutter::EncodableValue*>& response)
  {
    // MethodResult::Success() supplies nullptr. An optional containing that
    // pointer is engaged, so has_value() alone does not make dereferencing safe.
    if (!response || !*response) return "null";
    const auto json = std::get_if<std::string>(*response);
    return json ? *json : "null";
  }
}
#endif