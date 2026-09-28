#include "new_window_requested_args.h"
#include "../utils/log.h"

namespace flutter_inappwebview_plugin
{
  NewWindowRequestedArgs::NewWindowRequestedArgs(const void* owner, wil::com_ptr<ICoreWebView2NewWindowRequestedEventArgs> args,
    wil::com_ptr<ICoreWebView2Deferral> deferral)
    : PendingWindowRequest(owner,
      [args](ICoreWebView2* child) { return succeededOrLog(args->put_NewWindow(child)); },
      [args] { return succeededOrLog(args->put_Handled(TRUE)); },
      [deferral] { return succeededOrLog(deferral->Complete()); })
  {}
}