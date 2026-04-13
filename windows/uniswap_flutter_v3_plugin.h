#ifndef FLUTTER_PLUGIN_UNISWAP_FLUTTER_V3_PLUGIN_H_
#define FLUTTER_PLUGIN_UNISWAP_FLUTTER_V3_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace uniswap_flutter_v3 {

class UniswapFlutterV3Plugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  UniswapFlutterV3Plugin();

  virtual ~UniswapFlutterV3Plugin();

  // Disallow copy and assign.
  UniswapFlutterV3Plugin(const UniswapFlutterV3Plugin&) = delete;
  UniswapFlutterV3Plugin& operator=(const UniswapFlutterV3Plugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace uniswap_flutter_v3

#endif  // FLUTTER_PLUGIN_UNISWAP_FLUTTER_V3_PLUGIN_H_
