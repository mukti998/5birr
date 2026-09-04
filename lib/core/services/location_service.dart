import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  LocationService._();
  static final instance = LocationService._();

  /// Check and request location permission.
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  /// Get current position.
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  /// Stream of position updates.
  Stream<Position> getPositionStream({
    int distanceFilter = 50,
    Duration interval = const Duration(seconds: 10),
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        timeLimit: interval,
      ),
    );
  }

  /// Update driver location on server.
  Future<void> updateDriverLocation(String providerId, double lat, double lng) async {
    await Supabase.instance.client.rpc('update_driver_location', params: {
      'p_provider_id': providerId,
      'p_lat': lat,
      'p_lng': lng,
    });
  }

  /// Set driver online/offline.
  Future<void> setDriverOnline(String providerId, bool online,
      {double? lat, double? lng}) async {
    await Supabase.instance.client.rpc('set_driver_online', params: {
      'p_provider_id': providerId,
      'p_online': online,
      'p_lat': lat,
      'p_lng': lng,
    });
  }

  /// Get driver's current status.
  Future<Map<String, dynamic>?> getDriverStatus(String providerId) async {
    final data = await Supabase.instance.client
        .from('driver_status')
        .select()
        .eq('provider_id', providerId)
        .maybeSingle();
    return data;
  }

  /// Find nearby drivers.
  Future<List<Map<String, dynamic>>> findNearbyDrivers(
      double lat, double lng,
      {double radiusKm = 10, String? vehicleCategoryId}) async {
    final data = await Supabase.instance.client.rpc('find_nearby_drivers', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm,
      'p_vehicle_category_id': vehicleCategoryId,
    });
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Calculate distance between two points using Haversine.
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }
}
