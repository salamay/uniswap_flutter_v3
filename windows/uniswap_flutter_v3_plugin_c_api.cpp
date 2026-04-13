#include "include/uniswap_flutter_v3/uniswap_flutter_v3_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "uniswap_flutter_v3_plugin.h"

void UniswapFlutterV3PluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  uniswap_flutter_v3::UniswapFlutterV3Plugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
