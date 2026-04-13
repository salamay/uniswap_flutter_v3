import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'uniswap_flutter_v3_method_channel.dart';

abstract class UniswapFlutterV3Platform extends PlatformInterface {
  /// Constructs a UniswapFlutterV3Platform.
  UniswapFlutterV3Platform() : super(token: _token);

  static final Object _token = Object();

  static UniswapFlutterV3Platform _instance = MethodChannelUniswapFlutterV3();

  /// The default instance of [UniswapFlutterV3Platform] to use.
  ///
  /// Defaults to [MethodChannelUniswapFlutterV3].
  static UniswapFlutterV3Platform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UniswapFlutterV3Platform] when
  /// they register themselves.
  static set instance(UniswapFlutterV3Platform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
