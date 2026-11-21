// phase-02
// Capture-pipeline health record — one row per raw event seen.
//
// Privacy law for this table: `rawText` is allowed only inside a 24h
// window (review queue needs it); older rows are reduced to
// `rawHash` + parsed fields by the nightly purge job (`CaptureHealthDao
// .purgeRawTextOlderThan`) which Phase 05 schedules.
class CaptureEvent {
  const CaptureEvent({
    required this.id,
    required this.source,
    required this.receivedAt,
    required this.parsed,
    required this.deduped,
    required this.confidence,
    required this.rawHash,
    this.rawText,
    this.parserId,
    this.dropReason,
  });

  final String id;

  /// `notification` or `sms` (mirrors [TxnSource] names).
  final String source;
  final DateTime receivedAt;
  final bool parsed;
  final bool deduped;
  final double confidence;
  final String rawHash;
  final String? rawText;
  final String? parserId;
  final String? dropReason;

  CaptureEvent copyWith({
    String? id,
    String? source,
    DateTime? receivedAt,
    bool? parsed,
    bool? deduped,
    double? confidence,
    String? rawHash,
    String? rawText,
    String? parserId,
    String? dropReason,
  }) {
    return CaptureEvent(
      id: id ?? this.id,
      source: source ?? this.source,
      receivedAt: receivedAt ?? this.receivedAt,
      parsed: parsed ?? this.parsed,
      deduped: deduped ?? this.deduped,
      confidence: confidence ?? this.confidence,
      rawHash: rawHash ?? this.rawHash,
      rawText: rawText ?? this.rawText,
      parserId: parserId ?? this.parserId,
      dropReason: dropReason ?? this.dropReason,
    );
  }

  @override
  bool operator ==(Object other) => other is CaptureEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'source': source,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'parsed': parsed ? 1 : 0,
        'deduped': deduped ? 1 : 0,
        'confidence': confidence,
        'raw_hash': rawHash,
        'raw_text': rawText,
        'parser_id': parserId,
        'drop_reason': dropReason,
      };

  factory CaptureEvent.fromRow(Map<String, Object?> row) {
    return CaptureEvent(
      id: row['id']! as String,
      source: row['source']! as String,
      receivedAt:
          DateTime.fromMillisecondsSinceEpoch(row['received_at']! as int),
      parsed: (row['parsed']! as int) == 1,
      deduped: (row['deduped']! as int) == 1,
      confidence: (row['confidence']! as num).toDouble(),
      rawHash: row['raw_hash']! as String,
      rawText: row['raw_text'] as String?,
      parserId: row['parser_id'] as String?,
      dropReason: row['drop_reason'] as String?,
    );
  }
}
