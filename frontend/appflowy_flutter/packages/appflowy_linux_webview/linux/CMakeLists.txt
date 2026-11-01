cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "appflowy_linux_webview")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "appflowy_linux_webview_plugin")

# WebKitGTK is loaded at runtime (see the .cc file), so neither its headers
# nor its library are needed to build, and AppFlowy still starts without it.
add_library(${PLUGIN_NAME} SHARED
  "appflowy_linux_webview_plugin.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${CMAKE_DL_LIBS})

set(appflowy_linux_webview_bundled_libraries
  ""
  PARENT_SCOPE
)
