import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person,
                  color: AppTheme.primaryGreen, size: 40),
            ),
            const SizedBox(height: 12),
            Text(profile?.fullName ?? 'User',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(profile?.phone ?? '',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            _tile(Icons.person_outline, 'Edit Profile'),
            _tile(Icons.location_on_outlined, 'Addresses'),
            _tile(Icons.favorite_border, 'Favorites'),
            _tile(Icons.notifications_outlined, 'Notification Settings'),
            _tile(Icons.help_outline, 'Help & Support'),
            _tile(Icons.info_outline, 'About 5BIRR'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ref.read(authProvider.notifier).signOut(),
                icon: const Icon(Icons.logout, color: AppTheme.error),
                label: const Text('Logout',
                    style: TextStyle(color: AppTheme.error)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary),
      title:
          Text(label, style: const TextStyle(fontSize: 15)),
      trailing:
          const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
