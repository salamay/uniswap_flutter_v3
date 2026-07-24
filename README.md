# uniswap_flutter_v3

A Flutter plugin that wraps the Uniswap V3 protocol with a small, high-level
Dart API. It handles on-chain pool discovery, gas estimation, ERC-20/Permit2
approvals, and token/native swaps across multiple EVM chains, so you can work
with human-readable amounts instead of raw `BigInt` wei.

Supported chains out of the box: **Ethereum (1), BSC (56) and Polygon (137)**. Any chain with a deployed Uniswap V3
SwapRouter02 / Universal Router can be added by extending the constants.

---

## Features

- One `UniswapV3` facade per chain — no manual `NetworkRpc` / `NetworkFee` wiring.
- Automatic best-pool lookup, discovered fully on-chain via the Uniswap V3 Factory and Pool contracts.
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
  uniswap_flutter_v3: ^0.0.9
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
2. **A funded wallet** whose private key will sign transactions.

> Private keys should never be hard-coded in production apps. Use a secure
> storage solution such as `flutter_secure_storage`.

---

## Initialization

Create one instance per chain you want to target:

```dart
final bsc = UniswapV3(
  rpcUrl: 'https://bsc-dataseed.binance.org',
  chainId: 56,
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

### Understanding `pool.isInverse`

A Uniswap V3 pool contract always stores its two tokens ordered by contract
address, not by the order you pass `tokenA`/`tokenB`. Sometimes the pool that
actually exists on-chain is only available in the *opposite* order of what
you asked for — e.g. you request `tokenA: usdt, tokenB: usdc`, but the pool
only exists on-chain as USDC/USDT.

When that happens, `getPool` doesn't fail — it returns the pool it found and
sets `pool.isInverse = true`. In that case `pool.token0`/`pool.token1` (and
`pool.token0Price`/`pool.token1Price`) are **swapped** relative to what you
requested: `pool.token0` is actually the token you passed as `tokenB`, and
`pool.token1` is the token you passed as `tokenA`.

All of this library's `estimate*`/`swap*` methods already account for
`isInverse` internally, so you don't need to think about it for normal swaps.
You only need to check `pool.isInverse` yourself if you read
`pool.token0`/`pool.token1`/`pool.token0Price`/`pool.token1Price` directly to
do your own calculations, e.g.:

```dart
final pool = await bsc.getPool(tokenA: usdt, tokenB: usdc,rpcUrl:rpcUrl);

// Decimals/price for the token you originally requested as tokenA (usdt):
final tokenADecimals = !pool!.isInverse ? pool.token0.decimals : pool.token1.decimals;
final tokenAPriceInTokenB = !pool.isInverse ? pool.token0Price : pool.token1Price;
BigInt gasPrice = await uniswapV3.getChainNetworkFee(rpcUrl: rpcUrl, chainId: chainId);;

```

---

## Token → Token Swap

```dart
final pool = await bsc.getPool(tokenA: dai, tokenB: usdt,rpcUrl:rpcUrl);

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
  slippagePercent: 5,    // 5% tolerance
  maxGas: swapGas.toInt(),
);
```

---

## Token → Native Swap

Token → native swaps go through Uniswap's Universal Router and therefore
require a **Permit2** allowance (not a regular ERC-20 approval):

Uniswap V3 pools only ever trade against the **wrapped** native token (WBNB,
WETH, WMATIC, ...) — there is no on-chain USDT/BNB pool, only USDT/WBNB. So
`wbnb` is what you pass to `getPool` to locate the pool. The Universal Router
then handles unwrapping for you as part of the swap: `swapTokenToNative`
actually delivers plain **native BNB** to your wallet, not WBNB tokens — you
never receive or need to unwrap WBNB yourself.

```dart
final pool = await bsc.getPool(tokenA: usdt, tokenB: wbnb,rpcUrl:rpcUrl);

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
// Call permit2
String callPermitHash=await uniswapV3.callPermit2(
token: usdt,
privateKey: key,
maxGas: permit2Gas.toInt(),
gasPrice: gasPrice
);
final swapGas = await bsc.estimateTokenToNativeSwap(
  pool: pool!, amountIn: 1, privateKey: key,
);

final swapHash = await bsc.swapTokenToNative(
  privateKey: key,
  pool: pool,
  amountIn: 1,
  slippagePercent: 5,    // 5% tolerance
  maxGas: swapGas.toInt(),
);
```

---

## Native → Token Swap

No approval is needed — native currency is paid directly with the transaction.

As with the token → native flow, `wbnb` is passed to `getPool` because pools
only exist as WBNB/USDC on-chain, never native BNB/USDC directly. You still
send plain **native BNB** as `amountIn` — the Universal Router wraps it into
WBNB internally to route through the pool, then delivers the output token
(USDC) to your wallet. You never touch WBNB directly:

```dart
final pool = await bsc.getPool(tokenA: wbnb, tokenB: usdc,rpcUrl:rpcUrl);

final swapGas = await bsc.estimateNativeToTokenSwap(
  pool: pool!, amountIn: 0.001, privateKey: key,
);

final swapHash = await bsc.swapNativeToToken(
  privateKey: key,
  pool: pool,
  amountIn: 0.001,       // 0.001 BNB
  slippagePercent: 5,
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
| `networkName` | `String?` | no       | Display name. Auto-resolved from `chainId` if omitted.     |

### Pool discovery

- `Future<Pool?> getPool({required Token tokenA, required Token tokenB})`

`Pool` fields:

| Field                        | Type     | Description                                                                                   |
| ---------------------------- | -------- | ----------------------------------------------------------------------------------------------|
| `poolAddress`                | `String` | The on-chain address of the pool contract.                                                    |
| `feeTier`                    | `String?`| The fee tier the pool was found on (`100`, `500`, `3000`, or `10000`).                         |
| `token0` / `token1`          | `Token`  | The pool's tokens **as actually found on-chain** — see `isInverse` below.                     |
| `token0Price` / `token1Price`| `double?`| Price of one token denominated in the other, matching `token0`/`token1` order.                |
| `liquidity`                  | `double?`| Raw on-chain liquidity of the selected pool.                                                   |
| `isInverse`                  | `bool`   | `true` if `token0`/`token1` are swapped relative to the `tokenA`/`tokenB` you requested — see [Understanding `pool.isInverse`](#understanding-poolisinverse). |

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
