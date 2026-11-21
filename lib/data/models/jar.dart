// phase-02
// A savings jar — money mentally parked for a labelled goal.
import 'package:udao/core/utils/money.dart';

class Jar {
  const Jar({
    required this.id,
    required this.label,
    required this.goal,
    required this.saved,
    required this.sort,
    required this.createdAt,
  });

  final String id;
  final String label;
  final Money goal;
  final Money saved;
  final int sort;
  final DateTime createdAt;

  Jar copyWith({
    String? id,
    String? label,
    Money? goal,
    Money? saved,
    int? sort,
    DateTime? createdAt,
  }) {
    return Jar(
      id: id ?? this.id,
      label: label ?? this.label,
      goal: goal ?? this.goal,
      saved: saved ?? this.saved,
      sort: sort ?? this.sort,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is Jar && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'label': label,
        'goal': goal.toJson(),
        'saved': saved.toJson(),
        'sort': sort,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
      };

  factory Jar.fromJson(Map<String, Object?> json) {
    return Jar(
      id: json['id']! as String,
      label: json['label']! as String,
      goal: Money.fromJson(json['goal']! as Map<String, Object?>),
      saved: Money.fromJson(json['saved']! as Map<String, Object?>),
      sort: json['sort']! as int,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(json['createdAtMs']! as int),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'label': label,
        'goal_paise': goal.paise,
        'saved_paise': saved.paise,
        'sort': sort,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Jar.fromRow(Map<String, Object?> row) {
    return Jar(
      id: row['id']! as String,
      label: row['label']! as String,
      goal: Money(row['goal_paise']! as int),
      saved: Money(row['saved_paise']! as int),
      sort: row['sort']! as int,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }
}
