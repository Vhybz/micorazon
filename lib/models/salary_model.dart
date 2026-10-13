import 'dart:convert';

enum SalaryPaymentCategory { salary, advance, loan, loanRepayment }

class SalaryRecord {
  final String id;
  final String userId;
  final double amount;
  final bool isAdvance;
  final bool isLoan;
  final bool isLoanRepayment;
  final DateTime date;
  final DateTime targetMonth;
  final String? note;

  SalaryRecord({
    required this.id,
    required this.userId,
    required this.amount,
    required this.isAdvance,
    this.isLoan = false,
    this.isLoanRepayment = false,
    required this.date,
    required this.targetMonth,
    this.note,
  });

  SalaryPaymentCategory get paymentCategory {
    if (isLoan) return SalaryPaymentCategory.loan;
    if (isLoanRepayment) return SalaryPaymentCategory.loanRepayment;
    if (isAdvance) return SalaryPaymentCategory.advance;
    return SalaryPaymentCategory.salary;
  }

  String get categoryLabel {
    switch (paymentCategory) {
      case SalaryPaymentCategory.loan:
        return 'LOAN';
      case SalaryPaymentCategory.loanRepayment:
        return 'LOAN REPAYMENT';
      case SalaryPaymentCategory.advance:
        return 'SALARY ADVANCE';
      case SalaryPaymentCategory.salary:
        return 'SALARY';
    }
  }

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
    if (note == null) return null;
    try {
      final decoded = json.decode(note!);
      if (decoded is Map<String, dynamic> && decoded.containsKey('user_note')) {
        return decoded['user_note'];
      }
    } catch (_) {}
    return note;
  }

  Map<String, dynamic> toJson() {
    String? finalNote = note;
    if (isLoan || isLoanRepayment) {
      try {
        final existing = (note != null && note!.startsWith('{')) ? json.decode(note!) : {'user_note': note};
        existing['is_loan'] = isLoan;
        existing['is_loan_repayment'] = isLoanRepayment;
        finalNote = json.encode(existing);
      } catch (_) {}
    }
    
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'is_advance': isAdvance,
      'is_loan': isLoan,
      'is_loan_repayment': isLoanRepayment,
      'date': date.toIso8601String(),
      'target_month': targetMonth.toIso8601String(),
      'note': finalNote,
    };
  }

  factory SalaryRecord.fromJson(Map<String, dynamic> json) {
    bool rawLoan = json['is_loan'] == true;
    bool rawRepayment = json['is_loan_repayment'] == true;
    
    if (!rawLoan && !rawRepayment && json['note'] != null) {
      try {
        final decoded = jsonDecode(json['note'].toString());
        if (decoded is Map<String, dynamic>) {
          if (decoded['is_loan'] == true) rawLoan = true;
          if (decoded['is_loan_repayment'] == true) rawRepayment = true;
        }
      } catch (_) {}
    }

    return SalaryRecord(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      isAdvance: json['is_advance'] == true,
      isLoan: rawLoan,
      isLoanRepayment: rawRepayment,
      date: DateTime.parse(json['date']),
      targetMonth: json['target_month'] != null 
          ? DateTime.parse(json['target_month']) 
          : DateTime.parse(json['date']),
      note: json['note'],
    );
  }

  SalaryRecord copyWith({
    String? id,
    String? userId,
    double? amount,
    bool? isAdvance,
    bool? isLoan,
    bool? isLoanRepayment,
    DateTime? date,
    DateTime? targetMonth,
    String? note,
  }) {
    return SalaryRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      isAdvance: isAdvance ?? this.isAdvance,
      isLoan: isLoan ?? this.isLoan,
      isLoanRepayment: isLoanRepayment ?? this.isLoanRepayment,
      date: date ?? this.date,
      targetMonth: targetMonth ?? this.targetMonth,
      note: note ?? this.note,
    );
  }
}
