#include "workflow_background.h"

#include <dlfcn.h>
#include <glib/gstdio.h>

#include <cerrno>
#include <cstring>
#include <string>

namespace {

constexpr char kChannel[] = "appflowy/background";
constexpr char kAutostartFile[] = "io.appflowy.appflowy-background.desktop";
constexpr char kDesktopEntry[] = "Desktop Entry";

gchar* AutostartPath() {
  return g_build_filename(g_get_user_config_dir(), "autostart", kAutostartFile,
                          nullptr);
}

std::string QuoteDesktopExecutable(const gchar* executable) {
  std::string quoted = "\"";
  for (const char* c = executable; *c != '\0'; ++c) {
    if (*c == '\\' || *c == '"' || *c == '$' || *c == '`') {
      quoted += '\\';
    } else if (*c == '%') {
      quoted += '%';
    }
    quoted += *c;
  }
  return quoted + "\" --background";
}

bool HasTrayHost(GError** error) {
  g_autoptr(GDBusConnection) bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, error);
  if (bus == nullptr) return false;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "NameHasOwner",
      g_variant_new("(s)", "org.kde.StatusNotifierWatcher"),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, error);
  if (reply == nullptr) return false;
  gboolean present = FALSE;
  g_variant_get(reply, "(b)", &present);
  if (!present) {
    g_set_error_literal(
        error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
        "Enable a StatusNotifier/AppIndicator notification area on your desktop "
        "before running AppFlowy in the background.");
  }
  return present;
}

const gchar* StringValue(FlValue* map, const gchar* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

}  // namespace

WorkflowBackground::WorkflowBackground(GtkWindow* window,
                                       FlBinaryMessenger* messenger,
                                       bool started_in_background)
    : window_(window) {
  g_object_add_weak_pointer(G_OBJECT(window_),
                            reinterpret_cast<gpointer*>(&window_));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel_,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        static_cast<WorkflowBackground*>(data)->HandleMethodCall(call);
      },
      this, nullptr);
  close_handler_ = g_signal_connect(
      window_, "delete-event",
      G_CALLBACK(+[](GtkWidget* window, GdkEvent*, gpointer data) -> gboolean {
        auto* self = static_cast<WorkflowBackground*>(data);
        if (!self->keep_running_ || self->quitting_) return FALSE;
        gtk_widget_hide(window);
        self->NotifyDart("onClosedToTray");
        return TRUE;
      }),
      this);
  if (started_in_background) {
    gtk_widget_hide(GTK_WIDGET(window_));
    startup_watchdog_ = g_timeout_add_seconds(
        15,
        [](gpointer data) -> gboolean {
          auto* self = static_cast<WorkflowBackground*>(data);
          self->startup_watchdog_ = 0;
          g_warning("Background startup was not configured; showing AppFlowy.");
          self->ShowWindow();
          return G_SOURCE_REMOVE;
        },
        this);
  }
}

WorkflowBackground::~WorkflowBackground() {
  if (startup_watchdog_ != 0) g_source_remove(startup_watchdog_);
  if (action_source_ != 0) g_source_remove(action_source_);
  if (window_ != nullptr) {
    g_signal_handler_disconnect(window_, close_handler_);
    g_object_remove_weak_pointer(G_OBJECT(window_),
                                reinterpret_cast<gpointer*>(&window_));
  }
  RemoveIndicator();
  g_clear_object(&channel_);
  if (indicator_library_ != nullptr) dlclose(indicator_library_);
}

void WorkflowBackground::NotifyDart(const gchar* method, FlValue* arguments) {
  fl_method_channel_invoke_method(channel_, method, arguments, nullptr, nullptr,
                                  nullptr);
}

void WorkflowBackground::ShowWindow() {
  if (window_ == nullptr) return;
  gtk_widget_show(GTK_WIDGET(window_));
  gtk_window_deiconify(window_);
  gtk_window_present(window_);
  NotifyDart("onWindowShown");
}

void WorkflowBackground::ScheduleWindowAction(WindowAction action) {
  if (quitting_) return;
  pending_action_ = action;
  quitting_ = action == WindowAction::quit;
  if (action_source_ != 0) return;
  // Mapping a hidden Flutter view can re-enter the engine. Reply to the
  // method-channel call before changing the window.
  action_source_ = g_idle_add(
      [](gpointer data) -> gboolean {
        auto* self = static_cast<WorkflowBackground*>(data);
        self->action_source_ = 0;
        if (self->window_ == nullptr) return G_SOURCE_REMOVE;
        switch (self->pending_action_) {
          case WindowAction::show:
            self->ShowWindow();
            break;
          case WindowAction::hide:
            gtk_widget_hide(GTK_WIDGET(self->window_));
            break;
          case WindowAction::quit:
            g_application_quit(
                G_APPLICATION(gtk_window_get_application(self->window_)));
            break;
        }
        return G_SOURCE_REMOVE;
      },
      this);
}

void WorkflowBackground::RemoveIndicator() {
  if (indicator_ == nullptr) return;
  indicator_set_status_(indicator_, 0);
  g_clear_object(&indicator_);
}

bool WorkflowBackground::CreateIndicator(GtkWidget* menu, const gchar* tooltip,
                                          GError** error) {
  if (!HasTrayHost(error)) return false;
  if (indicator_library_ == nullptr) {
    // AppIndicator registers GTypes, which must remain resident after dlclose.
    constexpr int flags = RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE;
    indicator_library_ = dlopen("libayatana-appindicator3.so.1", flags);
    if (indicator_library_ == nullptr) {
      indicator_library_ = dlopen("libappindicator3.so.1", flags);
    }
    if (indicator_library_ == nullptr) {
      g_set_error_literal(
          error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
          "Install libayatana-appindicator3 (or libappindicator3) to enable "
          "the AppFlowy notification-area icon.");
      return false;
    }
    indicator_new_ = reinterpret_cast<decltype(indicator_new_)>(
        dlsym(indicator_library_, "app_indicator_new"));
    indicator_set_status_ = reinterpret_cast<decltype(indicator_set_status_)>(
        dlsym(indicator_library_, "app_indicator_set_status"));
    indicator_set_menu_ = reinterpret_cast<decltype(indicator_set_menu_)>(
        dlsym(indicator_library_, "app_indicator_set_menu"));
    indicator_set_title_ = reinterpret_cast<decltype(indicator_set_title_)>(
        dlsym(indicator_library_, "app_indicator_set_title"));
    indicator_set_icon_full_ =
        reinterpret_cast<decltype(indicator_set_icon_full_)>(
            dlsym(indicator_library_, "app_indicator_set_icon_full"));
    if (indicator_new_ == nullptr || indicator_set_status_ == nullptr ||
        indicator_set_menu_ == nullptr || indicator_set_title_ == nullptr ||
        indicator_set_icon_full_ == nullptr) {
      dlclose(indicator_library_);
      indicator_library_ = nullptr;
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                          "The AppIndicator library is missing required APIs.");
      return false;
    }
  }
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", error);
  if (executable == nullptr) return false;
  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* icon =
      g_build_filename(directory, "data", "appflowy.png", nullptr);
  if (!g_file_test(icon, G_FILE_TEST_IS_REGULAR)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND,
                        "The AppFlowy notification-area icon is missing.");
    return false;
  }
  if (indicator_ == nullptr) {
    indicator_ = indicator_new_("appflowy-workflows", icon, 0);
  }
  if (indicator_ == nullptr) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                        "The AppFlowy notification-area icon could not start.");
    return false;
  }
  indicator_set_menu_(indicator_, GTK_MENU(menu));
  indicator_set_title_(indicator_, tooltip);
  indicator_set_icon_full_(indicator_, icon, tooltip);
  indicator_set_status_(indicator_, 1);
  return true;
}

bool WorkflowBackground::Configure(FlValue* arguments, GError** error) {
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "configure expects a map.");
    return false;
  }
  FlValue* keep = fl_value_lookup_string(arguments, "keepRunning");
  if (keep == nullptr || fl_value_get_type(keep) != FL_VALUE_TYPE_BOOL) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "keepRunning must be a boolean.");
    return false;
  }
  if (!fl_value_get_bool(keep)) {
    keep_running_ = false;
    RemoveIndicator();
    if (window_ != nullptr && !gtk_widget_get_visible(GTK_WIDGET(window_))) {
      ScheduleWindowAction(WindowAction::show);
    }
    return true;
  }
  FlValue* entries = fl_value_lookup_string(arguments, "menu");
  if (entries == nullptr || fl_value_get_type(entries) != FL_VALUE_TYPE_LIST) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                        "menu must be a list.");
    return false;
  }
  g_autoptr(GtkWidget) menu = gtk_menu_new();
  g_object_ref_sink(menu);
  for (size_t i = 0; i < fl_value_get_length(entries); ++i) {
    FlValue* entry = fl_value_get_list_value(entries, i);
    if (fl_value_get_type(entry) != FL_VALUE_TYPE_MAP) {
      g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                          "Each tray menu entry must be a map.");
      return false;
    }
    GtkWidget* item = nullptr;
    FlValue* separator = fl_value_lookup_string(entry, "separator");
    if (separator != nullptr &&
        fl_value_get_type(separator) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(separator)) {
      item = gtk_separator_menu_item_new();
    } else {
      const gchar* id = StringValue(entry, "id");
      const gchar* label = StringValue(entry, "label");
      if (id == nullptr || *id == '\0' || label == nullptr || *label == '\0') {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Tray menu entries need an id and label.");
        return false;
      }
      FlValue* checked = fl_value_lookup_string(entry, "checked");
      if (checked != nullptr &&
          fl_value_get_type(checked) == FL_VALUE_TYPE_BOOL &&
          fl_value_get_bool(checked)) {
        item = gtk_check_menu_item_new_with_label(label);
        gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(item), TRUE);
      } else {
        item = gtk_menu_item_new_with_label(label);
      }
      g_object_set_data_full(G_OBJECT(item), "workflow-action", g_strdup(id),
                              g_free);
      g_signal_connect(
          item, "activate",
          G_CALLBACK(+[](GtkMenuItem* item, gpointer data) {
            auto* self = static_cast<WorkflowBackground*>(data);
            const auto* id = static_cast<const gchar*>(
                g_object_get_data(G_OBJECT(item), "workflow-action"));
            if (g_strcmp0(id, "open") == 0) self->ShowWindow();
            g_autoptr(FlValue) action = fl_value_new_string(id);
            self->NotifyDart("onTrayAction", action);
          }),
          this);
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
  }
  gtk_widget_show_all(menu);
  const gchar* tooltip = StringValue(arguments, "tooltip");
  keep_running_ =
      CreateIndicator(menu, tooltip != nullptr ? tooltip : "AppFlowy", error);
  if (!keep_running_) {
    RemoveIndicator();
    ScheduleWindowAction(WindowAction::show);
  }
  return keep_running_;
}

bool WorkflowBackground::IsLaunchAtLoginEnabled(GError** error) {
  g_autofree gchar* path = AutostartPath();
  g_autoptr(GKeyFile) entry = g_key_file_new();
  g_autoptr(GError) load_error = nullptr;
  if (!g_key_file_load_from_file(entry, path, G_KEY_FILE_NONE, &load_error)) {
    if (g_error_matches(load_error, G_FILE_ERROR, G_FILE_ERROR_NOENT)) return false;
    g_propagate_error(error, g_steal_pointer(&load_error));
    return false;
  }
  if (g_key_file_has_key(entry, kDesktopEntry, "Hidden", nullptr) &&
      g_key_file_get_boolean(entry, kDesktopEntry, "Hidden", error)) {
    return false;
  }
  if (error != nullptr && *error != nullptr) return false;
  if (g_key_file_has_key(entry, kDesktopEntry, "X-GNOME-Autostart-enabled",
                          nullptr)) {
    return g_key_file_get_boolean(entry, kDesktopEntry,
                                  "X-GNOME-Autostart-enabled", error);
  }
  return true;
}

bool WorkflowBackground::SetLaunchAtLogin(bool enabled, GError** error) {
  g_autofree gchar* path = AutostartPath();
  if (!enabled) {
    if (g_unlink(path) == 0 || errno == ENOENT) return true;
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Could not remove the AppFlowy autostart entry: %s",
                g_strerror(errno));
    return false;
  }
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", error);
  if (executable == nullptr) return false;
  g_autofree gchar* directory = g_path_get_dirname(path);
  if (g_mkdir_with_parents(directory, 0700) != 0) {
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Could not create the autostart directory: %s",
                g_strerror(errno));
    return false;
  }
  g_autoptr(GKeyFile) entry = g_key_file_new();
  g_key_file_set_string(entry, kDesktopEntry, "Type", "Application");
  g_key_file_set_string(entry, kDesktopEntry, "Name", "AppFlowy");
  g_key_file_set_string(entry, kDesktopEntry, "Exec",
                         QuoteDesktopExecutable(executable).c_str());
  g_key_file_set_string(entry, kDesktopEntry, "Icon", "appflowy");
  g_key_file_set_boolean(entry, kDesktopEntry, "Terminal", FALSE);
  g_key_file_set_boolean(entry, kDesktopEntry, "X-GNOME-Autostart-enabled", TRUE);
  return g_key_file_save_to_file(entry, path, error);
}

void WorkflowBackground::HandleMethodCall(FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* arguments = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = nullptr;
  g_autoptr(GError) error = nullptr;
  if (g_strcmp0(method, "configure") == 0) {
    const bool configured = Configure(arguments, &error);
    if (startup_watchdog_ != 0) {
      g_source_remove(startup_watchdog_);
      startup_watchdog_ = 0;
    }
    if (error != nullptr) ScheduleWindowAction(WindowAction::show);
    result = fl_value_new_bool(configured);
  } else if (g_strcmp0(method, "isLaunchAtLoginEnabled") == 0) {
    result = fl_value_new_bool(IsLaunchAtLoginEnabled(&error));
  } else if (g_strcmp0(method, "setLaunchAtLogin") == 0) {
    FlValue* enabled =
        arguments != nullptr &&
                fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
            ? fl_value_lookup_string(arguments, "enabled")
            : nullptr;
    if (enabled == nullptr ||
        fl_value_get_type(enabled) != FL_VALUE_TYPE_BOOL) {
      g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                          "enabled must be a boolean.");
    } else {
      result = fl_value_new_bool(
          SetLaunchAtLogin(fl_value_get_bool(enabled), &error));
    }
  } else if (g_strcmp0(method, "showWindow") == 0) {
    ScheduleWindowAction(WindowAction::show);
  } else if (g_strcmp0(method, "hideWindow") == 0) {
    if (keep_running_) {
      ScheduleWindowAction(WindowAction::hide);
    } else {
      g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
                          "Enable background mode before hiding AppFlowy.");
    }
  } else if (g_strcmp0(method, "quit") == 0) {
    ScheduleWindowAction(WindowAction::quit);
  } else {
    g_autoptr(GError) response_error = nullptr;
    fl_method_call_respond_not_implemented(call, &response_error);
    if (response_error != nullptr) g_warning("%s", response_error->message);
    return;
  }
  g_autoptr(GError) response_error = nullptr;
  if (error != nullptr) {
    fl_method_call_respond_error(
        call,
        g_error_matches(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT)
            ? "bad-arguments"
            : "background-unavailable",
        error->message, nullptr, &response_error);
  } else {
    fl_method_call_respond_success(call, result, &response_error);
  }
  if (response_error != nullptr) g_warning("%s", response_error->message);
}
