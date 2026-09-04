import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesService {
  FavoritesService._();
  static final instance = FavoritesService._();
  final _client = Supabase.instance.client;

  /// Check if item is favorited.
  Future<bool> isFavorited(String targetType, String targetId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final data = await _client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .maybeSingle();
    return data != null;
  }

  /// Toggle favorite.
  Future<bool> toggle(String targetType, String targetId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final existing = await _client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .maybeSingle();

    if (existing != null) {
      await _client.from('favorites').delete().eq('id', existing['id']);
      return false;
    } else {
      await _client.from('favorites').insert({
        'user_id': userId,
        'target_type': targetType,
        'target_id': targetId,
      });
      return true;
    }
  }

  /// Get user's favorites.
  Future<List<Map<String, dynamic>>> getFavorites({
    String? targetType,
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    var q = _client.from('favorites').select().eq('user_id', userId);
    if (targetType != null) q = q.eq('target_type', targetType);
    final data = await q
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(data as List);
  }
}
