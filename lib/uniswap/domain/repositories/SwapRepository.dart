import 'package:flutter/services.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/pool.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';

import '../../utils/constants/constants.dart';
import '../entities/network_fee.dart';
import '../entities/network_rpc.dart';
import '../entities/transaction_status.dart';

abstract class SwapRepository {


  Future<String> getUniswapSwapRouterAbi();
  Future<String> getUniswapUniversalRouterAbi();
  Future<String> getUniswapPaymentAbi();
  String getUniversalRouterAddress({required int chainId});
  String getUniswapSwapRouterAddress({required int chainId});
  String getWETHContractAddress({required int chainId});
  Future<TransactionStatus> waitForTransactionConfirmation({
    required String txHash,
    required String rpcUrl,
    int maxWaitTime = 60,
    int pollInterval = 2,
  });

  Future<Pool?> getPool({required int chainId, required Token token0, required Token token1, required String graphApiKey});

  Future<BigInt> estimateApproveTx({required Token from,required  NetworkRpc network, required double amountIn, required String privateKey});
  Future<BigInt> estimateSwapTx({required String privateKey, required String fromAddress, required BigInt poolFee, required Pool pair, required BigInt amountIn, required NetworkRpc network});
  Future<BigInt> estimateTokenToNativeSwapTx({ required String privateKey,required Pool pool, required NetworkRpc network,required BigInt amountIn,required BigInt wethAmountMin, required BigInt poolFee});
  Future<BigInt> estimateNativeToTokenSwapTx({required String privateKey,required Pool pool,required BigInt amountIn, required BigInt amountOutMin, required BigInt poolFee,required NetworkRpc network});

  Future<String> swap({required String privateKey,required BigInt poolFee, required Pool pair, required BigInt amountIn, required BigInt amountOutMin, required NetworkFee fee,required NetworkRpc network});
  Future<String> tokenToNativeSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt wethAmountMin,required NetworkRpc network,required NetworkFee fee, required BigInt poolFee});
  Future<String> nativeToTokenSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt amountOutMin, required BigInt wethAmountMin, required BigInt poolFee,required NetworkFee fee,required NetworkRpc network});


  Future<Uint8List> encodeV3SwapExactInput({required List<dynamic> param, required String address});
  Future<Uint8List> encodeWrapWETH({required List<dynamic> param, required String address});
  Future<Uint8List> encodeUnwrapWETH({required List<dynamic> param, required String address});
  Future<Uint8List> encodeSweepETH({required List<dynamic> param, required String address});



  }