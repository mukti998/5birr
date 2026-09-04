import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class UserNotificationsScreen extends StatefulWidget {
  const UserNotificationsScreen({super.key});
  @override
  State<UserNotificationsScreen> createState() =>
      _UserNotificationsScreenState();
}

class _UserNotificationsScreenState extends State<UserNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primaryGreen))
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 64, color: AppTheme.textMuted),
                    SizedBox(height: 16),
                    Text('No notifications',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ],
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (_, i) {
                      final n = _notifications[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            _iconForType(n['type'] ?? ''),
                            color: AppTheme.primaryGreen,
                          ),
                          title: Text(n['title'] ?? '',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(n['body'] ?? '',
                              style: const TextStyle(fontSize: 12)),
                          trailing: n['is_read'] == true
                              ? null
                              : Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.primaryGreen)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  IconData _iconForType(String type) {
    if (type.contains('ORDER')) return Icons.receipt_outlined;
    if (type.contains('APPROVAL') || type.contains('APPROVE'))
      return Icons.check_circle_outline;
    if (type.contains('REJECT')) return Icons.cancel_outlined;
    if (type.contains('WALLET')) return Icons.account_balance_wallet_outlined;
    if (type.contains('RIDE')) return Icons.directions_car_outlined;
    return Icons.notifications_outlined;
  }
}
