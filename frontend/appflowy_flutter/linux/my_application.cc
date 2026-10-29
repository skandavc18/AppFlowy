#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Files the system asks AppFlowy to open reach Dart on this channel.
static constexpr char kFileOpenChannel[] = "appflowy/file_open";

struct _MyApplication
{
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
  FlMethodChannel *file_open_channel;
  // Paths waiting for Dart, which asks for them once it is listening.
  GPtrArray *pending_files;
  gboolean dart_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue *take_pending_files(MyApplication *self)
{
  FlValue *paths = fl_value_new_list();
  for (guint i = 0; i < self->pending_files->len; i++)
  {
    fl_value_append_take(
        paths,
        fl_value_new_string(
            static_cast<const gchar *>(g_ptr_array_index(self->pending_files, i))));
  }
  g_ptr_array_set_size(self->pending_files, 0);
  return paths;
}

static void send_pending_files(MyApplication *self)
{
  if (!self->dart_ready || self->file_open_channel == nullptr ||
      self->pending_files->len == 0)
  {
    return;
  }
  g_autoptr(FlValue) paths = take_pending_files(self);
  fl_method_channel_invoke_method(self->file_open_channel, "openFiles", paths,
                                  nullptr, nullptr, nullptr);
}

static void file_open_method_call_cb(FlMethodChannel *channel,
                                     FlMethodCall *method_call,
                                     gpointer user_data)
{
  MyApplication *self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  if (g_strcmp0(fl_method_call_get_name(method_call), "takePendingFiles") == 0)
  {
    self->dart_ready = TRUE;
    g_autoptr(FlValue) paths = take_pending_files(self);
    fl_method_call_respond_success(method_call, paths, &error);
  }
  else
  {
    fl_method_call_respond_not_implemented(method_call, &error);
  }
  if (error != nullptr)
  {
    g_warning("Failed to answer on %s: %s", kFileOpenChannel, error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application)
{
  MyApplication *self = MY_APPLICATION(application);

  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_title(window, "AppFlowy");

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView *view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // A new window runs a new engine, which has to ask for files again.
  g_clear_object(&self->file_open_channel);
  self->dart_ready = FALSE;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->file_open_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      kFileOpenChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->file_open_channel, file_open_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open, for files named on this command line, on a
// later launch while AppFlowy runs, or through D-Bus activation.
static void my_application_open(GApplication *application, GFile **files,
                                gint n_files, const gchar *hint)
{
  MyApplication *self = MY_APPLICATION(application);
  for (gint i = 0; i < n_files; i++)
  {
    g_autofree gchar *path = g_file_get_path(files[i]);
    if (path != nullptr && g_file_test(path, G_FILE_TEST_IS_REGULAR))
    {
      g_ptr_array_add(self->pending_files, g_steal_pointer(&path));
    }
  }
  // Raises the window, or creates it when these files launched AppFlowy.
  g_application_activate(application);
  send_pending_files(self);
}

// The absolute path of the regular file [argument] names, or null. File
// managers pass file: URIs, and URIs of network shares that GVfs exposes
// as local paths. Options and appflowy-flutter: deep links are not files.
static gchar *regular_file_path(const gchar *argument)
{
  if (argument[0] == '\0' || argument[0] == '-')
  {
    return nullptr;
  }
  // A name such as "notes:draft.md" looks like a URI but is a file here.
  g_autoptr(GFile) file = g_file_test(argument, G_FILE_TEST_IS_REGULAR)
                              ? g_file_new_for_path(argument)
                              : g_file_new_for_commandline_arg(argument);
  gchar *path = g_file_get_path(file);
  if (path != nullptr && !g_file_test(path, G_FILE_TEST_IS_REGULAR))
  {
    g_clear_pointer(&path, g_free);
  }
  return path;
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application, gchar ***arguments, int *exit_status)
{
  MyApplication *self = MY_APPLICATION(application);

  // Files are opened rather than passed on. The rest of the command line
  // still reaches the deep link handler, which reads its first argument as
  // a link.
  g_autoptr(GPtrArray) kept = g_ptr_array_new_with_free_func(g_free);
  g_autoptr(GPtrArray) files = g_ptr_array_new_with_free_func(g_object_unref);
  for (gchar **argument = *arguments; *argument != nullptr; argument++)
  {
    g_autofree gchar *path =
        argument == *arguments ? nullptr : regular_file_path(*argument);
    if (path != nullptr)
    {
      g_ptr_array_add(files, g_file_new_for_path(path));
    }
    else
    {
      g_ptr_array_add(kept, g_strdup(*argument));
    }
  }
  g_ptr_array_add(kept, nullptr);
  g_strfreev(*arguments);
  *arguments = reinterpret_cast<gchar **>(
      g_ptr_array_free(static_cast<GPtrArray *>(g_steal_pointer(&kept)), FALSE));

  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error))
  {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (files->len > 0)
  {
    // A running AppFlowy opens them in its window; otherwise this one does.
    g_application_open(application,
                       reinterpret_cast<GFile **>(files->pdata),
                       static_cast<gint>(files->len), "");
  }
  else
  {
    g_application_activate(application);
  }
  *exit_status = 0;

  return FALSE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object)
{
  MyApplication *self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->file_open_channel);
  g_clear_pointer(&self->pending_files, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass)
{
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self)
{
  self->pending_files = g_ptr_array_new_with_free_func(g_free);
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
