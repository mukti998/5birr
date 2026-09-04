/// Provider profile model mapped to the `provider_profiles` Supabase table.
class ProviderProfile {
  final String id;
  final String userId;
  final String providerType; // VEHICLE_PROVIDER | SERVICE_PROVIDER
  final String? businessName;
  final String? ownerNationalId;
  final String status;
  final DateTime registrationDate;
  final DateTime subscriptionStartDate;
  final String? categoryId;
  final String? addressText;
  final double? serviceAreaRadiusKm;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProviderProfile({
    required this.id,
    required this.userId,
    required this.providerType,
    this.businessName,
    this.ownerNationalId,
    required this.status,
    required this.registrationDate,
    required this.subscriptionStartDate,
    this.categoryId,
    this.addressText,
    this.serviceAreaRadiusKm,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProviderProfile.fromJson(Map<String, dynamic> json) {
    return ProviderProfile(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      providerType: json['provider_type'] as String,
      businessName: json['business_name'] as String?,
      ownerNationalId: json['owner_national_id'] as String?,
      status: json['status'] as String,
      registrationDate: DateTime.parse(json['registration_date'] as String),
      subscriptionStartDate:
          DateTime.parse(json['subscription_start_date'] as String),
      categoryId: json['category_id'] as String?,
      addressText: json['address_text'] as String?,
      serviceAreaRadiusKm:
          (json['service_area_radius_km'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isApproved => status == 'APPROVED';
  bool get isPending => status == 'PENDING_APPROVAL';
  bool get isRejected => status == 'REJECTED';
  bool get isSuspended => status == 'SUSPENDED';
  bool get isVehicleProvider => providerType == 'VEHICLE_PROVIDER';
  bool get isServiceProvider => providerType == 'SERVICE_PROVIDER';
}
