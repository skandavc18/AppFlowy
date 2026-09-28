#include "../types/base_callback_result.h"
#include "../types/javascript_handler_response.h"
#include <stdexcept>

using namespace flutter_inappwebview_plugin;

int main()
{
  const auto check = [](bool valid) {
    if (!valid) throw std::runtime_error("JavaScript handler reply regression");
  };
  BaseCallbackResult<const flutter::EncodableValue*> callback;
  callback.decodeResult = [](const flutter::EncodableValue* value) {
    return value;
  };
  std::string result;
  callback.defaultBehaviour = [&result](const auto response) {
    result = javaScriptHandlerResponse(response);
  };
  callback.Success(); // Engaged optional containing a null pointer: native crash.
  check(result == "null");
  callback.Success(flutter::EncodableValue());
  check(result == "null");
  callback.Success(flutter::EncodableValue("{\"actual\":20,\"atStart\":false}"));
  check(result == "{\"actual\":20,\"atStart\":false}");
  callback.Success(flutter::EncodableValue(42));
  check(result == "null");
  callback.NotImplemented();
  check(result == "null");

  auto owner = std::make_shared<bool>(true);
  int replies = 0;
  int errors = 0;
  callback.defaultBehaviour = withLiveJavaScriptOwner(owner,
    [&replies](const auto&) { ++replies; });
  callback.error = withLiveJavaScriptOwner(owner,
    [&errors](const auto&, const auto&, const auto*) { ++errors; });
  callback.Success();
  callback.Error("live");
  check(replies == 1 && errors == 1);
  *owner = false; // Dispose starts before the owner's allocation is released.
  callback.Success();
  callback.Error("disposed");
  callback.NotImplemented();
  check(replies == 1 && errors == 1);
  owner.reset(); // A queued response must not resurrect or touch a freed view.
  callback.Success();
  callback.Error("destroyed");
  callback.NotImplemented();
  check(replies == 1 && errors == 1);
}