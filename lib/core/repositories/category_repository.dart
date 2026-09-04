import '../models/models.dart';
import '../services/supabase_service.dart';

class CategoryRepository {
  final _svc = SupabaseService.instance;

  /// Get all active parent categories for a sector.
  Future<List<AppCategory>> getCategories({String sector = 'SERVICE'}) async {
    final data = await _svc.client
        .from('categories')
        .select()
        .eq('sector', sector)
        .eq('is_active', true)
        .is_('parent_id', null)
        .order('sort_order');
    return (data as List).map((j) => AppCategory.fromJson(j)).toList();
  }

  /// Get subcategories for a parent.
  Future<List<AppCategory>> getSubcategories(String parentId) async {
    final data = await _svc.client
        .from('categories')
        .select()
        .eq('parent_id', parentId)
        .eq('is_active', true)
        .order('sort_order');
    return (data as List).map((j) => AppCategory.fromJson(j)).toList();
  }

  /// Get categories with subcategories nested.
  Future<List<AppCategory>> getCategoriesWithSubs(
      {String sector = 'SERVICE'}) async {
    final parents = await getCategories(sector: sector);
    final result = <AppCategory>[];
    for (final p in parents) {
      final subs = await getSubcategories(p.id);
      result.add(AppCategory(
        id: p.id,
        parentId: p.parentId,
        name: p.name,
        sector: p.sector,
        slug: p.slug,
        icon: p.icon,
        isActive: p.isActive,
        sortOrder: p.sortOrder,
        createdAt: p.createdAt,
        subcategories: subs,
      ));
    }
    return result;
  }

  /// Get category by ID.
  Future<AppCategory?> getCategory(String id) async {
    final data = await _svc.client
        .from('categories')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (data == null) return null;
    return AppCategory.fromJson(data);
  }

  /// Count active products in a category.
  Future<int> countProducts(String categoryId) async {
    final data = await _svc.client
        .from('products')
        .select('id', const FetchOptions(count: CountOption.exact))
        .eq('category_id', categoryId)
        .eq('is_active', true);
    return data.count ?? 0;
  }
}
