import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document_model.dart';
import '../core/supabase_config.dart';

class SupabaseDocumentService {
  SupabaseClient get _client => SupabaseConfig.client;

  Stream<List<DocumentRecord>> watchDocuments(String branchCode) {
    return _client.from('documentss')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .map((data) => data.map((json) => DocumentRecord.fromJson(json)).toList());
  }

  Future<void> addDocument(DocumentRecord doc) async {
    await _client.from('documentss').insert(doc.toJson());
  }

  Future<void> updateDocument(DocumentRecord doc) async {
    await _client.from('documentss').update(doc.toJson()).eq('id', doc.id);
  }

  Future<void> deleteDocument(String id) async {
    await _client.from('documentss').delete().eq('id', id);
  }

  Future<String?> uploadFile(Uint8List bytes, String fileName) async {
    try {
      final path = 'docs/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      await _client.storage.from('documents').uploadBinary(
        path, 
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );
      return _client.storage.from('documents').getPublicUrl(path);
    } catch (e) {
      debugPrint('SUPABASE STORAGE UPLOAD ERROR: $e');
      rethrow; // Rethrow to catch it in the provider and show to user
    }
  }

  Future<void> deleteFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.sublist(uri.pathSegments.indexOf('documents') + 1).join('/');
      await _client.storage.from('documents').remove([path]);
    } catch (e) {
      // Ignore errors
    }
  }
}
