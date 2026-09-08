import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/cart_service.dart';

class BirrBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BirrBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartCountProvider).valueOrNull ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _item(context, 0, Icons.home_outlined, Icons.home, 'Home'),
              _item(context, 1, Icons.search_outlined, Icons.search, 'Search'),
              _item(context, 2, Icons.receipt_long_outlined, Icons.receipt_long,
                  'Orders', cartBadge: cartCount),
              _item(context, 3, Icons.notifications_outlined, Icons.notifications,
                  'Alerts'),
              _item(context, 4, Icons.person_outlined, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData outline,
    IconData filled,
    String label, {
    int cartBadge = 0,
  }) {
    final selected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? filled : outline,
                    color: selected ? AppTheme.primaryGreen : AppTheme.textMuted,
                    size: 24),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? AppTheme.primaryGreen
                            : AppTheme.textMuted)),
              ],
            ),
            // Cart entry point badge on the Orders tab. Tapping the badge
            // opens the cart; tapping the tab itself still opens Orders.
            if (index == 2)
              Positioned(
                top: -6,
                right: -2,
                child: GestureDetector(
                  onTap: () => context.go('/user/cart'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: cartBadge > 0
                          ? AppTheme.error
                          : AppTheme.textMuted.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: cartBadge > 0
                        ? Text('$cartBadge',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600))
                        : const Icon(Icons.shopping_cart_outlined,
                            size: 12, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}