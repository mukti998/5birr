import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository for profile-related database operations.
class ProfileRepository {
  final _svc = SupabaseService.instance;

  /// Fetch user profile by ID.
  Future<UserProfile?> getProfile(String userId) async {
    final data = await _svc.client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  /// Update user profile (name, phone, email only — status is protected).
  Future<UserProfile> updateProfile({
    required String userId,
    String? fullName,
    String? phone,
    String? email,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (phone != null) updates['phone'] = phone;
    if (email != null) updates['email'] = email;

    final data = await _svc.client
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
    return UserProfile.fromJson(data);
  }

  /// Fetch provider profile for current user.
  Future<ProviderProfile?> getProviderProfile(String userId) async {
    final data = await _svc.client
        .from('provider_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return ProviderProfile.fromJson(data);
  }

  /// Fetch provider profile by provider ID.
  Future<ProviderProfile?> getProviderById(String providerId) async {
    final data = await _svc.client
        .from('provider_profiles')
        .select()
        .eq('id', providerId)
        .maybeSingle();
    if (data == null) return null;
    return ProviderProfile.fromJson(data);
  }

  /// Fetch approval requests for a provider.
  Future<List<Map<String, dynamic>>> getApprovalHistory(
      String subjectType, String subjectId) async {
    final data = await _svc.client
        .from('approval_history')
        .select()
        .eq('subject_type', subjectType)
        .eq('subject_id', subjectId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Resubmit after correction — updates provider profile status from
  /// REJECTED back to PENDING_APPROVAL. The server-side trigger
  /// (prevent_provider_self_privilege_escalation) explicitly allows this
  /// specific transition for non-admin users.
  Future<void> resubmitProvider(String providerId) async {
    await _svc.client.from('provider_profiles').update({
      'status': 'PENDING_APPROVAL',
    }).eq('id', providerId);
  }
}
