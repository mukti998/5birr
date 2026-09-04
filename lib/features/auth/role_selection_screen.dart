import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/role_card.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryGreen, AppTheme.cream],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('₅',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Choose Your Role',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'Select how you want to use 5BIRR',
                  style: TextStyle(
                      fontSize: 14, color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 28),
                RoleCard(
                  icon: Icons.person_outline,
                  title: 'User',
                  description:
                      'Browse products, services, and book rides in your area',
                  onTap: () => context.go('/signup/user'),
                ),
                const SizedBox(height: 12),
                RoleCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Vehicle Provider',
                  description:
                      'Offer ride, delivery, and transportation services',
                  onTap: () => context.go('/signup/vehicle'),
                ),
                const SizedBox(height: 12),
                RoleCard(
                  icon: Icons.storefront_outlined,
                  title: 'Service Provider',
                  description:
                      'List your business, products, and professional services',
                  onTap: () => context.go('/signup/service'),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondary)),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text('Sign In',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.teal)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
