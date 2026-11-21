// phase-02
// Spending category — Hinglish by design. `isEssential` is the roast
// guardrail foundation: essentials are NEVER roasted, only reported.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorRole,
    required this.isEssential,
    required this.sort,
    this.parentId,
  });

  final String id;
  final String name;

  /// Asset icon key from `AppIcons`.
  final String icon;

  /// Theme semantic role: `flame` | `lime` | `gold` | `sky`.
  final String colorRole;

  /// Rent, health, education — protected from savage roasts.
  final bool isEssential;
  final String? parentId;
  final int sort;

  Category copyWith({
    String? id,
    String? name,
    String? icon,
    String? colorRole,
    bool? isEssential,
    String? parentId,
    int? sort,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorRole: colorRole ?? this.colorRole,
      isEssential: isEssential ?? this.isEssential,
      parentId: parentId ?? this.parentId,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'icon': icon,
        'colorRole': colorRole,
        'isEssential': isEssential,
        'parentId': parentId,
        'sort': sort,
      };

  factory Category.fromJson(Map<String, Object?> json) {
    return Category(
      id: json['id']! as String,
      name: json['name']! as String,
      icon: json['icon']! as String,
      colorRole: json['colorRole']! as String,
      isEssential: json['isEssential']! as bool,
      parentId: json['parentId'] as String?,
      sort: json['sort']! as int,
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'icon': icon,
        'color_role': colorRole,
        'is_essential': isEssential ? 1 : 0,
        'parent_id': parentId,
        'sort': sort,
      };

  factory Category.fromRow(Map<String, Object?> row) {
    return Category(
      id: row['id']! as String,
      name: row['name']! as String,
      icon: row['icon']! as String,
      colorRole: row['color_role']! as String,
      isEssential: (row['is_essential']! as int) == 1,
      parentId: row['parent_id'] as String?,
      sort: row['sort']! as int,
    );
  }
}

/// The 16 seed categories, fixed ids — stable across installs so
/// categories survive export/import and DB wipes.
const List<Category> kSeedCategories = <Category>[
  Category(id: 'cat_khaana', name: 'Khaana', icon: 'food', colorRole: 'flame', isEssential: false, sort: 0),
  Category(id: 'cat_chai', name: 'Chai-Nashta', icon: 'chai', colorRole: 'gold', isEssential: false, sort: 1),
  Category(id: 'cat_groceries', name: 'Groceries', icon: 'basket', colorRole: 'lime', isEssential: false, sort: 2),
  Category(id: 'cat_rent_bill', name: 'Rent/Bill', icon: 'receipt', colorRole: 'sky', isEssential: true, sort: 3),
  Category(id: 'cat_recharge', name: 'Recharge', icon: 'phone', colorRole: 'sky', isEssential: false, sort: 4),
  Category(id: 'cat_transport', name: 'Transport', icon: 'bus', colorRole: 'sky', isEssential: false, sort: 5),
  Category(id: 'cat_fuel', name: 'Fuel', icon: 'fuel', colorRole: 'flame', isEssential: false, sort: 6),
  Category(id: 'cat_shopping', name: 'Shopping', icon: 'bag', colorRole: 'flame', isEssential: false, sort: 7),
  Category(id: 'cat_entertainment', name: 'Entertainment', icon: 'film', colorRole: 'gold', isEssential: false, sort: 8),
  Category(id: 'cat_health', name: 'Health', icon: 'health', colorRole: 'lime', isEssential: true, sort: 9),
  Category(id: 'cat_education', name: 'Education', icon: 'education', colorRole: 'sky', isEssential: true, sort: 10),
  Category(id: 'cat_udan_jhari', name: 'Udan-Jhari', icon: 'sparkle', colorRole: 'flame', isEssential: false, sort: 11),
  Category(id: 'cat_subscriptions', name: 'Subscriptions', icon: 'repeat', colorRole: 'gold', isEssential: false, sort: 12),
  Category(id: 'cat_salary', name: 'Salary', icon: 'salary', colorRole: 'lime', isEssential: false, sort: 13),
  Category(id: 'cat_transfer', name: 'Transfer', icon: 'swap', colorRole: 'sky', isEssential: false, sort: 14),
  Category(id: 'cat_cash', name: 'Cash', icon: 'cash', colorRole: 'gold', isEssential: false, sort: 15),
];
