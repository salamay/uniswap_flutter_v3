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
    print('No pool found for');
    return;
  }

  print('Pool address: ${pool.poolAddress}');
  print('Fee tier: ${pool.feeTier}');
  print('token0Price price: ${pool.token0Price}');
  print('token1Price price: ${pool.token1Price}');
  print('Liquidity: ${pool.liquidity}');
}


// ---------------------------------------------------------------------------
// 5. TOKEN-TO-TOKEN SWAP (e.g., USDC -> DAI)
// ---------------------------------------------------------------------------

void tokenToTokenSwapExample() async{
  String rpcUrl="https://bsc-dataseed.binance.org";
  int chainId=56;
  String p =   "PrivateKey";
  final usdc = Token(
    name: 'USD Coin',
    symbol: 'USDC',
    contractAddress: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    decimals: 18,
  );

  final dai = Token(
    name: 'Dai Stablecoin',
    symbol: 'DAI',
    contractAddress: '0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3',
    decimals: 18,
  );

  final pool = await bscUniswap.getPool(tokenA: usdc, tokenB: dai);
  if (pool == null) {
    print('No pool found for');
    return;
  }
  print('Pool address: ${pool.poolAddress}');
  print('Fee tier: ${pool.feeTier}');
  print('token0Price price: ${pool.token0Price}');
  print('token1Price price: ${pool.token1Price}');
  print('Liquidity: ${pool.liquidity}');
  BigInt? gasPrice=await bscUniswap.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);

  BigInt approveGas=await bscUniswap.estimateApproval(
    token: usdc,
    amount: 1,
    privateKey: p,
  );

  // Approve first
  String approveHash=await bscUniswap.approveToken(
      token: usdc,
      amount: 1,
      privateKey: p,
      maxGas: approveGas.toInt(),
      gasPrice: gasPrice
  );
  print('Approve hash: $approveHash');
  TransactionStatus status=await bscUniswap.waitForTransaction(approveHash,30);
  print('Approve status: $status');
  // Estimate gas for a token-to-token swap
  final gas = await bscUniswap.estimateTokenToTokenSwap(
    pool: pool,
    amountIn: 1, // 1 USDC — human-readable!
    privateKey: p,
  );
  print('Estimated gas: $gas wei');
  String swapHash=await bscUniswap.swapTokenToToken(
      pool: pool,
      amountIn: 1, // 100 USDC — human-readable!
      privateKey: p,
      gasPrice: gasPrice,
      maxGas: gas.toInt()
  );
  print('Swap hash: $swapHash');

}


// ---------------------------------------------------------------------------
// 6. TOKEN-TO-NATIVE SWAP (e.g., USDC -> ETH)
// ---------------------------------------------------------------------------
void tokenToNativeExample() async{
  String rpcUrl="https://bsc-dataseed.binance.org";
  int chainId=56;
  String p =   "PrivateKey";
  final bscUniswap = UniswapV3(
    rpcUrl: rpcUrl,
    chainId: chainId, // BSC
    graphApiKey: '7e8b89f52322d9cdf2d03b3c2d135400',
  );
  final usdc = Token(
    name: 'USD Coin',
    symbol: 'USDC',
    contractAddress: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    decimals: 18,
  );
  ///For Native token, you should use WETH address
  //e.g for BNB you use WBNB, for ETH you use WETH, for MATIC you use WMATIC

  final nativeToken = Token(
    name: 'WBNB',
    symbol: 'WBNB',
    contractAddress: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c" ,
    decimals: 18,
  );

  final pool = await bscUniswap.getPool(tokenA: usdc, tokenB: nativeToken);
  if (pool == null) {
    print('No pool found for ');
    return;
  }
  print('Pool address: ${pool.poolAddress}');
  print('Fee tier: ${pool.feeTier}');
  print('Token0 price: ${pool.token0Price}');
  print('Token1  price: ${pool.token1Price}');
  print('Liquidity: ${pool.liquidity}');
  BigInt? gasPrice=await bscUniswap.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);

  BigInt approveGas=await bscUniswap.estimatePermit2Approval(
    token: usdc,
    amount: 1,
    privateKey: p,
  );

  // Approve first
  String approveHash=await bscUniswap.approveUniswapPermit2(
      token: usdc,
      amount: 1,
      privateKey: p,
      maxGas: approveGas.toInt(),
      gasPrice: gasPrice
  );
  print('Approve hash: $approveHash');
  TransactionStatus status=await bscUniswap.waitForTransaction(approveHash,30);
  print('Approve status: $status');
  // Estimate gas for a token-to-token swap
  final gas = await bscUniswap.estimateTokenToNativeSwap(
    pool: pool,
    amountIn: 1, // 100 USDC — human-readable!
    privateKey: p,
  );
  print('Estimated gas: $gas wei');
  String swapHash=await bscUniswap.swapTokenToNative(
    pool: pool,
    amountIn: 1, // 100 USDC — human-readable!
    privateKey: p,
    gasPrice: gasPrice,
    maxGas: gas.toInt(),

  );
  print('Swap hash: $swapHash');

}


// ---------------------------------------------------------------------------
// 7. NATIVE-TO-TOKEN SWAP (e.g., ETH -> USDC)
// ---------------------------------------------------------------------------
void nativeToToken() async{
  String rpcUrl="https://bsc-dataseed.binance.org";
  int chainId=56;
  String p =   "PrivateKey";
  final bscUniswap = UniswapV3(
    rpcUrl: rpcUrl,
    chainId: chainId, // BSC
    graphApiKey: '7e8b89f52322d9cdf2d03b3c2d135400',
  );
  ///For Native token, you should use WETH address
  //e.g for BNB you use WBNB, for ETH you use WETH, for MATIC you use WMATIC
  final nativeToken = Token(
    name: 'WBNB',
    symbol: 'WBNB',
    contractAddress: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c" ,
    decimals: 18,
  );
  final usdc = Token(
    name: 'USD Coin',
    symbol: 'USDC',
    contractAddress: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
    decimals: 18,
  );

  final pool = await bscUniswap.getPool(tokenA: nativeToken, tokenB: usdc);
  if (pool == null) {
    print('No pool found for');
    return;
  }
  print('Pool address: ${pool.poolAddress}');
  print('Fee tier: ${pool.feeTier}');
  print('Token0 price: ${pool.token0Price}');
  print('Token1  price: ${pool.token1Price}');
  print('Liquidity: ${pool.liquidity}');
  BigInt? gasPrice=await bscUniswap.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);

  // Estimate gas for a token-to-token swap
  final gas = await bscUniswap.estimateNativeToTokenSwap(
    pool: pool,
    amountIn: 0.001623,
    privateKey: p,
  );
  print('Estimated gas: $gas wei');

  String swapHash=await bscUniswap.swapNativeToToken(
    pool: pool,
    amountIn: 0.001623,
    privateKey: p,
    gasPrice: gasPrice,
    maxGas: gas.toInt(),

  );
  print('Swap hash: $swapHash');

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
