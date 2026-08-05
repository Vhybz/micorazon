class SalaryRecord {
  final String id;
  final String userId;
  final double amount;
  final bool isAdvance;
  final DateTime date;
  final DateTime targetMonth;
  final String? note;

  SalaryRecord({
    required this.id,
    required this.userId,
    required this.amount,
    required this.isAdvance,
    required this.date,
    required this.targetMonth,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'amount': amount,
    'is_advance': isAdvance,
    'date': date.toIso8601String(),
    'target_month': targetMonth.toIso8601String(),
    'note': note,
  };

  factory SalaryRecord.fromJson(Map<String, dynamic> json) => SalaryRecord(
    id: json['id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    amount: (json['amount'] as num).toDouble(),
    isAdvance: json['is_advance'] ?? false,
    date: DateTime.parse(json['date']),
    targetMonth: json['target_month'] != null 
        ? DateTime.parse(json['target_month']) 
        : DateTime.parse(json['date']),
    note: json['note'],
  );
}
