import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';

class Pool {
  String? feeTier;
  String poolAddress;
  double? token0Price;
  double? token1Price;
  double? volumeToken0;
  double? volumeToken1;
  double? volumeUsd;
  double? liquidity;
  Token token0;
  Token token1;
  bool isInverse;

  Pool({
    required this.feeTier,
    required this.token0Price,
    required this.token1Price,
    this.volumeToken0,
    this.volumeToken1,
    this.volumeUsd,
    this.liquidity,
    required this.token0,
    required this.token1,
    required this.poolAddress,
    required this.isInverse,
  });

}