import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/document_model.dart';
import 'supabase_document_service.dart';
import 'user_provider.dart';

class DocumentNotifier extends StateNotifier<List<DocumentRecord>> {
  final SupabaseDocumentService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  DocumentNotifier(this._service, this.ref) : super([]) {
    // Watch for user changes to restart the subscription
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startWatching();
      }
    }, fireImmediately: true);
  }

  void _startWatching() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchDocuments(user!.branchCode!).listen((docs) {
        state = docs;
      });
    } else {
      state = [];
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> uploadAndAddDocument(Uint8List bytes, String fileName, String title, String description) async {
    try {
      final user = ref.read(currentUserProvider);
      final url = await _service.uploadFile(bytes, fileName);
      if (url != null) {
        final doc = DocumentRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          branchCode: user?.branchCode ?? 'HQ',
          title: title,
          description: description,
          fileUrl: url,
          createdAt: DateTime.now(),
        );
        await _service.addDocument(doc);
      } else {
        // This should not happen now because uploadFile rethrows, 
        // but just in case it returns null without throwing.
        throw Exception('Failed to upload file to storage bucket. Please check if the "documents" bucket exists and is set to Public.');
      }
    } catch (e) {
      debugPrint('Document Upload Error: $e');
      rethrow;
    }
  }

  Future<void> updateDocument(DocumentRecord doc, {Uint8List? newBytes, String? newFileName, String? title, String? description}) async {
    try {
      String fileUrl = doc.fileUrl;
      if (newBytes != null && newFileName != null) {
        final newUrl = await _service.uploadFile(newBytes, newFileName);
        if (newUrl != null) fileUrl = newUrl;
      }

      final updatedDoc = DocumentRecord(
        id: doc.id,
        branchCode: doc.branchCode,
        title: title ?? doc.title,
        description: description ?? doc.description,
        fileUrl: fileUrl,
        createdAt: doc.createdAt,
      );
      await _service.updateDocument(updatedDoc);
    } catch (e) {
      debugPrint('Document Update Error: $e');
      rethrow;
    }
  }

  Future<void> deleteDocument(DocumentRecord doc) async {
    try {
      await _service.deleteDocument(doc.id);
      await _service.deleteFile(doc.fileUrl);
    } catch (e) {
      debugPrint('Document Delete Error: $e');
      rethrow;
    }
  }
}

final documentServiceProvider = Provider((ref) => SupabaseDocumentService());
final documentProvider = StateNotifierProvider<DocumentNotifier, List<DocumentRecord>>((ref) {
  return DocumentNotifier(ref.watch(documentServiceProvider), ref);
});
