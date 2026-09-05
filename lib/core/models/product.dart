/// Product/Listing model mapped to the `products` Supabase table.
/// Supports all listing types: PRODUCT, FOOD, SERVICE, ROOM, OTHER.
class Product {
  final String id;
  final String providerId;
  final String? categoryId;
  final String name;
  final String? description;
  final double price;
  final String currency;
  final String listingType; // PRODUCT, FOOD, SERVICE, ROOM, OTHER
  final int? quantity;
  final int? stockQuantity;
  final int? lowStockThreshold;
  final String listingStatus; // ACTIVE, DRAFT, SOLD_OUT, ARCHIVED
  final bool isAvailable;
  final bool isActive;
  final double rating;
  final int reviewCount;
  final int salesCount;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ListingImage> images;

  const Product({
    required this.id,
    required this.providerId,
    this.categoryId,
    required this.name,
    this.description,
    required this.price,
    this.currency = 'ETB',
    this.listingType = 'PRODUCT',
    this.quantity,
    this.stockQuantity,
    this.lowStockThreshold,
    this.listingStatus = 'ACTIVE',
    this.isAvailable = true,
    this.isActive = true,
    this.rating = 0,
    this.reviewCount = 0,
    this.salesCount = 0,
    this.metadata,
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
      listingType: json['listing_type'] as String? ?? 'PRODUCT',
      quantity: json['quantity'] as int?,
      stockQuantity: json['stock_quantity'] as int?,
      lowStockThreshold: json['low_stock_threshold'] as int?,
      listingStatus: json['listing_status'] as String? ?? 'ACTIVE',
      isAvailable: json['is_available'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: json['review_count'] as int? ?? 0,
      salesCount: json['sales_count'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get formattedPrice => '$price $currency';

  bool get inStock =>
      stockQuantity == null || (stockQuantity ?? 0) > 0;

  bool get isLowStock =>
      stockQuantity != null &&
      lowStockThreshold != null &&
      stockQuantity! <= lowStockThreshold!;

  bool get isActiveListing =>
      isActive && listingStatus == 'ACTIVE' && isAvailable;
}

/// Listing image model mapped to the `listing_images` Supabase table.
/// Unified image management for all listing types.
class ListingImage {
  final String id;
  final String listingId;
  final String storagePath;
  final String? altText;
  final bool isPrimary;
  final int sortOrder;

  const ListingImage({
    required this.id,
    required this.listingId,
    required this.storagePath,
    this.altText,
    this.isPrimary = false,
    this.sortOrder = 0,
  });

  factory ListingImage.fromJson(Map<String, dynamic> json) {
    return ListingImage(
      id: json['id'] as String,
      listingId: json['listing_id'] as String? ?? json['product_id'] as String? ?? '',
      storagePath: json['storage_path'] as String,
      altText: json['alt_text'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

/// Legacy product image model mapped to the `product_images` Supabase table.
/// Kept for backward compatibility with existing code.
@Deprecated('Use ListingImage instead for new code')
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
