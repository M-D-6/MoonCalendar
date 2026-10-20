cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. Change BINARY_NAME in the top-level
# CMakeLists.txt if you need to change the executable name.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

apply_standard_settings(${BINARY_NAME})
target_compile_options(${BINARY_NAME} PRIVATE /utf-8)

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"1.1.8\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=1")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=1")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=7")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=12")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "psapi.lib")
add_dependencies(${BINARY_NAME} flutter_assemble)
