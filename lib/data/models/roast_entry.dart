// phase-02
// One roast the engine produced — kept for history, feedback loops and
// "roast of the month" replays.

enum RoastSurface { verdict, micro, full, card }

extension RoastSurfaceName on RoastSurface {
  static RoastSurface? fromName(String? name) {
    for (final RoastSurface v in RoastSurface.values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

class RoastEntry {
  const RoastEntry({
    required this.id,
    required this.templateId,
    required this.createdAt,
    required this.surface,
    required this.text,
    this.txnContextJson,
  });

  final String id;

  /// Which template produced it (dedup + analytics).
  final String templateId;
  final DateTime createdAt;
  final RoastSurface surface;
  final String text;

  /// JSON-encoded txn context snapshot (ids + amounts only, no raw text).
  final String? txnContextJson;

  RoastEntry copyWith({
    String? id,
    String? templateId,
    DateTime? createdAt,
    RoastSurface? surface,
    String? text,
    String? txnContextJson,
  }) {
    return RoastEntry(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      createdAt: createdAt ?? this.createdAt,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      txnContextJson: txnContextJson ?? this.txnContextJson,
    );
  }

  @override
  bool operator ==(Object other) => other is RoastEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'templateId': templateId,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'surface': surface.name,
        'text': text,
        'txnContextJson': txnContextJson,
      };

  factory RoastEntry.fromJson(Map<String, Object?> json) {
    return RoastEntry(
      id: json['id']! as String,
      templateId: json['templateId']! as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(json['createdAtMs']! as int),
      surface: RoastSurfaceName.fromName(json['surface']! as String)!,
      text: json['text']! as String,
      txnContextJson: json['txnContextJson'] as String?,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'template_id': templateId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'surface': surface.name,
        'text': text,
        'txn_context': txnContextJson,
      };

  factory RoastEntry.fromRow(Map<String, Object?> row) {
    return RoastEntry(
      id: row['id']! as String,
      templateId: row['template_id']! as String,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      surface: RoastSurfaceName.fromName(row['surface']! as String)!,
      text: row['text']! as String,
      txnContextJson: row['txn_context'] as String?,
    );
  }
}
