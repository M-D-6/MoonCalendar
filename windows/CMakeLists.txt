# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(mooncalendar LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "mooncalendar")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release" CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Profile" "Release")
  endif()
endif()

# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This also makes building and running from Visual Studio work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
endif()

# Bundle the MSVC runtime locally when it is available on the build machine.
# Flutter's Windows deployment guidance calls for these runtime DLLs next to
# the executable so the app does not depend on a separately installed VC++
# runtime on the target machine.
get_filename_component(MSVC_BIN_DIR "${CMAKE_CXX_COMPILER}" DIRECTORY)
get_filename_component(MSVC_HOST_DIR "${MSVC_BIN_DIR}" DIRECTORY)
get_filename_component(MSVC_TOOLS_BIN_DIR "${MSVC_HOST_DIR}" DIRECTORY)
get_filename_component(MSVC_TOOLSET_DIR "${MSVC_TOOLS_BIN_DIR}" DIRECTORY)
get_filename_component(MSVC_TOOLS_DIR "${MSVC_TOOLSET_DIR}" DIRECTORY)
get_filename_component(MSVC_VC_DIR "${MSVC_TOOLS_DIR}" DIRECTORY)

set(MSVC_RUNTIME_ROOTS
  "${MSVC_VC_DIR}/Redist/MSVC"
  "$ENV{SystemRoot}/System32"
)

# Runtime folder name inside the Visual C++ redistributable: x64 or arm64.
if(CMAKE_GENERATOR_PLATFORM MATCHES "(?i)arm64" OR CMAKE_SYSTEM_PROCESSOR MATCHES "(?i)arm64|aarch64")
  set(MSVC_RUNTIME_ARCH "arm64")
else()
  set(MSVC_RUNTIME_ARCH "x64")
endif()

foreach(MSVC_RUNTIME_NAME IN ITEMS
  msvcp140.dll
  vcruntime140.dll
  vcruntime140_1.dll
)
  unset(MSVC_RUNTIME_FILE CACHE)
  find_file(MSVC_RUNTIME_FILE
    NAMES "${MSVC_RUNTIME_NAME}"
    PATHS ${MSVC_RUNTIME_ROOTS}
    PATH_SUFFIXES "${MSVC_RUNTIME_ARCH}/Microsoft.VC143.CRT" "${MSVC_RUNTIME_ARCH}"
    NO_DEFAULT_PATH
  )
  if(NOT MSVC_RUNTIME_FILE)
    find_file(MSVC_RUNTIME_FILE
      NAMES "${MSVC_RUNTIME_NAME}"
      PATHS "$ENV{SystemRoot}/System32"
      NO_DEFAULT_PATH
    )
  endif()

  if(MSVC_RUNTIME_FILE)
    install(FILES "${MSVC_RUNTIME_FILE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
  else()
    message(WARNING "Could not locate ${MSVC_RUNTIME_NAME}. The Windows app may require the Microsoft Visual C++ Redistributable on the target machine.")
  endif()
endforeach()

# Copy native assets provided by packages.
# Flutter's build target depends on the application target, so these assets
# are available by the time CMake reaches the install stage. Keep this as a
# normal install(DIRECTORY) rule so Flutter's generated INSTALL.vcxproj can
# handle the bundle in the same way as a standard Windows Flutter project.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)

# Remove any stale Flutter asset bundle and then install the freshly-generated
# assets. In Debug this directory contains kernel_blob.bin, which the Flutter
# engine needs to start the Dart VM.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")" COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" CONFIGURATIONS Profile;Release COMPONENT Runtime)

set_property(DIRECTORY PROPERTY VS_STARTUP_PROJECT ${BINARY_NAME})

if(DEFINED FLUTTER_APP_FLAVOR)
  add_definitions(-DFLUTTER_APP_FLAVOR="${FLUTTER_APP_FLAVOR}")
endif()
