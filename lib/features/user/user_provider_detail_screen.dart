import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/favorites_service.dart';
import '../../core/models/product.dart';

class UserProviderDetailScreen extends StatefulWidget {
  final String providerId;
  const UserProviderDetailScreen({super.key, required this.providerId});
  @override
  State<UserProviderDetailScreen> createState() => _State();
}

class _State extends State<UserProviderDetailScreen> {
  Map<String, dynamic>? _provider;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final prov = await client
          .from('provider_profiles')
          .select()
          .eq('id', widget.providerId)
          .single();
      final prods = await client
          .from('products')
          .select('*, product_images(*)')
          .eq('provider_id', widget.providerId)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);
      final fav = await FavoritesService.instance
          .isFavorited('PROVIDER', widget.providerId);
      if (mounted) {
        setState(() {
          _provider = prov;
          _products = List<Map<String, dynamic>>.from(prods as List);
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
    if (_provider == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Provider')),
          body: const Center(child: Text('Provider not found')));
    }
    final p = _provider!;

    return Scaffold(
      appBar: AppBar(
        title: Text(p['business_name'] ?? ''),
        actions: [
          IconButton(
            icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                color: _fav ? AppTheme.error : null),
            onPressed: () async {
              final now = await FavoritesService.instance
                  .toggle('PROVIDER', widget.providerId);
              if (mounted) setState(() => _fav = now);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppTheme.teal, Color(0xFF00695C)]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['business_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(p['address_text'] ?? 'Location not set',
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.8))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.gold, size: 16),
                      const SizedBox(width: 4),
                      const Text('0.0',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(width: 12),
                      Text('${_products.length} products',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            // Products
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Products (${_products.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (_products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: Text('No products yet',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _products.length,
                itemBuilder: (_, i) {
                  final prod = _products[i];
                  return ListTile(
                    onTap: () =>
                        context.go('/user/product/${prod['id']}'),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: AppTheme.creamDark,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.inventory_2_outlined,
                          color: AppTheme.textMuted),
                    ),
                    title: Text(prod['name'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${prod['price']} ${prod['currency'] ?? 'ETB'}',
                        style: const TextStyle(
                            color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.w600)),
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
