import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/auth_provider.dart';
import '../features/splash/splash_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart' show SignupScreen, SignupRole;
import '../features/auth/role_selection_screen.dart';
import '../features/auth/admin_login_screen.dart';
import '../features/user/user_dashboard.dart';
import '../features/provider/service_provider_dashboard.dart';
import '../features/vehicle/vehicle_provider_dashboard.dart';
import '../features/admin/admin_dashboard.dart';
import '../features/approval/pending_approval_screen.dart';
import '../features/approval/rejected_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      final isAuthenticated = authState.isAuthenticated;
  final isOnAuthRoute = state.matchedLocation == '/login' ||
      state.matchedLocation == '/role-select' ||
      state.matchedLocation == '/admin-login' ||
      state.matchedLocation == '/';

      // Still loading — stay on splash
      if (isLoading) return null;

      // Not authenticated — allow auth routes, redirect others to login
      if (!isAuthenticated) {
        if (isOnAuthRoute || state.matchedLocation.startsWith('/signup/')) return null;
        return '/login';
      }

      // Authenticated but on auth route — redirect to appropriate dashboard
      if ((isOnAuthRoute || state.matchedLocation.startsWith('/signup/')) && state.matchedLocation != '/') {
        return _getDashboardPath(authState);
      }

      // Authenticated but profile not loaded yet
      if (authState.profile == null && isAuthenticated) {
        return '/role-select';
      }

      // Check pending approval states
      if (authState.isPendingApproval && !_isApprovalRoute(state.matchedLocation)) {
        return '/pending-approval';
      }

      if (authState.isRejected && !_isApprovalRoute(state.matchedLocation)) {
        return '/rejected';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/role-select',
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/signup/:role',
        builder: (context, state) {
          final roleParam = state.pathParameters['role']!;
          final role = switch (roleParam) {
            'user' => SignupRole.user,
            'vehicle' => SignupRole.vehicleProvider,
            'service' => SignupRole.serviceProvider,
            _ => SignupRole.user,
          };
          return SignupScreen(role: role);
        },
      ),
      GoRoute(
        path: '/admin-login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/rejected',
        builder: (context, state) => const RejectedScreen(),
      ),
      GoRoute(
        path: '/user',
        builder: (context, state) => const UserDashboard(),
      ),
      GoRoute(
        path: '/provider',
        builder: (context, state) => const ServiceProviderDashboard(),
      ),
      GoRoute(
        path: '/vehicle',
        builder: (context, state) => const VehicleProviderDashboard(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboard(),
      ),
    ],
  );
});

String _getDashboardPath(AuthState auth) {
  if (auth.isAdmin) return '/admin';
  if (auth.primaryRole == AppUserRole.vehicleProvider) return '/vehicle';
  if (auth.primaryRole == AppUserRole.serviceProvider) return '/provider';
  return '/user';
}

bool _isApprovalRoute(String path) {
  return path == '/pending-approval' || path == '/rejected';
}
