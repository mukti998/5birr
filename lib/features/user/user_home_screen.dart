import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/product_card.dart';
import '../../core/widgets/category_card.dart';
import '../../core/models/product.dart';
import '../../core/models/category.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});
  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  List<AppCategory> _categories = [];
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final catData = await client
          .from('categories')
          .select()
          .eq('sector', 'SERVICE')
          .eq('is_active', true)
          .isFilter('parent_id', null)
          .order('sort_order')
          .limit(12);
      final prodData = await client
          .from('products')
          .select('*, product_images(*)')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        setState(() {
          _categories = (catData as List)
              .map((j) => AppCategory.fromJson(j))
              .toList();
          _products = (prodData as List).map((j) {
            final imgs = (j['product_images'] as List?)
                    ?.map((i) => ProductImage.fromJson(i))
                    .toList() ??
                [];
            return Product(
              id: j['id'],
              providerId: j['provider_id'],
              categoryId: j['category_id'],
              name: j['name'],
              description: j['description'],
              price: (j['price'] as num).toDouble(),
              currency: j['currency'] ?? 'ETB',
              quantity: j['quantity'],
              isAvailable: j['is_available'] ?? true,
              isActive: j['is_active'] ?? true,
              rating: (j['rating'] as num?)?.toDouble() ?? 0,
              reviewCount: j['review_count'] ?? 0,
              salesCount: j['sales_count'] ?? 0,
              createdAt: DateTime.parse(j['created_at']),
              updatedAt: DateTime.parse(j['updated_at']),
              images: imgs,
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
        : RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryGreen, AppTheme.primaryGreenDark],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('5BIRR',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text('Marketplace • Services • Transport',
                            style: TextStyle(
                                fontSize: 12, color: Colors.white.withOpacity(0.7))),
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: () => context.go('/user/search'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.search, color: Colors.white70, size: 20),
                                SizedBox(width: 10),
                                Text('Search products, services...',
                                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Quick ride button
                        GestureDetector(
                          onTap: () => context.go('/user/ride-request'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.teal.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.local_taxi, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text('Request a Ride',
                                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Categories
                if (_categories.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Text('Categories',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (_, i) {
                          final c = _categories[i];
                          return CategoryCard(
                            name: c.name,
                            icon: _catIcon(c.slug),
                            onTap: () => context.go('/user/category/${c.id}'),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                // Products
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text('Recently Added',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                  ),
                ),
                if (_products.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text('No products yet',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => ProductCard(
                          product: _products[i],
                          onTap: () => context
                              .go('/user/product/${_products[i].id}'),
                        ),
                        childCount: _products.length,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          );
  }

  IconData _catIcon(String slug) {
    if (slug.contains('hotel')) return Icons.hotel_outlined;
    if (slug.contains('food') || slug.contains('restaurant'))
      return Icons.restaurant_outlined;
    if (slug.contains('retail') || slug.contains('grocery'))
      return Icons.shopping_cart_outlined;
    if (slug.contains('health') || slug.contains('pharma'))
      return Icons.local_hospital_outlined;
    if (slug.contains('beauty') || slug.contains('barber'))
      return Icons.content_cut;
    if (slug.contains('home') || slug.contains('repair'))
      return Icons.home_repair_service_outlined;
    if (slug.contains('education')) return Icons.school_outlined;
    if (slug.contains('fitness')) return Icons.fitness_center;
    if (slug.contains('real-estate')) return Icons.apartment;
    return Icons.category_outlined;
  }
}
