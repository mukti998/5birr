import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository for notification-related database operations.
class NotificationRepository {
  final _svc = SupabaseService.instance;

  /// Fetch notifications for the current user.
  Future<List<AppNotification>> getNotifications({
    bool? unreadOnly,
    int limit = 50,
    int offset = 0,
  }) async {
    var q = _svc.client.from('notifications').select();
    if (unreadOnly == true) q = q.eq('is_read', false);
    final data = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((j) => AppNotification.fromJson(j)).toList();
  }

  /// Watch notifications in real-time.
  Stream<List<AppNotification>> watchNotifications() {
    return _svc.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50)
        .map((list) => list.map((j) => AppNotification.fromJson(j)).toList());
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _svc.client
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    await _svc.client
        .from('notifications')
        .update({'is_read': true}).eq('is_read', false);
  }

  /// Get unread count.
  Future<int> getUnreadCount() async {
    final data = await _svc.client
        .from('notifications')
        .select('id')
        .eq('is_read', false);
    return (data as List).length;
  }

  /// Watch unread count.
  Stream<int> watchUnreadCount() {
    return _svc.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('is_read', false)
        .map((list) => list.length);
  }
}
