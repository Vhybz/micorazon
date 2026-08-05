import '../core/uuid_utils.dart';
import '../models/product.dart';
import '../models/butcher_models.dart';
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
        'HARD CHICKEN (LAYER)': [
          'Hard Whole Chicken (Layer)',
          'Hard Thigh (Layer)',
          'Hard Breast (Layer)',
          'Hard Back (Layer)',
          'Hard Wings (Layer)',
          'Hard Drumsticks (Layer)',
          'Gizzard'
        ]
      },
      {
        'SOFT CHICKEN (BROILER)': [
          'Soft Whole Chicken (Broiler)',
          'Soft Thigh (Broiler)',
          'Soft Breast (Broiler)',
          'Soft Back (Broiler)',
          'Soft Wings (Broiler)',
          'Soft Drumsticks (Broiler)',
          'Gizzard'
        ]
      },
      {
        'COW': [ 
          'Offals / Yemadeɛ', 'Feet', 'Head'
        ]
      },
      {
        'BEEF': [
          'Standard Meat', 'Boneless', 'Cow Steak', 'Liver & Lungs', 
          'Grounded Meat', 'Tail / Padua'
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
        final bool isChicken = category == 'HARD CHICKEN (LAYER)' || category == 'SOFT CHICKEN (BROILER)';
        
        if (isChicken && name.toUpperCase() != 'GIZZARD') {
          // Special handling for chicken parts - Create separate cards for each weight range
          final bool isHard = category == 'HARD CHICKEN (LAYER)';
          final type = isHard ? AnimalType.hardChicken : AnimalType.softChicken;
          final ranges = type.chickenRanges;

          for (var range in ranges) {
            final rangeName = '$name (${range.label})';
            if (existingNames.contains(rangeName.toLowerCase())) continue;

            // Only set price automatically for Whole Chickens
            final double initialPrice = name.contains('Whole') ? range.price : 0.0;
            final String validUuid = UuidUtils.generate();

            final product = Product(
              id: validUuid,
              branchCode: user.branchCode,
              name: rangeName,
              retailPrice: initialPrice,
              wholesalePrice: 0.0,
              costPrice: 0.0,
              imageUrl: '', 
              category: category,
              stockQuantity: 0.0,
              unit: name.contains('Whole') ? 'unit' : 'kg',
            );
            await service.addProduct(product);
          }
        } else {
          // Standard single card seeding for other items
          if (existingNames.contains(name.toLowerCase())) continue;

          final String validUuid = UuidUtils.generate();

          final product = Product(
            id: validUuid,
            branchCode: user.branchCode,
            name: name,
            retailPrice: 0.0,
            wholesalePrice: 0.0,
            costPrice: 0.0,
            imageUrl: '', 
            category: category,
            stockQuantity: 0.0,
            unit: (name.contains('Whole') || 
                   category == 'TURKEY' || 
                   category == 'RABBIT') 
                  ? 'unit' 
                  : 'kg',
          );
          
          await service.addProduct(product);
        }
      }
    }
  }
}

final productSeederProvider = Provider<ProductSeeder>((ref) => ProductSeeder(ref));
