import 'package:uniswap_flutter_v3/uniswap/utils/token_factory.dart';
import 'package:web3dart/web3dart.dart';




class ClientResolver{
  static TokenFactory _tokenFactory=TokenFactory();

  static Future<Web3Client> resolveClient({required String rpcUrl}) async {
    Web3Client? webClient=await _tokenFactory.initWebClient(rpcUrl);
    return webClient;
  }

}