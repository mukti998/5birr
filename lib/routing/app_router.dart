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
import '../features/user/user_product_detail_screen.dart';
import '../features/user/user_provider_detail_screen.dart';
import '../features/user/user_category_screen.dart';
import '../features/user/user_favorites_screen.dart';
import '../features/user/user_cart_screen.dart';
import '../features/user/user_checkout_screen.dart';
import '../features/provider/service_provider_dashboard.dart';
import '../features/provider/provider_business_profile_screen.dart';
import '../features/provider/provider_product_list_screen.dart';
import '../features/provider/provider_product_form_screen.dart';
import '../features/vehicle/vehicle_provider_dashboard.dart';
import '../features/vehicle/vehicle_management_screen.dart';
import '../features/vehicle/vehicle_form_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/wallet/recharge_screen.dart';
import '../features/admin/admin_dashboard.dart';
import '../features/admin/admin_provider_management_screen.dart';
import '../features/admin/admin_payment_methods_screen.dart';
import '../features/admin/admin_payment_verification_screen.dart';
import '../features/admin/admin_cash_recharge_screen.dart';
import '../features/admin/admin_provider_wallet_screen.dart';
import '../features/approval/pending_approval_screen.dart';
import '../features/approval/rejected_screen.dart';
import '../features/vehicle/driver_ride_requests_screen.dart';
import '../features/vehicle/driver_trip_screen.dart';
import '../features/user/user_ride_request_screen.dart';
import '../features/user/user_active_ride_screen.dart';
import '../features/shared/ride_history_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      final isAuthenticated = authState.isAuthenticated;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' ||
          loc == '/role-select' ||
          loc == '/admin-login' ||
          loc == '/';

      if (isLoading) return null;

      if (!isAuthenticated) {
        if (isAuthRoute || loc.startsWith('/signup/')) return null;
        return '/login';
      }

      if ((isAuthRoute || loc.startsWith('/signup/')) && loc != '/') {
        return _getDashboardPath(authState);
      }

      if (authState.profile == null && isAuthenticated) {
        return '/role-select';
      }

      if (authState.isPendingApproval && !_isApprovalRoute(loc)) {
        return '/pending-approval';
      }
      if (authState.isRejected && !_isApprovalRoute(loc)) {
        return '/rejected';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/role-select', builder: (_, __) => const RoleSelectionScreen()),
      GoRoute(
        path: '/signup/:role',
        builder: (_, state) {
          final r = state.pathParameters['role']!;
          return SignupScreen(role: switch (r) {
            'user' => SignupRole.user,
            'vehicle' => SignupRole.vehicleProvider,
            'service' => SignupRole.serviceProvider,
            _ => SignupRole.user,
          });
        },
      ),
      GoRoute(path: '/admin-login', builder: (_, __) => const AdminLoginScreen()),
      GoRoute(path: '/pending-approval', builder: (_, __) => const PendingApprovalScreen()),
      GoRoute(path: '/rejected', builder: (_, __) => const RejectedScreen()),

      // ── User ──
      GoRoute(path: '/user', builder: (_, __) => const UserDashboard()),
      GoRoute(path: '/user/product/:id', builder: (_, s) => UserProductDetailScreen(productId: s.pathParameters['id']!)),
      GoRoute(path: '/user/provider/:id', builder: (_, s) => UserProviderDetailScreen(providerId: s.pathParameters['id']!)),
      GoRoute(path: '/user/category/:id', builder: (_, s) => UserCategoryScreen(categoryId: s.pathParameters['id']!)),
      GoRoute(path: '/user/favorites', builder: (_, __) => const UserFavoritesScreen()),
      GoRoute(path: '/user/cart', builder: (_, __) => const UserCartScreen()),
      GoRoute(path: '/user/checkout', builder: (_, s) => UserCheckoutScreen(providerId: s.extra as String)),
      GoRoute(path: '/user/search', builder: (_, __) => const UserSearchScreen()),
      GoRoute(path: '/user/ride-request', builder: (_, __) => const UserRideRequestScreen()),
      GoRoute(path: '/user/ride-active', builder: (_, __) => const UserActiveRideScreen()),
      GoRoute(path: '/user/ride-history', builder: (_, __) => const RideHistoryScreen(isProvider: false)),

      // ── Service Provider ──
      GoRoute(path: '/provider', builder: (_, __) => const ServiceProviderDashboard()),
      GoRoute(path: '/provider/business', builder: (_, __) => const ProviderBusinessProfileScreen()),
      GoRoute(path: '/provider/products', builder: (_, __) => const ProviderProductListScreen()),
      GoRoute(path: '/provider/products/new', builder: (_, __) => const ProviderProductFormScreen()),
      GoRoute(path: '/provider/products/:id', builder: (_, s) => ProviderProductFormScreen(productId: s.pathParameters['id'])),

      // ── Wallet (provider) ──
      GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/wallet/recharge', builder: (_, __) => const RechargeScreen()),

      // ── Vehicle Provider ──
      GoRoute(path: '/vehicle', builder: (_, __) => const VehicleProviderDashboard()),
      GoRoute(path: '/vehicle/vehicles', builder: (_, __) => const VehicleManagementScreen()),
      GoRoute(path: '/vehicle/vehicles/new', builder: (_, __) => const VehicleFormScreen()),
      GoRoute(path: '/vehicle/vehicles/:id', builder: (_, s) => VehicleFormScreen(vehicleId: s.pathParameters['id'])),
      GoRoute(path: '/vehicle/ride-requests', builder: (_, __) => const DriverRideRequestsScreen()),
      GoRoute(path: '/vehicle/trip/:id', builder: (_, s) => DriverTripScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/vehicle/history', builder: (_, __) => const RideHistoryScreen(isProvider: true)),

      // ── Admin ──
      GoRoute(path: '/admin', builder: (_, __) => const AdminDashboard()),
      GoRoute(path: '/admin/approvals', builder: (_, __) => const AdminProviderManagementScreen()),
      GoRoute(path: '/admin/providers', builder: (_, __) => const AdminProviderManagementScreen()),
      GoRoute(path: '/admin/payment-methods', builder: (_, __) => const AdminPaymentMethodsScreen()),
      GoRoute(path: '/admin/payments', builder: (_, __) => const AdminPaymentVerificationScreen()),
      GoRoute(path: '/admin/providers/:id/wallet', builder: (_, s) => AdminProviderWalletScreen(providerId: s.pathParameters['id']!)),
      GoRoute(path: '/admin/providers/:id/wallet/recharge', builder: (_, s) => AdminCashRechargeScreen(providerId: s.pathParameters['id']!)),
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
