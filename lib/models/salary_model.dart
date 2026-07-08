class SalaryRecord {
  final String id;
  final String userId;
  final double amount;
  final bool isAdvance;
  final DateTime date;
  final String? note;

  SalaryRecord({
    required this.id,
    required this.userId,
    required this.amount,
    required this.isAdvance,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'amount': amount,
    'is_advance': isAdvance,
    'date': date.toIso8601String(),
    'note': note,
  };

  factory SalaryRecord.fromJson(Map<String, dynamic> json) => SalaryRecord(
    id: json['id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    amount: (json['amount'] as num).toDouble(),
    isAdvance: json['is_advance'] ?? false,
    date: DateTime.parse(json['date']),
    note: json['note'],
  );
}
