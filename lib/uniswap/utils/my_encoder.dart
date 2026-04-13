
class MyEncoder{
  static int feeSize = 3; // Fee size in bytes

  static String encodePath({required List<String> path, required List<int> fees}) {

    if (path.length != fees.length + 1) {
      throw ArgumentError('path/fee lengths do not match');
    }

    String encoded = '';
    for (int i = 0; i < fees.length; i++) {
      // 20 byte encoding of the address, removing '0x' prefix
      encoded += path[i].substring(2);
      // 3 byte encoding of the fee, converted to hex and padded to 6 characters
      encoded += fees[i].toRadixString(16).padLeft(feeSize * 2, '0');
    }

    // encode the final token
    encoded += path[path.length - 1].substring(2);

    return encoded.toLowerCase();
  }


}