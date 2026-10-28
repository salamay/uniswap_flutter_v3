const int chain_id_eth=1;
const int chain_id_pol=137;
const int chain_id_bsc=56;
const int chain_id_arb=42161;
const int chain_id_avax=43114;
const int chain_id_celo=42220;
const int chain_id_monad=143;
const int chain_id_optimism=10;
const int chain_id_zora=7777777;
const int chain_id_base=8453;

String permit2ContractAddress = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

String bsc_swapRouter02 = "0xB971eF87ede563556b2ED4b1C0b0019111Dd85d2";
 String eth_swapRouter02 = "0xE592427A0AEce92De3Edee1F18E0157C05861564";
 String pol_swapRouter02 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
 String arb_swapRouter02 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
 String celo_swapRouter02 = "0x5615CDAb10dc425a742d643d949a7F474C01abc4";
 String monad_swapRouter02 = "0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900";
 String optmism_swapRouter02 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45";
 String zora_swapRouter02 = "0x7De04c96BE5159c3b5CeffC82aa176dc81281557";
 String avax_swapRouter02 = "0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE";
 String base_swapRouter02 = "0x2626664c2603336E57B271c5C0b26F421741e481";


String eth_uniswap_universal_router_contract = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af";
String bsc_uniswap_universal_router_contract = "0x1906c1d672b88cd1b9ac7593301ca990f94eae07";
String pol_uniswap_universal_router_contract = "0x1095692A6237d83C6a72F3F5eFEdb9A670C49223";
String arb_uniswap_universal_router_contract = "0xa51afafe0263b40edaef0df8781ea9aa03e381a3";
String celo_uniswap_universal_router_contract = "0x643770E279d5D0733F21d6DC03A8efbABf3255B4";
String monad_uniswap_universal_router_contract = "0x0d97dc33264bfc1c226207428a79b26757fb9dc3";
String optmism_uniswap_universal_router_contract = "0x851116d9223fabed8e56c0e6b8ad0c31d98b3507";
String zora_uniswap_universal_router_contract = "0x3315ef7ca28db74abadc6c44570efdf06b04b020";
String avax_uniswap_universal_router_contract = "0x94b75331ae8d42c1b61065089b7d48fe14aa73b7";
String base_uniswap_universal_router_contract = "0x6fF5693b99212Da76ad316178A184AB56D299b43";


 BigInt unlimited = BigInt.parse("115792089237316195423570985008687907853269984665640564039457584007913129639935");
 BigInt permitUnlimited = BigInt.parse("1461501637330902918203684832716283019655932542975");



const String bsc_wbnb_contract = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const String polygon_wpol_contract = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270";
const String eth_weth_contract = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const String arb_weth_contract = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
const String celo_weth_contract = "0x471EcE3750Da237f93B8E339c536989b8978a438";
const String monad_weth_contract = "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A";
const String opt_weth_contract = "0x4200000000000000000000000000000000000006";
const String zora_weth_contract = "0x4200000000000000000000000000000000000006";
const String avax_weth_contract = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
const String base_weth_contract = "0x4200000000000000000000000000000000000006";

/// Uniswap V3 Factory contract addresses per chain.
 Map<int, String> chainFactoryAddresses = {
   chain_id_eth: "0x1F98431c8aD98523631AE4a59f267346ea31F984",   // Ethereum
   chain_id_bsc: "0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7",  // BSC
   chain_id_pol: "0x1F98431c8aD98523631AE4a59f267346ea31F984",  // Polygon
   chain_id_arb: "0x1F98431c8aD98523631AE4a59f267346ea31F984",  // ARB
  chain_id_celo: "0xAfE208a311B21f13EF87E33A90049fC17A7acDEc",  // CELO
  chain_id_monad: "0x204faca1764b154221e35c0d20abb3c525710498",  // Monad
  chain_id_optimism: "0x1F98431c8aD98523631AE4a59f267346ea31F984",  // Optimism
  chain_id_zora: "0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb",  // Zora
  chain_id_avax: "0x740b1c1de25031C31FF4fC9A62f554A55cdC1baD",  // Avalanche
  chain_id_base: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",  // base
};


/// Uniswap V3 QuoterV2 contract addresses per chain.
const Map<int, String> chainQuoterV2Addresses = {
  chain_id_eth: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",   // Ethereum
  chain_id_bsc: "0x78D78E420Da98ad378D7799bE8f4AF69033EB077",   // BSC
  chain_id_pol: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",  // Polygon
  chain_id_arb: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",  // ARB
  chain_id_celo: "0x82825d0554fA07f7FC52Ab63c961F330fdEFa8E8",  // CELO
  chain_id_monad: "0x661e93cca42afacb172121ef892830ca3b70f08d",  // Monad
  chain_id_optimism: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",  // Optimism
  chain_id_zora: "0x11867e1b3348F3ce4FcC170BC5af3d23E07E64Df",  // Zora
  chain_id_avax: "0xbe0F5544EC67e9B3b2D979aaA43f18Fd87E6257F",  // Avalanche
  chain_id_base: "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a",  // base
};

/// Standard Uniswap V3 fee tiers in hundredths of a bip.
const List<int> uniswapV3FeeTiers = [100, 500, 10000];

/// Returns the Factory address for a given [chainId], or `null` if unsupported.
String? getFactoryAddress({required int chainId}) => chainFactoryAddresses[chainId];

/// Returns the QuoterV2 address for a given [chainId], or `null` if unsupported.
String? getQuoterV2Address({required int chainId}) => chainQuoterV2Addresses[chainId];

