import 'package:flutter/services.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:uniswap_flutter_v3/uniswap/data/datasources/services/transaction_service.dart';

import 'package:uniswap_flutter_v3/uniswap/utils/token_factory.dart';
import 'package:web3dart/web3dart.dart';
import 'dart:typed_data';

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
import '../../models/pool_data.dart';




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
        logger(e.toString(),"SwapService");
        rethrow;
      }
    }
    Future<BigInt> getPoolFee({required Pool pool, required NetworkRpc network, required String poolAbi}) async {
      logger("Swap: Getting pool fee $pool.","SwapService");
      try {
        TokenFactory tokenFactory = TokenFactory();
        int chainId = network.chainId;
        Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: network.rpcUrl);
        Token tokenIn = pool.token0;

        Token tokenOut = pool.token1;
        String poolAddress = pool.poolAddress;
        DeployedContract poolContract = await tokenFactory.intContract(poolAbi, poolAddress, tokenIn.symbol);
        logger("Swap: pool: Setting up contract",runtimeType.toString());
        logger("Swap: pool: Pool contract abi loaded",runtimeType.toString());
        logger("Swap: pool: Calling fee function",runtimeType.toString());
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

    Future<Pool?> getPool({required int chainId, required Token token0, required Token token1, required String graphApiKey}) async {
      logger("Getting pool for ${token0.contractAddress} and ${token1.contractAddress}", runtimeType.toString());
      final link = getGraphUrl(apiKey: graphApiKey, chainId: chainId);
      if (link == null) throw Exception('Unsupported chain ID $chainId for The Graph');
      logger("Swap: Getting pool for $chainId", runtimeType.toString());
      final HttpLink httpLink = HttpLink(link);
      final client = GraphQLClient(
        link: httpLink,
        // The default store is the InMemoryStore, which does NOT persist to disk
        cache: GraphQLCache(store: HiveStore()),
        defaultPolicies: DefaultPolicies(query: Policies(fetch: FetchPolicy.networkOnly)),
      );
      String token0Address = token0.contractAddress.toLowerCase();
      String token1Address = token1.contractAddress.toLowerCase();
      String readPools =
      """{
  pools(where: {
    or: [
      { token0: "$token0Address", token1: "$token1Address" },
      { token0: "$token1Address", token1: "$token0Address" },
    ]
  },orderBy:liquidity orderDirection: desc) {
    id
    feeTier
    token0Price
    token1Price,
    volumeToken0
    volumeToken1
    volumeUSD
    liquidity
    token0 {
    id
    name
    symbol
    decimals
    derivedETH
    }
    token1 {
    id
    name
    symbol
    decimals
    derivedETH
    }
  }
}""";
      final tokensResult = await client.query(QueryOptions(document: gql(readPools)));
      if (tokensResult.hasException) {
        throw Exception(tokensResult.exception.toString());
      }
      PoolData poolData = PoolData.fromJson(tokensResult.data!);
      if (poolData.pools!.isEmpty) {
        return null;
      }
      GraphPool pool = poolData.pools!.first;
      logger("Swap route: Pools result: ${pool.toJson()}", runtimeType.toString());

      if (token0.contractAddress.toLowerCase() == pool.token0?.id?.toLowerCase() && token1.contractAddress.toLowerCase() == pool.token1?.id?.toLowerCase()) {
        logger("Normal pool", runtimeType.toString());
        return Pool(
          token0: token0,
          token1: token1,
          feeTier:  pool.feeTier!,
          poolAddress: pool.id!,
          //Since graph returns the prices in inverse order for a normal pool, so we need to swap them
          token0Price: double.parse(pool.token1Price!),
          token1Price: double.parse(pool.token0Price!),
          volumeToken0: double.parse(pool.volumeToken1!),
          volumeToken1: double.parse(pool.volumeToken0!),
          volumeUsd: double.parse(pool.volumeUsd!),
          liquidity: double.parse(pool.liquidity!),
          isInverse: false
        );
      } else {
        logger("Inverse pool", runtimeType.toString());
        return Pool(
          token0: token1,
          token1: token0,
          feeTier: pool.feeTier!,
          poolAddress: pool.id!,
          token0Price: double.parse(pool.token1Price!),
          token1Price: double.parse(pool.token0Price!),
          volumeToken0: double.parse(pool.volumeToken1!),
          volumeToken1: double.parse(pool.volumeToken0!),
          volumeUsd: double.parse(pool.volumeUsd!),
          liquidity: double.parse(pool.liquidity!),
          isInverse: true
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
        logger(e.toString(),"SwapService");
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
        logger(e.toString(),"SwapService");
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
      logger(params.toString(),"SwapService");
      Transaction tx = await transactionService.constructTx(contract: contract, function: exactInputSingle, credentials: credentials, params: params);
      BigInt gas = await transactionService.estimateTxGas(sender: fromAddress, to: routerAddress, rpcUrl: rpcUrl, data: tx.data!);
      return gas;
    } catch (e) {
      logger(e.toString(),"SwapService");
      throw Exception("Could not get gas");
    }
  }

  Future<BigInt> estimateTokenToNativeSwapTx({ required String privateKey,required Pool pool, required NetworkRpc network,required BigInt amountIn,required BigInt wethAmountMin, required BigInt poolFee}) async {
    try {
      logger("Estimating token to native swap tx from ${pool.token0.symbol} to ${pool.token1.symbol}","SwapService");
      logger("Amount In: $amountIn","SwapService");
      logger("Amount Out Min: $wethAmountMin","SwapService");
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
      logger("Path:$path","SwapService");
      //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
      String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
      String recipientContract = 2.toRadixString(16).padLeft(40, "0");
      logger("Recipient (msg.sender): $recipientMsgSender","SwapService");
      logger("Recipient (Contract): $recipientContract","SwapService");
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
      logger(e.toString(),"SwapService");
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
      logger("Encoded Path:$encodedPath","SwapService");
      //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
      String ethAddress = 0.toRadixString(16).padLeft(40, "0");
      String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
      String recipientContract = 2.toRadixString(16).padLeft(40, "0");
      logger("Recipient (msg.sender): $recipientMsgSender","SwapService");
      logger("Recipient (Contract): $recipientContract","SwapService");
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
      logger(e.toString(),"SwapService");
      throw Exception("Could not get execute gas");
    }
  }

    Future<String> swap({required String privateKey,required BigInt poolFee, required Pool pair, required BigInt amountIn, required BigInt amountOutMin, required NetworkFee fee,required NetworkRpc network}) async {
      Token from = pair.token0;
      try {
        logger("Amount In: $amountIn","SwapService");
        logger("Amount Out Min: $amountOutMin","SwapService");
        logger("Pool Fee: $poolFee","SwapService");
        logger("Pair: $pair","SwapService");
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
        logger("TxId: $txId","SwapService");
        return txId;
      } catch (e) {
        logger(e.toString(),"SwapService");
        throw Exception("Unable to swap ${from.name} to ${pair.token1.name}");
      }
    }

    Future<String> tokenToNativeSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt wethAmountMin,required NetworkRpc network,required NetworkFee fee, required BigInt poolFee}) async {
      try {
        logger("Token to Native","SwapService");
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
        logger("Encoded Path:$encodedPath","SwapService");
        //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
        String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
        String recipientContract = 2.toRadixString(16).padLeft(40, "0");
        logger("Recipient (msg.sender): $recipientMsgSender","SwapService");
        logger("Recipient (Contract): $recipientContract","SwapService");
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
        logger("TxId: $txId","SwapService");
        return txId;
      } catch (e) {
        logger(e.toString(),"SwapService");
        rethrow;
      }
    }

    Future<String> nativeToTokenSwap({required String privateKey,required Pool pool, required BigInt amountIn, required BigInt wethAmountMin, required BigInt poolFee,required NetworkFee fee,required NetworkRpc network}) async {
      try {
        logger("Native to token","SwapService");
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
        logger("Encoded Path:$encodedPath","SwapService");
        //The recipient in the case of uniswap, 2 indicate the address of the contract and 1 indicate the MSG.SENDER
        String ethAddress = 0.toRadixString(16).padLeft(40, "0");
        String recipientMsgSender = 1.toRadixString(16).padLeft(40, "0");
        String recipientContract = 2.toRadixString(16).padLeft(40, "0");
        logger("Recipient (msg.sender): $recipientMsgSender","SwapService");
        logger("Recipient (Contract): $recipientContract","SwapService");
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
        logger("TxId: $txId","SwapService");
        return txId;
      } catch (e) {
        logger(e.toString(),"SwapService");
        rethrow;
      }
    }


    Future<Uint8List> encodeV3SwapExactInput({required List<dynamic> param, required String address}) async {
    try {
      logger("////////////////////////////////////////encodeV3SwapExactInput////////////////////////////////////////", "SwapService");
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
      logger(bytesToHex(dd), "SwapService");
      logger("////////////////////////////////////////encodeV3SwapExactInput////////////////////////////////////////", "SwapService");
      return dd;
    } catch (e) {
      logger(e.toString(), "SwapService");
      throw Exception("Could not encode V3SwapExactInput param");
    }
  }

  Future<Uint8List> encodeWrapWETH({required List<dynamic> param, required String address}) async {
    try {
      logger("////////////////////////////////////////encodeWrapWETH////////////////////////////////////////",runtimeType.toString());

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
      logger(bytesToHex(dd),"SwapService");
      logger("////////////////////////////////////////encodeWrapWETH////////////////////////////////////////","SwapService");
      return dd;
    } catch (e) {
      logger(e.toString(),"SwapService");
      throw Exception("Could not encode encodeWrapWETH param");
    }
  }

  Future<Uint8List> encodeUnwrapWETH({required List<dynamic> param, required String address}) async {
    try {
      logger("////////////////////////////////////////encodeUnwrapWETH////////////////////////////////////////","SwapService");
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
      logger(bytesToHex(dd),"SwapService");
      logger("////////////////////////////////////////encodeUnwrapWETH////////////////////////////////////////","SwapService");
      return dd;
    } catch (e) {
      logger(e.toString(),"SwapService");
      throw Exception("Could not encode unwrapWETH9 param");
    }
  }


  Future<Uint8List> encodeSweepETH({required List<dynamic> param, required String address}) async {
    try {
      logger("////////////////////////////////////////sweepETH////////////////////////////////////////","SwapService");
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
      logger(bytesToHex(dd),"SwapService");
      logger("////////////////////////////////////////sweepETH////////////////////////////////////////","SwapService");
      return dd;
    } catch (e) {
      logger(e.toString(),"SwapService");
      throw Exception("Could not encode sweepETH param");
    }
  }
}