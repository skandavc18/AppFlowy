#ifndef DISPLAY_VSYNC_H_
#define DISPLAY_VSYNC_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Has [view]'s engine start its frames on the display's refreshes instead of
// at a fixed 60 Hz. Call after fl_view_new and before the view is realized,
// which starts the engine. Does nothing if the engine is not the version this
// was built for, or when APPFLOWY_DISPLAY_VSYNC is 0.
void appflowy_display_vsync_install(FlView* view, GtkWindow* window);

#endif  // DISPLAY_VSYNC_H_
