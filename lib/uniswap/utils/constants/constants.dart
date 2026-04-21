const int chain_id_eth=1;
const int chain_id_pol=137;
const int chain_id_bsc=56;
const int chain_id_arb=42161;
const int chain_id_avax=43114;

String permit2ContractAddress = "0x000000000022D473030F116dDEE9F6B43aC78BA3";
String bsc_swapRouter02 = "0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2";
 String eth_swapRouter02 = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
 String pol_swapRouter02 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";

 String bsc_uniswap_universal_router_contract = "0x4Dae2f939ACf50408e13d58534Ff8c2776d45265";
 String pol_uniswap_universal_router_contract = "0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2";
 String eth_uniswap_universal_router_contract = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af";
 BigInt unlimited = BigInt.parse("115792089237316195423570985008687907853269984665640564039457584007913129639935");
 BigInt permitUnlimited = BigInt.parse("1461501637330902918203684832716283019655932542975");



const String bsc_wbnb_contract = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const String polygon_wpol_contract = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270";
const String eth_weth_contract = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

/// Uniswap V3 Factory contract addresses per chain.
const Map<int, String> chainFactoryAddresses = {
  1: "0x1F98431c8aD98523631AE4a59f267346ea31F984",   // Ethereum
  56: "0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7",  // BSC
  137: "0x1F98431c8aD98523631AE4a59f267346ea31F984",  // Polygon
};

/// Uniswap V3 QuoterV2 contract addresses per chain.
const Map<int, String> chainQuoterV2Addresses = {
  1: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",   // Ethereum
  56: "0x78D78E420Da98ad378D7799bE8f4AF69033EB077",   // BSC
  137: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",  // Polygon
};

/// Standard Uniswap V3 fee tiers in hundredths of a bip.
const List<int> uniswapV3FeeTiers = [100, 500, 3000, 10000];

/// Returns the Factory address for a given [chainId], or `null` if unsupported.
String? getFactoryAddress({required int chainId}) => chainFactoryAddresses[chainId];

/// Returns the QuoterV2 address for a given [chainId], or `null` if unsupported.
String? getQuoterV2Address({required int chainId}) => chainQuoterV2Addresses[chainId];

