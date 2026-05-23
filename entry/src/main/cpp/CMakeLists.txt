# =============================================================================
# Readmigo HarmonyOS NEXT — top-level NDK CMake entry
#
# DevEco Studio / hvigorw passes the following variables automatically when it
# invokes CMake through the OHOS toolchain:
#
#   -DCMAKE_TOOLCHAIN_FILE=<sdk>/native/build/cmake/ohos.toolchain.cmake
#   -DOHOS_ARCH=arm64-v8a          (HarmonyOS NEXT supports arm64 only)
#   -DOHOS_PLATFORM=OHOS
#   -DCMAKE_BUILD_TYPE=Debug|Release
#
# Output: libreadmigo_native.so
#   Packaged automatically by hvigorw into:
#     entry/libs/arm64-v8a/libreadmigo_native.so  →  HAP bundle
# =============================================================================

cmake_minimum_required(VERSION 3.20)

project(readmigo_native
    VERSION 0.1.0
    LANGUAGES C CXX
)

# ---------------------------------------------------------------------------
# Language standard
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# All static libraries must be compiled as PIC so they can be linked into
# a shared library (.so) on Linux/OHOS.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Export compile_commands.json for IDE tooling.
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ---------------------------------------------------------------------------
# Architecture guard
# HarmonyOS NEXT only ships on arm64-v8a devices.  Catch mis-configurations
# early rather than producing a silently broken binary.
# ---------------------------------------------------------------------------
if(DEFINED OHOS_ARCH AND NOT OHOS_ARCH STREQUAL "arm64-v8a")
    message(FATAL_ERROR
        "Unsupported OHOS_ARCH='${OHOS_ARCH}'.\n"
        "HarmonyOS NEXT targets arm64-v8a exclusively.\n"
        "Pass -DOHOS_ARCH=arm64-v8a or let DevEco set it automatically."
    )
endif()

# When cross-compiling via the OHOS toolchain, CMAKE_SYSTEM_PROCESSOR is set
# to 'aarch64'.  Verify it if the toolchain file is already active.
if(CMAKE_CROSSCOMPILING AND
   NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" AND
   NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
    message(WARNING
        "CMAKE_SYSTEM_PROCESSOR='${CMAKE_SYSTEM_PROCESSOR}' — "
        "expected 'aarch64' for OHOS arm64-v8a."
    )
endif()

# ---------------------------------------------------------------------------
# Paths — all source trees live in the monorepo root, four levels above
# entry/src/main/cpp/.
#
#   <repo-root>/
#     native/typesetting/     (C++ typesetting engine)
#     native/badge-engine/    (C++ 3D badge renderer)
#     napi-bridge/src/        (NAPI binding sources)
# ---------------------------------------------------------------------------
set(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../..")
get_filename_component(REPO_ROOT "${REPO_ROOT}" ABSOLUTE)

set(TYPESETTING_DIR   "${REPO_ROOT}/native/typesetting")
set(BADGE_ENGINE_DIR  "${REPO_ROOT}/native/badge-engine")
set(NAPI_BRIDGE_DIR   "${REPO_ROOT}/napi-bridge")

# Sanity-check that subdirectory paths resolve to real locations.
foreach(_dir TYPESETTING_DIR BADGE_ENGINE_DIR NAPI_BRIDGE_DIR)
    if(NOT EXISTS "${${_dir}}")
        message(FATAL_ERROR
            "${_dir}='${${_dir}}' does not exist.\n"
            "Ensure the monorepo structure is intact."
        )
    endif()
endforeach()

# ---------------------------------------------------------------------------
# HarmonyOS SDK compile-time flags
#
# OHOS_SDK_NATIVE_ROOT is injected by the OHOS toolchain file and points to
# <sdk>/native/.  We derive the NAPI include path from it when available;
# otherwise we fall back to a well-known relative path inside the SDK.
# ---------------------------------------------------------------------------
if(DEFINED OHOS_SDK_NATIVE_ROOT)
    set(NAPI_INCLUDE_DIR "${OHOS_SDK_NATIVE_ROOT}/oh_jsvm")
    # The OHOS toolchain already sets the sysroot; but we explicitly mark the
    # compile-SDK version so downstream code can do #if checks.
    add_compile_definitions(
        OHOS_PLATFORM=1
        OHOS_SDK_VERSION=12      # HarmonyOS NEXT API 12 baseline
    )
else()
    # Fallback for local builds without the toolchain file (unit-test builds on
    # macOS/Linux use stub headers placed alongside the bridge).
    set(NAPI_INCLUDE_DIR "${NAPI_BRIDGE_DIR}/include/stub")
    message(STATUS
        "OHOS_SDK_NATIVE_ROOT not set — "
        "falling back to stub NAPI headers for local builds."
    )
endif()

# ---------------------------------------------------------------------------
# Sub-library 1: typesetting (static)
#
# We enable the HarmonyOS platform adapter so that the engine uses OHOS
# font/layout APIs instead of CoreText.  Tests and macOS tools are disabled
# because they are irrelevant in the NDK cross-compilation context.
# ---------------------------------------------------------------------------
set(TYPESETTING_PLATFORM_HARMONY ON  CACHE BOOL "Use OHOS platform adapter"    FORCE)
set(TYPESETTING_BUILD_TESTS      OFF CACHE BOOL "Skip typesetting tests in NDK" FORCE)
set(TYPESETTING_BUILD_TOOLS      OFF CACHE BOOL "Skip CLI tools in NDK"         FORCE)

add_subdirectory("${TYPESETTING_DIR}" native_typesetting_build)
# The CMakeLists in native/typesetting/ defines the target named 'typesetting'.

# ---------------------------------------------------------------------------
# Sub-library 2: badge_engine (static)
#
# Filament is disabled by default; enable it only when the Filament SDK is
# present and the caller explicitly sets BADGE_ENGINE_USE_FILAMENT=ON.
# Tests and examples are off in the NDK context.
# ---------------------------------------------------------------------------
set(BADGE_ENGINE_BUILD_TESTS    OFF CACHE BOOL "Skip badge-engine tests"    FORCE)
set(BADGE_ENGINE_BUILD_EXAMPLES OFF CACHE BOOL "Skip badge-engine examples" FORCE)
# BADGE_ENGINE_USE_FILAMENT defaults to OFF inside badge-engine/CMakeLists.txt;
# do not override here — let the caller pass -DBADGE_ENGINE_USE_FILAMENT=ON if
# the Filament SDK has been set up on the build machine.

add_subdirectory("${BADGE_ENGINE_DIR}" native_badge_engine_build)
# The CMakeLists in native/badge-engine/ defines the target named 'badge_engine'.

# ---------------------------------------------------------------------------
# Shared library: libreadmigo_native.so
#
# This is the single .so that the ArkTS runtime loads via:
#   import native from 'libreadmigo_native.so'
#
# NAPI binding sources are compiled directly into this shared library rather
# than into a separate static lib so that NAPI symbols are resolved against
# the HarmonyOS NAPI ABI at link time.
# ---------------------------------------------------------------------------

# Enumerate NAPI bridge sources.  Files are listed explicitly (not glob) so
# that CMake re-configures when new files are added to the source tree.
set(NAPI_BRIDGE_SOURCES
    # Common utilities shared by all NAPI modules
    "${NAPI_BRIDGE_DIR}/src/common/napi_error.cpp"
    "${NAPI_BRIDGE_DIR}/src/common/napi_convert.cpp"

    # Typesetting NAPI bindings
    "${NAPI_BRIDGE_DIR}/src/typesetting_napi.cpp"
    "${NAPI_BRIDGE_DIR}/src/typesetting_bridge.cpp"

    # Badge-engine NAPI bindings
    "${NAPI_BRIDGE_DIR}/src/badge_engine_napi.cpp"
)

# Warn — not error — for sources that don't exist yet.  During early
# development some files are stubs; the build will fail at compile time
# with a clear message rather than a confusing CMake configure error.
foreach(_src ${NAPI_BRIDGE_SOURCES})
    if(NOT EXISTS "${_src}")
        message(WARNING "NAPI source not found (will fail at compile): ${_src}")
    endif()
endforeach()

add_library(readmigo_native SHARED ${NAPI_BRIDGE_SOURCES})

# ---------------------------------------------------------------------------
# Include paths for readmigo_native
# ---------------------------------------------------------------------------
target_include_directories(readmigo_native
    PRIVATE
        # NAPI / JSVM headers from the HarmonyOS SDK
        "${NAPI_INCLUDE_DIR}"

        # napi-bridge public headers (napi_error.h, napi_convert.h, etc.)
        "${NAPI_BRIDGE_DIR}/include"

        # napi-bridge internal sources (typesetting_bridge.h, etc.)
        "${NAPI_BRIDGE_DIR}/src"

        # Typesetting engine public API
        "${TYPESETTING_DIR}/include"

        # Badge-engine public API
        "${BADGE_ENGINE_DIR}/include"
)

# ---------------------------------------------------------------------------
# Link libraries
# ---------------------------------------------------------------------------
target_link_libraries(readmigo_native
    PRIVATE
        # ── Native engine static libraries ──────────────────────────────────
        typesetting         # from native/typesetting/CMakeLists.txt
        badge_engine        # from native/badge-engine/CMakeLists.txt

        # ── HarmonyOS system libraries ───────────────────────────────────────
        # libace_napi.z.so  provides the napi_* symbol table.
        # The .so suffix tells the linker to treat it as a system shared lib
        # that will be present at runtime in the OHOS environment; it must NOT
        # be bundled inside the HAP.
        libace_napi.z.so

        # libnative_window.so is required by XComponent (the OHOS surface that
        # the badge-engine renders into).  Link it only when XComponent APIs
        # are used; harmless to include unconditionally for future use.
        libnative_window.so
)

# ---------------------------------------------------------------------------
# Compiler flags
# ---------------------------------------------------------------------------
target_compile_options(readmigo_native
    PRIVATE
        # Treat warnings as errors in Debug builds to keep quality high.
        $<$<CONFIG:Debug>:-Wall -Wextra -Wpedantic>

        # Release: aggressive optimisation + strip debug info.
        $<$<CONFIG:Release>:-O2 -ffunction-sections -fdata-sections>
)

# Strip unused sections at link time in Release builds to reduce .so size.
target_link_options(readmigo_native
    PRIVATE
        $<$<CONFIG:Release>:-Wl,--gc-sections>
)

# ---------------------------------------------------------------------------
# Output location
# DevEco Studio automatically picks up the .so from the cmake binary dir;
# the hvigorw build task then copies it into entry/libs/arm64-v8a/.
# Setting LIBRARY_OUTPUT_DIRECTORY here makes manual / script builds
# (build-native.sh) deposit the .so in the expected location too.
# ---------------------------------------------------------------------------
set_target_properties(readmigo_native PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../../harmony-app/entry/libs/arm64-v8a"
)
