# =============================================================================
# Readmigo HarmonyOS NEXT — NDK CMake entry (W3 baseline)
#
# DevEco Studio / hvigorw passes the following variables automatically:
#   -DCMAKE_TOOLCHAIN_FILE=<sdk>/native/build/cmake/ohos.toolchain.cmake
#   -DOHOS_ARCH=arm64-v8a          (HarmonyOS NEXT supports arm64 only)
#   -DOHOS_PLATFORM=OHOS
#   -DCMAKE_BUILD_TYPE=Debug|Release
#
# Output:  libreadmigo_native.so   (loaded by ArkTS via requireNapi)
#
# W3 sources are local to this cpp/ directory. A future W5 milestone will pull
# in the richer engine living under <repo-root>/native/typesetting/ — until
# then the standalone sources below are authoritative.
# =============================================================================

cmake_minimum_required(VERSION 3.20)

project(readmigo_native
    VERSION 0.1.0
    LANGUAGES C CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# HarmonyOS NEXT only ships on arm64-v8a.
if(DEFINED OHOS_ARCH AND NOT OHOS_ARCH STREQUAL "arm64-v8a")
    message(FATAL_ERROR
        "Unsupported OHOS_ARCH='${OHOS_ARCH}'.\n"
        "HarmonyOS NEXT targets arm64-v8a exclusively."
    )
endif()

# ---------------------------------------------------------------------------
# NAPI header resolution
#
#   * Under DevEco Studio, the OHOS toolchain points at the HarmonyOS NDK's
#     napi/native_api.h via the SDK sysroot.
#   * Outside DevEco (local desktop build), we fall back to the napi-bridge
#     stubs at <repo-root>/napi-bridge/stubs/napi/ when present so the sources
#     at least compile in IDE mode.
# ---------------------------------------------------------------------------
if(DEFINED OHOS_SDK_NATIVE_ROOT)
    set(NAPI_INCLUDE_DIR "${OHOS_SDK_NATIVE_ROOT}/sysroot/usr/include")
    add_compile_definitions(OHOS_PLATFORM=1)
else()
    set(_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/../../../../..")
    get_filename_component(_repo_root "${_repo_root}" ABSOLUTE)
    set(NAPI_INCLUDE_DIR "${_repo_root}/napi-bridge/stubs")
    message(STATUS
        "OHOS_SDK_NATIVE_ROOT not set — using napi-bridge stubs at "
        "${NAPI_INCLUDE_DIR} for local desktop builds."
    )
endif()

# ---------------------------------------------------------------------------
# Shared library: libreadmigo_native.so
# ---------------------------------------------------------------------------
add_library(readmigo_native SHARED
    napi_bindings.cpp
    text_layout.cpp
    line_break.cpp
    glyph_metrics.cpp
    utf8.cpp
)

target_include_directories(readmigo_native
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${NAPI_INCLUDE_DIR}"
)

target_compile_options(readmigo_native
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
        $<$<CONFIG:Release>:-O2 -ffunction-sections -fdata-sections>
)

target_link_options(readmigo_native
    PRIVATE
        $<$<CONFIG:Release>:-Wl,--gc-sections>
)

# Link against the HarmonyOS NAPI shared library at runtime. Only required
# in cross-compilation mode (OHOS toolchain).
if(DEFINED OHOS_SDK_NATIVE_ROOT)
    target_link_libraries(readmigo_native
        PRIVATE
            libace_napi.z.so
    )
endif()

# DevEco picks up the .so from the CMake binary dir automatically; setting
# LIBRARY_OUTPUT_DIRECTORY here makes manual / scripted builds drop the .so
# in the same place hvigorw expects.
set_target_properties(readmigo_native PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/arm64-v8a"
)
