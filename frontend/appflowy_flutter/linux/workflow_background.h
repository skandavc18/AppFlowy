#ifndef APPFLOWY_WORKFLOW_BACKGROUND_H_
#define APPFLOWY_WORKFLOW_BACKGROUND_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

struct _AppIndicator;
using AppIndicator = _AppIndicator;

class WorkflowBackground {
 public:
  WorkflowBackground(GtkWindow* window, FlBinaryMessenger* messenger,
                     bool started_in_background);
  ~WorkflowBackground();

  void ShowWindow();

  static bool IsLaunchAtLoginEnabled(GError** error);
  static bool SetLaunchAtLogin(bool enabled, GError** error);

 private:
  enum class WindowAction { show, hide, quit };

  void HandleMethodCall(FlMethodCall* call);
  bool Configure(FlValue* arguments, GError** error);
  bool CreateIndicator(GtkWidget* menu, const gchar* tooltip, GError** error);
  void RemoveIndicator();
  void NotifyDart(const gchar* method, FlValue* arguments = nullptr);
  void ScheduleWindowAction(WindowAction action);

  GtkWindow* window_;
  FlMethodChannel* channel_ = nullptr;
  gulong close_handler_ = 0;
  guint startup_watchdog_ = 0;
  guint action_source_ = 0;
  WindowAction pending_action_ = WindowAction::show;
  bool keep_running_ = false;
  bool quitting_ = false;
  AppIndicator* indicator_ = nullptr;
  void* indicator_library_ = nullptr;
  AppIndicator* (*indicator_new_)(const gchar*, const gchar*, int) = nullptr;
  void (*indicator_set_status_)(AppIndicator*, int) = nullptr;
  void (*indicator_set_menu_)(AppIndicator*, GtkMenu*) = nullptr;
  void (*indicator_set_title_)(AppIndicator*, const gchar*) = nullptr;
  void (*indicator_set_icon_full_)(AppIndicator*, const gchar*, const gchar*) =
      nullptr;
};

#endif  // APPFLOWY_WORKFLOW_BACKGROUND_H_
