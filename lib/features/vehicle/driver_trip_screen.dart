import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/ride_service.dart';

class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({super.key});
  @override
  State<DriverTripScreen> createState() => _State();
}

class _State extends State<DriverTripScreen> {
  Map<String, dynamic>? _ride;
  StreamSubscription? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ride = await RideService.instance.getMyActiveDriverRide();
      if (ride != null) {
        _sub = RideService.instance.watchRide(ride['id']).listen((updated) {
          if (mounted && updated.isNotEmpty) {
            setState(() => _ride = updated);
          }
        });
      }
      if (mounted) {
        setState(() {
          _ride = ride;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _transition(String newStatus) async {
    if (_ride == null) return;
    try {
      await RideService.instance.transitionRide(
        rideId: _ride!['id'],
        newStatus: newStatus,
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active Trip')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.teal))
          : _ride == null
              ? Center(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 64, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    const Text('No active trip',
                        style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/vehicle'),
                      child: const Text('Back to Dashboard'),
                    ),
                  ],
                ))
              : _buildTrip(),
    );
  }

  Widget _buildTrip() {
    final status = _ride!['status'] ?? '';
    final pickup = _ride!['pickup_text'] ?? 'Pickup';
    final dest = _ride!['destination_text'] ?? 'Destination';
    final profile = _ride!['profiles'] as Map<String, dynamic>?;
    final passengerName = profile?['full_name'] ?? 'Passenger';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status.replaceAll('_', ' '),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.teal)),
          ),
          const SizedBox(height: 20),
          // Passenger info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Passenger',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                Text(passengerName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Pickup
          _locationTile(Icons.circle, AppTheme.success, 'Pickup', pickup),
          const SizedBox(height: 8),
          _locationTile(
              Icons.location_on, AppTheme.error, 'Destination', dest),
          const SizedBox(height: 24),
          // Actions based on status
          if (status == 'CLAIMED')
            _actionButton('DRIVER_ARRIVING', 'HEADING TO PICKUP', AppTheme.teal),
          if (status == 'DRIVER_ARRIVING' || status == 'ARRIVED')
            _actionButton('ARRIVED', 'ARRIVED AT PICKUP', AppTheme.primaryGreen),
          if (status == 'ARRIVED')
            _actionButton('TRIP_STARTED', 'START TRIP', AppTheme.primaryGreen),
          if (status == 'TRIP_STARTED')
            _actionButton('COMPLETED', 'COMPLETE TRIP', AppTheme.success),
        ],
      ),
    );
  }

  Widget _locationTile(
      IconData icon, Color color, String label, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String status, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _transition(status),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
    );
  }
}
