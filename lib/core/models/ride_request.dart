/// Ride request model mapped to the `ride_requests` Supabase table.
class RideRequest {
  final String id;
  final String userId;
  final String? vehicleCategoryId;
  final String status;
  final String? claimedByProviderId;
  final String? claimedVehicleId;
  final DateTime? claimedAt;
  final double? fareEstimate;
  final String? pickupText;
  final String? destinationText;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RideRequest({
    required this.id,
    required this.userId,
    this.vehicleCategoryId,
    required this.status,
    this.claimedByProviderId,
    this.claimedVehicleId,
    this.claimedAt,
    this.fareEstimate,
    this.pickupText,
    this.destinationText,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    return RideRequest(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vehicleCategoryId: json['vehicle_category_id'] as String?,
      status: json['status'] as String,
      claimedByProviderId: json['claimed_by_provider_id'] as String?,
      claimedVehicleId: json['claimed_vehicle_id'] as String?,
      claimedAt: json['claimed_at'] != null
          ? DateTime.parse(json['claimed_at'] as String)
          : null,
      fareEstimate: (json['fare_estimate'] as num?)?.toDouble(),
      pickupText: json['pickup_text'] as String?,
      destinationText: json['destination_text'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isRequested => status == 'REQUESTED';
  bool get isClaimed => status == 'CLAIMED';
  bool get isActive => !['COMPLETED', 'CANCELLED'].contains(status);
  String get displayPickup => pickupText ?? 'Current location';
  String get displayDestination => destinationText ?? 'Destination';
}
