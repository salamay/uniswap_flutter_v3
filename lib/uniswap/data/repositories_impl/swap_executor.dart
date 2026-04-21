import 'dart:typed_data';

import 'package:uniswap_flutter_v3/uniswap/data/datasources/services/swap_service.dart';
import 'package:uniswap_flutter_v3/uniswap/data/datasources/services/transaction_service.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_fee.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/pool.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/repositories/SwapRepository.dart';

import '../../domain/entities/allowance.dart';
import '../../domain/entities/transaction_status.dart';

class SwapExecutor extends SwapRepository {
  late final SwapService swapService;

  SwapExecutor() {
    final transactionService = TransactionService(swapRepository: this);
    swapService = SwapService(transactionService: transactionService);
  }


  @override
  Future<TransactionStatus> waitForTransactionConfirmation(
      {required String txHash,
      required String rpcUrl,
      int maxWaitTime = 60,
      int pollInterval = 2}) {
    return swapService.waitForTransactionConfirmation(txHash: txHash, rpcUrl: rpcUrl, maxWaitTime: maxWaitTime, pollInterval: pollInterval);
  }
  @override
  Future<BigInt> getChainNetworkFee({required String rpcUrl, required int chainId}) {
    // TODO: implement getChainNetworkFee
    return swapService.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);
  }

  @override
  Future<Uint8List> encodeSweepETH({required List param, required String address}) {
    // TODO: implement encodeSweepETH
    return swapService.encodeSweepETH(param: param, address: address);
  }

  @override
  Future<Uint8List> encodeUnwrapWETH({required List param, required String address}) {
    // TODO: implement encodeUnwrapWETH
    return swapService.encodeUnwrapWETH(param: param, address: address);
  }

  @override
  Future<Uint8List> encodeV3SwapExactInput({required List param, required String address}) {
    // TODO: implement encodeV3SwapExactInput
    return swapService.encodeV3SwapExactInput(param: param, address: address);
  }

  @override
  Future<Uint8List> encodeWrapWETH({required List param, required String address}) {
    // TODO: implement encodeWrapWETH
    return swapService.encodeWrapWETH(param: param, address: address);
  }

  @override
  Future<BigInt> estimateApproveTx({required Token from, required NetworkRpc network, required double amountIn, required String privateKey}) {
    // TODO: implement estimateApproveTx
    return swapService.estimateApproveTx(token: from, network: network, amountIn: amountIn, privateKey: privateKey);
  }
  @override
  Future<BigInt> estimatePermit2Approval({required Token token,required  NetworkRpc network, required double amountIn, required String privateKey}) async {
    // TODO: implement estimateApproveTx
    return swapService.estimateApproveTx(token: token, network: network, amountIn: amountIn, privateKey: privateKey);
  }


  @override
  Future<BigInt> estimatePermit2Call(
      {required String privateKey,
      required String tokenAddress,
      required String spenderAddress,
      required String rpcUrl,
      required int chainId
      }) {
    return swapService.estimatePermit2Call(privateKey: privateKey, tokenAddress: tokenAddress, spenderAddress: spenderAddress, rpcUrl: rpcUrl, chainId: chainId);
  }


  @override
  Future<Allowance> getPermitAllowance(
      {required String ownerAddress,
      required String tokenAddress,
      required String spenderAddress,
      required String rpcUrl,
        required int chainId}) {
    return swapService.getPermitAllowance(ownerAddress: ownerAddress, tokenAddress: tokenAddress, spenderAddress: spenderAddress, rpcUrl: rpcUrl, chainId: chainId);
  }

  @override
  Future<BigInt> estimateNativeToTokenSwapTx({required String privateKey, required Pool pool, required BigInt amountIn, required BigInt amountOutMin, required BigInt poolFee, required NetworkRpc network}) {
    // TODO: implement estimateNativeToTokenSwapTx
    return swapService.estimateNativeToTokenSwapTx(privateKey: privateKey, pool: pool, amountIn: amountIn, amountOutMin: amountOutMin, poolFee: poolFee, network: network);
  }

  @override
  Future<BigInt> estimateSwapTx({required String privateKey, required String fromAddress, required BigInt poolFee, required Pool pair, required BigInt amountIn, required NetworkRpc network}) {
    // TODO: implement estimateSwapTx
    return swapService.estimateSwapTx(privateKey: privateKey, fromAddress: fromAddress, poolFee: poolFee, pair: pair, amountIn: amountIn, network: network);
  }

  @override
  Future<BigInt> estimateTokenToNativeSwapTx({required String privateKey, required Pool pool, required NetworkRpc network, required BigInt amountIn, required BigInt wethAmountMin, required BigInt poolFee}) {
    // TODO: implement estimateTokenToNativeSwapTx
    return swapService.estimateTokenToNativeSwapTx(privateKey: privateKey, pool: pool, network: network, amountIn: amountIn, wethAmountMin: wethAmountMin, poolFee: poolFee);
  }


  @override
  Future<String> getUniswapPaymentAbi() {
    // TODO: implement getUniswapPaymentAbi
    return swapService.getUniswapPaymentAbi();
  }

  @override
  Future<String> getUniswapSwapRouterAbi() {
    // TODO: implement getUniswapSwapRouterAbi
    return swapService.getUniswapSwapRouterAbi();
  }

  @override
  String getUniswapSwapRouterAddress({required int chainId}) {
    // TODO: implement getUniswapSwapRouterAddress
    return swapService.getUniswapSwapRouterAddress(chainId: chainId);
  }

  @override
  Future<String> getUniswapUniversalRouterAbi() {
    // TODO: implement getUniswapUniversalRouterAbi
    return swapService.getUniswapUniversalRouterAbi();
  }

  @override
  String getUniversalRouterAddress({required int chainId}) {
    // TODO: implement getUniversalRouterAddress
    return swapService.getUniversalRouterAddress(chainId: chainId);
  }

  @override
  String getWETHContractAddress({required int chainId}) {
    // TODO: implement getWETHContractAddress
    return swapService.getWETHContractAddress(chainId: chainId);
  }

  @override
  Future<Pool?> getPool({required int chainId, required Token token0, required Token token1, required String rpcUrl}) {
    return swapService.getPool(chainId: chainId, token0: token0, token1: token1, rpcUrl: rpcUrl);
  }

  @override
  Future<String> approve({required String privateKey, required String spender, required  Token token, required BigInt amountIn, required NetworkRpc network,required NetworkFee fee}) async {
    return swapService.approve(privateKey: privateKey, spender: spender, token: token, amountIn: amountIn, network: network, fee: fee);
  }


  @override
  Future<String> swap({required String privateKey, required BigInt poolFee, required Pool pair, required BigInt amountIn, required BigInt amountOutMin, required NetworkFee fee, required NetworkRpc network}) {
    // TODO: implement swap
    return swapService.swap(privateKey: privateKey, poolFee: poolFee, pair: pair, amountIn: amountIn, amountOutMin: amountOutMin, fee: fee, network: network);
  }

  @override
  Future<String> tokenToNativeSwap({required String privateKey, required Pool pool, required BigInt amountIn, required BigInt wethAmountMin, required NetworkRpc network, required NetworkFee fee, required BigInt poolFee}) {
    // TODO: implement tokenToNativeSwap
    return swapService.tokenToNativeSwap(privateKey: privateKey, pool: pool, amountIn: amountIn, wethAmountMin: wethAmountMin, network: network, fee: fee, poolFee: poolFee);
  }

  @override
  Future<String> nativeToTokenSwap({required String privateKey, required Pool pool, required BigInt amountIn, required BigInt wethAmountMin, required BigInt poolFee, required NetworkFee fee, required NetworkRpc network}) {
    // TODO: implement nativeToTokenSwap
    return swapService.nativeToTokenSwap(privateKey: privateKey, pool: pool, amountIn: amountIn, wethAmountMin: wethAmountMin, poolFee: poolFee, fee: fee, network: network);
  }

  @override
  Future<String> callPermit(
      {required String privateKey,
      required String tokenAddress,
      required String spenderAddress,
      required String rpcUrl,
      required int chainId,
      required String chainSymbol,
      required NetworkFee fee}) {
    return swapService.callPermit(privateKey: privateKey, tokenAddress: tokenAddress, spenderAddress: spenderAddress, rpcUrl: rpcUrl, chainId: chainId, chainSymbol: chainSymbol, fee: fee);
  }
}