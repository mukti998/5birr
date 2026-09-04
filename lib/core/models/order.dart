/// Order model mapped to the `orders` Supabase table.
class AppOrder {
  final String id;
  final String userId;
  final String providerId;
  final String status;
  final double totalAmount;
  final String currency;
  final bool requiresPaymentProof;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppOrder({
    required this.id,
    required this.userId,
    required this.providerId,
    required this.status,
    required this.totalAmount,
    this.currency = 'ETB',
    this.requiresPaymentProof = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppOrder.fromJson(Map<String, dynamic> json) {
    return AppOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      providerId: json['provider_id'] as String,
      status: json['status'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'ETB',
      requiresPaymentProof: json['requires_payment_proof'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get formattedAmount => '$totalAmount $currency';
  bool get isTerminal =>
      status == 'CANCELLED' ||
      status == 'COMPLETED' ||
      status == 'REFUNDED' ||
      status == 'REJECTED';
}

/// Order status history entry.
class OrderStatusHistory {
  final String id;
  final String orderId;
  final String? fromStatus;
  final String toStatus;
  final String? changedBy;
  final String? note;
  final DateTime createdAt;

  const OrderStatusHistory({
    required this.id,
    required this.orderId,
    this.fromStatus,
    required this.toStatus,
    this.changedBy,
    this.note,
    required this.createdAt,
  });

  factory OrderStatusHistory.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistory(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      fromStatus: json['from_status'] as String?,
      toStatus: json['to_status'] as String,
      changedBy: json['changed_by'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
