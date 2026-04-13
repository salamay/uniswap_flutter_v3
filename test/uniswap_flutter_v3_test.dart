import 'package:flutter_test/flutter_test.dart';
import 'package:uniswap_flutter_v3/uniswap_flutter_v3.dart';
import 'package:uniswap_flutter_v3/uniswap_flutter_v3_platform_interface.dart';
import 'package:uniswap_flutter_v3/uniswap_flutter_v3_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockUniswapFlutterV3Platform
    with MockPlatformInterfaceMixin
    implements UniswapFlutterV3Platform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final UniswapFlutterV3Platform initialPlatform = UniswapFlutterV3Platform.instance;

  test('$MethodChannelUniswapFlutterV3 is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelUniswapFlutterV3>());
  });

  test('getPlatformVersion', () async {
    UniswapFlutterV3 uniswapFlutterV3Plugin = UniswapFlutterV3();
    MockUniswapFlutterV3Platform fakePlatform = MockUniswapFlutterV3Platform();
    UniswapFlutterV3Platform.instance = fakePlatform;

    expect(await uniswapFlutterV3Plugin.getPlatformVersion(), '42');
  });
}
