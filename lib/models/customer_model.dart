class Customer {
  final String id;
  final String? branchCode;
  final String name;
  final String phone;
  final String? phone2;
  final String? location;
  final bool isFavorite;
  final double loyaltyPoints;
  final int visitCount;
  final bool isBulkPurchaser;
  final bool isWholesaler;
  final bool isDeleted;

  Customer({
    required this.id,
    this.branchCode,
    required this.name,
    required this.phone,
    this.phone2,
    this.location,
    this.isFavorite = false,
    this.isBulkPurchaser = false,
    this.isWholesaler = false,
    this.loyaltyPoints = 0.0,
    this.visitCount = 0,
    this.isDeleted = false,
  });

  Customer copyWith({
    String? id,
    String? branchCode,
    String? name,
    String? phone,
    String? phone2,
    String? location,
    bool? isFavorite,
    bool? isBulkPurchaser,
    bool? isWholesaler,
    double? loyaltyPoints,
    int? visitCount,
    bool? isDeleted,
  }) {
    return Customer(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      phone2: phone2 ?? this.phone2,
      location: location ?? this.location,
      isFavorite: isFavorite ?? this.isFavorite,
      isBulkPurchaser: isBulkPurchaser ?? this.isBulkPurchaser,
      isWholesaler: isWholesaler ?? this.isWholesaler,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      visitCount: visitCount ?? this.visitCount,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  factory Customer.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    return Customer(
      id: map['id'],
      branchCode: map['branch_code'],
      name: map['name'],
      phone: map['phone'],
      phone2: map['phone2'],
      location: map['location'],
      isFavorite: map['is_favorite'] ?? false,
      isBulkPurchaser: map['is_bulk_purchaser'] ?? false,
      isWholesaler: map['is_wholesaler'] ?? false,
      loyaltyPoints: (map['loyalty_points'] as num? ?? 0.0).toDouble(),
      visitCount: map['visit_count'] ?? 0,
      isDeleted: map['is_deleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branch_code': branchCode,
      'name': name,
      'phone': phone,
      'phone2': phone2,
      'location': location,
      'is_favorite': isFavorite,
      'is_bulk_purchaser': isBulkPurchaser,
      'is_wholesaler': isWholesaler,
      'loyalty_points': loyaltyPoints,
      'visit_count': visitCount,
      'is_deleted': isDeleted,
    };
  }
}
