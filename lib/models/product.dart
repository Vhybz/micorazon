import 'customer_model.dart';
import 'system_models.dart';

enum PromoTarget { retail, wholesale, both }
enum PromoCustomerTarget { all, regularsOnly, specialOnly, specificPerson }

class PriceBracket {
  final double minWeight;
  final double maxWeight;
  final double price;

  PriceBracket({
    required this.minWeight, 
    required this.maxWeight, 
    required this.price
  });

  factory PriceBracket.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return PriceBracket(
      minWeight: (map['minWeight'] as num).toDouble(),
      maxWeight: (map['maxWeight'] as num).toDouble(),
      price: (map['price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'minWeight': minWeight,
    'maxWeight': maxWeight,
    'price': price,
  };
}

class Product {
  final String id;
  final String? branchCode;
  final String name;
  final double retailPrice;
  final double wholesalePrice;
  final double costPrice;
  final List<PriceBracket>? retailBrackets;
  final List<PriceBracket>? wholesaleBrackets;
  final String imageUrl;
  final String category;
  final double stockQuantity;
  final String unit;
  final double discountPercentage;
  final DateTime? promoStartDate;
  final DateTime? promoEndDate;
  final PromoTarget promoTarget;
  final PromoCustomerTarget promoCustomerTarget;
  final String? targetCustomerId;
  final bool isDeleted; // Soft delete
  final bool isUnlimited; // Stock doesn't decrease on sales
  final double lowStockThreshold;
  final double dailyStockAdded;
  final DateTime? lastStockUpdate;

  Product({
    required this.id,
    this.branchCode,
    required this.name,
    required this.retailPrice,
    required this.wholesalePrice,
    this.costPrice = 0,
    this.retailBrackets,
    this.wholesaleBrackets,
    required this.imageUrl,
    required this.category,
    this.stockQuantity = 0,
    this.unit = 'kg',
    this.discountPercentage = 0.0,
    this.promoStartDate,
    this.promoEndDate,
    this.promoTarget = PromoTarget.both,
    this.promoCustomerTarget = PromoCustomerTarget.all,
    this.targetCustomerId,
    this.isDeleted = false,
    this.isUnlimited = false,
    this.lowStockThreshold = 5.0, // Default threshold
    this.dailyStockAdded = 0.0,
    this.lastStockUpdate,
  });

  /// Logic to check if promotion is currently scheduled correctly by date
  bool get isPromoScheduled {
    if (discountPercentage <= 0) return false;
    if (promoStartDate == null || promoEndDate == null) return true;
    
    final now = DateTime.now();
    return !now.isBefore(promoStartDate!) && now.isBefore(promoEndDate!.add(const Duration(days: 1)));
  }

  /// Check if promo is active for a specific mode and customer
  bool isPromoActiveFor(bool isWholesale, Customer? customer, {bool ignoreCustomerFilter = false}) {
    if (!isPromoScheduled) return false;
    
    // Check mode target
    bool modeMatch = false;
    if (promoTarget == PromoTarget.both) {
      modeMatch = true;
    } else if (isWholesale) {
      modeMatch = (promoTarget == PromoTarget.wholesale);
    } else {
      modeMatch = (promoTarget == PromoTarget.retail);
    }

    if (!modeMatch) return false;

    // Check customer target
    if (ignoreCustomerFilter || promoCustomerTarget == PromoCustomerTarget.all) return true;
    if (customer == null) return false;

    switch (promoCustomerTarget) {
      case PromoCustomerTarget.all:
        return true;
      case PromoCustomerTarget.regularsOnly:
        return customer.isFavorite;
      case PromoCustomerTarget.specialOnly:
        return customer.isSpecial;
      case PromoCustomerTarget.specificPerson:
        return targetCustomerId != null && customer.id == targetCustomerId;
    }
  }

  /// Helper to get price based on mode, weight, and active discount
  double getPrice(bool isWholesale, {double? weight, Customer? customer, bool ignoreCustomerFilter = false}) {
    final brackets = isWholesale ? wholesaleBrackets : retailBrackets;
    double currentPrice = isWholesale ? wholesalePrice : retailPrice;
    
    if (weight != null && brackets != null && brackets.isNotEmpty) {
      for (var bracket in brackets) {
        if (weight >= bracket.minWeight && weight <= bracket.maxWeight) {
          currentPrice = bracket.price;
          break;
        }
      }
    }

    if (isPromoActiveFor(isWholesale, customer, ignoreCustomerFilter: ignoreCustomerFilter)) {
      return currentPrice * (1 - (discountPercentage / 100));
    }
    return currentPrice;
  }

  Product copyWith({
    String? name,
    String? branchCode,
    double? retailPrice,
    double? wholesalePrice,
    double? costPrice,
    double? stockQuantity,
    double? discountPercentage,
    DateTime? promoStartDate,
    DateTime? promoEndDate,
    PromoTarget? promoTarget,
    PromoCustomerTarget? promoCustomerTarget,
    String? targetCustomerId,
    String? category,
    String? unit,
    String? imageUrl,
    bool? isDeleted,
    bool? isUnlimited,
    double? lowStockThreshold,
    double? dailyStockAdded,
    DateTime? lastStockUpdate,
  }) {
    return Product(
      id: id,
      branchCode: branchCode ?? this.branchCode,
      name: name ?? this.name,
      retailPrice: retailPrice ?? this.retailPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      costPrice: costPrice ?? this.costPrice,
      retailBrackets: retailBrackets,
      wholesaleBrackets: wholesaleBrackets,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      unit: unit ?? this.unit,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      promoStartDate: promoStartDate ?? this.promoStartDate,
      promoEndDate: promoEndDate ?? this.promoEndDate,
      promoTarget: promoTarget ?? this.promoTarget,
      promoCustomerTarget: promoCustomerTarget ?? this.promoCustomerTarget,
      targetCustomerId: targetCustomerId ?? this.targetCustomerId,
      isDeleted: isDeleted ?? this.isDeleted,
      isUnlimited: isUnlimited ?? this.isUnlimited,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      dailyStockAdded: dailyStockAdded ?? this.dailyStockAdded,
      lastStockUpdate: lastStockUpdate ?? this.lastStockUpdate,
    );
  }

  factory Product.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json as Map);
    
    PromoTarget safePromoTarget(String? target) {
      if (target == null || target.isEmpty) return PromoTarget.both;
      try {
        return PromoTarget.values.byName(target.toLowerCase());
      } catch (_) {
        return PromoTarget.both;
      }
    }

    PromoCustomerTarget safeCustomerTarget(String? target) {
      if (target == null || target.isEmpty) return PromoCustomerTarget.all;
      try {
        return PromoCustomerTarget.values.byName(target);
      } catch (_) {
        return PromoCustomerTarget.all;
      }
    }

    DateTime? safeParseDate(dynamic val) {
      if (val == null) return null;
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return null;
      }
    }

    return Product(
      id: map['id']?.toString() ?? '',
      branchCode: map['branch_code']?.toString(),
      name: map['name']?.toString() ?? 'Unnamed Product',
      retailPrice: (map['retail_price'] as num? ?? 0.0).toDouble(),
      wholesalePrice: (map['wholesale_price'] as num? ?? 0.0).toDouble(),
      costPrice: (map['cost_price'] as num? ?? 0.0).toDouble(),
      retailBrackets: (map['retail_brackets'] as List?)
          ?.map((e) => PriceBracket.fromJson(e))
          .toList(),
      wholesaleBrackets: (map['wholesale_brackets'] as List?)
          ?.map((e) => PriceBracket.fromJson(e))
          .toList(),
      imageUrl: map['image_url']?.toString() ?? '',
      category: map['category']?.toString() ?? 'General',
      stockQuantity: (map['stock_quantity'] as num? ?? 0.0).toDouble(),
      unit: map['unit']?.toString() ?? 'kg',
      discountPercentage: (map['discount_percentage'] as num? ?? 0.0).toDouble(),
      promoStartDate: safeParseDate(map['promo_start']),
      promoEndDate: safeParseDate(map['promo_end']),
      promoTarget: safePromoTarget(map['promo_target']?.toString()),
      promoCustomerTarget: safeCustomerTarget(map['promo_customer_target']?.toString()),
      targetCustomerId: map['target_customer_id']?.toString(),
      isDeleted: map['is_deleted'] == true,
      isUnlimited: map['is_unlimited'] == true,
      lowStockThreshold: (map['low_stock_threshold'] as num? ?? 5.0).toDouble(),
      dailyStockAdded: (map['daily_stock_added'] as num? ?? 0.0).toDouble(),
      lastStockUpdate: safeParseDate(map['last_stock_update']),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'branch_code': branchCode,
      'name': name,
      'retail_price': retailPrice,
      'wholesale_price': wholesalePrice,
      'cost_price': costPrice,
      'retail_brackets': retailBrackets?.map((e) => e.toJson()).toList(),
      'wholesale_brackets': wholesaleBrackets?.map((e) => e.toJson()).toList(),
      'image_url': imageUrl,
      'category': category,
      'stock_quantity': stockQuantity,
      'unit': unit,
      'discount_percentage': discountPercentage,
      'promo_start': promoStartDate?.toIso8601String(),
      'promo_end': promoEndDate?.toIso8601String(),
      'promo_target': promoTarget.name,
      'promo_customer_target': promoCustomerTarget.name,
      'is_deleted': isDeleted,
      'is_unlimited': isUnlimited,
      'low_stock_threshold': lowStockThreshold,
      'daily_stock_added': dailyStockAdded,
      'last_stock_update': lastStockUpdate?.toIso8601String(),
    };
    if (targetCustomerId != null) {
      map['target_customer_id'] = targetCustomerId;
    }
    return map;
  }
}

class CartItem {
  final Product product;
  final double quantity;
  final double priceAtSale;
  final double originalPrice;
  final String? selectedUnit;

  CartItem({
    required this.product, 
    required this.quantity,
    required this.priceAtSale,
    required this.originalPrice,
    this.selectedUnit,
  });

  double get total => priceAtSale * quantity;
  double get discount => (originalPrice - priceAtSale) * quantity;
}

class ProductActivityReportData {
  final Product product;
  final double totalIntakeQty;
  final List<StockHistory> intakeEntries;
  final DateTime? lastIntakeDate;
  final double totalQtySold;
  final double totalRevenue;
  final List<Map<String, dynamic>> salesBreakdown;
  final double remainingStock;

  ProductActivityReportData({
    required this.product,
    required this.totalIntakeQty,
    required this.intakeEntries,
    this.lastIntakeDate,
    required this.totalQtySold,
    required this.totalRevenue,
    required this.salesBreakdown,
    required this.remainingStock,
  });
}
