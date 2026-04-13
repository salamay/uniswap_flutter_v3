// To parse this JSON data, do
//
//     final uniswapToken = uniswapTokenFromJson(jsonString);

import 'dart:convert';

UniswapToken uniswapTokenFromJson(String str) => UniswapToken.fromJson(json.decode(str));

String uniswapTokenToJson(UniswapToken data) => json.encode(data.toJson());

class UniswapToken {
  List<UniToken>? tokens;

  UniswapToken({
    this.tokens,
  });

  factory UniswapToken.fromJson(Map<String, dynamic> json) => UniswapToken(
    tokens: json["tokens"] == null ? [] : List<UniToken>.from(json["tokens"]!.map((x) => UniToken.fromJson(x))),
  );

  Map<String, dynamic> toJson() => {
    "tokens": tokens == null ? [] : List<dynamic>.from(tokens!.map((x) => x.toJson())),
  };
}

class UniToken {
  String? decimals;
  String? id;
  String? name;
  String? symbol;
  String? volumeUsd;

  UniToken({
    this.decimals,
    this.id,
    this.name,
    this.symbol,
    this.volumeUsd,
  });

  factory UniToken.fromJson(Map<String, dynamic> json) => UniToken(
    decimals: json["decimals"],
    id: json["id"],
    name: json["name"],
    symbol: json["symbol"],
    volumeUsd: json["volumeUSD"],
  );

  Map<String, dynamic> toJson() => {
    "decimals": decimals,
    "id": id,
    "name": name,
    "symbol": symbol,
    "volumeUSD": volumeUsd,
  };
}
