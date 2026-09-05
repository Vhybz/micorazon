import 'sale_model.dart';

class AuditLog {
  final String id;
  final String? branchCode;
  final String? userId;
  final String? userName;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final DateTime timestamp;

  AuditLog({
    required this.id,
    this.branchCode,
    this.userId,
    this.userName,
    required this.action,
    required this.entityType,
    this.entityId,
    this.oldData,
    this.newData,
    required this.timestamp,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'],
      branchCode: json['branch_code'],
      userId: json['user_id'],
      userName: json['user_name'],
      action: json['action'],
      entityType: json['entity_type'],
      entityId: json['entity_id'],
      oldData: json['old_data'],
      newData: json['new_data'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'user_id': userId,
    'user_name': userName,
    'action': action,
    'entity_type': entityType,
    'entity_id': entityId,
    'old_data': oldData,
    'new_data': newData,
    'timestamp': timestamp.toIso8601String(),
  };
}

class SystemNotification {
  final String id;
  final String? branchCode;
  final String? userId;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  SystemNotification({
    required this.id,
    this.branchCode,
    this.userId,
    required this.title,
    required this.message,
    this.type = 'info',
    this.isRead = false,
    required this.createdAt,
  });

  factory SystemNotification.fromJson(Map<String, dynamic> json) {
    return SystemNotification(
      id: json['id'],
      branchCode: json['branch_code'],
      userId: json['user_id'],
      title: json['title'],
      message: json['message'],
      type: json['type'] ?? 'info',
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'user_id': userId,
    'title': title,
    'message': message,
    'type': type,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
  };
}

class CustomerPayment {
  final String id;
  final String? branchCode;
  final String customerId;
  final double amount;
  final PaymentMethod method;
  final String? reference;
  final String? saleId;
  final String? collectedBy;
  final DateTime paymentDate;

  CustomerPayment({
    required this.id,
    this.branchCode,
    required this.customerId,
    required this.amount,
    required this.method,
    this.reference,
    this.saleId,
    this.collectedBy,
    required this.paymentDate,
  });

  factory CustomerPayment.fromJson(Map<String, dynamic> json) {
    return CustomerPayment(
      id: json['id'],
      branchCode: json['branch_code'],
      customerId: json['customer_id'],
      amount: (json['amount'] as num).toDouble(),
      method: PaymentMethod.values.byName(json['payment_method']),
      reference: json['reference'],
      saleId: json['sale_id'],
      collectedBy: json['collected_by'],
      paymentDate: DateTime.parse(json['payment_date']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'customer_id': customerId,
    'amount': amount,
    'payment_method': method.name,
    'reference': reference,
    'sale_id': saleId,
    'collected_by': collectedBy,
    'payment_date': paymentDate.toIso8601String(),
  };
}

class StockHistory {
  final String id;
  final String? branchCode;
  final String productId;
  final double changeAmount;
  final double newQuantity;
  final String reason;
  final String? referenceId;
  final DateTime timestamp;

  StockHistory({
    required this.id,
    this.branchCode,
    required this.productId,
    required this.changeAmount,
    required this.newQuantity,
    required this.reason,
    this.referenceId,
    required this.timestamp,
  });

  factory StockHistory.fromJson(Map<String, dynamic> json) {
    return StockHistory(
      id: json['id'],
      branchCode: json['branch_code'],
      productId: json['product_id'],
      changeAmount: (json['change_amount'] as num).toDouble(),
      newQuantity: (json['new_quantity'] as num).toDouble(),
      reason: json['reason'],
      referenceId: json['reference_id'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'branch_code': branchCode,
    'product_id': productId,
    'change_amount': changeAmount,
    'new_quantity': newQuantity,
    'reason': reason,
    'reference_id': referenceId,
    'timestamp': timestamp.toIso8601String(),
  };
}

enum TillMovementType { cashIn, cashOut, openingBalance, closure }

class TillMovement {
  final String id;
  final String title;
  final String description;
  final double amount;
  final DateTime timestamp;
  final TillMovementType type;
  final String? userName;
  final double runningBalance;

  TillMovement({
    required this.id,
    required this.title,
    required this.description,
    required this.amount,
    required this.timestamp,
    required this.type,
    this.userName,
    this.runningBalance = 0,
  });
}
