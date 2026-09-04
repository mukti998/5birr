/// Subscription model mapped to the `subscriptions` Supabase table.
class Subscription {
  final String id;
  final String providerId;
  final String status;
  final DateTime nextDueDate;
  final DateTime? lastChargedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Subscription({
    required this.id,
    required this.providerId,
    required this.status,
    required this.nextDueDate,
    this.lastChargedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      status: json['status'] as String,
      nextDueDate: DateTime.parse(json['next_due_date'] as String),
      lastChargedAt: json['last_charged_at'] != null
          ? DateTime.parse(json['last_charged_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isActive => status == 'ACTIVE';
  bool get isDue => status == 'DUE';
  bool get isGrace => status == 'GRACE';
  bool get isSuspended => status == 'SUSPENDED';
  bool get isOverdue => nextDueDate.isBefore(DateTime.now());
}
