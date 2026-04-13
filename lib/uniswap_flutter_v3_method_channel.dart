import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'uniswap_flutter_v3_platform_interface.dart';

/// An implementation of [UniswapFlutterV3Platform] that uses method channels.
class MethodChannelUniswapFlutterV3 extends UniswapFlutterV3Platform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('uniswap_flutter_v3');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
