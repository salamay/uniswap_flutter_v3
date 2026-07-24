import 'package:uniswap_flutter_v3/uniswap/domain/entities/network_rpc.dart';
import 'package:uniswap_flutter_v3/uniswap/domain/entities/token.dart';

/// Represents an on-chain Uniswap V3 pool for a given token pair, as returned
/// by `getPool`.
///
/// ### Why [isInverse] exists
///
/// A Uniswap V3 pool contract always stores its two tokens ordered by
/// contract address (`token0 < token1` numerically), not in the order a
/// caller happens to request them. When you ask for a pool with
/// `token0: USDT, token1: USDC`, the on-chain pool may actually be ordered
/// `USDC/USDT` — i.e. the *opposite* of what was requested.
///
/// Rather than silently returning prices/tokens that don't match the
/// requested order, [Pool] reports this mismatch via [isInverse]:
///
/// - `isInverse == false`: the pool was found in the exact order requested.
///   [token0]/[token1] and [token0Price]/[token1Price] correspond directly
///   to the `token0`/`token1` arguments passed to `getPool`.
/// - `isInverse == true`: the pool was only found in the *opposite* order.
///   [token0] now holds what was originally requested as `token1` (and vice
///   versa), so [token0]/[token1] are swapped relative to the original
///   request. [token0Price]/[token1Price] are swapped accordingly, so they
///   still correctly describe [token0]/[token1] as returned.
///
/// In practice, this means calculations that need to know "which side is
/// the token I originally asked for as input" must branch on [isInverse],
/// e.g.:
///
/// ```dart
/// // Decimals of the token that was originally requested as token0:
/// final decimals = !pool.isInverse ? pool.token0.decimals : pool.token1.decimals;
/// ```
class Pool {
  String? feeTier;
  String poolAddress;

  /// Price of [token1] denominated in [token0] (how many [token1] per 1 [token0]).
  double? token0Price;

  /// Price of [token0] denominated in [token1] (how many [token0] per 1 [token1]).
  double? token1Price;
  double? volumeToken0;
  double? volumeToken1;
  double? volumeUsd;
  double? liquidity;

  /// The first token of the pool as actually returned. When [isInverse] is
  /// `true`, this is the token that was originally requested as `token1`.
  Token token0;

  /// The second token of the pool as actually returned. When [isInverse] is
  /// `true`, this is the token that was originally requested as `token0`.
  Token token1;

  /// Whether the on-chain pool was only found with its tokens in the
  /// opposite order of what was requested (e.g. requested USDT/USDC but the
  /// pool only exists as USDC/USDT).
  ///
  /// When `true`, [token0]/[token1] (and their prices) are swapped relative
  /// to the original request — see the class-level docs for how to account
  /// for this in calculations.
  bool isInverse;

  Pool({
    required this.feeTier,
    required this.token0Price,
    required this.token1Price,
    this.volumeToken0,
    this.volumeToken1,
    this.volumeUsd,
    this.liquidity,
    required this.token0,
    required this.token1,
    required this.poolAddress,
    required this.isInverse,
  });

}