// phase-02
// No-spend streak — the Khel heart. Single row, whole app.

class StreakState {
  const StreakState({
    required this.length,
    required this.freezesLeft,
    required this.longest,
    this.currentStart,
    this.lastNoSpendDate,
  });

  /// IST start of the current streak (day precision). Null = no streak.
  final DateTime? currentStart;

  /// Completed no-spend days in the current streak.
  final int length;

  /// Remaining streak-freeze tokens (earned via Khel challenges).
  final int freezesLeft;

  /// Best streak ever completed.
  final int longest;

  /// IST date of the most recent no-spend day.
  final DateTime? lastNoSpendDate;

  static const int defaultFreezes = 2;

  /// The pristine state a fresh install (or a wipe) starts from.
  const StreakState.initial()
      : this(
          currentStart: null,
          length: 0,
          freezesLeft: defaultFreezes,
          longest: 0,
          lastNoSpendDate: null,
        );

  StreakState copyWith({
    DateTime? currentStart,
    int? length,
    int? freezesLeft,
    int? longest,
    DateTime? lastNoSpendDate,
  }) {
    return StreakState(
      currentStart: currentStart ?? this.currentStart,
      length: length ?? this.length,
      freezesLeft: freezesLeft ?? this.freezesLeft,
      longest: longest ?? this.longest,
      lastNoSpendDate: lastNoSpendDate ?? this.lastNoSpendDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreakState &&
      other.length == length &&
      other.longest == longest &&
      other.freezesLeft == freezesLeft &&
      other.currentStart == currentStart &&
      other.lastNoSpendDate == lastNoSpendDate;

  @override
  int get hashCode =>
      Object.hash(length, longest, freezesLeft, currentStart, lastNoSpendDate);

  Map<String, Object?> toJson() => <String, Object?>{
        'currentStartMs': currentStart?.millisecondsSinceEpoch,
        'length': length,
        'freezesLeft': freezesLeft,
        'longest': longest,
        'lastNoSpendDateMs': lastNoSpendDate?.millisecondsSinceEpoch,
      };

  factory StreakState.fromJson(Map<String, Object?> json) {
    return StreakState(
      currentStart: json['currentStartMs'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['currentStartMs']! as int,
            ),
      length: json['length']! as int,
      freezesLeft: json['freezesLeft']! as int,
      longest: json['longest']! as int,
      lastNoSpendDate: json['lastNoSpendDateMs'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['lastNoSpendDateMs']! as int,
            ),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': 1,
        'current_start': currentStart?.millisecondsSinceEpoch,
        'length': length,
        'freezes_left': freezesLeft,
        'longest': longest,
        'last_no_spend_date': lastNoSpendDate?.millisecondsSinceEpoch,
      };

  factory StreakState.fromRow(Map<String, Object?> row) {
    return StreakState(
      currentStart: row['current_start'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['current_start']! as int,
            ),
      length: row['length']! as int,
      freezesLeft: row['freezes_left']! as int,
      longest: row['longest']! as int,
      lastNoSpendDate: row['last_no_spend_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['last_no_spend_date']! as int,
            ),
    );
  }
}
