import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniswap_flutter_v3/uniswap_flutter_v3_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelUniswapFlutterV3 platform = MethodChannelUniswapFlutterV3();
  const MethodChannel channel = MethodChannel('uniswap_flutter_v3');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
