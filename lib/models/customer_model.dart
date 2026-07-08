class Customer {
  final String id;
  final String? branchCode;
  final String name;
  final String phone;
  final String? location;
  final bool isFavorite;
  final double loyaltyPoints;
  final int visitCount;
  final bool isDeleted;

  Customer({
    required this.id,
    this.branchCode,
    required this.name,
    required this.phone,
    this.location,
    this.isFavorite = false,
    this.loyaltyPoints = 0.0,
    this.visitCount = 0,
    this.isDeleted = false,
  });

  Customer copyWith({
    String? id,
    String? branchCode,
    String? name,
    String? phone,
    String? location,
    bool? isFavorite,
    double? loyaltyPoints,
    int? visitCount,
    bool? isDeleted,
  }) {
    return Customer(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      isFavorite: isFavorite ?? this.isFavorite,
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
      location: map['location'],
      isFavorite: map['is_favorite'] ?? false,
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
      'location': location,
      'is_favorite': isFavorite,
      'loyalty_points': loyaltyPoints,
      'visit_count': visitCount,
      'is_deleted': isDeleted,
    };
  }
}
