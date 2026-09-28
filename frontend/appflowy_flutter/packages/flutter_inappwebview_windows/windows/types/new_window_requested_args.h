#ifndef FLUTTER_INAPPWEBVIEW_PLUGIN_NEW_WINDOW_REQUESTED_ARGS_H_
#define FLUTTER_INAPPWEBVIEW_PLUGIN_NEW_WINDOW_REQUESTED_ARGS_H_

#include <WebView2.h>
#include <wil/com.h>
#include "pending_window_request.h"

namespace flutter_inappwebview_plugin
{
  class NewWindowRequestedArgs : public PendingWindowRequest<ICoreWebView2*>
  {
  public:
    NewWindowRequestedArgs(const void* owner, wil::com_ptr<ICoreWebView2NewWindowRequestedEventArgs> args, wil::com_ptr<ICoreWebView2Deferral> deferral);
    ~NewWindowRequestedArgs() = default;
  };
}

#endif //FLUTTER_INAPPWEBVIEW_PLUGIN_NEW_WINDOW_REQUESTED_ARGS_H_