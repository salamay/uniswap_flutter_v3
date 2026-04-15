import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:uniswap_flutter_v3/uniswap/data/repositories_impl/swap_executor.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_fee.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/pool.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/client_resolver.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/constants/constants.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/logger.dart';
import 'package:uniswap_flutter_v3/uniswap/utils/token_factory.dart';

import 'domain/entities/allowance.dart';
import 'domain/entities/transaction_status.dart';

/// A simplified facade for interacting with Uniswap V3.
///
/// Instead of manually creating [NetworkRpc], [NetworkFee], converting amounts
/// to [BigInt], and calling different methods for different swap types,
/// this class lets you work with human-readable amounts and a clean API.
///
/// ---
///
/// ## Quick Start — Token-to-Token Swap (SwapRouter02)
///
/// Token-to-token swaps (e.g. USDC → DAI) go through the SwapRouter02 and
/// only need a single ERC-20 approval.
///
/// ```dart
/// // 0. Initialize Hive (once, typically in main())
/// await UniswapV3.init();
///
/// // 1. Create an instance
/// final uniswap = UniswapV3(
///   rpcUrl: 'https://mainnet.infura.io/v3/YOUR_KEY',
///   chainId: 1,
///   graphApiKey: 'YOUR_GRAPH_API_KEY',
/// );
///
/// // 2. Define tokens
/// final usdc = Token(name: 'USD Coin', symbol: 'USDC', contractAddress: '0xA0b8...', decimals: 6);
/// final dai  = Token(name: 'Dai',      symbol: 'DAI',  contractAddress: '0x6B17...', decimals: 18);
///
/// // 3. Find the best pool
/// final pool = await uniswap.getPool(tokenA: usdc, tokenB: dai);
///
/// // 4. Approve the SwapRouter02 to spend USDC (one-time per token)
/// final approvalGas = await uniswap.estimateApproval(token: usdc, amount: double.infinity, privateKey: myKey);
/// await uniswap.approveToken(token: usdc, amount: double.infinity, privateKey: myKey, maxGas: approvalGas.toInt());
///
/// // 5. Estimate swap gas, then swap
/// final gas = await uniswap.estimateTokenToTokenSwap(pool: pool!, amountIn: 100.0, privateKey: myKey);
/// final txHash = await uniswap.swapTokenToToken(
///   privateKey: myKey, pool: pool, amountIn: 100.0, slippagePercent: 1, maxGas: gas.toInt(),
/// );
/// ```
///
/// ---
///
/// ## Permit2 — Native ↔ Token Swaps (Universal Router)
///
/// Swaps that involve the native currency (ETH, BNB, POL, etc.) are routed
/// through Uniswap's **Universal Router**, which uses **Permit2** for token
/// authorisation instead of a direct ERC-20 allowance. Permit2 is an
/// intermediary contract that holds allowances on behalf of spenders; it lets
/// the Universal Router pull tokens without ever being approved directly.
///
/// There are **two separate on-chain approval steps** required before the first
/// native ↔ token swap. Both are one-time setups per token:
///
/// ### Step 1 — ERC-20 → Permit2 (`approveUniswapPermit2`)
///
/// A standard ERC-20 `approve` that grants the **Permit2 contract** the right
/// to move tokens from the wallet. Without this, the Permit2 contract cannot
/// pull the token when the Universal Router requests it.
///
/// ```dart
/// final gas1 = await uniswap.estimatePermit2Approval(token: usdc, amount: double.infinity, privateKey: myKey);
/// await uniswap.approveUniswapPermit2(token: usdc, amount: double.infinity, privateKey: myKey, maxGas: gas1.toInt());
/// ```
///
/// ### Step 2 — Permit2 → Universal Router (`callPermit2`)
///
/// Calls Permit2's own `approve(token, spender, amount, deadline)` to record a
/// time-bounded allowance inside Permit2's internal ledger, scoped to the
/// Universal Router. This is what the Universal Router actually reads when it
/// asks Permit2 to transfer tokens on your behalf.
///
/// ```dart
/// // Check first — skip if already set
/// final allowance = await uniswap.checkPermitAllowance(token: usdc, ownerAddress: myAddress);
/// if (allowance == BigInt.zero) {
///   final gas2 = await uniswap.estimatePermit2Call(token: usdc, privateKey: myKey);
///   await uniswap.callPermit2(token: usdc, privateKey: myKey, maxGas: gas2.toInt());
/// }
/// ```
///
/// ### Full Permit2 → Swap Example (ETH → USDC)
///
/// ```dart
/// // One-time setup (per token)
/// final approvalGas = await uniswap.estimatePermit2Approval(token: usdc, amount: double.infinity, privateKey: myKey);
/// await uniswap.approveUniswapPermit2(token: usdc, amount: double.infinity, privateKey: myKey, maxGas: approvalGas.toInt());
///
/// final permit2Gas = await uniswap.estimatePermit2Call(token: usdc, privateKey: myKey);
/// await uniswap.callPermit2(token: usdc, privateKey: myKey, maxGas: permit2Gas.toInt());
///
/// // Swap native → token
/// final pool = await uniswap.getPool(tokenA: weth, tokenB: usdc);
/// final swapGas = await uniswap.estimateNativeToTokenSwap(pool: pool!, amountIn: 0.1, privateKey: myKey);
/// final txHash = await uniswap.swapNativeToToken(
///   privateKey: myKey, pool: pool, amountIn: 0.1, slippagePercent: 1, maxGas: swapGas.toInt(),
/// );
/// ```
///
/// > **Tip:** Call [checkPermitAllowance] before each swap to decide whether
/// > Step 2 needs to be repeated (Permit2 allowances carry a 30-minute
/// > deadline and must be refreshed after expiry).
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

  /// Initializes Hive storage for `graphql_flutter` caching.
  ///
  /// Must be called once (typically from `main()`) before any instance of
  /// [UniswapV3] is used to fetch pools from The Graph.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await UniswapV3.init();
  ///   runApp(const MyApp());
  /// }
  /// ```
  static Future<void> init() async {
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

  /// Polls the network until a transaction is mined, reverted, or the timeout elapses.
  ///
  /// [txHash] - The transaction hash returned by any swap/approve method.
  /// [maxWaitTime] - Maximum total time to wait, in seconds. Polls every 4s.
  ///
  /// Returns a [TransactionStatus] indicating success, failure, or pending.
  ///
  /// ```dart
  /// final status = await uniswap.waitForTransaction(txHash, 60);
  /// ```
  Future<TransactionStatus> waitForTransaction(String txHash, int maxWaitTime) {
    return executor.waitForTransactionConfirmation(
      txHash: txHash,
      rpcUrl: rpcUrl,
      maxWaitTime: maxWaitTime,
      pollInterval: 4,
    );
  }

  // ---------------------------------------------------------------------------
  // Gas Estimation (simplified)
  // ---------------------------------------------------------------------------

  /// Fetches the current gas price (in wei) from the configured RPC.
  ///
  /// Useful to pre-compute `gasPrice` before estimating or sending a swap.
  /// [rpcUrl] and [chainId] are passed explicitly so you can override them
  /// for a different network without constructing a new [UniswapV3] instance.
  Future<BigInt> getChainNetworkFee({
    required String rpcUrl,
    required int chainId,
  }) async {
    return executor.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);
  }
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
  /// Estimates gas for the ERC-20 → Permit2 approval (Permit2 Step 1).
  ///
  /// This is a standard ERC-20 `approve` that grants the **Permit2 contract**
  /// itself the right to move [token] from the wallet. It must be executed once
  /// per token before [callPermit2] (Step 2) can be called.
  ///
  /// See the class-level documentation for the full Permit2 approval flow.
  ///
  /// [token] - The ERC-20 token to approve for Permit2.
  /// [amount] - Human-readable amount (e.g., 100.0 for 100 USDC).
  ///            Pass [double.infinity] for an unlimited (max uint256) approval.
  /// [privateKey] - The wallet's private key (hex string, with or without 0x prefix).
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimatePermit2Approval({
    required Token token,
    required double amount,
    required String privateKey,
  }) {
    return _executor.estimatePermit2Approval(
      token: token,
      network: _network,
      amountIn: amount,
      privateKey: privateKey,
    );
  }

  /// Estimates gas for the Permit2 → Universal Router allowance call (Permit2 Step 2).
  ///
  /// This calls Permit2's `approve(token, spender, amount, deadline)` to record
  /// a time-bounded allowance inside Permit2's internal ledger, scoped to
  /// [spender] (defaults to the Universal Router). The Universal Router reads
  /// this ledger when pulling tokens during a swap — it never holds the ERC-20
  /// allowance directly.
  ///
  /// Call [checkPermitAllowance] beforehand to skip this step if a valid
  /// allowance already exists. Permit2 allowances carry a 30-minute deadline
  /// and must be refreshed after expiry.
  ///
  /// See the class-level documentation for the full Permit2 approval flow.
  ///
  /// [token] - The ERC-20 token whose Permit2 allowance is being set.
  /// [privateKey] - The wallet's private key (hex string, with or without 0x prefix).
  /// [spender] - Optional spender address. Defaults to the Universal Router
  ///             for the configured chain.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Upper-bound gas limit for the estimation transaction. Defaults to 300000.
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimatePermit2Call({
    required Token token,
    required String privateKey,
    String? spender,
  }) async {
    final spenderAddress = spender ?? _executor.getUniversalRouterAddress(chainId: chainId);
    return _executor.estimatePermit2Call(
      privateKey: privateKey,
      tokenAddress: token.contractAddress!,
      spenderAddress: spenderAddress,
      rpcUrl: rpcUrl,
      chainId: chainId,
    );
  }

  /// Executes the Permit2 → Universal Router allowance call (Permit2 Step 2).
  ///
  /// Sends Permit2's `approve(token, spender, amount, deadline)` transaction,
  /// recording a 30-minute allowance inside Permit2's internal ledger for
  /// [spender] (defaults to the Universal Router). After this call the
  /// Universal Router can pull [token] from the wallet during swaps.
  ///
  /// This is the **second of two approval steps** required before the first
  /// native ↔ token swap. The first step ([approveUniswapPermit2]) must already
  /// be complete before calling this method.
  ///
  /// Use [checkPermitAllowance] to check whether a valid allowance is already
  /// in place and avoid sending unnecessary transactions. Allowances expire
  /// after 30 minutes and need to be refreshed before each swap session.
  ///
  /// See the class-level documentation for the full Permit2 approval flow and
  /// a complete code example.
  ///
  /// [token] - The ERC-20 token whose Permit2 allowance is being set.
  /// [privateKey] - The wallet's private key (hex string, with or without 0x prefix).
  /// [spender] - Optional spender address. Defaults to the Universal Router.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimatePermit2Call] to compute a value.
  ///
  /// Returns the transaction hash on success.
  Future<String> callPermit2({
    required Token token,
    required String privateKey,
    String? spender,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    final spenderAddress = spender ?? _executor.getUniversalRouterAddress(chainId: chainId);
    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );
    return _executor.callPermit(
      privateKey: privateKey,
      tokenAddress: token.contractAddress!,
      spenderAddress: spenderAddress,
      rpcUrl: rpcUrl,
      chainId: chainId,
      chainSymbol: _resolveNativeSymbol(chainId),
      fee: fee,
    );
  }

  /// Reads the current Permit2 allowance granted to [spender] for [token].
  ///
  /// Queries the `allowance(owner, token, spender)` view on the Permit2 contract
  /// and returns the approved amount as a raw [BigInt] in the token's smallest unit.
  ///
  /// Use this before every native ↔ token swap session to decide whether
  /// [callPermit2] (Step 2) needs to be called again. Permit2 allowances
  /// expire after 30 minutes, so a non-zero value from a previous session may
  /// no longer be valid. A return value of [BigInt.zero] always means [callPermit2]
  /// must be called before the Universal Router can pull tokens.
  ///
  /// ```dart
  /// final allowance = await uniswap.checkPermitAllowance(token: usdc, ownerAddress: myAddress);
  /// if (allowance == BigInt.zero) {
  ///   final gas = await uniswap.estimatePermit2Call(token: usdc, privateKey: myKey);
  ///   await uniswap.callPermit2(token: usdc, privateKey: myKey, maxGas: gas.toInt());
  /// }
  /// ```
  ///
  /// [token] - The ERC-20 token to query.
  /// [ownerAddress] - The wallet address whose allowance is being read.
  /// [spender] - Optional spender address. Defaults to the Universal Router.
  ///
  /// Returns the Permit2-approved amount in the token's smallest unit.
  /// [BigInt.zero] means no active allowance — [callPermit2] is required.
  Future<Allowance> getPermitAllowance({
    required Token token,
    required String ownerAddress,
    String? spender,
  }) async {
    final spenderAddress = spender ?? _executor.getUniversalRouterAddress(chainId: chainId);
    return _executor.getPermitAllowance(
      ownerAddress: ownerAddress,
      tokenAddress: token.contractAddress!,
      spenderAddress: spenderAddress,
      rpcUrl: rpcUrl,
      chainId: chainId,
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
    Pool newPool=_checkPool(pool);

    return _executor.estimateSwapTx(
      privateKey: privateKey,
      fromAddress: walletAddress,
      poolFee: poolFee,
      pair: newPool,
      amountIn: amountInWei,
      network: _network,
    );
  }

  /// Estimates gas for a token-to-native swap (e.g., USDC -> ETH).
  ///
  /// [pool] - The pool obtained from [getPool].
  /// [amountIn] - Human-readable input amount.
  /// [privateKey] - The wallet's private key.
  ///
  /// Note: estimation is always performed with `amountOutMin = 0`;
  /// apply slippage only when calling [swapTokenToNative].
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateTokenToNativeSwap({
    required Pool pool,
    required double amountIn,
    required String privateKey,
  }) {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    final price=pool.token0Price??0;
    Pool newPool=_checkPool(pool);
    return _executor.estimateTokenToNativeSwapTx(
      privateKey: privateKey,
      pool: newPool,
      network: _network,
      amountIn: amountInWei,
      //Set this to zero for estimation, dont set for the actual transaction
      wethAmountMin: BigInt.zero,
      poolFee: poolFee,
    );
  }

  /// Estimates gas for a native-to-token swap (e.g., ETH -> USDC).
  ///
  /// [pool] - The pool obtained from [getPool].
  /// [amountIn] - Human-readable input amount of native currency.
  /// [privateKey] - The wallet's private key.
  ///
  /// Note: estimation is always performed with `amountOutMin = 0`;
  /// apply slippage only when calling [swapNativeToToken].
  ///
  /// Returns estimated gas as [BigInt] in wei.
  Future<BigInt> estimateNativeToTokenSwap({
    required Pool pool,
    required double amountIn,
    required String privateKey,
  }) {
    // Native input is always 18 decimals
    final amountInWei = toWei(amountIn, 18);
    final poolFee = _parsePoolFee(pool);
    Pool newPool=_checkPool(pool);

    return _executor.estimateNativeToTokenSwapTx(
      privateKey: privateKey,
      pool: newPool,
      amountIn: amountInWei,
      //Set this to zero for estimation, dont set for the actual transaction
      amountOutMin: BigInt.zero,
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
  /// [slippagePercent] - Slippage tolerance as a percentage (e.g., 1 for 1%, 0.5 for 0.5%). Defaults to 1.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimateTokenToTokenSwap] to compute a value.
  ///
  /// Returns the transaction hash on success.
  ///
  /// ```dart
  /// final gas = await uniswap.estimateTokenToTokenSwap(
  ///   pool: pool, amountIn: 100.0, privateKey: myKey,
  /// );
  /// final txHash = await uniswap.swapTokenToToken(
  ///   privateKey: myKey,
  ///   pool: pool,
  ///   amountIn: 100.0,
  ///   slippagePercent: 1,
  ///   maxGas: gas.toInt(),
  /// );
  /// print('Swap tx: $txHash');
  /// ```
  Future<String> swapTokenToToken({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 1,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    double price=!pool.isInverse?pool.token0Price ?? 0:pool.token1Price ?? 0;
    Pool newPool=_checkPool(pool);
    // Calculate minimum output with slippage
    final amountOutMin = _calculateMinOutput(
      amountIn: amountIn,
      price: price,
      outputDecimals: newPool.token1.decimals,
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
      pair: newPool,
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
  /// [slippagePercent] - Slippage tolerance as a percentage (e.g., 1 for 1%). Defaults to 0.5.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimateTokenToNativeSwap] to compute a value.
  ///
  /// Returns the transaction hash on success.
  Future<String> swapTokenToNative({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 0.5,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    final amountInWei = toWei(amountIn, pool.token0.decimals);
    final poolFee = _parsePoolFee(pool);
    double price=pool.token0Price??0;
    Pool newPool=_checkPool(pool);

    // For token->native, calculate min native output (18 decimals)
    final wethAmountMin = _calculateMinOutput(
      amountIn: amountIn,
      price: price,
      outputDecimals: 18,
      slippagePercent: slippagePercent,
    );

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );

    return _executor.tokenToNativeSwap(
      privateKey: privateKey,
      pool: newPool,
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
  /// [amountIn] - Human-readable amount of native currency to swap (e.g., 1 for 1 ETH).
  /// [slippagePercent] - Slippage tolerance as a percentage (e.g., 1 for 1%). Defaults to 1.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimateNativeToTokenSwap] to compute a value.
  ///
  /// Returns the transaction hash on success.
  Future<String> swapNativeToToken({
    required String privateKey,
    required Pool pool,
    required double amountIn,
    double slippagePercent = 1,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    // Native is always 18 decimals
    final amountInWei = toWei(amountIn, 18);
    final poolFee = _parsePoolFee(pool);
    double price=!pool.isInverse?pool.token0Price ?? 0:pool.token1Price ?? 0;
    Pool newPool=_checkPool(pool);

    final amountOutMin = _calculateMinOutput(
      amountIn: amountIn,
      price: price,
      outputDecimals: newPool.token1.decimals,
      slippagePercent: slippagePercent,
    );

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );

    return _executor.nativeToTokenSwap(
      privateKey: privateKey,
      pool: newPool,
      amountIn: amountInWei,
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
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimateApproval] to compute a value.
  ///
  /// Returns the approval transaction hash.
  ///
  /// ```dart
  /// final gas = await uniswap.estimateApproval(
  ///   token: usdc, amount: double.infinity, privateKey: myKey,
  /// );
  /// // Approve unlimited USDC spending
  /// await uniswap.approveToken(
  ///   token: usdc,
  ///   amount: double.infinity,
  ///   privateKey: myKey,
  ///   maxGas: gas.toInt(),
  /// );
  /// ```
  Future<String> approveToken({
    required Token token,
    required double amount,
    required String privateKey,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    final spender = _executor.getUniswapSwapRouterAddress(chainId: chainId);
    final amountInWei = amount == double.infinity
        ? BigInt.parse(
            "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        : toWei(amount, token.decimals);

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );
    return _executor.swapService.approve(
      privateKey: privateKey,
      spender: spender,
      token: token,
      amountIn: amountInWei,
      network: _network,
      fee: fee,
    );
  }

  /// Executes the ERC-20 → Permit2 approval (Permit2 Step 1).
  ///
  /// Sends a standard ERC-20 `approve` transaction granting the **Permit2
  /// contract** the right to transfer [token] from the wallet. This is a
  /// prerequisite for [callPermit2] (Step 2) and only needs to be done once
  /// per token (or once with an unlimited amount).
  ///
  /// This method does **not** interact with the Universal Router directly;
  /// it solely authorises the Permit2 contract at the ERC-20 level. See
  /// [callPermit2] for the second step that registers the Universal Router
  /// inside Permit2's internal ledger.
  ///
  /// See the class-level documentation for the full Permit2 approval flow.
  ///
  /// [token] - The ERC-20 token to approve for Permit2.
  /// [amount] - Human-readable amount. Pass [double.infinity] for an unlimited
  ///            (max uint256) approval so this step never needs repeating.
  /// [privateKey] - The wallet's private key.
  /// [gasPrice] - Optional gas price in wei. If omitted, fetched from the network.
  /// [maxGas] - Required max gas limit. Use [estimatePermit2Approval] to compute a value.
  ///
  /// Returns the approval transaction hash.
  Future<String> approveUniswapPermit2({
    required Token token,
    required double amount,
    required String privateKey,
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    final spender = permit2ContractAddress;
    final amountInWei = amount == double.infinity
        ? BigInt.parse(
        "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        : toWei(amount, token.decimals);

    final fee = await _buildNetworkFee(
      gasPrice: gasPrice,
      maxGas: maxGas,
    );
    return _executor.swapService.approve(
      privateKey: privateKey,
      spender: spender,
      token: token,
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

    //Get the rate
    final expectedOutput = amountIn * price;
    logger("AmountIn ${amountIn.toString()}", runtimeType.toString());
    logger("Expected ${toWei(expectedOutput, outputDecimals)}", runtimeType.toString());
    logger("Slippage $slippagePercent", runtimeType.toString());
    final minOutput = expectedOutput * (1 - (slippagePercent / 100));
    logger("Expected min ${toWei(minOutput, outputDecimals)}", runtimeType.toString());

    if (minOutput <= 0) return BigInt.zero;
    return toWei(minOutput, outputDecimals);
  }

  /// Builds a [NetworkFee] by fetching the current gas price from the network
  /// if not explicitly provided.
  Future<NetworkFee> _buildNetworkFee({
    BigInt? gasPrice,
    required int maxGas,
  }) async {
    BigInt networkGasPrice;

    if (gasPrice != null) {
      // Caller-supplied gas price is expected to already be in wei.
      networkGasPrice = gasPrice;
    } else {
      // Fetch current gas price from the network (returned in wei).
      networkGasPrice = await getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);
    }

    return NetworkFee(
      gasPrice: networkGasPrice,
      maxGas: maxGas,
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

      default:
        return 'ETH';
    }
  }


  //Change back or reverse the token if the pool indicate inverse
  //So  that the executor maintain the trading path, this is because the graph can return the pool in the wrong order as the user intends
  Pool _checkPool(Pool pool){
    Token token0=pool.token0;
    Token token1=pool.token1;
    Pool newPool=Pool(feeTier: pool.feeTier, token0Price: pool.token0Price, token1Price: pool.token1Price, token0: token0, token1: token1, poolAddress:pool. poolAddress, isInverse: pool.isInverse);

    if(!pool.isInverse){
      newPool.token0=token0;
      newPool.token1=token1;
    }else{
      newPool.token0=token1;
      newPool.token1=token0;
    }
    return newPool;
  }
}
