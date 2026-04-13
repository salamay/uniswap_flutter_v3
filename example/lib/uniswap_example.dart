/// Uniswap V3 Flutter Plugin — Usage Examples
///
/// This file demonstrates the simplified API provided by [UniswapV3].
/// It is NOT meant to be run directly — it shows the patterns you'd
/// use in your own Flutter app.
library;

import 'package:uniswap_flutter_v3/uniswap_flutter_v3.dart';

// ---------------------------------------------------------------------------
// 1. SETUP — Create a UniswapV3 instance
// ---------------------------------------------------------------------------

/// One instance per chain. Pass your RPC URL, chain ID, and Graph API key.
/// Get your Graph API key at: https://thegraph.com/studio/apikeys/
final ethUniswap = UniswapV3(
  rpcUrl: 'https://mainnet.infura.io/v3/YOUR_INFURA_KEY',
  chainId: 1, // Ethereum Mainnet
  graphApiKey: 'YOUR_GRAPH_API_KEY',
);

final bscUniswap = UniswapV3(
  rpcUrl: 'https://bsc-dataseed.binance.org',
  chainId: 56, // BSC
  graphApiKey: 'YOUR_GRAPH_API_KEY',
);

final polygonUniswap = UniswapV3(
  rpcUrl: 'https://polygon-rpc.com',
  chainId: 137, // Polygon
  graphApiKey: 'YOUR_GRAPH_API_KEY',
);

// ---------------------------------------------------------------------------
// 2. DEFINE TOKENS
// ---------------------------------------------------------------------------

/// Tokens only need an address, symbol, name, and decimals.
final usdc = Token(
  name: 'USD Coin',
  symbol: 'USDC',
  contractAddress: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
  decimals: 6,
);

final dai = Token(
  name: 'Dai Stablecoin',
  symbol: 'DAI',
  contractAddress: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
  decimals: 18,
);

final weth = Token(
  name: 'Wrapped Ether',
  symbol: 'WETH',
  contractAddress: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  decimals: 18,
);

// ---------------------------------------------------------------------------
//. Wait for transaction to complete
// ---------------------------------------------------------------------------
Future<void> waitForTx(String hash) async {
  TransactionStatus status=await bscUniswap.waitForTransaction(hash,30);
}

// ---------------------------------------------------------------------------
//. Wait for transaction to complete
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 3. FIND A POOL
// ---------------------------------------------------------------------------

Future<void> findPoolExample() async {
  // Automatically fetches the highest-liquidity pool from The Graph
  final pool = await ethUniswap.getPool(tokenA: usdc, tokenB: weth);

  if (pool == null) {
    print('No pool found for USDC/WETH');
    return;
  }

  print('Pool address: ${pool.poolAddress}');
  print('Fee tier: ${pool.feeTier}');
  print('USDC price in WETH: ${pool.token0Price}');
  print('WETH price in USDC: ${pool.token1Price}');
  print('Liquidity: ${pool.liquidity}');
}


// ---------------------------------------------------------------------------
// 4. ESTIMATE GAS
// ---------------------------------------------------------------------------

Future<void> estimateGasExample() async {
  const privateKey = '0xYOUR_PRIVATE_KEY';
  final pool = await ethUniswap.getPool(tokenA: usdc, tokenB: dai);

  if (pool == null) return;

  // Estimate gas for a token-to-token swap
  final gas = await ethUniswap.estimateTokenToTokenSwap(
    pool: pool,
    amountIn: 100.0, // 100 USDC — human-readable!
    privateKey: privateKey,
  );
  print('Estimated gas: $gas wei');

  // Estimate gas for approval
  final approvalGas = await ethUniswap.estimateApproval(
    token: usdc,
    amount: 100.0,
    privateKey: privateKey,
  );
  print('Approval gas: $approvalGas wei');
}

// ---------------------------------------------------------------------------
// 5. TOKEN-TO-TOKEN SWAP (e.g., USDC -> DAI)
// ---------------------------------------------------------------------------

Future<void> tokenToTokenSwapExample() async {
  const privateKey = '0xYOUR_PRIVATE_KEY';
  final pool = await ethUniswap.getPool(tokenA: usdc, tokenB: dai);

  if (pool == null) return;

  // Step 1: Approve the router to spend USDC (only needed once or if allowance is used up)
  final approvalTx = await ethUniswap.approveToken(
    token: usdc,
    amount: double.infinity, // Unlimited approval
    privateKey: privateKey,
  );
  print('Approval tx: $approvalTx');

  // Step 2: Swap 100 USDC for DAI with 0.5% slippage
  final swapTx = await ethUniswap.swapTokenToToken(
    privateKey: privateKey,
    pool: pool,
    amountIn: 100.0, // 100 USDC
    slippagePercent: 0.5,
  );
  print('Swap tx: $swapTx');
}

// ---------------------------------------------------------------------------
// 6. TOKEN-TO-NATIVE SWAP (e.g., USDC -> ETH)
// ---------------------------------------------------------------------------

Future<void> tokenToNativeSwapExample() async {
  const privateKey = '0xYOUR_PRIVATE_KEY';
  final pool = await ethUniswap.getPool(tokenA: usdc, tokenB: weth);

  if (pool == null) return;

  // Approve first
  await ethUniswap.approveToken(
    token: usdc,
    amount: 500.0,
    privateKey: privateKey,
  );

  // Swap 500 USDC for ETH
  final txHash = await ethUniswap.swapTokenToNative(
    privateKey: privateKey,
    pool: pool,
    amountIn: 500.0,
    slippagePercent: 1.0, // 1% slippage for volatile pairs
  );
  print('Token -> Native tx: $txHash');
}

// ---------------------------------------------------------------------------
// 7. NATIVE-TO-TOKEN SWAP (e.g., ETH -> USDC)
// ---------------------------------------------------------------------------

Future<void> nativeToTokenSwapExample() async {
  const privateKey = '0xYOUR_PRIVATE_KEY';
  final pool = await ethUniswap.getPool(tokenA: weth, tokenB: usdc);

  if (pool == null) return;

  // No approval needed for native currency!
  final txHash = await ethUniswap.swapNativeToToken(
    privateKey: privateKey,
    pool: pool,
    amountIn: 0.5, // 0.5 ETH
    slippagePercent: 0.5,
  );
  print('Native -> Token tx: $txHash');
}

// ---------------------------------------------------------------------------
// 8. CUSTOM GAS SETTINGS
// ---------------------------------------------------------------------------

Future<void> customGasExample() async {
  const privateKey = '0xYOUR_PRIVATE_KEY';
  final pool = await ethUniswap.getPool(tokenA: usdc, tokenB: dai);

  if (pool == null) return;

  // Provide your own gas price (in Gwei) and max gas limit
  final txHash = await ethUniswap.swapTokenToToken(
    privateKey: privateKey,
    pool: pool,
    amountIn: 50.0,
    slippagePercent: 0.3,
    gasPrice: 25.0, // 25 Gwei
    maxGas: 250000,
  );
  print('Custom gas swap tx: $txHash');
}

// ---------------------------------------------------------------------------
// 9. AMOUNT CONVERSION UTILITIES
// ---------------------------------------------------------------------------

void conversionExamples() {
  // Human-readable to wei
  final weiAmount = UniswapV3.toWei(1.5, 18);
  print('1.5 ETH = $weiAmount wei'); // 1500000000000000000

  final usdcWei = UniswapV3.toWei(100.0, 6);
  print('100 USDC = $usdcWei smallest unit'); // 100000000

  // Wei back to human-readable
  final ethAmount = UniswapV3.fromWei(BigInt.parse('1500000000000000000'), 18);
  print('$ethAmount ETH'); // 1.5

  final usdcAmount = UniswapV3.fromWei(BigInt.from(100000000), 6);
  print('$usdcAmount USDC'); // 100.0
}

// ---------------------------------------------------------------------------
// 10. ACCESSING THE LOW-LEVEL API (advanced usage)
// ---------------------------------------------------------------------------

Future<void> advancedExample() async {
  // If you need the full low-level API, access the executor directly
  final executor = ethUniswap.executor;

  // Or access contract addresses
  print('SwapRouter: ${ethUniswap.swapRouterAddress}');
  print('Universal Router: ${ethUniswap.universalRouterAddress}');
  print('WETH: ${ethUniswap.wrappedNativeAddress}');

  // You can also access the NetworkRpc object
  final network = ethUniswap.network;
  print('Network: ${network.name}, Chain ID: ${network.chainId}');
}
