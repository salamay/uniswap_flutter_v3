import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/pool.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/repositories/SwapRepository.dart';
import 'package:wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

import '../../../domain/entities/network_fee.dart';
import '../../../domain/entities/transaction_status.dart';
import '../../../utils/client_resolver.dart';
import '../../../utils/constants/abi_paths.dart';
import '../../../utils/logger.dart';
import '../../../utils/token_factory.dart';


class TransactionService{

  final SwapRepository swapRepository;

  TransactionService({required this.swapRepository});

  Future<Transaction> constructTx({required DeployedContract contract, required ContractFunction function, required Credentials credentials, required List<dynamic> params, EtherAmount? gasPrice, int? maxGas, EtherAmount? value}) async {
    if (value == null) {
      Transaction transaction = Transaction.callContract(contract: contract, function: function, gasPrice: gasPrice, maxGas: maxGas, from: credentials.address, parameters: params);
      return transaction;
    } else {
      Transaction transaction = Transaction.callContract(contract: contract, function: function, gasPrice: gasPrice, maxGas: maxGas, value: value, from: credentials.address, parameters: params);
      return transaction;
    }
  }

  Future<BigInt> estimateTxGas({required String sender, required String to, required String rpcUrl, required Uint8List data, EtherAmount? value}) async {
    try {
      logger(runtimeType.toString(),"SwapService");
      Web3Client? webClient = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      BigInt gasPrice = await webClient.estimateGas(sender: EthereumAddress.fromHex(sender), to: EthereumAddress.fromHex(to), data: data, value: value);
      logger("Gas : ${gasPrice.toString()}","SwapService");
      BigInt totalGas = BigInt.from(gasPrice.toInt() * 2);
      return totalGas;
    } catch (e) {
      logger(e.toString(),"SwapService");
      throw Exception(e.toString());
    }
  }

  Future<String> approve({required String walletAddress, required String privateKey, required String spender, required  Token token0, required BigInt amountIn, required NetworkRpc network,required NetworkFee fee}) async {
    try {
      logger("Approving $spender to spend ${token0.symbol} $amountIn",runtimeType.toString());
      TokenFactory _tokenFactory = TokenFactory();
      Web3Client web3client = await ClientResolver.resolveClient(rpcUrl: network.rpcUrl);
      int chainId = network.chainId;
      bool isIntermediary = false;
      final String abi = await rootBundle.loadString(token_contract_abi);
      String contractAddress = token0.contractAddress!;
      final credentials = await _tokenFactory.getCredentials(privateKey);
      final contract = await _tokenFactory.intContract(abi, contractAddress, token0.name);
      final function = contract.function('approve');
      List<dynamic> params = [EthereumAddress.fromHex(spender), amountIn];
      //if its not intermediary, approves the router address, otherwise approves the universal router
      // if (!isIntermediary) {
      //   params = [EthereumAddress.fromHex(spender), amountIn];
      // } else {
      //   params = [EthereumAddress.fromHex(spender2), amountIn];
      // }
      int maxGas = fee.maxGas;
      EtherAmount gasPrice = EtherAmount.fromBigInt(EtherUnit.wei, fee.gasPrice);
      Transaction transaction = await constructTx(contract: contract, function: function, credentials: credentials, params: params, gasPrice: gasPrice, maxGas: maxGas);
      Uint8List signedTransaction = await web3client.signTransaction(credentials, transaction, chainId: chainId, fetchChainIdFromNetworkId: false);
      String txId = await web3client.sendRawTransaction(signedTransaction);
      logger("TxId: $txId",runtimeType.toString());
      return txId;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception(e);
    }
  }

  Future<BigInt> estimateApprove2Tx({required String privateKey, required spender, required BigInt amountIn, required String contractAddress, required String rpcUrl}) async {
    try {
      TokenFactory _tokenFactory = TokenFactory();
      Web3Client? web3client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      final String abi = await rootBundle.loadString(token_contract_abi);
      final credentials = await _tokenFactory.getCredentials(privateKey);
      final contract = await _tokenFactory.intContract(abi, contractAddress, "TokenContract");
      final function = contract.function('approve');
      List<dynamic> params = [EthereumAddress.fromHex(spender), amountIn];
      Transaction tx = await constructTx(contract: contract, function: function, credentials: credentials, params: params);
      BigInt gas = await estimateTxGas(sender: credentials.address.with0x, to: contractAddress, rpcUrl: rpcUrl, data: tx.data!);
      return gas;
    } catch (e) {
      logger(e.toString(),runtimeType.toString());
      throw Exception("Could not get fee");
    }
  }

  /// Waits for a transaction to be confirmed and returns its status
  ///
  /// [txHash] - The transaction hash to check
  /// [rpcUrl] - The RPC URL of the network where the transaction was sent
  /// [maxWaitTime] - Maximum time to wait in seconds (default: 60 seconds)
  /// [pollInterval] - Interval between checks in seconds (default: 2 seconds)
  ///
  /// Returns a [TransactionStatus] object when the transaction is confirmed
  /// Throws an exception if maxWaitTime is exceeded or network error occurs
  Future<TransactionStatus> waitForTransactionConfirmation({
    required String txHash,
    required String rpcUrl,
    int maxWaitTime = 60,
    int pollInterval = 2,
  }) async {
    try {
      logger("Waiting for transaction confirmation: $txHash", runtimeType.toString());
      final startTime = DateTime.now();

      while (true) {
        final status = await checkTransactionStatus(txHash: txHash, rpcUrl: rpcUrl);

        if (!status.isPending) {
          // Transaction has been confirmed (success or failed)
          return status;
        }

        // Check if max wait time exceeded
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        if (elapsed >= maxWaitTime) {
          logger("Max wait time exceeded for transaction: $txHash", runtimeType.toString());
          throw Exception("Transaction confirmation timeout after $maxWaitTime seconds");
        }

        // Wait before next check
        await Future.delayed(Duration(seconds: pollInterval));
      }
    } catch (e) {
      logger("Error waiting for transaction confirmation: $e", runtimeType.toString());
      rethrow;
    }
  }

  /// Checks the status of a transaction by its hash
  ///
  /// [txHash] - The transaction hash to check
  /// [rpcUrl] - The RPC URL of the network where the transaction was sent
  ///
  /// Returns a [TransactionStatus] object containing:
  /// - [isSuccess] - true if transaction was successful, false if failed
  /// - [isPending] - true if transaction is still pending, false if confirmed
  /// - [blockNumber] - The block number where the transaction was included (null if pending)
  /// - [gasUsed] - The amount of gas used by the transaction (null if pending)
  ///
  /// Throws an exception if the transaction hash is invalid or network error occurs
  Future<TransactionStatus> checkTransactionStatus({
    required String txHash,
    required String rpcUrl,
  }) async {
    try {
      logger("Checking transaction status for: $txHash", runtimeType.toString());
      Web3Client webClient = await ClientResolver.resolveClient(rpcUrl: rpcUrl);

      // Get transaction receipt
      TransactionReceipt? receipt = await webClient.getTransactionReceipt(txHash);

      if (receipt == null) {
        // Transaction is still pending
        logger("Transaction $txHash is still pending", runtimeType.toString());
        return TransactionStatus(
          isSuccess: false,
          isPending: true,
          blockNumber: null,
          gasUsed: null,
          txHash: txHash,
        );
      }

      // Transaction has been mined, check status
      // Status 1 = success, Status 0 = failed
      bool isSuccess = receipt.status == true;

      // Convert BlockNum to int
      int? blockNum;
      try {
        // BlockNum can be converted to string and parsed
        blockNum = int.tryParse(receipt.blockNumber.toString());
      } catch (e) {
        logger("Error parsing block number: $e", runtimeType.toString());
      }

      logger("Transaction $txHash status: ${isSuccess ? 'SUCCESS' : 'FAILED'}", runtimeType.toString());
      logger("Block number: $blockNum", runtimeType.toString());
      logger("Gas used: ${receipt.gasUsed}", runtimeType.toString());

      return TransactionStatus(
        isSuccess: isSuccess,
        isPending: false,
        blockNumber: blockNum,
        gasUsed: receipt.gasUsed,
        txHash: txHash,
      );
    } catch (e) {
      logger("Error checking transaction status: $e", runtimeType.toString());
      throw Exception("An error occurred while checking transaction status: $e");
    }
  }
}
