import 'package:flutter/material.dart';

/// Wrap the splash/login logo with this widget: tapping it 5 times within
/// 3 seconds navigates to the hidden admin login route. This is a UX
/// convenience only — it grants no privilege by itself. Real admin
/// authorization happens via Supabase Auth + has_role('ADMIN') server-side.
class AdminGate extends StatefulWidget {
  final Widget child;
  final VoidCallback onUnlocked;
  const AdminGate({super.key, required this.child, required this.onUnlocked});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  int _taps = 0;
  DateTime? _firstTap;

  void _handleTap() {
    final now = DateTime.now();
    if (_firstTap == null || now.difference(_firstTap!) > const Duration(seconds: 3)) {
      _firstTap = now;
      _taps = 1;
    } else {
      _taps++;
    }
    if (_taps >= 5) {
      _taps = 0;
      _firstTap = null;
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: _handleTap, child: widget.child);
  }
}
