enum SlaughterStatus { pending, slaughtering, cleaned, completed, processed }

enum MeatBatchStatus { 
  transporting, 
  received, 
  preparing, 
  mincing, 
  cutting, 
  packaging, 
  frozen, 
  completed 
}

class ChickenRange {
  final double minWeight;
  final double maxWeight;
  final double price;

  ChickenRange({required this.minWeight, required this.maxWeight, required this.price});

  String get label => '$minWeight - $maxWeight LB';
  double get averageWeight => (minWeight + maxWeight) / 2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChickenRange &&
          runtimeType == other.runtimeType &&
          minWeight == other.minWeight &&
          maxWeight == other.maxWeight &&
          price == other.price;

  @override
  int get hashCode => minWeight.hashCode ^ maxWeight.hashCode ^ price.hashCode;
}

enum AnimalType { cow, bull, pig, sheep, goat, hardChicken, softChicken, turkey, rabbit }

extension AnimalTypeX on AnimalType {
  String get displayName {
    switch (this) {
      case AnimalType.hardChicken: return 'HARD CHICKEN (LAYER)';
      case AnimalType.softChicken: return 'SOFT CHICKEN (BROILER)';
      default: return name.toUpperCase();
    }
  }

  List<ChickenRange> get chickenRanges {
    if (this == AnimalType.softChicken) {
      return [
        ChickenRange(minWeight: 3.0, maxWeight: 4.0, price: 140),
        ChickenRange(minWeight: 4.1, maxWeight: 5.0, price: 165),
        ChickenRange(minWeight: 5.1, maxWeight: 6.0, price: 170),
        ChickenRange(minWeight: 6.1, maxWeight: 7.0, price: 180),
      ];
    } else if (this == AnimalType.hardChicken) {
      return [
        ChickenRange(minWeight: 1.5, maxWeight: 1.9, price: 95),
        ChickenRange(minWeight: 2.0, maxWeight: 2.3, price: 100),
        ChickenRange(minWeight: 2.4, maxWeight: 2.8, price: 110),
      ];
    }
    return [];
  }

  String get shortCode {
    switch (this) {
      case AnimalType.cow: return 'CW'; // Changed from BF to CW
      case AnimalType.bull: return 'BL';
      case AnimalType.pig: return 'PK'; // Pork
      case AnimalType.sheep: return 'SH';
      case AnimalType.goat: return 'GT';
      case AnimalType.hardChicken: return 'CH-H';
      case AnimalType.softChicken: return 'CH-S';
      case AnimalType.turkey: return 'TK';
      case AnimalType.rabbit: return 'RB';
    }
  }

  /// Typical dressing percentage for various animals
  double get dressingPercentage {
    switch (this) {
      case AnimalType.cow: return 0.62;
      case AnimalType.bull: return 0.60;
      case AnimalType.pig: return 0.74;
      case AnimalType.sheep: return 0.50;
      case AnimalType.goat: return 0.48;
      case AnimalType.hardChicken: return 0.70;
      case AnimalType.softChicken: return 0.72;
      case AnimalType.turkey: return 0.78;
      case AnimalType.rabbit: return 0.55;
    }
  }

  List<String> get standardCuts {
    switch (this) {
      case AnimalType.cow:
      case AnimalType.bull:
        return [
          'Standard Meat',
          'Boneless',
          'Offals / Yemadeɛ',
          'Cow Steak',
          'Liver & Lungs',
          'Grounded Meat',
          'Feet',
          'Head',
          'Tail / Padua',
        ];
      case AnimalType.pig:
        return [
          'Standard Meat',
          'Boneless Meat',
          'Offals / Yemadeɛ',
          'Pork Steak',
          'Head',
          'Ear',
          'Feet',
          'Liver',
          'Skin',
        ];
      case AnimalType.goat:
      case AnimalType.sheep:
        return [
          'Standard Meat',
          'Boneless',
          'Offals / Yemadeɛ',
          'Head',
          'Feet',
        ];
      case AnimalType.hardChicken:
        return [
          'Hard Whole Chicken (Layer)',
          'Hard Thigh (Layer)',
          'Hard Breast (Layer)',
          'Hard Back (Layer)',
          'Hard Wings (Layer)',
          'Hard Drumsticks (Layer)',
          'Gizzard',
        ];
      case AnimalType.softChicken:
        return [
          'Soft Whole Chicken (Broiler)',
          'Soft Thigh (Broiler)',
          'Soft Breast (Broiler)',
          'Soft Back (Broiler)',
          'Soft Wings (Broiler)',
          'Soft Drumsticks (Broiler)',
          'Gizzard',
        ];
      case AnimalType.turkey:
        return ['Whole Turkey', 'Breast', 'Thighs', 'Drumsticks', 'Wings', 'Gizzards', 'Feet'];
      case AnimalType.rabbit:
        return ['Whole Rabbit', 'Legs', 'Saddle', 'Shoulders'];
    }
  }

  String defaultUnitFor(String cut) {
    if (cut == 'Head' && (this == AnimalType.goat || this == AnimalType.sheep)) {
      return 'Qty';
    }
    return 'kg';
  }

  double? defaultValueFor(String cut) {
    if (cut == 'Head' && (this == AnimalType.goat || this == AnimalType.sheep)) {
      return 1.0;
    }
    return null;
  }
}

class SlaughterLog {
  final String id;
  final String? branchCode;
  final String animalId; // Database UUID
  final String? tagNumber; // Human-readable ID (Auto-generated)
  final String? manualFarmTag; // Optional manual farm tag from the farm
  final AnimalType type;
  final int quantity; // Added for batches (e.g. Chicken)
  final double liveWeight;
  final double meatWeight;
  final double price; // Selling price (Standard)
  final double? farmPrice; // Optional cost price from the farm
  final DateTime? slaughterTime;
  final SlaughterStatus status;
  final String? chickenRangeLabel; // Added for whole chicken stock mapping
  final String? sourceFarm; // Added for editing support
  final String? slaughteredBy;
  final String? portionedBy;

  SlaughterLog({
    required this.id,
    this.branchCode,
    required this.animalId,
    this.tagNumber,
    this.manualFarmTag,
    required this.type,
    this.quantity = 1,
    required this.liveWeight,
    required this.meatWeight,
    required this.price,
    this.farmPrice,
    this.slaughterTime,
    required this.status,
    this.chickenRangeLabel,
    this.sourceFarm,
    this.slaughteredBy,
    this.portionedBy,
  });

  double get weightLoss => liveWeight - meatWeight;
  double get yieldPercentage => liveWeight > 0 ? (meatWeight / liveWeight) * 100 : 0;

  // Profit calculation logic: If farmPrice is null, full price is profit.
  double get estimatedProfit => price - (farmPrice ?? 0.0);

  // Compatibility getters
  double get weight => liveWeight;
  double get estimatedYield => meatWeight;

  SlaughterLog copyWith({
    String? id,
    String? branchCode,
    String? animalId,
    String? tagNumber,
    String? manualFarmTag,
    AnimalType? type,
    int? quantity,
    double? liveWeight,
    double? meatWeight,
    double? price,
    double? farmPrice,
    DateTime? slaughterTime,
    SlaughterStatus? status,
    String? chickenRangeLabel,
    String? sourceFarm,
    String? slaughteredBy,
    String? portionedBy,
  }) {
    return SlaughterLog(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      animalId: animalId ?? this.animalId,
      tagNumber: tagNumber ?? this.tagNumber,
      manualFarmTag: manualFarmTag ?? this.manualFarmTag,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      liveWeight: liveWeight ?? this.liveWeight,
      meatWeight: meatWeight ?? this.meatWeight,
      price: price ?? this.price,
      farmPrice: farmPrice ?? this.farmPrice,
      slaughterTime: slaughterTime ?? this.slaughterTime,
      status: status ?? this.status,
      chickenRangeLabel: chickenRangeLabel ?? this.chickenRangeLabel,
      sourceFarm: sourceFarm ?? this.sourceFarm,
      slaughteredBy: slaughteredBy ?? this.slaughteredBy,
      portionedBy: portionedBy ?? this.portionedBy,
    );
  }

  factory SlaughterLog.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return SlaughterLog(
      id: map['id'] as String,
      branchCode: map['branch_code'] as String?,
      animalId: map['animal_id'] as String,
      tagNumber: map['tag_number'] as String?,
      manualFarmTag: map['manual_farm_tag'] as String?,
      type: AnimalType.values.firstWhere((e) => e.name == map['type']),
      quantity: map['quantity'] as int? ?? 1,
      liveWeight: (map['initial_weight'] as num).toDouble(),
      meatWeight: (map['carcass_weight'] as num? ?? 0).toDouble(),
      price: (map['price'] as num? ?? 0).toDouble(),
      farmPrice: (map['farm_price'] as num?)?.toDouble(),
      slaughterTime: map['slaughter_time'] != null ? DateTime.parse(map['slaughter_time'] as String) : null,
      status: SlaughterStatus.values.firstWhere((e) => e.name == map['status']),
      chickenRangeLabel: map['chicken_range_label'] as String?,
      sourceFarm: map['source_farm'] as String?,
      slaughteredBy: map['slaughtered_by'] as String?,
      portionedBy: map['portioned_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'animal_id': animalId,
    'tag_number': tagNumber,
    'manual_farm_tag': manualFarmTag,
    'type': type.name,
    'quantity': quantity,
    'initial_weight': liveWeight,
    'carcass_weight': meatWeight,
    'price': price,
    'farm_price': farmPrice,
    'slaughter_time': slaughterTime?.toIso8601String(),
    'status': status.name,
    'chicken_range_label': chickenRangeLabel,
    'source_farm': sourceFarm,
    'slaughtered_by': slaughteredBy,
    'portioned_by': portionedBy,
  };
}

class BatchSource {
  final String name;
  final String location;
  final String owner;

  BatchSource({required this.name, required this.location, required this.owner});

  factory BatchSource.empty() => BatchSource(name: '', location: '', owner: '');
}

class MeatBatch {
  final String id;
  final String? branchCode;
  final String? animalId;
  final String meatType;
  final double weight;
  final double costPrice;
  final DateTime createdAt;
  final String status;
  final BatchSource source;
  final String? inspectedBy;
  final String? receivedBy;
  final String? portionedBy;

  MeatBatch({
    required this.id,
    this.branchCode,
    this.animalId,
    required this.meatType,
    required this.weight,
    this.costPrice = 0.0,
    required this.createdAt,
    required this.status,
    required this.source,
    this.inspectedBy,
    this.receivedBy,
    this.portionedBy,
  });

  MeatBatch copyWith({
    String? id,
    String? branchCode,
    String? animalId,
    String? meatType,
    double? weight,
    double? costPrice,
    DateTime? createdAt,
    String? status,
    BatchSource? source,
    String? inspectedBy,
    String? receivedBy,
    String? portionedBy,
  }) {
    return MeatBatch(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      animalId: animalId ?? this.animalId,
      meatType: meatType ?? this.meatType,
      weight: weight ?? this.weight,
      costPrice: costPrice ?? this.costPrice,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      source: source ?? this.source,
      inspectedBy: inspectedBy ?? this.inspectedBy,
      receivedBy: receivedBy ?? this.receivedBy,
      portionedBy: portionedBy ?? this.portionedBy,
    );
  }

  factory MeatBatch.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return MeatBatch(
      id: map['id'] as String,
      branchCode: map['branch_code'] as String?,
      animalId: map['animal_id'] as String?,
      meatType: map['meat_type'] as String,
      weight: (map['initial_weight'] as num).toDouble(),
      costPrice: (map['cost_price'] as num? ?? 0.0).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      status: map['status'] as String,
      source: BatchSource(
        name: map['source_name'] ?? '',
        location: map['source_location'] ?? '',
        owner: map['owner_name'] ?? '',
      ),
      inspectedBy: map['inspected_by'] as String?,
      receivedBy: map['received_by'] as String?,
      portionedBy: map['portioned_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'animal_id': animalId,
    'meat_type': meatType,
    'initial_weight': weight,
    'current_weight': weight,
    'cost_price': costPrice,
    'status': status,
    'source_name': source.name,
    'source_location': source.location,
    'owner_name': source.owner,
    'inspected_by': inspectedBy,
    'received_by': receivedBy,
    'portioned_by': portionedBy,
    'created_at': createdAt.toIso8601String(),
  };
}

class MeatCut {
  final String id;
  final String? branchCode;
  final String name;
  final String? meatType;
  final String batchId;
  final double weight;
  final String unit; // Added for 'kg' vs 'Qty' support
  final DateTime processedAt;

  MeatCut({
    required this.id,
    this.branchCode,
    required this.name,
    this.meatType,
    required this.batchId,
    required this.weight,
    this.unit = 'kg', // Default to kg
    required this.processedAt,
  });

  MeatCut copyWith({
    String? id,
    String? branchCode,
    String? name,
    String? meatType,
    String? batchId,
    double? weight,
    String? unit,
    DateTime? processedAt,
  }) {
    return MeatCut(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      name: name ?? this.name,
      meatType: meatType ?? this.meatType,
      batchId: batchId ?? this.batchId,
      weight: weight ?? this.weight,
      unit: unit ?? this.unit,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  factory MeatCut.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return MeatCut(
      id: map['id'] as String,
      branchCode: map['branch_code'] as String?,
      name: map['name'] as String,
      meatType: map['meat_type'] as String?,
      batchId: map['batch_id'] as String,
      weight: (map['weight'] as num).toDouble(),
      unit: map['unit']?.toString() ?? 'kg',
      processedAt: DateTime.parse(map['processed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'batch_id': batchId,
    'name': name,
    'meat_type': meatType,
    'weight': weight,
    'unit': unit,
    'processed_at': processedAt.toIso8601String(),
  };
}

enum ButcherOrderStatus { pending, preparing, ready, completed }

class ButcherOrder {
  final String id;
  final String? branchCode;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final List<String> items;
  final double totalWeight;
  final DateTime dueDate;
  final ButcherOrderStatus status;

  ButcherOrder({
    required this.id,
    this.branchCode,
    this.customerId,
    required this.customerName,
    this.customerPhone,
    required this.items,
    required this.totalWeight,
    required this.dueDate,
    required this.status,
  });

  ButcherOrder copyWith({
    String? id,
    String? branchCode,
    String? customerId,
    String? customerName,
    String? customerPhone,
    List<String>? items,
    double? totalWeight,
    DateTime? dueDate,
    ButcherOrderStatus? status,
  }) {
    return ButcherOrder(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      items: items ?? this.items,
      totalWeight: totalWeight ?? this.totalWeight,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
    );
  }

  factory ButcherOrder.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return ButcherOrder(
      id: map['id'] as String,
      branchCode: map['branch_code'] as String?,
      customerId: map['customer_id'] as String?,
      customerName: map['customer_name'] as String,
      customerPhone: map['customer_phone'] as String?,
      items: List<String>.from(map['items'] ?? []),
      totalWeight: (map['total_weight'] as num).toDouble(),
      dueDate: DateTime.parse(map['due_date'] as String),
      status: ButcherOrderStatus.values.firstWhere((e) => e.name == map['status']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'customer_id': customerId,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'items': items,
    'total_weight': totalWeight,
    'due_date': dueDate.toIso8601String(),
    'status': status.name,
  };
}
