import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class VehicleProviderDashboard extends ConsumerStatefulWidget {
  const VehicleProviderDashboard({super.key});
  @override
  ConsumerState<VehicleProviderDashboard> createState() =>
      _VehicleProviderDashboardState();
}

class _VehicleProviderDashboardState
    extends ConsumerState<VehicleProviderDashboard> {
  Map<String, dynamic>? _providerProfile;
  int _vehicleCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final prov = await client
          .from('provider_profiles')
          .select()
          .eq('user_id', userId)
          .eq('provider_type', 'VEHICLE_PROVIDER')
          .maybeSingle();
      if (prov == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final vehicles = await client
          .from('vehicles')
          .select('id', const FetchOptions(count: CountOption.exact))
          .eq('provider_id', prov['id']);
      if (mounted) {
        setState(() {
          _providerProfile = prov;
          _vehicleCount = vehicles.count ?? 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('5BIRR Transport'),
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authProvider.notifier).signOut()),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.teal))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppTheme.teal, Color(0xFF00695C)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _providerProfile?['business_name'] ??
                                  auth.profile?.fullName ??
                                  'Provider',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                                (_providerProfile?['status'] ?? 'UNKNOWN')
                                    .replaceAll('_', ' '),
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _stat(Icons.directions_car, 'Vehicles', '$_vehicleCount'),
                        const SizedBox(width: 12),
                        _stat(Icons.star_outline, 'Rating', '0.0'),
                        const SizedBox(width: 12),
                        _stat(Icons.receipt_long, 'Rides', '0'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Actions',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _action(Icons.directions_car_outlined, 'Manage Vehicles',
                        () => context.go('/vehicle/vehicles')),
                    _action(Icons.add_circle_outline, 'Add Vehicle',
                        () => context.go('/vehicle/vehicles/new')),
                    _action(Icons.local_taxi_outlined, 'Ride Requests', null),
                    _action(Icons.history, 'Ride History', null),
                    _action(Icons.account_balance_wallet_outlined, 'Wallet',
                        () => context.go('/wallet')),
                    _action(Icons.person_outline, 'Profile', null),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.teal, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.teal),
        title: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right,
            color: AppTheme.textMuted, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: AppTheme.surface,
      ),
    );
  }
}
