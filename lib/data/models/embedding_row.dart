// phase-02
// On-device embedding vector for one txn (Phase 06 writes these;
// stored as a float64 BLOB, never JSON — compact + fast).
import 'dart:typed_data';

class EmbeddingRow {
  const EmbeddingRow({
    required this.txnId,
    required this.vector,
    required this.modelTag,
  });

  final String txnId;
  final List<double> vector;

  /// Which on-device model produced the vector.
  final String modelTag;

  @override
  bool operator ==(Object other) =>
      other is EmbeddingRow && other.txnId == txnId && other.modelTag == modelTag;

  @override
  int get hashCode => Object.hash(txnId, modelTag);

  Map<String, Object?> toRow() => <String, Object?>{
        'txn_id': txnId,
        'vector': _vectorToBytes(vector),
        'model_tag': modelTag,
      };

  factory EmbeddingRow.fromRow(Map<String, Object?> row) {
    return EmbeddingRow(
      txnId: row['txn_id']! as String,
      vector: _bytesToVector(row['vector']! as List<int>),
      modelTag: row['model_tag']! as String,
    );
  }

  static Uint8List _vectorToBytes(List<double> vector) {
    final Float64List floats = Float64List.fromList(vector);
    return floats.buffer.asUint8List();
  }

  static List<double> _bytesToVector(List<int> bytes) {
    final Uint8List data = Uint8List.fromList(bytes);
    return Float64List.view(data.buffer).toList(growable: false);
  }
}
