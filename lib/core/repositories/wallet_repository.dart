import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository for wallet-related database operations.
class WalletRepository {
  final _svc = SupabaseService.instance;

  /// Fetch wallet for a provider.
  Future<Wallet?> getWallet(String providerId) async {
    final data = await _svc.client
        .from('wallets')
        .select()
        .eq('provider_id', providerId)
        .maybeSingle();
    if (data == null) return null;
    return Wallet.fromJson(data);
  }

  /// Fetch wallet transactions.
  Future<List<Map<String, dynamic>>> getTransactions({
    required String providerId,
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _svc.client
        .from('wallet_transactions')
        .select()
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Deduct fee via Edge Function (admin only).
  Future<Map<String, dynamic>> deductFee({
    required String providerId,
    String? orderId,
    String? rideId,
    double grossAmount = 0,
    required String idempotencyKey,
  }) async {
    final result = await _svc.invokeFunction('wallet-deduct-fee', body: {
      'provider_id': providerId,
      'order_id': orderId,
      'ride_id': rideId,
      'gross_amount': grossAmount,
      'idempotency_key': idempotencyKey,
    });
    return result['transaction'] as Map<String, dynamic>;
  }
}
