import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/ride_service.dart';

class RideHistoryScreen extends StatefulWidget {
  final bool isDriver;
  const RideHistoryScreen({super.key, this.isDriver = false});
  @override
  State<RideHistoryScreen> createState() => _State();
}

class _State extends State<RideHistoryScreen> {
  List<Map<String, dynamic>> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rides = widget.isDriver
          ? await RideService.instance.getDriverRideHistory()
          : await RideService.instance.getUserRideHistory();
      if (mounted) {
        setState(() {
          _rides = rides;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.isDriver ? 'Ride History' : 'My Rides')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : _rides.isEmpty
              ? Center(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history,
                        size: 64, color: AppTheme.textMuted),
                    const SizedBox(height: 16),
                    const Text('No rides yet',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ],
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rides.length,
                    itemBuilder: (_, i) {
                      final r = _rides[i];
                      final status = r['status'] ?? '';
                      final pickup = r['pickup_text'] ?? 'Pickup';
                      final dest = r['destination_text'] ?? 'Destination';
                      final date = r['created_at'] != null
                          ? DateTime.parse(r['created_at'])
                          : DateTime.now();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Icon(
                            _statusIcon(status),
                            color: _statusColor(status),
                            size: 28,
                          ),
                          title: Text('$pickup → $dest',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${date.day}/${date.month}/${date.year} • ${status.replaceAll('_', ' ')}'),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'REQUESTED': return Icons.search;
      case 'CLAIMED': return Icons.check_circle_outline;
      case 'DRIVER_ARRIVING': return Icons.directions_car;
      case 'ARRIVED': return Icons.location_on;
      case 'TRIP_STARTED': return Icons.play_arrow;
      case 'COMPLETED': return Icons.check_circle;
      case 'CANCELLED': return Icons.cancel;
      default: return Icons.help_outline;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'COMPLETED': return AppTheme.success;
      case 'CANCELLED': return AppTheme.error;
      case 'TRIP_STARTED': return AppTheme.primaryGreen;
      default: return AppTheme.teal;
    }
  }
}
