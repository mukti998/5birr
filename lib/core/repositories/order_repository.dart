import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository for order-related database operations.
class OrderRepository {
  final _svc = SupabaseService.instance;

  /// Fetch orders for the current user (as customer).
  Future<List<AppOrder>> getMyOrders({int limit = 20, int offset = 0}) async {
    final data = await _svc.client
        .from('orders')
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((j) => AppOrder.fromJson(j)).toList();
  }

  /// Fetch orders for a provider (as seller).
  Future<List<AppOrder>> getProviderOrders({
    required String providerId,
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _svc.client
        .from('orders')
        .select()
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((j) => AppOrder.fromJson(j)).toList();
  }

  /// Create a new order via server-side Edge Function.
  /// The Edge Function validates prices, availability, and stock server-side,
  /// ensuring the client cannot manipulate pricing.
  Future<AppOrder> createOrder({
    required String providerId,
    required List<Map<String, dynamic>> items,
    String? note,
  }) async {
    final result = await _svc.invokeFunction('order-create', body: {
      'provider_id': providerId,
      'items': items.map((item) => {
        'product_id': item['product_id'],
        'quantity': item['quantity'],
      }).toList(),
      if (note != null) 'note': note,
    });
    return AppOrder.fromJson(result['order'] as Map<String, dynamic>);
  }

  /// Transition order status via Edge Function.
  Future<AppOrder> transitionStatus({
    required String orderId,
    required String newStatus,
    String? note,
  }) async {
    final result = await _svc.invokeFunction('order-transition', body: {
      'order_id': orderId,
      'new_status': newStatus,
      'note': note,
    });
    return AppOrder.fromJson(result['order'] as Map<String, dynamic>);
  }

  /// Fetch order status history.
  Future<List<OrderStatusHistory>> getOrderHistory(String orderId) async {
    final data = await _svc.client
        .from('order_status_history')
        .select()
        .eq('order_id', orderId)
        .order('created_at', ascending: false);
    return (data as List).map((j) => OrderStatusHistory.fromJson(j)).toList();
  }

  /// Fetch all orders (admin only).
  Future<List<AppOrder>> getAllOrders({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var q = _svc.client.from('orders').select();
    if (status != null) q = q.eq('status', status);
    final data = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List).map((j) => AppOrder.fromJson(j)).toList();
  }
}
