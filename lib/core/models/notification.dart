/// Notification model mapped to the `notifications` Supabase table.
class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String? body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      isRead: json['is_read'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  bool get isApproval => type == 'APPROVAL';
  bool get isRejection => type == 'REJECTION';
  bool get isCorrectionRequired => type == 'CORRECTION_REQUIRED';
  bool get isOrderRelated =>
      type.startsWith('ORDER_') || type == 'PAYMENT_REMINDER';
  bool get isRideRelated => type.startsWith('RIDE_');
  bool get isWalletRelated => type.startsWith('WALLET_');
}
