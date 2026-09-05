/// Provider store model mapped to the `provider_stores` Supabase table.
/// Public marketplace store profile for approved providers.
class ProviderStore {
  final String id;
  final String providerId;
  final String businessName;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final String? marketplaceSector;
  final String? addressText;
  final String? contactPhone;
  final String? contactEmail;
  final String? websiteUrl;
  final String? logoStoragePath;
  final String? coverImageStoragePath;
  final double rating;
  final int reviewCount;
  final int listingCount;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProviderStore({
    required this.id,
    required this.providerId,
    required this.businessName,
    this.description,
    this.categoryId,
    this.categoryName,
    this.marketplaceSector,
    this.addressText,
    this.contactPhone,
    this.contactEmail,
    this.websiteUrl,
    this.logoStoragePath,
    this.coverImageStoragePath,
    this.rating = 0,
    this.reviewCount = 0,
    this.listingCount = 0,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProviderStore.fromJson(Map<String, dynamic> json) {
    return ProviderStore(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      businessName: json['business_name'] as String,
      description: json['description'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      marketplaceSector: json['marketplace_sector'] as String?,
      addressText: json['address_text'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
      websiteUrl: json['website_url'] as String?,
      logoStoragePath: json['logo_storage_path'] as String?,
      coverImageStoragePath: json['cover_image_storage_path'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: json['review_count'] as int? ?? 0,
      listingCount: json['listing_count'] as int? ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.parse(json['created_at'] as String),
    );
  }
}
