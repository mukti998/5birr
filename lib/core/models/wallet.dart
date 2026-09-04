/// Wallet model mapped to the `wallets` Supabase table.
class Wallet {
  final String id;
  final String providerId;
  final double balance;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Wallet({
    required this.id,
    required this.providerId,
    required this.balance,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      balance: (json['balance'] as num).toDouble(),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isRestricted => status == 'RESTRICTED';
  bool get isLowBalance => balance < 15; // matches system_settings default
}
