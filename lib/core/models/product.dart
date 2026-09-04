/// Product model mapped to the `products` Supabase table.
class Product {
  final String id;
  final String providerId;
  final String? categoryId;
  final String name;
  final String? description;
  final double price;
  final String currency;
  final int? quantity;
  final bool isAvailable;
  final bool isActive;
  final double rating;
  final int reviewCount;
  final int salesCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProductImage> images;

  const Product({
    required this.id,
    required this.providerId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.currency = 'ETB',
    this.quantity,
    this.isAvailable = true,
    this.isActive = true,
    this.rating = 0,
    this.reviewCount = 0,
    this.salesCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.images = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
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
    );
  }

  String get formattedPrice => '$price $currency';
}

/// Product image model mapped to the `product_images` Supabase table.
class ProductImage {
  final String id;
  final String productId;
  final String storagePath;
  final int sortOrder;

  const ProductImage({
    required this.id,
    required this.productId,
    required this.storagePath,
    this.sortOrder = 0,
  });

  factory ProductImage.fromJson(Map<String, dynamic> json) {
    return ProductImage(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      storagePath: json['storage_path'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
