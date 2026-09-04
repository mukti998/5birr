import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/birr_text_field.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ride_service.dart';

class UserRideRequestScreen extends StatefulWidget {
  const UserRideRequestScreen({super.key});
  @override
  State<UserRideRequestScreen> createState() => _State();
}

class _State extends State<UserRideRequestScreen> {
  final _pickupCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  Position? _pickupPos;
  Position? _destPos;
  String? _selectedVehicleCategory;
  List<Map<String, dynamic>> _vehicleCategories = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Get current location for pickup
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos != null) {
        _pickupPos = pos;
        _pickupCtrl.text = 'Current Location';
      }
      // Load vehicle categories
      final cats = await Supabase.instance.client
          .from('categories')
          .select('id,name,slug')
          .eq('sector', 'VEHICLE')
          .eq('is_active', true)
          .order('sort_order');
      if (mounted) {
        setState(() {
          _vehicleCategories = List<Map<String, dynamic>>.from(cats as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_pickupPos == null) {
      setState(() => _error = 'Pickup location is required');
      return;
    }
    if (_destPos == null) {
      setState(() => _error = 'Destination is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await RideService.instance.createRideRequest(
        pickupLat: _pickupPos!.latitude,
        pickupLng: _pickupPos!.longitude,
        destLat: _destPos!.latitude,
        destLng: _destPos!.longitude,
        pickupText: _pickupCtrl.text,
        destText: _destCtrl.text,
        vehicleCategoryId: _selectedVehicleCategory,
      );
      if (mounted) {
        context.go('/user/ride-active');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Failed to create ride: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Ride')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.error)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Pickup Location',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  BirrTextField(
                    label: 'Pickup',
                    controller: _pickupCtrl,
                    hint: 'Tap to use current location',
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      final pos =
                          await LocationService.instance.getCurrentPosition();
                      if (pos != null && mounted) {
                        setState(() => _pickupPos = pos);
                        _pickupCtrl.text = 'Current Location';
                      }
                    },
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Use current location'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Destination',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  BirrTextField(
                    label: 'Destination',
                    controller: _destCtrl,
                    hint: 'Where are you going?',
                  ),
                  // For now, use a simple lat/lng input or placeholder
                  // In production, this would be a map picker
                  const SizedBox(height: 16),
                  // Vehicle category selection
                  const Text('Vehicle Type',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _vehicleCategories.map((c) {
                      final selected = _selectedVehicleCategory == c['id'];
                      return ChoiceChip(
                        label: Text(c['name'] ?? ''),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedVehicleCategory =
                              selected ? null : c['id']);
                        },
                        selectedColor: AppTheme.teal,
                        labelStyle: TextStyle(
                            color: selected ? Colors.white : AppTheme.textPrimary,
                            fontSize: 13),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: 'REQUEST RIDE',
                      isLoading: _submitting,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
