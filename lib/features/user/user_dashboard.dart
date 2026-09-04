import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/birr_bottom_nav.dart';
import 'user_home_screen.dart';
import 'user_search_screen.dart';
import 'user_orders_screen.dart';
import 'user_notifications_screen.dart';
import 'user_profile_screen.dart';

class UserDashboard extends ConsumerStatefulWidget {
  const UserDashboard({super.key});
  @override
  ConsumerState<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends ConsumerState<UserDashboard> {
  int _navIndex = 0;

  final _screens = const [
    UserHomeScreen(),
    UserSearchScreen(),
    UserOrdersScreen(),
    UserNotificationsScreen(),
    UserProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _navIndex, children: _screens),
      bottomNavigationBar: BirrBottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}
