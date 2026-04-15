// Simplified API (recommended for most users)
import 'package:uniswap_flutter_v3/uniswap_flutter_v3_platform_interface.dart';

export 'uniswap/uniswap_v3.dart';

// Core entities
export 'uniswap/domain/entities/token.dart';
export 'uniswap/domain/entities/pool.dart';
export 'uniswap/domain/entities/network_rpc.dart';
export 'uniswap/domain/entities/network_fee.dart';
export 'uniswap/domain/entities/transaction_status.dart';
export 'uniswap/domain/entities/allowance.dart';

// Advanced / low-level API
export 'uniswap/domain/repositories/SwapRepository.dart';
export 'uniswap/data/repositories_impl/swap_executor.dart';



class UniswapFlutterV3 {
  Future<String?> getPlatformVersion() {
    return UniswapFlutterV3Platform.instance.getPlatformVersion();
  }
}