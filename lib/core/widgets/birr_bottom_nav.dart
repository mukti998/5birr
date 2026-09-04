import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BirrBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BirrBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              _item(0, Icons.home_outlined, Icons.home, 'Home'),
              _item(1, Icons.search_outlined, Icons.search, 'Search'),
              _item(2, Icons.receipt_long_outlined, Icons.receipt_long, 'Orders'),
              _item(3, Icons.notifications_outlined, Icons.notifications, 'Alerts'),
              _item(4, Icons.person_outlined, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int index, IconData outline, IconData filled, String label) {
    final selected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
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
                    color:
                        selected ? AppTheme.primaryGreen : AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
