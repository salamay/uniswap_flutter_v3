# uniswap_flutter_v3

A Flutter plugin that wraps the Uniswap V3 protocol with a small, high-level
Dart API. It handles pool discovery via The Graph, gas estimation,
ERC-20/Permit2 approvals, and token/native swaps across multiple EVM chains,
so you can work with human-readable amounts instead of raw `BigInt` wei.

Supported chains out of the box: **Ethereum (1), BSC (56) and Polygon (137)**. Any chain with a deployed Uniswap V3
SwapRouter02 / Universal Router can be added by extending the constants.

---

## Features

- One `UniswapV3` facade per chain — no manual `NetworkRpc` / `NetworkFee` wiring.
- Automatic best-pool lookup from the Uniswap V3 subgraph on The Graph.
- Gas estimation helpers for every swap and approval type.
- Token → Token, Token → Native, Native → Token swap execution.
- Standard ERC-20 `approve` and Uniswap `Permit2` approval flows.
- Slippage protection using on-chain pool prices.
- Transaction confirmation polling with a simple `TransactionStatus` result.
- Human-readable amounts in (`double`) and out (`BigInt`) via `toWei` / `fromWei`.

---

## Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  uniswap_flutter_v3: ^0.0.1
```

Then run:

```bash
flutter pub get
```

---

## Prerequisites

You will need:

1. **A JSON-RPC endpoint** for your target chain (Infura, Alchemy, QuickNode, or
   a public RPC such as `https://bsc-dataseed.binance.org`).
2. **A Graph API key** for pool discovery. Create one free at
   <https://thegraph.com/studio/apikeys/>.
3. **A funded wallet** whose private key will sign transactions.

> Private keys should never be hard-coded in production apps. Use a secure
> storage solution such as `flutter_secure_storage`.

---

## Initialization

Call `UniswapV3.init()` once before constructing any instance. It boots the
Hive store used by `graphql_flutter` for subgraph caching.

```dart
import 'package:flutter/material.dart';
import 'package:uniswap_flutter_v3/uniswap_flutter_v3.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UniswapV3.init();
  runApp(const MyApp());
}
```

Create one instance per chain you want to target:

```dart
final bsc = UniswapV3(
  rpcUrl: 'https://bsc-dataseed.binance.org',
  chainId: 56,
  graphApiKey: 'YOUR_GRAPH_API_KEY',
);
```

---

## Defining Tokens

A `Token` only needs a name, symbol, contract address, and decimals:

```dart
final usdc = Token(
  name: 'USD Coin',
  symbol: 'USDC',
  contractAddress: '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d',
  decimals: 18,
);

// For native-currency swaps, use the wrapped-native address
// (WETH on Ethereum, WBNB on BSC, WMATIC on Polygon, etc.).
final wbnb = Token(
  name: 'Wrapped BNB',
  symbol: 'WBNB',
  contractAddress: '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c',
  decimals: 18,
);
```

---

## Finding a Pool

```dart
final pool = await bsc.getPool(tokenA: usdc, tokenB: wbnb);
if (pool == null) {
  // no liquidity for this pair
  return;
}
print('Pool: ${pool.poolAddress}, fee tier: ${pool.feeTier}');
```

`getPool` returns the highest-liquidity pool for the pair, or `null` if none
exists.

---

## Token → Token Swap

```dart
final pool = await bsc.getPool(tokenA: dai, tokenB: usdt);

// 1. Approve the SwapRouter to spend DAI.
final approveGas = await bsc.estimateApproval(
  token: dai, amount: 1, privateKey: key,
);
final approveHash = await bsc.approveToken(
  token: dai,
  amount: 1,
  privateKey: key,
  maxGas: approveGas.toInt(),
);
await bsc.waitForTransaction(approveHash, 60);

// 2. Estimate gas for the swap.
final swapGas = await bsc.estimateTokenToTokenSwap(
  pool: pool!, amountIn: 1, privateKey: key,
);

// 3. Execute.
final swapHash = await bsc.swapTokenToToken(
  privateKey: key,
  pool: pool,
  amountIn: 1,           // 1 DAI (human-readable)
  slippagePercent: 1,    // 1% tolerance
  maxGas: swapGas.toInt(),
);
```

---

## Token → Native Swap

Token → native swaps go through Uniswap's Universal Router and therefore
require a **Permit2** allowance (not a regular ERC-20 approval):

```dart
final pool = await bsc.getPool(tokenA: usdt, tokenB: wbnb);

final permit2Gas = await bsc.estimatePermit2Approval(
  token: usdt, amount: 1, privateKey: key,
);
final approveHash = await bsc.approveUniswapPermit2(
  token: usdt,
  amount: 1,
  privateKey: key,
  maxGas: permit2Gas.toInt(),
);
await bsc.waitForTransaction(approveHash, 60);

final swapGas = await bsc.estimateTokenToNativeSwap(
  pool: pool!, amountIn: 1, privateKey: key,
);

final swapHash = await bsc.swapTokenToNative(
  privateKey: key,
  pool: pool,
  amountIn: 1,
  slippagePercent: 0.5,
  maxGas: swapGas.toInt(),
);
```

---

## Native → Token Swap

No approval is needed — native currency is paid directly with the transaction:

```dart
final pool = await bsc.getPool(tokenA: wbnb, tokenB: usdc);

final swapGas = await bsc.estimateNativeToTokenSwap(
  pool: pool!, amountIn: 0.001, privateKey: key,
);

final swapHash = await bsc.swapNativeToToken(
  privateKey: key,
  pool: pool,
  amountIn: 0.001,       // 0.001 BNB
  slippagePercent: 1,
  maxGas: swapGas.toInt(),
);
```

---

## Waiting for Confirmation

```dart
final status = await bsc.waitForTransaction(swapHash, 60);
// status is one of: TransactionStatus.success / failed / pending
```

Poll interval is 4s; `maxWaitTime` is in seconds.

---

## API Reference

### Constructor

| Parameter     | Type      | Required | Description                                                |
| ------------- | --------- | -------- | ---------------------------------------------------------- |
| `rpcUrl`      | `String`  | yes      | JSON-RPC endpoint for the chain.                           |
| `chainId`     | `int`     | yes      | Chain ID (1, 56, 137, 42161, 43114, ...).                  |
| `graphApiKey` | `String`  | yes      | The Graph API key for subgraph queries.                    |
| `networkName` | `String?` | no       | Display name. Auto-resolved from `chainId` if omitted.     |

### Pool discovery

- `Future<Pool?> getPool({required Token tokenA, required Token tokenB})`

### Gas estimation (all return `BigInt` in wei)

- `estimateApproval({token, amount, privateKey})`
- `estimatePermit2Approval({token, amount, privateKey})`
- `estimateTokenToTokenSwap({pool, amountIn, privateKey})`
- `estimateTokenToNativeSwap({pool, amountIn, privateKey})`
- `estimateNativeToTokenSwap({pool, amountIn, privateKey})`
- `getChainNetworkFee({rpcUrl, chainId})` — current network gas price in wei.

### Approvals (return the transaction hash)

- `approveToken({token, amount, privateKey, gasPrice?, maxGas})`
- `approveUniswapPermit2({token, amount, privateKey, gasPrice?, maxGas})`

Pass `double.infinity` as `amount` for an unlimited allowance.

### Swaps (return the transaction hash)

- `swapTokenToToken({privateKey, pool, amountIn, slippagePercent=1, gasPrice?, maxGas})`
- `swapTokenToNative({privateKey, pool, amountIn, slippagePercent=0.5, gasPrice?, maxGas})`
- `swapNativeToToken({privateKey, pool, amountIn, slippagePercent=1, gasPrice?, maxGas})`

`slippagePercent` is expressed as a percentage: `1` = 1%, `0.5` = 0.5%.

### Utilities

- `waitForTransaction(String txHash, int maxWaitTimeSeconds)`
- `static BigInt UniswapV3.toWei(double amount, int decimals)`
- `static double UniswapV3.fromWei(BigInt wei, int decimals)`
- `swapRouterAddress` / `universalRouterAddress` / `wrappedNativeAddress`
- `network` — the underlying `NetworkRpc`.
- `executor` — the low-level `SwapExecutor` for advanced use.

---

## Notes on slippage

Minimum output is computed from the pool's on-chain price and the decimals of
the output token:

```
minOut = amountIn * price * (1 - slippagePercent / 100)
```

For highly volatile pairs, use a larger `slippagePercent` (e.g. `3`–`5`).

---

## Security

- Never commit private keys or API keys to source control.
- Prefer secure key storage (`flutter_secure_storage`, hardware wallets, MPC).
- Always `waitForTransaction` on approvals before sending the dependent swap.

---

## Example

A runnable sample lives in the [`example/`](example) directory.

---

## License

See [LICENSE](LICENSE).
