import '../models/models.dart';
import '../services/supabase_service.dart';
import 'package:storage_client/storage_client.dart' show FileOptions;

/// Repository for product-related database operations.
class ProductRepository {
  final _svc = SupabaseService.instance;

  /// Fetch products with optional filters.
  Future<List<Product>> getProducts({
    String? providerId,
    String? categoryId,
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    var q = _svc.client.from('products').select('*, product_images(*)');
    if (providerId != null) q = q.eq('provider_id', providerId);
    if (categoryId != null) q = q.eq('category_id', categoryId);
    if (query != null && query.isNotEmpty) {
      q = q.or('name.ilike.%$query%,description.ilike.%$query%');
    }

    final data = await q
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((json) {
      final images = (json['product_images'] as List?)
              ?.map((i) => ListingImage.fromJson(i))
              .toList() ??
          [];
      return Product(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        categoryId: json['category_id'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'ETB',
        quantity: json['quantity'] as int?,
        isAvailable: json['is_available'] as bool? ?? true,
        isActive: json['is_active'] as bool? ?? true,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        reviewCount: json['review_count'] as int? ?? 0,
        salesCount: json['sales_count'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        images: images,
      );
    }).toList();
  }

  /// Create a new product.
  Future<Product> createProduct({
    required String providerId,
    required String name,
    String? description,
    required double price,
    String? categoryId,
    int? quantity,
  }) async {
    final data = await _svc.client
        .from('products')
        .insert({
          'provider_id': providerId,
          'name': name,
          'description': description,
          'price': price,
          'category_id': categoryId,
          'quantity': quantity,
        })
        .select()
        .single();
    return Product.fromJson(data);
  }

  /// Update an existing product (provider must own it — enforced by RLS).
  Future<Product> updateProduct({
    required String productId,
    String? name,
    String? description,
    double? price,
    String? categoryId,
    int? quantity,
    bool? isAvailable,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (price != null) updates['price'] = price;
    if (categoryId != null) updates['category_id'] = categoryId;
    if (quantity != null) updates['quantity'] = quantity;
    if (isAvailable != null) updates['is_available'] = isAvailable;

    final data = await _svc.client
        .from('products')
        .update(updates)
        .eq('id', productId)
        .select()
        .single();
    return Product.fromJson(data);
  }

  /// Soft-delete a product (set is_active = false).
  Future<void> deleteProduct(String productId) async {
    await _svc.client
        .from('products')
        .update({'is_active': false}).eq('id', productId);
  }

  /// Upload product image to storage and record in product_images.
  Future<ProductImage> addProductImage({
    required String productId,
    required String filePath,
    int sortOrder = 0,
  }) async {
    final fileName = '${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = 'product-images/$productId/$fileName';

    await _svc.client.storage.from('product-images').upload(
          storagePath,
          filePath,
          fileOptions: const FileOptions(upsert: true),
        );

    final data = await _svc.client
        .from('product_images')
        .insert({
          'product_id': productId,
          'storage_path': storagePath,
          'sort_order': sortOrder,
        })
        .select()
        .single();

    return ProductImage.fromJson(data);
  }

  /// Delete a product image.
  Future<void> deleteProductImage(String imageId, String storagePath) async {
    await _svc.client.from('product_images').delete().eq('id', imageId);
    await _svc.client.storage.from('product-images').remove([storagePath]);
  }

  /// Get signed URL for private storage.
  Future<String> getSignedUrl(String bucket, String path) async {
    final signedUrl = await _svc.client.storage
        .from(bucket)
        .createSignedUrl(path, 3600); // 1 hour
    return signedUrl;
  }
}
