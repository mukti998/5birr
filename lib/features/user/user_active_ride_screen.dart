import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/ride_service.dart';

class UserActiveRideScreen extends StatefulWidget {
  const UserActiveRideScreen({super.key});
  @override
  State<UserActiveRideScreen> createState() => _State();
}

class _State extends State<UserActiveRideScreen> {
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
      final ride = await RideService.instance.getMyActiveRide();
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

  Future<void> _cancel() async {
    if (_ride == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel Ride',
                  style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await RideService.instance.cancelRide(_ride!['id']);
      if (mounted) context.go('/user');
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
      appBar: AppBar(title: const Text('Active Ride')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : _ride == null
              ? Center(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car_outlined,
                        size: 64, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    const Text('No active ride',
                        style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/user'),
                      child: const Text('Back to Home'),
                    ),
                  ],
                ))
              : _buildRide(),
    );
  }

  Widget _buildRide() {
    final status = _ride!['status'] ?? '';
    final pickup = _ride!['pickup_text'] ?? 'Pickup';
    final dest = _ride!['destination_text'] ?? 'Destination';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _statusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_statusText(status),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(status))),
          ),
          const SizedBox(height: 20),
          // Map placeholder
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.creamDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined,
                      size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 8),
                  Text('Map view',
                      style: TextStyle(color: AppTheme.textMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Locations
          _locationTile(Icons.circle, AppTheme.success, 'Pickup', pickup),
          const SizedBox(height: 8),
          _locationTile(
              Icons.location_on, AppTheme.error, 'Destination', dest),
          const SizedBox(height: 20),
          // Cancel button (only before trip starts)
          if (['REQUESTED', 'CLAIMED', 'DRIVER_ARRIVING'].contains(status))
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('CANCEL RIDE',
                    style: TextStyle(color: AppTheme.error)),
              ),
            ),
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

  Color _statusColor(String status) {
    switch (status) {
      case 'REQUESTED': return AppTheme.warning;
      case 'CLAIMED': return AppTheme.info;
      case 'DRIVER_ARRIVING': return AppTheme.teal;
      case 'ARRIVED': return AppTheme.primaryGreen;
      case 'TRIP_STARTED': return AppTheme.primaryGreen;
      case 'COMPLETED': return AppTheme.success;
      case 'CANCELLED': return AppTheme.error;
      default: return AppTheme.textMuted;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'REQUESTED': return 'Searching for driver...';
      case 'CLAIMED': return 'Driver is on the way';
      case 'DRIVER_ARRIVING': return 'Driver is approaching';
      case 'ARRIVED': return 'Driver has arrived';
      case 'TRIP_STARTED': return 'Trip in progress';
      case 'COMPLETED': return 'Trip completed';
      case 'CANCELLED': return 'Ride cancelled';
      default: return status;
    }
  }
}
