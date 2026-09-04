/// Category model mapped to the `categories` Supabase table.
class AppCategory {
  final String id;
  final String? parentId;
  final String name;
  final String sector; // SERVICE | VEHICLE
  final String slug;
  final String? icon;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final List<AppCategory> subcategories;

  const AppCategory({
    required this.id,
    this.parentId,
    required this.name,
    required this.sector,
    required this.slug,
    this.icon,
    this.isActive = true,
    this.sortOrder = 0,
    required this.createdAt,
    this.subcategories = const [],
  });

  factory AppCategory.fromJson(Map<String, dynamic> json) {
    return AppCategory(
      id: json['id'] as String,
      parentId: json['parent_id'] as String?,
      name: json['name'] as String,
      sector: json['sector'] as String,
      slug: json['slug'] as String,
      icon: json['icon'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isService => sector == 'SERVICE';
  bool get isVehicle => sector == 'VEHICLE';
  bool get isParent => parentId == null;
}
