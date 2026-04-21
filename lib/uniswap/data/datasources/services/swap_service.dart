import 'package:flutter/services.dart';
import 'package:uniswap_flutter_v3/uniswap/data/datasources/services/transaction_service.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/allowance.dart';

import 'package:uniswap_flutter_v3/uniswap/utils/token_factory.dart';
import 'package:web3dart/web3dart.dart';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';

import 'package:uniswap_flutter_v3/uniswap/domain/repositories/SwapRepository.dart';
import 'package:wallet/wallet.dart';

import '../../../domain/entities/network_fee.dart';
import '../../../domain/entities/pool.dart';
import '../../../domain/entities/token.dart';
import '../../../domain/entities/transaction_status.dart';
import '../../../utils/client_resolver.dart';
import '../../../utils/constants/abi_paths.dart';
import '../../../utils/constants/constants.dart';
import '../../../utils/logger.dart';
import '../../../utils/my_encoder.dart';




class SwapService {

    final TransactionService transactionService;
    SwapService ({required this.transactionService});

  Future<String> getUniswapSwapRouterAbi() async {
    return await rootBundle.loadString(uniswap_swap_router_abi);
  }

  Future<String> getUniswapUniversalRouterAbi() async {
    return await rootBundle.loadString(uniswap_universal_router_abi);
  }

  Future<String> getUniswapPaymentAbi() async {
    return await rootBundle.loadString(uniswap_payment_abi);
  }

  String getUniversalRouterAddress({required int chainId}) {
    switch (chainId) {
      case chain_id_bsc:
        return bsc_uniswap_universal_router_contract;
      case chain_id_pol:
        return pol_uniswap_universal_router_contract;
      case chain_id_eth:
        return eth_uniswap_universal_router_contract;
      default:
        return bsc_uniswap_universal_router_contract;
    }
  }

  String getUniswapSwapRouterAddress({required int chainId}) {
    switch (chainId) {
      case chain_id_bsc:
        return bsc_swapRouter02;
      case chain_id_pol:
        return pol_swapRouter02;
      case chain_id_eth:
        return eth_swapRouter02;
      default:
        return bsc_swapRouter02;
    }
  }


  String getWETHContractAddress({required int chainId}) {
    switch (chainId) {
      case chain_id_bsc:
        return bsc_wbnb_contract;
      case chain_id_pol:
        return polygon_wpol_contract;
      case chain_id_eth:
        return eth_weth_contract;
      default:
        return eth_weth_contract;
    }
  }

    Future<TransactionStatus> waitForTransactionConfirmation({
      required String txHash,
      required String rpcUrl,
      int maxWaitTime = 60,
      int pollInterval = 2,
    })async{
      try {
        return await transactionService.waitForTransactionConfirmation(txHash: txHash, rpcUrl: rpcUrl, maxWaitTime: maxWaitTime, pollInterval: pollInterval);
      }catch (e){
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }
    Future<BigInt> getPoolFee({required Pool pool, required NetworkRpc network, required String poolAbi}) async {
      logger("Swap: Getting pool fee $pool.",runtimeType.toString());
      try {
        TokenFactory tokenFactory = TokenFactory();
        int chainId = network.chainId;
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: network.rpcUrl);
        Token tokenIn = pool.token0;

        Token tokenOut = pool.token1;
        String poolAddress = pool.poolAddress;
        DeployedContract poolContract = await tokenFactory.intContract(poolAbi, poolAddress, tokenIn.symbol);
        final balanceFunction = poolContract.function('fee');
        final balance = await web3client.call(contract: poolContract, function: balanceFunction, params: []);
        BigInt amount = balance.first;
        logger('${tokenIn.symbol}/${tokenOut.symbol} Pool fee: $amount',runtimeType.toString());
        return amount;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }

    /// Discovers the best liquidity pool for a token pair directly from on-chain
    /// contracts (Uniswap V3 Factory + Pool).
    ///
    /// Iterates over all standard fee tiers (100, 500, 3000, 10000), queries the
    /// Factory for each, reads slot0 (sqrtPriceX96) and liquidity from each Pool
    /// contract, and returns the pool with the highest liquidity.
    ///
    /// Token prices are derived on-chain from sqrtPriceX96.
    Future<Pool?> getPool({required int chainId, required Token token0, required Token token1, required String rpcUrl}) async {
      logger("Getting pool on-chain for ${token0.contractAddress} and ${token1.contractAddress}", runtimeType.toString());

      final factoryAddress = getFactoryAddress(chainId: chainId);
      if (factoryAddress == null) throw Exception('Unsupported chain ID $chainId for Uniswap V3 Factory');

      final Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      final TokenFactory tokenFactory = TokenFactory();

      // Load Factory ABI
      final String factoryAbiStr = await rootBundle.loadString(uniswap_v3_factory_abi);
      final DeployedContract factoryContract = await tokenFactory.intContract(factoryAbiStr, factoryAddress, "UniswapV3Factory");
      final getPoolFunction = factoryContract.function('getPool');

      // Load Pool ABI
      final String poolAbiStr = await rootBundle.loadString(uniswap_v3_pool_abi);

      final EthereumAddress tokenAAddress = EthereumAddress.fromHex(token0.contractAddress);
      final EthereumAddress tokenBAddress = EthereumAddress.fromHex(token1.contractAddress);

      // Track the best pool (highest liquidity)
      String? bestPoolAddress;
      BigInt bestLiquidity = BigInt.zero;
      BigInt bestSqrtPriceX96 = BigInt.zero;
      int bestFeeTier = 0;
      String? onChainToken0Address;

      // Iterate over all standard fee tiers to find pools
      for (final feeTier in uniswapV3FeeTiers) {
        try {
          final result = await web3client.call(
            contract: factoryContract,
            function: getPoolFunction,
            params: [tokenAAddress, tokenBAddress, BigInt.from(feeTier)],
          );

          final EthereumAddress poolAddr = result.first as EthereumAddress;

          // Zero address means no pool exists for this fee tier
          if (poolAddr.with0x == '0x0000000000000000000000000000000000000000') {
            logger("No pool for fee tier $feeTier", runtimeType.toString());
            continue;
          }

          final String poolAddrHex = poolAddr.with0x;
          logger("Found pool at $poolAddrHex for fee tier $feeTier", runtimeType.toString());

          // Read liquidity and slot0 from the pool contract
          final DeployedContract poolContract = await tokenFactory.intContract(poolAbiStr, poolAddrHex, "Pool_$feeTier");

          final liquidityResult = await web3client.call(
            contract: poolContract,
            function: poolContract.function('liquidity'),
            params: [],
          );
          final BigInt liquidity = liquidityResult.first as BigInt;

          if (liquidity == BigInt.zero) {
            logger("Pool $poolAddrHex has zero liquidity, skipping", runtimeType.toString());
            continue;
          }

          final slot0Result = await web3client.call(
            contract: poolContract,
            function: poolContract.function('slot0'),
            params: [],
          );
          final BigInt sqrtPriceX96 = slot0Result[0] as BigInt;

          // Read on-chain token0 to determine ordering
          final token0Result = await web3client.call(
            contract: poolContract,
            function: poolContract.function('token0'),
            params: [],
          );
          final String poolToken0 = (token0Result.first as EthereumAddress).with0x;

          logger("Pool $poolAddrHex: liquidity=$liquidity, sqrtPriceX96=$sqrtPriceX96, token0=$poolToken0", runtimeType.toString());

          if (liquidity > bestLiquidity) {
            bestLiquidity = liquidity;
            bestPoolAddress = poolAddrHex;
            bestSqrtPriceX96 = sqrtPriceX96;
            bestFeeTier = feeTier;
            onChainToken0Address = poolToken0;
          }
        } catch (e) {
          logger("Error checking fee tier $feeTier: $e", runtimeType.toString());
          continue;
        }
      }

      if (bestPoolAddress == null) {
        logger("No pool found for ${token0.symbol}/${token1.symbol}", runtimeType.toString());
        return null;
      }

      // Derive prices from sqrtPriceX96
      // sqrtPriceX96 = sqrt(token1/token0) * 2^96
      // price (token1 per token0) = (sqrtPriceX96 / 2^96)^2
      print("sqrtPriceX96: $bestSqrtPriceX96");
      final double sqrtPrice = bestSqrtPriceX96/BigInt.two.pow(96);
      print("sqrtPrice: $sqrtPrice");
      final double rawPrice = sqrtPrice * sqrtPrice;
      print("rawPrice: $rawPrice");

      // Adjust for decimals: price = rawPrice * 10^(token0Decimals - token1Decimals)
      // But we need to know which token is on-chain token0
      final bool userToken0IsOnChainToken0 = token0.contractAddress.toLowerCase() == onChainToken0Address!.toLowerCase();

      double token0Price; // How many token1 per token0
      double token1Price; // How many token0 per token1

      if (userToken0IsOnChainToken0) {
        // On-chain price = token1/token0 (adjusted for decimals)
        final double decimalAdjustment = math.pow(10, token0.decimals - token1.decimals).toDouble();
        token0Price = rawPrice * decimalAdjustment;
        token1Price = token0Price > 0 ? 1.0 / token0Price : 0;
        logger("Normal pool order: ${token0.symbol}/${token1.symbol} price=$token0Price", runtimeType.toString());
        return Pool(
          token0: token0,
          token1: token1,
          feeTier: bestFeeTier.toString(),
          poolAddress: bestPoolAddress,
          token0Price: token0Price,
          token1Price: token1Price,
          liquidity: bestLiquidity.toDouble(),
          isInverse: false,
        );
      } else {
        // User's token0 is actually on-chain token1, so the pool is "inverse"
        // On-chain price gives onChainToken1/onChainToken0, but user wants token1/token0
        final double decimalAdjustment = math.pow(10, token1.decimals - token0.decimals).toDouble();
        print("decimalAdjustment: $decimalAdjustment");

        final double onChainPrice = rawPrice * decimalAdjustment; // user_token0 per user_token1
        token0Price = onChainPrice > 0 ? 1.0 / onChainPrice : 0; // user_token1 per user_token0
        token1Price = onChainPrice;
        logger("Inverse pool order: ${token0.symbol}/${token1.symbol} price=$token0Price", runtimeType.toString());
        return Pool(
          token0: token1,
          token1: token0,
          feeTier: bestFeeTier.toString(),
          poolAddress: bestPoolAddress,
          token0Price: token0Price,
          token1Price: token1Price,
          liquidity: bestLiquidity.toDouble(),
          isInverse: true,
        );
      }
    }

    Future<BigInt> getChainNetworkFee({required String rpcUrl,required int chainId})async {
    return transactionService.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);
    }
    Future<String> approve({required String privateKey, required String spender, required  Token token, required BigInt amountIn, required NetworkRpc network,required NetworkFee fee}) async {
      try {
        logger("Approving $spender to spend ${token.symbol} $amountIn",runtimeType.toString());
        TokenFactory _tokenFactory = TokenFactory();
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: network.rpcUrl);
        int chainId = network.chainId;
        final String abi = await rootBundle.loadString(token_contract_abi);
        String contractAddress = token.contractAddress!;
        final credentials = await _tokenFactory.getCredentials(privateKey);
        final contract = await _tokenFactory.intContract(abi, contractAddress, token.name);
        final function = contract.function('approve');
        List<dynamic> params = [EthereumAddress.fromHex(spender), amountIn];
        int maxGas = fee.maxGas;
        EtherAmount gasPrice = EtherAmount.fromBigInt(EtherUnit.wei, fee.gasPrice);
        Transaction transaction = await transactionService.constructTx(contract: contract, function: function, credentials: credentials, params: params, gasPrice: gasPrice, maxGas: maxGas);
        Uint8List signedTransaction = await web3client.signTransaction(credentials, transaction, chainId: chainId, fetchChainIdFromNetworkId: false);
        String txId = await web3client.sendRawTransaction(signedTransaction);
        return txId;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        throw Exception(e);
      }
    }

      Future<BigInt> estimateApproveTx({required Token token,required  NetworkRpc network, required double amountIn, required String privateKey}) async {
      try {
        bool isIntermediary = false;
        TokenFactory tokenFactory = TokenFactory();
        final String abi = await rootBundle.loadString(token_contract_abi);
        int chainId = network.chainId;
        String rpcUrl = network.rpcUrl;
        final contract = await tokenFactory.intContract(abi, token.contractAddress, "plugin_approval");
        final credentials = await tokenFactory.getCredentials(privateKey);
        final function = contract.function('approve');
        List<dynamic> params = [EthereumAddress.fromHex(getUniswapSwapRouterAddress(chainId: chainId)), BigInt.from(amountIn)];
        Transaction tx = await transactionService.constructTx(contract: contract, function: function, credentials: credentials, params: params);
        BigInt gas = await transactionService.estimateTxGas(sender: credentials.address.with0x, to: token.contractAddress, rpcUrl: rpcUrl, data: tx.data!);
        return gas;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }

    Future<BigInt> estimatePermit2Approval({required Token token,required  NetworkRpc network, required double amountIn, required String privateKey}) async {
      try {
        bool isIntermediary = false;
        TokenFactory tokenFactory = TokenFactory();
        final String abi = await rootBundle.loadString(token_contract_abi);
        int chainId = network.chainId;
        String rpcUrl = network.rpcUrl;
        final contract = await tokenFactory.intContract(abi, token.contractAddress, "plugin_approval");
        final credentials = await tokenFactory.getCredentials(privateKey);
        final function = contract.function('approve');
        List<dynamic> params = [EthereumAddress.fromHex(permit2ContractAddress), BigInt.from(amountIn)];
        Transaction tx = await transactionService.constructTx(contract: contract, function: function, credentials: credentials, params: params);
        BigInt gas = await transactionService.estimateTxGas(sender: credentials.address.with0x, to: token.contractAddress, rpcUrl: rpcUrl, data: tx.data!);
        return gas;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }



  Future<BigInt> estimateSwapTx({required String privateKey, required String fromAddress, required BigInt poolFee, required Pool pair, required BigInt amountIn, required NetworkRpc network}) async {
    try {
      TokenFactory _tokenFactory = TokenFactory();
      String routerAddress = getUniswapSwapRouterAddress(chainId: network.chainId);
      String routerAbi = await getUniswapSwapRouterAbi();
      DeployedContract contract = await _tokenFactory.intContract(routerAbi, routerAddress, "Router");
      final exactInputSingle = contract.function("exactInputSingle");
      final credentials = await _tokenFactory.getCredentials(privateKey);
      String rpcUrl = network.rpcUrl;
      // BigInt poolFee = await swapController.getPoolFee(pair: pair,poolAddress: pair.poolAddress, poolAbi: pair.poolAbi);
      List<dynamic> params = [
        [EthereumAddress.fromHex(pair.token0.contractAddress!), EthereumAddress.fromHex(pair.token1.contractAddress), poolFee, EthereumAddress.fromHex(fromAddress), amountIn, BigInt.zero, BigInt.zero],
      ];
      logger(params.toString(),runtimeType.toString());
      Transaction tx = await transactionService.constructTx(contract: contract, function: exactInputSingle, credentials: credentials, params: params);
      BigInt gas = await transactionService.estimateTxGas(sender: fromAddress, to: routerAddress, rpcUrl: rpcUrl, data: tx.data!);
      return gas;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not get gas");
    }
  }

  Future<BigInt> estimateTokenToNativeSwapTx({ required String privateKey,required Pool pool, required NetworkRpc network,required BigInt amountIn,required BigInt wethAmountMin, required BigInt poolFee}) async {
    try {
      logger("Estimating token to native swap tx from ${pool.token0.symbol} to ${pool.token1.symbol}",runtimeType.toString());
      logger("Amount In: $amountIn",runtimeType.toString());
      logger("Amount Out Min: $wethAmountMin",runtimeType.toString());
      TokenFactory _tokenFactory = TokenFactory();
      Token pairOne = pool.token0;
      // SupportedCoin pairTwo = pair.token1;
      String wethAddress = getWETHContractAddress(chainId: network.chainId);
      int chainId = network.chainId;
      String rpcUrl = network.rpcUrl;
      Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      String universalRouter = getUniversalRouterAddress(chainId: network.chainId);
      String universalRouterAbi = await getUniswapUniversalRouterAbi();
      DeployedContract contract = await _tokenFactory.intContract(universalRouterAbi, universalRouter, "universalRouter");
      //we need to call the execute function so as to run two functions together
      final execute = contract.findFunctionsByName("execute").first;
      final credentials = await _tokenFactory.getCredentials(privateKey);
      String walletAddress = credentials.address.with0x;
      List<int> commands = [0x00, 0x0c];
      //convert the command to bytes
      var commandBytes = Uint8List.fromList(commands);
      List<String> path = [EthereumAddress.fromHex(pairOne.contractAddress).with0x, EthereumAddress.fromHex(wethAddress!).with0x];
      // if (!isIntermediary) {
      //   path = [EthereumAddress.fromHex(pairOne.contractAddress!).with0x, EthereumAddress.fromHex(weth.contractAddress!).with0x];
      // } else {
      //   path = [EthereumAddress.fromHex(pairOne.contractAddress!).with0x, EthereumAddress.fromHex(pair.intermediaryContract).with0x, EthereumAddress.fromHex(weth.contractAddress!).with0x];
      // }
      //Path is the list of token addresses that the swap will go through
      List<int> poolFees = [poolFee.toInt()];
      // if (!isIntermediary) {
      //   poolFees = [poolFee.toInt()];
      // } else {
      //   poolFees = [poolFee.toInt(), pair.intermediaryPoolFee.toInt()];
      // }
      //This encode the path and fees then pad it to 64
      String encodedPath = MyEncoder.encodePath(path: path, fees: poolFees).padLeft(64, "0");
      logger("Path:$path",runtimeType.toString());
      //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
      String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
      String recipientContract = 2.toRadixString(16).padLeft(40, "0");
      logger("Recipient (msg.sender): $recipientMsgSender",runtimeType.toString());
      logger("Recipient (Contract): $recipientContract",runtimeType.toString());
      // flag for whether the input tokens should come from the msg.sender (through Permit2) or whether the funds are already in the UniversalRouter
      int flag = 1;
      final v3SwapExactInputParams = [EthereumAddress.fromHex("0x$recipientMsgSender"), amountIn, wethAmountMin, hexToBytes("0x$encodedPath"), EthereumAddress.fromHex("0x${flag.toRadixString(16).padLeft(40, "0")}")];
      // Ignore the address of the contract, we just used it so we can use the function for encoding
      final v3SwapExactInputEncoded = await encodeV3SwapExactInput(param: v3SwapExactInputParams, address: universalRouter);
      final EthereumAddress unwrapWETH9Recipient = EthereumAddress.fromHex(walletAddress??"");
      final unwrapWETH9Params = [unwrapWETH9Recipient, wethAmountMin];
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      final unwrapWETH9Encoded = await encodeUnwrapWETH(param: unwrapWETH9Params, address: universalRouter);
      List<String> inputsParams = [bytesToHex(v3SwapExactInputEncoded), bytesToHex(unwrapWETH9Encoded)];
      BigInt deadLine = BigInt.from(DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
      List<dynamic> executeParams = [commandBytes, inputsParams.map(hexToBytes).toList()];
      Transaction tx = await transactionService.constructTx(contract: contract, function: execute, credentials: credentials, params: executeParams);
      BigInt gas = await transactionService.estimateTxGas(sender: walletAddress!, to: universalRouter, rpcUrl: rpcUrl, data: tx.data!);
      return gas;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception(e);
    }
  }

  Future<BigInt> estimateNativeToTokenSwapTx({required String privateKey,required Pool pool,required BigInt amountIn, required BigInt amountOutMin, required BigInt poolFee,required NetworkRpc network}) async {
    try {
      TokenFactory _tokenFactory = TokenFactory();
      Token pairOne = pool.token0;
      Token pairTwo = pool.token1;
      int chainId = network.chainId;
      String rpcUrl = network.rpcUrl;
      String wethAddress = getWETHContractAddress(chainId: network.chainId);
      final credentials = await _tokenFactory.getCredentials(privateKey);
      String walletAddress = credentials.address.with0x;
      Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      String universalRouter = getUniversalRouterAddress(chainId: chainId);
      String universalRouterAbi = await getUniswapUniversalRouterAbi();
      DeployedContract contract = await _tokenFactory.intContract(universalRouterAbi, universalRouter, "universalRouter");
      //we need to call the execute function so as to run two functions together
      final execute = contract.findFunctionsByName("execute").first;
      List<int> commands = [0x0b, 0x00, 0x04];
      //convert the command to bytes
      var commandBytes = Uint8List.fromList(commands);
      List<String> path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pairTwo.contractAddress!).with0x];
      //Path is the list of token addresses that the swap will go through
      // if (!isIntermediary) {
      //   path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pairTwo.contractAddress!).with0x];
      // } else {
      //   path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pair.intermediaryContract).with0x, EthereumAddress.fromHex(pairTwo.contractAddress!).with0x];
      // }
      List<int> poolFees = [poolFee.toInt()];
      // if (!isIntermediary) {
      //   poolFees = [poolFee.toInt()];
      // } else {
      //   poolFees = [poolFee.toInt(), pair.intermediaryPoolFee!.toInt()];
      // }
      //This encode the path and fees then pad it to 64
      String encodedPath = MyEncoder.encodePath(path: path, fees: poolFees).padLeft(64, "0");
      logger("Encoded Path:$encodedPath",runtimeType.toString());
      //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
      String ethAddress = 0.toRadixString(16).padLeft(40, "0");
      String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
      String recipientContract = 2.toRadixString(16).padLeft(40, "0");

      // flag for whether the input tokens should come from the msg.sender (through Permit2) or whether the funds are already in the UniversalRouter
      int flag = 0;
      final v3wrapETHInputParams = [EthereumAddress.fromHex("0x$recipientContract"), amountIn];
      final v3SwapExactInputParams = [EthereumAddress.fromHex(walletAddress), amountIn, BigInt.zero, hexToBytes("0x$encodedPath"), EthereumAddress.fromHex("0x${flag.toRadixString(16).padLeft(40, "0")}")];
      final sweepParam = [EthereumAddress.fromHex(ethAddress), EthereumAddress.fromHex(walletAddress), BigInt.zero];
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      final v3wrapETHInputEncoded = await encodeWrapWETH(param: v3wrapETHInputParams, address: universalRouter);
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      final v3SwapExactInputEncoded = await encodeV3SwapExactInput(param: v3SwapExactInputParams, address: universalRouter);
      final sweepParamEncoded = await encodeSweepETH(param: sweepParam, address: universalRouter);

      List<String> inputsParams = [bytesToHex(v3wrapETHInputEncoded), bytesToHex(v3SwapExactInputEncoded), bytesToHex(sweepParamEncoded)];
      BigInt deadLine = BigInt.from(DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
      List<dynamic> executeParams = [commandBytes, inputsParams.map(hexToBytes).toList()];
      Transaction tx = await transactionService.constructTx(contract: contract, function: execute, credentials: credentials, params: executeParams, value: EtherAmount.fromBigInt(EtherUnit.wei, amountIn));
      BigInt gas = await transactionService.estimateTxGas(sender: walletAddress, to: universalRouter, rpcUrl: rpcUrl, data: tx.data!, value: EtherAmount.fromBigInt(EtherUnit.wei, amountIn));
      return gas;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not get execute gas");
    }
  }

    Future<BigInt> estimatePermit2Call({required String privateKey, required String tokenAddress, required String spenderAddress, required String rpcUrl, required int chainId}) async {
      try {
        logger("Estimating call permit for $tokenAddress on $spenderAddress",runtimeType.toString());
        logger("Amount In: $permitUnlimited", runtimeType.toString());
        TokenFactory tokenFactory = TokenFactory();
        final String permit2Abi = await rootBundle.loadString(permit2_abi);
        final contract = await tokenFactory.intContract(permit2Abi, permit2ContractAddress, "Permit2");
        final permitFunction = contract.findFunctionsByName('approve').last;
        final credentials = await tokenFactory.getCredentials(privateKey);
        String walletAddress = credentials.address.with0x;
        BigInt amountIn = permitUnlimited;
        BigInt deadline = BigInt.from(DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch);
        List<dynamic> param = [EthereumAddress.fromHex(tokenAddress), EthereumAddress.fromHex(spenderAddress), amountIn, deadline];
        Transaction tx = await transactionService.constructTx(contract: contract, function: permitFunction, credentials: credentials, params: param);
        BigInt gas = await transactionService.estimateTxGas(sender: walletAddress, to: permit2ContractAddress, rpcUrl: rpcUrl, data: tx.data!);
        return gas;
      } catch (e) {
        logger(e.toString(), runtimeType.toString());
        throw Exception(e);
      }
    }
    Future<String> callPermit({required String privateKey, required String tokenAddress, required String spenderAddress, required String rpcUrl, required int chainId, required String chainSymbol, required NetworkFee fee}) async {
      try {
        logger("Calling permit for $tokenAddress on $spenderAddress to spend $permitUnlimited with deadline 30 minutes",runtimeType.toString());
        logger("Token Address: $tokenAddress", runtimeType.toString());
        logger("Spender Address: $spenderAddress", runtimeType.toString());
        logger("Amount In: $permitUnlimited", runtimeType.toString());
        TokenFactory tokenFactory = TokenFactory();
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
        final String permit2Abi = await rootBundle.loadString(permit2_abi);
        final contract = await tokenFactory.intContract(permit2Abi, permit2ContractAddress, "Permit2");
        final permitFunction = contract.findFunctionsByName('approve').last;
        final credentials = await tokenFactory.getCredentials(privateKey);
        BigInt amountIn = permitUnlimited;
        final gasPrice = EtherAmount.inWei(fee.gasPrice);
        final maxGas = fee.maxGas;
        BigInt deadline = BigInt.from(DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch);
        List<dynamic> param = [EthereumAddress.fromHex(tokenAddress), EthereumAddress.fromHex(spenderAddress), amountIn, deadline];
        Transaction tx = await transactionService.constructTx(contract: contract, function: permitFunction, credentials: credentials, params: param, gasPrice: gasPrice, maxGas: maxGas);
        Uint8List signedTransaction = await web3client.signTransaction(credentials, tx, chainId: chainId, fetchChainIdFromNetworkId: false);
        String txId = await web3client.sendRawTransaction(signedTransaction);
        logger("Permit2 txId: $txId", runtimeType.toString());
        return txId;
      } catch (e) {
        logger(e.toString(), runtimeType.toString());
        throw Exception(e);
      }
    }

     Future<Allowance> getPermitAllowance({required String ownerAddress, required String tokenAddress, required String spenderAddress, required String rpcUrl, required int chainId}) async {
      try {
        logger("Checking allowance for $spenderAddress on $tokenAddress", runtimeType.toString());
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
        TokenFactory tokenFactory = TokenFactory();
        final String permit2Abi = await rootBundle.loadString(permit2_abi);
        final contract = await tokenFactory.intContract(permit2Abi, permit2ContractAddress, "Permit2");
        final permitFunction = contract.function('allowance');
        List<dynamic> param = [
          EthereumAddress.fromHex(ownerAddress),
          EthereumAddress.fromHex(tokenAddress),
          EthereumAddress.fromHex(spenderAddress)
        ];
        final result = await web3client.call(
            contract: contract, function: permitFunction, params: param);
        BigInt amount = result[0];
        BigInt expiration = result[1];
        BigInt nonce = result[2];
        logger("Allowance: $amount, expiration: $expiration, nonce: $nonce", runtimeType.toString());
        return Allowance(amount: amount, expiration: expiration, nonce: nonce);
      } catch (e) {
        logger(e.toString(), runtimeType.toString());
        throw Exception("Unable to check allowance");
      }
    }
    Future<String> swap({required String privateKey,required BigInt poolFee, required Pool pair, required BigInt amountIn, required BigInt amountOutMin, required NetworkFee fee,required NetworkRpc network}) async {
      Token from = pair.token0;
      try {
        logger("Amount In: $amountIn",runtimeType.toString());
        logger("Amount Out Min: $amountOutMin",runtimeType.toString());
        logger("Pool Fee: $poolFee",runtimeType.toString());
        logger("Pair: $pair",runtimeType.toString());
        String rpcUrl = network.rpcUrl;
        int chainId = network.chainId;
        TokenFactory _tokenFactory = TokenFactory();
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
        String routerAddress = getUniswapSwapRouterAddress(chainId: chainId);
        String routerAbi = await getUniswapSwapRouterAbi();
        DeployedContract contract = await _tokenFactory.intContract(routerAbi, routerAddress, "Router");
        final exactInputSingle = contract.function("exactInputSingle");
        final credentials = await _tokenFactory.getCredentials(privateKey);
        // BigInt poolFee = await swapController.getPoolFee(pair: pair,poolAddress: pair.poolAddress, poolAbi: pair.poolAbi);
        List<dynamic> params = [
          [EthereumAddress.fromHex(pair.token0.contractAddress!), EthereumAddress.fromHex(pair.token1.contractAddress!), poolFee, EthereumAddress.fromHex(credentials.address.with0x), amountIn, amountOutMin, BigInt.zero],
        ];
        final gasPrice = EtherAmount.inWei(fee.gasPrice);
        final maxGas = fee.maxGas;
        Transaction tx = await transactionService.constructTx(contract: contract, function: exactInputSingle, credentials: credentials, params: params, gasPrice: gasPrice, maxGas: maxGas);
        Uint8List signedTransaction = await web3client.signTransaction(credentials, tx, chainId: chainId, fetchChainIdFromNetworkId: false);
        String txId = await web3client.sendRawTransaction(signedTransaction);
        logger("TxId: $txId",runtimeType.toString());
        return txId;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        throw Exception("Unable to swap ${from.name} to ${pair.token1.name}");
      }
    }

    Future<String> tokenToNativeSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt wethAmountMin,required NetworkRpc network,required NetworkFee fee, required BigInt poolFee}) async {
      try {
        logger("Token to Native",runtimeType.toString());
        TokenFactory _tokenFactory = TokenFactory();
        Token pairOne = pool.token0;
        String wethAddress = getWETHContractAddress(chainId: network.chainId);
        int chainId = network.chainId;
        String rpcUrl = network.rpcUrl;
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
        String universalRouter = getUniversalRouterAddress(chainId: chainId);
        String universalRouterAbi = await getUniswapUniversalRouterAbi();
        DeployedContract contract = await _tokenFactory.intContract(universalRouterAbi, universalRouter, "universalRouter");
        //we need to call the execute function so as to run two functions together
        final execute = contract.findFunctionsByName("execute").first;
        final credentials = await _tokenFactory.getCredentials(privateKey);
        String walletAddress = credentials.address.with0x;
        List<int> commands = [0x00, 0x0c];
        // List<int> commands=[0x0c];
        //convert the command to bytes
        var commandBytes = Uint8List.fromList(commands);
        List<String> path = [EthereumAddress.fromHex(pairOne.contractAddress).with0x, EthereumAddress.fromHex(wethAddress).with0x];
        // if (!pair.isIntermediary) {
        //   path = [EthereumAddress.fromHex(pairOne.contractAddress!).with0x, EthereumAddress.fromHex(weth.contractAddress!).with0x];
        // } else {
        //   path = [EthereumAddress.fromHex(pairOne.contractAddress!).with0x, EthereumAddress.fromHex(pair.intermediaryContract!).with0x, EthereumAddress.fromHex(weth.contractAddress!).with0x];
        // }
        //Path is the list of token addresses that the swap will go through
        List<int> poolFees = [poolFee.toInt()];
        // if (!pair.isIntermediary) {
        //   poolFees = [poolFee.toInt()];
        // } else {
        //   poolFees = [poolFee.toInt(), pair.intermediaryPoolFee.toInt()];
        // }
        //This encode the path and fees then pad it to 64
        String encodedPath = MyEncoder.encodePath(path: path, fees: poolFees).padLeft(64, "0");
        logger("Encoded Path:$encodedPath",runtimeType.toString());
        //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
        String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
        String recipientContract = 2.toRadixString(16).padLeft(40, "0");
        // flag for whether the input tokens should come from the msg.sender (through Permit2) or whether the funds are already in the UniversalRouter
        int flag = 1;
        final v3SwapExactInputParams = [EthereumAddress.fromHex(recipientContract), amountIn, wethAmountMin, hexToBytes("0x$encodedPath"), EthereumAddress.fromHex("0x${flag.toRadixString(16).padLeft(40, "0")}")];
        // Ignore the address of the contract, we just used it so we can use the function for encoding
        final v3SwapExactInputEncoded = await encodeV3SwapExactInput(param: v3SwapExactInputParams, address: universalRouter);
        final EthereumAddress unwrapWETH9Recipient = EthereumAddress.fromHex(walletAddress);
        final unwrapWETH9Params = [unwrapWETH9Recipient, wethAmountMin];
        String ethAddress = 0.toRadixString(16).padLeft(40, "0");
        //Ignore the address of the contract, we just used it so we can use the function for encoding
        final unwrapWETH9Encoded = await encodeUnwrapWETH(param: unwrapWETH9Params, address: universalRouter);
        List<String> inputsParams = [bytesToHex(v3SwapExactInputEncoded), bytesToHex(unwrapWETH9Encoded)];
        BigInt deadLine = BigInt.from(DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
        List<dynamic> executeParams = [commandBytes, inputsParams.map(hexToBytes).toList()];
        // log(input);
        final gasPrice = EtherAmount.inWei(fee.gasPrice);
        final maxGas = fee.maxGas;
        Transaction tx = await transactionService.constructTx(contract: contract, function: execute, credentials: credentials, params: executeParams, gasPrice: gasPrice, maxGas: maxGas);
        Uint8List signedTransaction = await web3client.signTransaction(credentials, tx, chainId: chainId, fetchChainIdFromNetworkId: false);
        String txId = await web3client.sendRawTransaction(signedTransaction);
        logger("TxId: $txId",runtimeType.toString());
        return txId;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }

    Future<String> nativeToTokenSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt wethAmountMin, required BigInt poolFee,required NetworkFee fee,required NetworkRpc network}) async {
      try {
        logger("Native to token",runtimeType.toString());
        TokenFactory _tokenFactory = TokenFactory();
        Token pairOne = pool.token0;
        Token pairTwo = pool.token1;
        int chainId = network.chainId;
        String rpcUrl = network.rpcUrl;
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
        String universalRouter = getUniversalRouterAddress(chainId: chainId);
        String universalRouterAbi = await getUniswapUniversalRouterAbi();
        DeployedContract contract = await _tokenFactory.intContract(universalRouterAbi, universalRouter, "universalRouter");
        //we need to call the execute function so as to run two functions together
        final execute = contract.findFunctionsByName("execute").first;
        final credentials = await _tokenFactory.getCredentials(privateKey);
        String walletAddress = credentials.address.with0x;
        String wethAddress = getWETHContractAddress(chainId: network.chainId);
        List<int> commands = [0x0b, 0x00, 0x04];
        //convert the command to bytes
        var commandBytes = Uint8List.fromList(commands);
        List<String> path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pairTwo.contractAddress).with0x];
        //Path is the list of token addresses that the swap will go through
        // if (!isIntermediary) {
        //   path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pairTwo.contractAddress!).with0x];
        // } else {
        //   path = [EthereumAddress.fromHex(wethAddress).with0x, EthereumAddress.fromHex(pair.intermediaryContract!).with0x, EthereumAddress.fromHex(pairTwo.contractAddress!).with0x];
        // }
        List<int> poolFees = [poolFee.toInt()];
        // if (!isIntermediary) {
        //   poolFees = [poolFee.toInt()];
        // } else {
        //   poolFees = [poolFee.toInt(), pair.intermediaryPoolFee.toInt()];
        // }
        //This encode the path and fees then pad it to 64
        String encodedPath = MyEncoder.encodePath(path: path, fees: poolFees).padLeft(64, "0");
        logger("Encoded Path:$encodedPath",runtimeType.toString());
        //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
        String ethAddress = 0.toRadixString(16).padLeft(40, "0");
        String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
        String recipientContract = 2.toRadixString(16).padLeft(40, "0");
        // flag for whether the input tokens should come from the msg.sender (through Permit2) or whether the funds are already in the UniversalRouter
        int flag = 0;
        final v3wrapETHInputParams = [EthereumAddress.fromHex("0x$recipientContract"), amountIn];
        final v3SwapExactInputParams = [EthereumAddress.fromHex(walletAddress), amountIn, wethAmountMin, hexToBytes("0x$encodedPath"), EthereumAddress.fromHex("0x${flag.toRadixString(16).padLeft(40, "0")}")];
        final sweepParam = [EthereumAddress.fromHex(ethAddress), EthereumAddress.fromHex(walletAddress), BigInt.zero];
        //Ignore the address of the contract, we just used it so we can use the function for encoding
        final v3wrapETHInputEncoded = await encodeWrapWETH(param: v3wrapETHInputParams, address: universalRouter);
        //Ignore the address of the contract, we just used it so we can use the function for encoding
        final v3SwapExactInputEncoded = await encodeV3SwapExactInput(param: v3SwapExactInputParams, address: universalRouter);
        final sweepParamEncoded = await encodeSweepETH(param: sweepParam, address: universalRouter);

        List<String> inputsParams = [bytesToHex(v3wrapETHInputEncoded), bytesToHex(v3SwapExactInputEncoded), bytesToHex(sweepParamEncoded)];
        BigInt deadLine = BigInt.from(DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch);
        List<dynamic> executeParams = [commandBytes, inputsParams.map(hexToBytes).toList()];
        // log(input);
        final gasPrice = EtherAmount.inWei(fee.gasPrice);
        final maxGas = fee.maxGas;
        Transaction tx = await transactionService.constructTx(contract: contract, function: execute, credentials: credentials, params: executeParams, gasPrice: gasPrice, maxGas: maxGas, value: EtherAmount.fromBigInt(EtherUnit.wei, amountIn));
        Uint8List signedTransaction = await web3client.signTransaction(credentials, tx, chainId: chainId, fetchChainIdFromNetworkId: false);
        String txId = await web3client.sendRawTransaction(signedTransaction);
        logger("TxId: $txId",runtimeType.toString());
        return txId;
      } catch (e) {
        logger(e.toString(),runtimeType.toString());
        rethrow;
      }
    }


    Future<Uint8List> encodeV3SwapExactInput({required List<dynamic> param, required String address}) async {
    try {
      logger("////////////////////////////////////////encodeV3SwapExactInput////////////////////////////////////////", runtimeType.toString());
      TokenFactory _tokenFactory = TokenFactory();
      //The encoded data for the swap, we use the v3SwapRouter json to encode the function with web3Dart
      String v3SwapRouter = await rootBundle.loadString(v3_swap_router_abi);
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      DeployedContract c = await _tokenFactory.intContract(v3SwapRouter, address, "v3SwapRouter");
      final v3SwapExactInputFunction = c.function("v3SwapExactInput");
      final data = v3SwapExactInputFunction.encodeCall(param);
      final d = bytesToHex(data);
      //This is to the function selected which is the first 4 bytes e.g 0x12345678
      final dd = hexToBytes(d.substring(8));
      return dd;
    } catch (e) {
      logger(e.toString(), runtimeType.toString());
      throw Exception("Could not encode V3SwapExactInput param");
    }
  }

  Future<Uint8List> encodeWrapWETH({required List<dynamic> param, required String address}) async {
    try {
      //The encoded data for the swap, we use the v3SwapRouter json to encode the function with web3Dart
      String paymentAbi = await getUniswapPaymentAbi();
      TokenFactory _tokenFactory = TokenFactory();
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      DeployedContract c = await _tokenFactory.intContract(paymentAbi, address, "paymentAbi");
      final v3SwapExactInputFunction = c.function("wrapETH");
      final data = v3SwapExactInputFunction.encodeCall(param);
      final d = bytesToHex(data);
      //This is to the function selected which is the first 4 bytes e.g 0x12345678
      final dd = hexToBytes(d.substring(8));
      return dd;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not encode encodeWrapWETH param");
    }
  }

  Future<Uint8List> encodeUnwrapWETH({required List<dynamic> param, required String address}) async {
    try {
      TokenFactory _tokenFactory = TokenFactory();
      //The encoded data for the swap, we use the v3SwapRouter json to encode the function with web3Dart
      String paymentAbi = await getUniswapPaymentAbi();
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      DeployedContract c = await _tokenFactory.intContract(paymentAbi, address, "paymentAbi");
      final v3SwapExactInputFunction = c.function("unwrapWETH9");
      final data = v3SwapExactInputFunction.encodeCall(param);
      final d = bytesToHex(data);
      //This is to the function selected which is the first 4 bytes e.g 0x12345678
      final dd = hexToBytes(d.substring(8));
      return dd;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not encode unwrapWETH9 param");
    }
  }


  Future<Uint8List> encodeSweepETH({required List<dynamic> param, required String address}) async {
    try {
      TokenFactory _tokenFactory = TokenFactory();
      //The encoded data for the swap, we use the v3SwapRouter json to encode the function with web3Dart
      String paymentAbi = await getUniswapPaymentAbi();
      //Ignore the address of the contract, we just used it so we can use the function for encoding
      DeployedContract c = await _tokenFactory.intContract(paymentAbi, address, "paymentAbi");
      final v3SwapExactInputFunction = c.function("sweep");
      final data = v3SwapExactInputFunction.encodeCall(param);
      final d = bytesToHex(data);
      //This is to the function selected which is the first 4 bytes e.g 0x12345678
      final dd = hexToBytes(d.substring(8));
      return dd;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not encode sweepETH param");
    }
  }
}