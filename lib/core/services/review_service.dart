import 'package:supabase_flutter/supabase_flutter.dart';

/// Reviews backed by the existing `reviews` table (migration 0001), which
/// uses a polymorphic shape: target_type ('PRODUCT' | 'PROVIDER' | 'VEHICLE')
/// + target_id, with order_id used to verify a completed purchase.
class ReviewService {
  ReviewService._();
  static final instance = ReviewService._();
  final _client = Supabase.instance.client;

  /// Submit a review for an order (RLS requires the order to belong to the
  /// current user with status COMPLETED).
  Future<void> submitReview({
    required String orderId,
    required String targetType,
    required String targetId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('reviews').insert({
      'user_id': userId,
      'target_type': targetType,
      'target_id': targetId,
      'order_id': orderId,
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    });
  }

  /// Update an existing review (user owns it per RLS).
  Future<void> updateReview({
    required String reviewId,
    required int rating,
    String? comment,
  }) async {
    await _client.from('reviews').update({
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    }).eq('id', reviewId);
  }

  /// The user's review for an order, if any (used for edit prefill and to
  /// decide Leave-a-Review vs Edit-Your-Review state).
  Future<Map<String, dynamic>?> getReviewForOrder(String orderId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    return _client
        .from('reviews')
        .select()
        .eq('order_id', orderId)
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
  }

  /// Whether the current user has already reviewed an order.
  Future<bool> hasUserReviewedOrder(String orderId) async {
    return await getReviewForOrder(orderId) != null;
  }

  /// Reviews for a product, newest first, with reviewer names resolved.
  Future<List<Map<String, dynamic>>> getReviewsForProduct(
      String productId) {
    return _getReviews(targetType: 'PRODUCT', targetId: productId);
  }

  /// Reviews for a provider, newest first, with reviewer names resolved.
  Future<List<Map<String, dynamic>>> getReviewsForProvider(
      String providerId) {
    return _getReviews(targetType: 'PROVIDER', targetId: providerId);
  }

  Future<List<Map<String, dynamic>>> _getReviews({
    required String targetType,
    required String targetId,
  }) async {
    final data = await _client
        .from('reviews')
        .select()
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .order('created_at', ascending: false)
        .limit(50);
    final rows = List<Map<String, dynamic>>.from(data as List);

    // Resolve reviewer names (reviews.user_id references auth.users, not
    // profiles, so names come from a separate profiles lookup).
    final names = <String, String>{};
    try {
      final userIds = rows
          .map((r) => r['user_id'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      if (userIds.isNotEmpty) {
        final profiles = await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', userIds);
        for (final p in profiles as List) {
          names[p['id'] as String] = p['full_name'] as String? ?? '';
        }
      }
    } catch (_) {}

    return [
      for (final r in rows) {...r, 'reviewer_name': names[r['user_id']] ?? ''},
    ];
  }
}