#pragma once

// NAPI / Node-API entry point declarations.
//
// HarmonyOS's NAPI implementation is ABI-compatible with Node-API; we include
// <napi/native_api.h> (HarmonyOS NDK path). Local builds without the OHOS SDK
// can stub this header — see the README for instructions.

#include <napi/native_api.h>

namespace readmigo::napi {

// Registers all exported functions onto the `exports` object.
// Called from the module init callback in napi_bindings.cpp.
napi_value RegisterTypesettingModule(napi_env env, napi_value exports);

}  // namespace readmigo::napi
