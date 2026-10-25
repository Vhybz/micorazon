import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import 'product_service.dart';
import '../core/supabase_config.dart';

class SupabaseProductService implements ProductService {
  SupabaseClient get _client => SupabaseConfig.client;

  @override
  Future<List<Product>> getProducts(String branchCode) async {
    final response = await _client
        .from('products')
        .select()
        .eq('is_deleted', false);
    
    final List<Product> allProducts = [];
    for (var json in (response as List)) {
      try {
        allProducts.add(Product.fromJson(json));
      } catch (e) {
        debugPrint('Error parsing product from REST: $e');
      }
    }

    final cleanBranch = branchCode.trim().toLowerCase();
    if (cleanBranch.isEmpty) return allProducts;

    return allProducts.where((p) {
      if (p.branchCode == null || p.branchCode!.trim().isEmpty) return true;
      final pBranch = p.branchCode!.trim().toLowerCase();
      return pBranch == cleanBranch || pBranch == 'hq' || cleanBranch == 'hq';
    }).toList();
  }

  @override
  Future<Product> getProductById(String id) async {
    final response = await _client
        .from('products')
        .select()
        .eq('id', id)
        .single();
    
    return Product.fromJson(response);
  }

  Map<String, dynamic> _cleanProductPayload(Map<String, dynamic> map, String error) {
    final cleanMap = Map<String, dynamic>.from(map);
    if (error.contains('PGRST204') || error.contains('target_customer_id')) {
      cleanMap.remove('target_customer_id');
    }
    if (error.contains('23503') || error.contains('foreign key') || error.contains('products_branch_code_fkey')) {
      cleanMap['branch_code'] = null;
    }
    return cleanMap;
  }

  @override
  Future<void> addProduct(Product product) async {
    final payload = product.toJson();
    try {
      await _client.from('products').insert(payload);
    } catch (e) {
      final err = e.toString();
      final cleaned = _cleanProductPayload(payload, err);
      await _client.from('products').insert(cleaned);
    }
  }

  @override
  Future<void> updateProduct(Product product) async {
    final payload = product.toJson();
    try {
      await _client
          .from('products')
          .update(payload)
          .eq('id', product.id);
    } catch (e) {
      final err = e.toString();
      final cleaned = _cleanProductPayload(payload, err);
      await _client
          .from('products')
          .update(cleaned)
          .eq('id', product.id);
    }
  }

  @override
  Future<void> deleteProduct(String id) async {
    try {
      await _client
          .from('products')
          .update({'is_deleted': true})
          .eq('id', id);
    } catch (_) {
      await _client
          .from('products')
          .delete()
          .eq('id', id);
    }
  }

  @override
  Future<void> updateStock(String id, double newQuantity) async {
    // This is still useful for absolute overrides (Admin editing stock)
    await _client
        .from('products')
        .update({'stock_quantity': newQuantity})
        .eq('id', id);
  }

  // Add an atomic increment method using the RPC defined in SUPABASE_SETUP.md
  Future<void> incrementStock(String id, double amount) async {
    await _client.rpc('increment_stock', params: {
      'p_id': id,
      'p_amount': amount,
    });
  }

  @override
  Future<void> applyPromotion(String id, double percentage, DateTime? start, DateTime? end, PromoTarget target, PromoCustomerTarget customerTarget, [String? targetCustomerId]) async {
    await _client
        .from('products')
        .update({
          'discount_percentage': percentage,
          'promo_start': start?.toIso8601String(),
          'promo_end': end?.toIso8601String(),
          'promo_target': target.name,
          'promo_customer_target': customerTarget.name,
          'target_customer_id': targetCustomerId,
        })
        .eq('id', id);
  }

  @override
  Future<String?> uploadProductImage(Uint8List bytes, String fileName) async {
    try {
      final storage = _client.storage.from('product-images');
      final path = 'products/$fileName';
      
      // Upload using uploadBinary for Uint8List
      await storage.uploadBinary(
        path, 
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      
      // Return the public URL
      return storage.getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload Error: $e');
      return null;
    }
  }

  @override
  Stream<List<Product>> watchProducts(String branchCode) {
    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .map((data) {
          final cleanBranch = branchCode.trim().toLowerCase();
          final List<Product> list = [];
          for (var json in data) {
            try {
              list.add(Product.fromJson(json));
            } catch (e) {
              debugPrint('Error parsing product in stream: $e');
            }
          }
          return list.where((p) {
            if (p.isDeleted) return false;
            if (cleanBranch.isEmpty) return true;
            if (p.branchCode == null || p.branchCode!.trim().isEmpty) return true;
            final pBranch = p.branchCode!.trim().toLowerCase();
            return pBranch == cleanBranch || pBranch == 'hq' || cleanBranch == 'hq';
          }).toList();
        });
  }
}
