import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:storage_client/storage_client.dart' show FileOptions;

class ImageService {
  ImageService._();
  static final instance = ImageService._();
  final _client = Supabase.instance.client;

  /// Get public URL for product images (public bucket).
  String getPublicUrl(String bucket, String path) {
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Get signed URL for private documents (1h expiry).
  Future<String> getSignedUrl(String bucket, String path) async {
    return _client.storage.from(bucket).createSignedUrl(path, 3600);
  }

  /// Upload file to storage.
  Future<String> upload(String bucket, String path, String filePath,
      {bool upsert = true}) async {
    await _client.storage.from(bucket).upload(path, filePath,
        fileOptions: FileOptions(upsert: upsert));
    return path;
  }

  /// Delete file from storage.
  Future<void> delete(String bucket, String path) async {
    await _client.storage.from(bucket).remove([path]);
  }
}
