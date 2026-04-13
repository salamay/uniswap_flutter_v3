import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:uniswap_flutter_v3/uniswap/data/repositories_impl/swap_executor.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_fee.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/pool.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/client_resolver.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/logger.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/token_factory.dart';

import 'domain/entities/transaction_status.dart';

/// A simplified facade for interacting with Uniswap V3.
///
/// Instead of manually creating [NetworkRpc], [NetworkFee], converting amounts
/// to [BigInt], and calling different methods for different swap types,
/// this class lets you work with human-readable amounts and a clean API.
///
/// ## Quick Start
///
/// ```dart
/// // 1. Create an instance
/// final uniswap = UniswapV3(
///   rpcUrl: 'https://mainnet.infura.io/v3/YOUR_KEY',
///   chainId: 1,
///   graphApiKey: 'YOUR_GRAPH_API_KEY', // from https://thegraph.com/studio/apikeys/
/// );
///
/// // 2. Define your tokens
/// final usdc = Token(name: 'USD Coin', symbol: 'USDC', contractAddress: '0xA0b8...', decimals: 6);
/// final weth = Token(name: 'Wrapped Ether', symbol: 'WETH', contractAddress: '0xC02a...', decimals: 18);
///
/// // 3. Find the best pool
/// final pool = await uniswap.getPool(tokenA: usdc, tokenB: weth);
///
/// // 4. Swap (human-readable amounts, automatic gas estimation)
/// final txHash = await uniswap.swapTokenToToken(
///   privateKey: '0xYOUR_PRIVATE_KEY',
///   pool: pool!,
///   amountIn: 100.0,        // 100 USDC
///   slippagePercent: 0.5,   // 0.5% slippage tolerance
/// );
/// ```
class UniswapV3 {
  /// The RPC URL for the blockchain node.
  final String rpcUrl;

  /// The chain ID of the network (e.g., 1 for Ethereum, 56 for BSC, 137 for Polygon).
  final int chainId;

  /// Optional human-readable network name. Defaults based on [chainId].
  final String? networkName;

  /// The Graph API key for querying Uniswap subgraphs (pool discovery).
  ///
  /// Get your key at https://thegraph.com/studio/apikeys/
  final String graphApiKey;

  late final SwapExecutor _executor;
  late final NetworkRpc _network;
  final TokenFactory _tokenFactory = TokenFactory();

  static Future<void> init()async{
    await initHiveForFlutter();
  }
  /// Creates a new [UniswapV3] instance configured for a specific chain.
  ///
  /// [rpcUrl] - The JSON-RPC endpoint URL (e.g., Infura, Alchemy, or your own node).
  /// [chainId] - The chain ID: 1 (Ethereum), 56 (BSC), 137 (Polygon), 42161 (Arbitrum), 43114 (Avalanche).
  /// [graphApiKey] - Your API key from The Graph (https://thegraph.com/studio/apikeys/).
  /// [networkName] - Optional display name. Auto-resolved from [chainId] if not provided.
  UniswapV3({
    required this.rpcUrl,
    required this.chainId,
    required this.graphApiKey,
    this.networkName,
  }) {
    _executor = SwapExecutor();
    _network = NetworkRpc(
      name: networkName ?? _resolveNetworkName(chainId),
      chainId: chainId,
      rpcUrl: rpcUrl,
    );
  }

  // ---------------------------------------------------------------------------
  // Pool Discovery
  // ---------------------------------------------------------------------------

  /// Fetches the best liquidity pool for a token pair from The Graph.
  ///
  /// Returns `null` if no pool exists for the given pair.
  /// The pool with the highest liquidity is selected automatically.
  ///
  /// ```dart
  /// final pool = await uniswap.getPool(tokenA: usdc, tokenB: weth);
  /// if (pool != null) {
  ///   print('Pool found: ${pool.poolAddress}');
  ///   print('Fee tier: ${pool.feeTier}');
  /// }
  /// ```
  Future<Pool?> getPool({
    required Token tokenA,
    required Token tokenB,
  }) {
    return _executor.getPool(
      chainId: chainId,
      token0: tokenA,
      token1: tokenB,
      graphApiKey: graphApiKey,
    );
  }

  Future<TransactionStatus> waitForTransaction(String txHash, int maxWaitTime){
    return executor.waitForTransactionConfirmation(txHash: txHash, rpcUrl:  rpcUrl,maxWaitTime: maxWaitTime,pollInterval: 4);
  }

  // ---------------------------------------------------------------------------
  // Gas Estimation (simplified)
  // ---------------------------------------------------------------------------

  /// Estimates gas for approving a token spend (required before swapping ERC-20 tokens).
  ///
  /// [token] - The token to approve.
  /// [amount] - Human-readable amount (e.g., 100.0 for 100 USDC).
  /// [privateKey] - The wallet's private key (hex string, with or without 0x prefix).
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateApproval({
    required Token token,
    required double amount,
    required String privateKey,
  }) {
    return _executor.estimateApproveTx(
      from: token,
      network: _network,
      amountIn: amount,
      privateKey: privateKey,
    );
  }

  /// Estimates gas for a token-to-token swap.
  ///
  /// [pool] - The pool obtained from [getPool].
  /// [amountIn] - Human-readable input amount (e.g., 1.5 for 1.5 ETH).
  /// [privateKey] - The wallet's private key.
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateTokenToTokenSwap({
    required Pool pool,
    required double amountIn,
    required String privateKey,
  }) async {
    final walletAddress = await _getWalletAddress(privateKey);
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    return _executor.estimateSwapTx(
      privateKey: privateKey,
      fromAddress: walletAddress,
      poolFee: poolFee,
      pair: pool,
      amountIn: amountInWei,
      network: _network,
    );
  }

  /// Estimates gas for a token-to-native swap (e.g., USDC -> ETH).
  ///
  /// [pool] - The pool obtained from [getPool].
  /// [amountIn] - Human-readable input amount.
  /// [privateKey] - The wallet's private key.
  /// [minAmountOut] - Optional minimum output in human-readable form. Defaults to 0.
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateTokenToNativeSwap({
    required Pool pool,
    required double amountIn,
    required String privateKey,
    double minAmountOut = 0,
  }) {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    // For native output, use 18 decimals (ETH/BNB/POL are all 18)
    final minOutWei = toWei(minAmountOut, 18);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    return _executor.estimateTokenToNativeSwapTx(
      privateKey: privateKey,
      pool: pool,
      network: _network,
      amountIn: amountInWei,
      wethAmountMin: minOutWei,
      poolFee: poolFee,
    );
  }

  /// Estimates gas for a native-to-token swap (e.g., ETH -> USDC).
  ///
  /// [pool] - The pool obtained from [getPool].
  /// [amountIn] - Human-readable input amount of native currency.
  /// [privateKey] - The wallet's private key.
  /// [minAmountOut] - Optional minimum output in human-readable form. Defaults to 0.
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateNativeToTokenSwap({
    required Pool pool,
    required double amountIn,
    required String privateKey,
    double minAmountOut = 0,
  }) {
    // Native input is always 18 decimals
    final amountInWei = toWei(amountIn, 18);
    final poolFee = _parsePoolFee(pool);
    final minOutWei = toWei(minAmountOut, pool.token1.decimals);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    return _executor.estimateNativeToTokenSwapTx(
      privateKey: privateKey,
      pool: pool,
      amountIn: amountInWei,
      amountOutMin: minOutWei,
      poolFee: poolFee,
      network: _network,
    );
  }

  // ---------------------------------------------------------------------------
  // Swap Execution
  // ---------------------------------------------------------------------------

  /// Swaps one ERC-20 token for another (e.g., USDC -> DAI).
  ///
  /// [privateKey] - The wallet's private key.
  /// [pool] - The pool obtained from [getPool]. `pool.token0` is the input token.
  /// [amountIn] - Human-readable amount to swap (e.g., 100.0 for 100 USDC).
  /// [slippagePercent] - Slippage tolerance as a percentage (e.g., 0.5 for 0.5%). Defaults to 0.5.
  /// [gasPrice] - Optional gas price in Gwei. If omitted, fetched from the network.
  /// [maxGas] - Optional max gas limit. If omitted, estimated automatically.
  ///
  /// Returns the transaction hash on success.
  ///
  /// ```dart
  /// final txHash = await uniswap.swapTokenToToken(
  ///   privateKey: myKey,
  ///   pool: pool,
  ///   amountIn: 100.0,
  ///   slippagePercent: 0.5,
  /// );
  /// print('Swap tx: $txHash');
  /// ```
  Future<String> swapTokenToToken({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 0.5,
    double? gasPrice,
    int? maxGas,
  }) async {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    // Calculate minimum output with slippage
    final amountOutMin = _calculateMinOutput(
      amountIn: amountIn,
      price: pool.token0Price ?? 0,
      outputDecimals: pool.token1.decimals,
      slippagePercent: slippagePercent,
    );

    // Build network fee (auto-fetch gas price if not provided)
    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );

    return _executor.swap(
      privateKey: privateKey,
      poolFee: poolFee,
      pair: pool,
      amountIn: amountInWei,
      amountOutMin: amountOutMin,
      fee: fee,
      network: _network,
    );
  }

  /// Swaps an ERC-20 token for the native currency (e.g., USDC -> ETH).
  ///
  /// [privateKey] - The wallet's private key.
  /// [pool] - The pool obtained from [getPool]. `pool.token0` is the input token.
  /// [amountIn] - Human-readable amount to swap.
  /// [slippagePercent] - Slippage tolerance as a percentage. Defaults to 0.5.
  /// [gasPrice] - Optional gas price in Gwei.
  /// [maxGas] - Optional max gas limit.
  ///
  /// Returns the transaction hash on success.
  Future<String> swapTokenToNative({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 0.5,
    double? gasPrice,
    int? maxGas,
  }) async {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    // For token->native, calculate min native output (18 decimals)
    final wethAmountMin = _calculateMinOutput(
      amountIn: amountIn,
      price: pool.token0Price ?? 0,
      outputDecimals: 18,
      slippagePercent: slippagePercent,
    );

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );

    return _executor.tokenToNativeSwap(
      privateKey: privateKey,
      pool: pool,
      amountIn: amountInWei,
      wethAmountMin: wethAmountMin,
      network: _network,
      fee: fee,
      poolFee: poolFee,
    );
  }

  /// Swaps native currency for an ERC-20 token (e.g., ETH -> USDC).
  ///
  /// [privateKey] - The wallet's private key.
  /// [pool] - The pool obtained from [getPool]. `pool.token1` is the output token.
  /// [amountIn] - Human-readable amount of native currency to swap (e.g., 0.5 for 0.5 ETH).
  /// [slippagePercent] - Slippage tolerance as a percentage. Defaults to 0.5.
  /// [gasPrice] - Optional gas price in Gwei.
  /// [maxGas] - Optional max gas limit.
  ///
  /// Returns the transaction hash on success.
  Future<String> swapNativeToToken({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 0.5,
    double? gasPrice,
    int? maxGas,
  }) async {
    // Native is always 18 decimals
    final amountInWei = toWei(amountIn, 18);
    final poolFee = _parsePoolFee(pool);
    Token token0=pool.token0;
    Token token1=pool.token1;
    if(!pool.isInverse){
      pool.token0=token0;
      pool.token1=token1;
    }else{
      pool.token0=token1;
      pool.token1=token0;
    }

    final amountOutMin = _calculateMinOutput(
      amountIn: amountIn,
      price: pool.token1Price ?? 0,
      outputDecimals: pool.token1.decimals,
      slippagePercent: slippagePercent,
    );

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );

    return _executor.nativeToTokenSwap(
      privateKey: privateKey,
      pool: pool,
      amountIn: amountInWei,
      amountOutMin: amountOutMin,
      wethAmountMin: amountOutMin,
      poolFee: poolFee,
      fee: fee,
      network: _network,
    );
  }

  // ---------------------------------------------------------------------------
  // Token Approval
  // ---------------------------------------------------------------------------

  /// Approves the Uniswap router to spend a token on your behalf.
  ///
  /// This must be called before [swapTokenToToken] or [swapTokenToNative]
  /// if the token hasn't been approved yet.
  ///
  /// [token] - The ERC-20 token to approve.
  /// [amount] - Human-readable amount to approve (e.g., 1000.0).
  ///            Pass [double.infinity] for unlimited approval.
  /// [privateKey] - The wallet's private key.
  /// [gasPrice] - Optional gas price in Gwei.
  /// [maxGas] - Optional max gas limit. Defaults to 100000.
  ///
  /// Returns the approval transaction hash.
  ///
  /// ```dart
  /// // Approve unlimited USDC spending
  /// await uniswap.approveToken(
  ///   token: usdc,
  ///   amount: double.infinity,
  ///   privateKey: myKey,
  /// );
  /// ```
  Future<String> approveToken({
    required Token token,
    required double amount,
    required String privateKey,
    double? gasPrice,
    int? maxGas,
  }) async {
    final spender = _executor.getUniswapSwapRouterAddress(chainId: chainId);
    final amountInWei = amount == double.infinity
        ? BigInt.parse(
            "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        : toWei(amount, token.decimals);

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas ?? 100000,
    );

    return _executor.swapService.transactionService.approve(
      walletAddress: await _getWalletAddress(privateKey),
      privateKey: privateKey,
      spender: spender,
      token0: token,
      amountIn: amountInWei,
      network: _network,
      fee: fee,
    );
  }

  // ---------------------------------------------------------------------------
  // Contract Address Helpers
  // ---------------------------------------------------------------------------

  /// Returns the Uniswap V3 SwapRouter02 address for this chain.
  String get swapRouterAddress =>
      _executor.getUniswapSwapRouterAddress(chainId: chainId);

  /// Returns the Universal Router address for this chain.
  String get universalRouterAddress =>
      _executor.getUniversalRouterAddress(chainId: chainId);

  /// Returns the wrapped native token address (WETH/WBNB/WPOL) for this chain.
  String get wrappedNativeAddress =>
      _executor.getWETHContractAddress(chainId: chainId);

  /// Returns the underlying [NetworkRpc] configuration.
  NetworkRpc get network => _network;

  /// Returns the underlying [SwapExecutor] for advanced usage.
  ///
  /// Use this if you need access to the full low-level API (e.g., encoding
  /// functions, raw BigInt parameters, etc.).
  SwapExecutor get executor => _executor;

  // ---------------------------------------------------------------------------
  // Amount Conversion Utilities (static, usable without an instance)
  // ---------------------------------------------------------------------------

  /// Converts a human-readable amount to the smallest token unit (wei).
  ///
  /// ```dart
  /// UniswapV3.toWei(1.5, 18);  // 1500000000000000000 (1.5 ETH in wei)
  /// UniswapV3.toWei(100.0, 6); // 100000000 (100 USDC in smallest unit)
  /// UniswapV3.toWei(0.01, 8);  // 1000000 (0.01 BTC in satoshis)
  /// ```
  static BigInt toWei(double amount, int decimals) {
    // Use string manipulation to avoid floating point precision issues
    final parts = amount.toStringAsFixed(decimals).split('.');
    final wholePart = parts[0];
    final fracPart = parts.length > 1 ? parts[1] : '';

    // Pad or truncate fractional part to match decimals
    final paddedFrac = fracPart.length >= decimals
        ? fracPart.substring(0, decimals)
        : fracPart.padRight(decimals, '0');

    final combined = '$wholePart$paddedFrac';
    // Remove leading zeros but keep at least one digit
    return BigInt.parse(combined);
  }

  /// Converts a wei (smallest unit) amount back to a human-readable double.
  ///
  /// ```dart
  /// UniswapV3.fromWei(BigInt.from(1500000000000000000), 18); // 1.5
  /// UniswapV3.fromWei(BigInt.from(100000000), 6);            // 100.0
  /// ```
  static double fromWei(BigInt wei, int decimals) {
    final divisor = BigInt.from(10).pow(decimals);
    final wholePart = wei ~/ divisor;
    final fracPart = wei.remainder(divisor).abs();
    final fracString = fracPart.toString().padLeft(decimals, '0');
    return double.parse('$wholePart.$fracString');
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  /// Derives the wallet address from a private key using [TokenFactory].
  Future<String> _getWalletAddress(String privateKey) async {
    final credentials = await _tokenFactory.getCredentials(privateKey);
    return credentials.address.with0x;
  }

  /// Parses the pool fee tier string into a [BigInt].
  /// Defaults to 3000 (0.3%) if the pool has no fee tier.
  BigInt _parsePoolFee(Pool pool) {
    if (pool.feeTier == null) return BigInt.from(3000);
    return BigInt.parse(pool.feeTier!);
  }

  /// Calculates the minimum acceptable output amount after applying slippage.
  BigInt _calculateMinOutput({
    required double amountIn,
    required double price,
    required int outputDecimals,
    required double slippagePercent,
  }) {
    if (price <= 0) return BigInt.zero;
    final expectedOutput = amountIn * price;
    final minOutput = expectedOutput * (1 - slippagePercent / 100);
    if (minOutput <= 0) return BigInt.zero;
    return toWei(minOutput, outputDecimals);
  }

  /// Builds a [NetworkFee] by fetching the current gas price from the network
  /// if not explicitly provided.
  Future<NetworkFee> _buildNetworkFee({
    double? gasPrice,
    int? maxGas,
  }) async {
    BigInt gasPriceWei;

    if (gasPrice != null) {
      // User provided gas price in Gwei -> convert to wei
      gasPriceWei = BigInt.from(gasPrice * 1e9);
    } else {
      // Fetch current gas price from the network
      final client = await ClientResolver.resolveClient(rpcUrl: rpcUrl);
      final networkGasPrice = await client.getGasPrice();
      gasPriceWei = networkGasPrice.getInWei;
    }

    return NetworkFee(
      gasPrice: gasPriceWei,
      symbol: _resolveNativeSymbol(chainId),
      maxGas: maxGas ?? 300000, // Reasonable default for swap txs
    );
  }

  /// Resolves a human-readable network name from a chain ID.
  static String _resolveNetworkName(int chainId) {
    switch (chainId) {
      case 1:
        return 'Ethereum';
      case 56:
        return 'BSC';
      case 137:
        return 'Polygon';
      case 42161:
        return 'Arbitrum';
      case 43114:
        return 'Avalanche';
      default:
        return 'Chain $chainId';
    }
  }

  /// Resolves the native currency symbol from a chain ID.
  static String _resolveNativeSymbol(int chainId) {
    switch (chainId) {
      case 1:
      case 42161:
        return 'ETH';
      case 56:
        return 'BNB';
      case 137:
        return 'POL';
      case 43114:
        return 'AVAX';
      default:
        return 'ETH';
    }
  }
}
