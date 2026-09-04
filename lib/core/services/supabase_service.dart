import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Thin wrapper around the Supabase client. Role checks are NEVER done
/// client-side for authorization — this class is for reads/writes that RLS
/// already protects, and for calling Edge Functions for privileged actions.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    Env.assertConfigured();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  Future<AuthResponse> signUpWithPhone({
    required String phone,
    required String password,
  }) {
    return client.auth.signUp(phone: phone, password: password);
  }

  Future<AuthResponse> signInWithPhone({
    required String phone,
    required String password,
  }) {
    return client.auth.signInWithPassword(phone: phone, password: password);
  }

  Future<void> signOut() => client.auth.signOut();

  /// Calls a privileged Edge Function. Supabase client automatically attaches
  /// the current user's JWT — the function re-validates role server-side.
  Future<Map<String, dynamic>> invokeFunction(
    String name, {
    Map<String, dynamic>? body,
  }) async {
    final res = await client.functions.invoke(name, body: body);
    if (res.status != 200) {
      throw Exception('Function $name failed: ${res.data}');
    }
    return Map<String, dynamic>.from(res.data as Map);
  }
}
