import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/favorites_service.dart';

class UserProductDetailScreen extends StatefulWidget {
  final String productId;
  const UserProductDetailScreen({super.key, required this.productId});
  @override
  State<UserProductDetailScreen> createState() => _State();
}

class _State extends State<UserProductDetailScreen> {
  Map<String, dynamic>? _product;
  bool _loading = true;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client
          .from('products')
          .select('*, product_images(*), provider_profiles(id,business_name)')
          .eq('id', widget.productId)
          .single();
      final fav = await FavoritesService.instance
          .isFavorited('PRODUCT', widget.productId);
      if (mounted) {
        setState(() {
          _product = data;
          _fav = fav;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          body: const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen)));
    }
    if (_product == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Product')),
          body: const Center(child: Text('Product not found')));
    }
    final p = _product!;
    final imgs = (p['product_images'] as List?) ?? [];
    final provider = p['provider_profiles'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: Text(p['name'] ?? ''),
        actions: [
          IconButton(
            icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                color: _fav ? AppTheme.error : null),
            onPressed: () async {
              final now = await FavoritesService.instance
                  .toggle('PRODUCT', widget.productId);
              if (mounted) setState(() => _fav = now);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image gallery
            if (imgs.isNotEmpty)
              SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: imgs.length,
                  itemBuilder: (_, i) => Container(
                    color: AppTheme.creamDark,
                    child: const Center(
                        child: Icon(Icons.image_outlined,
                            size: 64, color: AppTheme.textMuted)),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                color: AppTheme.creamDark,
                child: const Center(
                    child: Icon(Icons.inventory_2_outlined,
                        size: 64, color: AppTheme.textMuted)),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Text('${p['price']} ${p['currency'] ?? 'ETB'}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryGreen)),
                  const SizedBox(height: 12),
                  if (p['rating'] != null && (p['rating'] as num) > 0)
                    Row(
                      children: [
                        const Icon(Icons.star, color: AppTheme.gold, size: 18),
                        const SizedBox(width: 4),
                        Text('${p['rating']}',
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text('${p['review_count'] ?? 0} reviews',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (provider != null)
                    GestureDetector(
                      onTap: () => context
                          .go('/user/provider/${provider['id']}'),
                      child: Row(
                        children: [
                          const Icon(Icons.store_outlined,
                              size: 18, color: AppTheme.teal),
                          const SizedBox(width: 6),
                          Text(provider['business_name'] ?? '',
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.teal,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (p['description'] != null) ...[
                    const Text('Description',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(p['description'],
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -2)),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order flow coming soon')));
              },
              child: const Text('CONTACT / ORDER'),
            ),
          ),
        ),
      ),
    );
  }
}
