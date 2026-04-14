// To parse this JSON data, do
//
//     final poolData = poolDataFromJson(jsonString);

import 'dart:convert';

PoolData poolDataFromJson(String str) => PoolData.fromJson(json.decode(str));

String poolDataToJson(PoolData data) => json.encode(data.toJson());

class PoolData {
  List<GraphPool>? pools;

  PoolData({
    this.pools,
  });

  factory PoolData.fromJson(Map<String, dynamic> json) => PoolData(
    pools: json["pools"] == null ? [] : List<GraphPool>.from(json["pools"]!.map((x) => GraphPool.fromJson(x))),
  );

  Map<String, dynamic> toJson() => {
    "pools": pools == null ? [] : List<dynamic>.from(pools!.map((x) => x.toJson())),
  };
}

class GraphPool {
  String? feeTier;
  String? id;
  String? liquidity;
  GraphToken? token0;
  String? token0Price;
  GraphToken? token1;
  String? token1Price;
  String? volumeToken0;
  String? volumeToken1;
  String? volumeUsd;

  GraphPool({
    this.feeTier,
    this.id,
    this.liquidity,
    this.token0,
    this.token0Price,
    this.token1,
    this.token1Price,
    this.volumeToken0,
    this.volumeToken1,
    this.volumeUsd,
  });

  factory GraphPool.fromJson(Map<String, dynamic> json) => GraphPool(
    feeTier: json["feeTier"],
    id: json["id"],
    liquidity: json["liquidity"],
    token0: json["token0"] == null ? null : GraphToken.fromJson(json["token0"]),
    token0Price: json["token0Price"],
    token1: json["token1"] == null ? null : GraphToken.fromJson(json["token1"]),
    token1Price: json["token1Price"],
    volumeToken0: json["volumeToken0"],
    volumeToken1: json["volumeToken1"],
    volumeUsd: json["volumeUSD"],
  );

  Map<String, dynamic> toJson() => {
    "feeTier": feeTier,
    "id": id,
    "liquidity": liquidity,
    "token0": token0?.toJson(),
    "token0Price": token0Price,
    "token1": token1?.toJson(),
    "token1Price": token1Price,
    "volumeToken0": volumeToken0,
    "volumeToken1": volumeToken1,
    "volumeUSD": volumeUsd,
  };
}

class GraphToken {
  String? id;
  String? decimals;
  String? derivedEth;
  String? name;
  String? symbol;

  GraphToken({
    this.id,
    this.decimals,
    this.derivedEth,
    this.name,
    this.symbol,
  });

  factory GraphToken.fromJson(Map<String, dynamic> json) => GraphToken(
    id: json["id"],
    decimals: json["decimals"],
    derivedEth: json["derivedETH"],
    name: json["name"],
    symbol: json["symbol"],
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "decimals": decimals,
    "derivedETH": derivedEth,
    "name": name,
    "symbol": symbol,
  };
}
