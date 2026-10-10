cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Flutter's generated_config.cmake is loaded in the flutter subdirectory. Its
# DART_DEFINES normally lives inside FLUTTER_TOOL_ENVIRONMENT, not in this scope.
get_directory_property(SELUMN_DART_DEFINES
  DIRECTORY "${FLUTTER_MANAGED_DIR}" DEFINITION DART_DEFINES)
get_directory_property(SELUMN_FLUTTER_TOOL_ENVIRONMENT
  DIRECTORY "${FLUTTER_MANAGED_DIR}" DEFINITION FLUTTER_TOOL_ENVIRONMENT)
include("${CMAKE_CURRENT_SOURCE_DIR}/selumn_environment.cmake")
selumn_windows_product_name(SELUMN_PRODUCT_NAME
  "${SELUMN_DART_DEFINES}" "${SELUMN_FLUTTER_TOOL_ENVIRONMENT}")
# path_provider and secure storage both use this resource to choose their data
# directory. Production must retain the existing product name.
target_compile_definitions(${BINARY_NAME} PRIVATE
  "SELUMN_PRODUCT_NAME=\"${SELUMN_PRODUCT_NAME}\"")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
