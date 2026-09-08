import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository for admin-only database operations.
class AdminRepository {
  final _svc = SupabaseService.instance;

  /// Fetch all pending approval requests.
  Future<List<Map<String, dynamic>>> getPendingApprovals() async {
    final data = await _svc.client
        .from('approval_requests')
        .select('*, provider_profiles(*), profiles(*)')
        .eq('status', 'PENDING_APPROVAL')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Approve a provider via Edge Function.
  Future<void> approveProvider(String providerId) async {
    await _svc.invokeFunction('provider-approval', body: {
      'provider_id': providerId,
      'action': 'APPROVE',
    });
  }

  /// Reject a provider via Edge Function.
  Future<void> rejectProvider(String providerId, String reason) async {
    await _svc.invokeFunction('provider-approval', body: {
      'provider_id': providerId,
      'action': 'REJECT',
      'reason': reason,
    });
  }

  /// Request correction via Edge Function.
  Future<void> requestCorrection(String providerId, String reason) async {
    await _svc.invokeFunction('provider-approval', body: {
      'provider_id': providerId,
      'action': 'REQUEST_CORRECTION',
      'reason': reason,
    });
  }

  /// Suspend a provider.
  Future<void> suspendProvider(String providerId, String? reason) async {
    await _svc.invokeFunction('provider-approval', body: {
      'provider_id': providerId,
      'action': 'SUSPEND',
      'reason': reason,
    });
  }

  /// Unsuspend a provider.
  Future<void> unsuspendProvider(String providerId) async {
    await _svc.invokeFunction('provider-approval', body: {
      'provider_id': providerId,
      'action': 'UNSUSPEND',
    });
  }

  /// Fetch all providers (admin view).
  Future<List<ProviderProfile>> getAllProviders({
    String? status,
    String? providerType,
    int limit = 50,
  }) async {
    var q = _svc.client.from('provider_profiles').select();
    if (status != null) q = q.eq('status', status);
    if (providerType != null) q = q.eq('provider_type', providerType);
    final data =
        await q.order('created_at', ascending: false).limit(limit);
    return (data as List).map((j) => ProviderProfile.fromJson(j)).toList();
  }

  /// Fetch all users (admin view).
  Future<List<UserProfile>> getAllUsers({int limit = 50}) async {
    final data = await _svc.client
        .from('profiles')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((j) => UserProfile.fromJson(j)).toList();
  }

  /// Fetch dashboard stats.
  Future<Map<String, int>> getDashboardStats() async {
    final providers = await _svc.client
        .from('provider_profiles')
        .select('id', count: CountOption.exact);
    final users = await _svc.client
        .from('profiles')
        .select('id', count: CountOption.exact);
    final orders = await _svc.client
        .from('orders')
        .select('id', count: CountOption.exact);
    final pending = await _svc.client
        .from('approval_requests')
        .select('id', count: CountOption.exact)
        .eq('status', 'PENDING_APPROVAL');

    return {
      'providers': providers.count ?? 0,
      'users': users.count ?? 0,
      'orders': orders.count ?? 0,
      'pendingApprovals': pending.count ?? 0,
    };
  }
}
