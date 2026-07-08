import '../core/uuid_utils.dart';
import '../models/product.dart';
import 'product_service.dart';
import 'user_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductSeeder {
  final Ref ref;
  ProductSeeder(this.ref);

  Future<void> seedProducts() async {
    final user = ref.read(currentUserProvider);
    if (user == null || user.branchCode == null) return;

    final service = ref.read(productServiceProvider);
    
    final List<Map<String, List<String>>> data = [
      {
        'CHICKEN': [
          'Hard Thigh (Layer)', 'Soft Thigh (Broiler)', 'Hard Breast (Layer)', 'Soft Breast (Broiler)', 
          'Hard Back (Layer)', 'Soft Back (Broiler)', 'Hard Wings (Layer)', 'Soft Wings (Broiler)', 
          'Hard Half Chicken (Layer)', 'Soft Half Chicken (Broiler)', 'Hard Whole Chicken (Layer)', 
          'Soft Whole Chicken (Broiler)', 'Hard Drumsticks (Layer)', 'Soft Drumsticks (Broiler)'
        ]
      },
      {
        'COW': [ // Changed from BEEF to COW
          'Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Cow Steak',
          'Liver & Lungs', 'Grounded Meat', 'Feet', 'Head', 'Tail / Padua'
        ]
      },
      {
        'GOAT': [
          'Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet'
        ]
      },
      {
        'SHEEP': [
          'Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet'
        ]
      },
      {
        'PORK': [
          'Standard Meat', 'Boneless Meat', 'Offals / Yemadeɛ', 'Pork Steak',
          'Head', 'Ear', 'Feet', 'Liver', 'Skin'
        ]
      },
      {
        'TURKEY': [
          'Whole Turkey', 'Breast', 'Thighs', 'Drumsticks', 'Wings', 'Gizzards', 'Feet'
        ]
      },
      {
        'RABBIT': [
          'Whole Rabbit', 'Legs', 'Saddle', 'Shoulders'
        ]
      }
    ];

    // Get existing products to avoid duplicates
    final existingProductsAsync = ref.read(productsFutureProvider);
    final existingNames = existingProductsAsync.value?.map((p) => p.name.toLowerCase()).toSet() ?? {};

    for (var categoryMap in data) {
      final category = categoryMap.keys.first;
      final productNames = categoryMap.values.first;

      for (var name in productNames) {
        if (existingNames.contains(name.toLowerCase())) continue;

        final String validUuid = UuidUtils.generate();

        final product = Product(
          id: validUuid,
          branchCode: user.branchCode,
          name: name,
          retailPrice: 0.0,
          wholesalePrice: 0.0,
          costPrice: 0.0, // Initializing with zero as requested
          imageUrl: '', 
          category: category,
          stockQuantity: 0.0,
          unit: (name.contains('Whole') || category == 'TURKEY' || category == 'RABBIT') ? 'unit' : 'kg',
        );
        
        await service.addProduct(product);
      }
    }
  }
}

final productSeederProvider = Provider<ProductSeeder>((ref) => ProductSeeder(ref));
