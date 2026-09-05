import 'dart:convert';

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

  // Helpers for External Workers
  bool get isExternal => userId == 'EXTERNAL';

  Map<String, dynamic>? get _externalData {
    if (!isExternal || note == null) return null;
    try {
      final decoded = json.decode(note!);
      if (decoded is Map<String, dynamic> && decoded.containsKey('external_worker')) {
        return decoded['external_worker'];
      }
    } catch (_) {}
    return null;
  }

  String? get externalName => _externalData?['name'];
  String? get externalPhone => _externalData?['phone'];
  String? get externalEmail => _externalData?['email'];
  String? get externalPhotoUrl => _externalData?['photo_url'];
  double? get externalBaseSalary => _externalData?['base_salary'] != null ? double.tryParse(_externalData?['base_salary'].toString() ?? '') : null;
  int? get externalPayDay => _externalData?['pay_day'] != null ? int.tryParse(_externalData?['pay_day'].toString() ?? '') : null;

  String? get displayNote {
    if (!isExternal || note == null) return note;
    try {
      final decoded = json.decode(note!);
      return decoded['user_note'];
    } catch (_) {
      return note;
    }
  }

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

  SalaryRecord copyWith({
    String? id,
    String? userId,
    double? amount,
    bool? isAdvance,
    DateTime? date,
    DateTime? targetMonth,
    String? note,
  }) {
    return SalaryRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      isAdvance: isAdvance ?? this.isAdvance,
      date: date ?? this.date,
      targetMonth: targetMonth ?? this.targetMonth,
      note: note ?? this.note,
    );
  }
}
