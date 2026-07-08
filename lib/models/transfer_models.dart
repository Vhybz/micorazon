enum TransferStatus { pending, received, rejected, awaitingPayment }

class StockTransfer {
  final String id;
  final String? branchCode;
  final String batchId;
  final String meatType;
  final double weight;
  final String unit; // Added for 'kg' vs 'Qty' support
  final String destination;
  final DateTime transferTime;
  final TransferStatus status;
  final bool isThirdParty;
  final bool isPaid;
  final bool isIndividual;
  final String? customerName;
  final String? customerPhone;
  final String? customerLocation;

  StockTransfer({
    required this.id,
    this.branchCode,
    required this.batchId,
    required this.meatType,
    required this.weight,
    this.unit = 'kg', // Default to kg
    required this.destination,
    required this.transferTime,
    this.status = TransferStatus.pending,
    this.isThirdParty = false,
    this.isPaid = false,
    this.isIndividual = false,
    this.customerName,
    this.customerPhone,
    this.customerLocation,
  });

  factory StockTransfer.fromJson(dynamic json) {
    final map = Map<String, dynamic>.from(json);
    TransferStatus safeStatus(String? name) {
      if (name == null) return TransferStatus.pending;
      try {
        return TransferStatus.values.byName(name.trim());
      } catch (_) {
        return TransferStatus.pending;
      }
    }

    return StockTransfer(
      id: map['id']?.toString() ?? '',
      branchCode: map['branch_code']?.toString(),
      batchId: map['batch_id']?.toString() ?? 'DIRECT',
      meatType: map['meat_type']?.toString() ?? 'Unknown Meat',
      weight: double.tryParse(map['weight']?.toString() ?? '0') ?? 0.0,
      unit: map['unit']?.toString() ?? 'kg',
      destination: map['destination']?.toString() ?? 'Unknown',
      transferTime: DateTime.tryParse(map['transfer_time'] ?? '') ?? DateTime.now(),
      status: safeStatus(map['status']?.toString()),
      isThirdParty: map['is_third_party'] == true,
      isPaid: map['is_paid'] == true,
      isIndividual: map['is_individual'] == true,
      customerName: map['customer_name']?.toString(),
      customerPhone: map['customer_phone']?.toString(),
      customerLocation: map['customer_location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branch_code': branchCode,
      'batch_id': batchId,
      'meat_type': meatType,
      'weight': weight,
      'unit': unit,
      'destination': destination,
      'transfer_time': transferTime.toIso8601String(),
      'status': status.name,
      'is_third_party': isThirdParty,
      'is_paid': isPaid,
      'is_individual': isIndividual,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_location': customerLocation,
    };
  }

  StockTransfer copyWith({
    TransferStatus? status,
    bool? isPaid,
    String? destination,
    bool? isIndividual,
    String? customerName,
    String? customerPhone,
    String? customerLocation,
    String? branchCode,
    String? unit,
    double? weight,
  }) {
    return StockTransfer(
      id: id,
      branchCode: branchCode ?? this.branchCode,
      batchId: batchId,
      meatType: meatType,
      weight: weight ?? this.weight,
      unit: unit ?? this.unit,
      destination: destination ?? this.destination,
      transferTime: transferTime,
      status: status ?? this.status,
      isThirdParty: isThirdParty,
      isPaid: isPaid ?? this.isPaid,
      isIndividual: isIndividual ?? this.isIndividual,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerLocation: customerLocation ?? this.customerLocation,
    );
  }
}
