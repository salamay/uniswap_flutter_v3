//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <uniswap_flutter_v3/uniswap_flutter_v3_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
  UniswapFlutterV3PluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UniswapFlutterV3PluginCApi"));
}
