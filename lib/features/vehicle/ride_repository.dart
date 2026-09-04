import '../../core/services/supabase_service.dart';

/// Repository for vehicle-provider ride actions. All mutating operations go
/// through Edge Functions (never direct table writes) so the atomic claim
/// and fee logic on the server is always the source of truth.
class RideRepository {
  final _svc = SupabaseService.instance;

  Stream<List<Map<String, dynamic>>> watchOpenRideRequests() {
    return _svc.client
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('status', 'REQUESTED')
        .order('created_at');
  }

  /// Attempts to claim a ride. On success returns the claimed ride.
  /// On 409 (already taken) throws so UI can show "This ride was just taken".
  Future<Map<String, dynamic>> claimRide({
    required String rideId,
    required String providerId,
    required String vehicleId,
  }) async {
    final result = await _svc.invokeFunction('ride-claim', body: {
      'ride_id': rideId,
      'provider_id': providerId,
      'vehicle_id': vehicleId,
    });
    return Map<String, dynamic>.from(result['ride'] as Map);
  }
}
