/// Represents the status of a blockchain transaction
class TransactionStatus {
  final bool isSuccess;
  final bool isPending;
  final int? blockNumber;
  final BigInt? gasUsed;
  final String txHash;

  TransactionStatus({
    required this.isSuccess,
    required this.isPending,
    required this.blockNumber,
    required this.gasUsed,
    required this.txHash,
  });

  @override
  String toString() {
    if (isPending) {
      return 'TransactionStatus(pending: true, txHash: $txHash)';
    }
    return 'TransactionStatus(success: $isSuccess, blockNumber: $blockNumber, gasUsed: $gasUsed, txHash: $txHash)';
  }
}