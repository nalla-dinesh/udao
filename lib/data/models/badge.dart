// phase-02
// Khel badges (definitions live in Phase-07 config) + challenge meters.

class Badge {
  const Badge({required this.id, this.seen = false, this.unlockedAt});

  final String id;

  /// IST unlock time; null = still locked.
  final DateTime? unlockedAt;

  /// Shown in the unlock celebration yet?
  final bool seen;

  Badge copyWith({String? id, DateTime? unlockedAt, bool? seen}) {
    return Badge(
      id: id ?? this.id,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      seen: seen ?? this.seen,
    );
  }

  @override
  bool operator ==(Object other) => other is Badge && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'unlockedAtMs': unlockedAt?.millisecondsSinceEpoch,
        'seen': seen,
      };

  factory Badge.fromJson(Map<String, Object?> json) {
    return Badge(
      id: json['id']! as String,
      unlockedAt: json['unlockedAtMs'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['unlockedAtMs']! as int,
            ),
      seen: json['seen']! as bool,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'unlocked_at': unlockedAt?.millisecondsSinceEpoch,
        'seen': seen ? 1 : 0,
      };

  factory Badge.fromRow(Map<String, Object?> row) {
    return Badge(
      id: row['id']! as String,
      unlockedAt: row['unlocked_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['unlocked_at']! as int,
            ),
      seen: (row['seen']! as int) == 1,
    );
  }
}

/// Progress on a measurable Khel challenge (e.g. "30 din no-spend").
class ChallengeProgress {
  const ChallengeProgress({
    required this.id,
    required this.metric,
    required this.current,
    required this.target,
    this.completedAt,
  });

  final String id;

  /// Machine key of the measured metric (`no_spend_days`, …).
  final String metric;
  final int current;
  final int target;
  final DateTime? completedAt;

  ChallengeProgress copyWith({
    String? id,
    String? metric,
    int? current,
    int? target,
    DateTime? completedAt,
  }) {
    return ChallengeProgress(
      id: id ?? this.id,
      metric: metric ?? this.metric,
      current: current ?? this.current,
      target: target ?? this.target,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChallengeProgress && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'metric': metric,
        'current': current,
        'target': target,
        'completedAtMs': completedAt?.millisecondsSinceEpoch,
      };

  factory ChallengeProgress.fromJson(Map<String, Object?> json) {
    return ChallengeProgress(
      id: json['id']! as String,
      metric: json['metric']! as String,
      current: json['current']! as int,
      target: json['target']! as int,
      completedAt: json['completedAtMs'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['completedAtMs']! as int,
            ),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'metric': metric,
        'current': current,
        'target': target,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      };

  factory ChallengeProgress.fromRow(Map<String, Object?> row) {
    return ChallengeProgress(
      id: row['id']! as String,
      metric: row['metric']! as String,
      current: row['current']! as int,
      target: row['target']! as int,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['completed_at']! as int,
            ),
    );
  }
}
