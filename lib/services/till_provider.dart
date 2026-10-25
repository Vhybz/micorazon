import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sale_model.dart';
import '../models/system_models.dart';
import 'sale_provider.dart';
import 'expense_provider.dart';

class DebtCollectionInfo {
  final String customerName;
  final String customerPhone;
  final String invoiceId;
  final double amountPaid;
  final double remainingBalance;
  final bool isFullSettlement;
  final DateTime paymentTime;
  final PaymentMethod paymentMethod;

  DebtCollectionInfo({
    required this.customerName,
    required this.customerPhone,
    required this.invoiceId,
    required this.amountPaid,
    required this.remainingBalance,
    required this.isFullSettlement,
    required this.paymentTime,
    this.paymentMethod = PaymentMethod.cash,
  });
}

class PaymentMethodBreakdown {
  final double physicalCashSales;
  final double physicalCashDebt;
  final double totalPhysicalCash;

  final double momoSales;
  final double momoDebt;
  final double totalMomo;

  final double bankSales;
  final double bankDebt;
  final double totalBank;

  final double totalRevenue;

  PaymentMethodBreakdown({
    required this.physicalCashSales,
    required this.physicalCashDebt,
    required this.totalPhysicalCash,
    required this.momoSales,
    required this.momoDebt,
    required this.totalMomo,
    required this.bankSales,
    required this.bankDebt,
    required this.totalBank,
    required this.totalRevenue,
  });
}

class TillState {
  final List<TillMovement> history;
  final double currentBalance;
  final Map<DateTime, double> pendingByDay;
  final Map<DateTime, List<TillMovement>> closuresByDay;

  TillState({
    required this.history, 
    required this.currentBalance, 
    required this.pendingByDay,
    required this.closuresByDay,
  });
}

class TillNotifier extends StateNotifier<TillState> {
  final Ref ref;

  TillNotifier(this.ref) : super(TillState(history: [], currentBalance: 0, pendingByDay: {}, closuresByDay: {})) {
    // Watch providers to trigger re-compute
    ref.listen(saleHistoryProvider, (prev, next) => _compute());
    ref.listen(expenseProvider, (prev, next) => _compute());
    _compute();
  }

  void _compute() {
    final sales = ref.read(saleHistoryProvider);
    final expenses = ref.read(expenseProvider).records;

    // 1. Extract Payment Movements from Sales (Includes Cash, MoMo, and Bank)
    final List<TillMovement> movements = [];
    for (var sale in sales) {
      if (sale.status == SaleStatus.cancelled || sale.status == SaleStatus.reversed) continue;
      
      for (int i = 0; i < sale.payments.length; i++) {
        final p = sale.payments[i];
        if (p.amount <= 0) continue;

        final pDate = (p.date ?? sale.timestamp).toLocal();
        
        final isDebtRepayment = i > 0 || 
            (p.date != null && !DateUtils.isSameDay(p.date!.toLocal(), sale.timestamp.toLocal())) ||
            (p.reference?.contains('Collection') ?? false);

        final invoiceShort = sale.id.length > 8 ? sale.id.substring(sale.id.length - 8).toUpperCase() : sale.id.toUpperCase();

        final methodLabel = p.method == PaymentMethod.cash 
            ? 'Cash' 
            : (p.method == PaymentMethod.mobileMoney ? 'MoMo' : 'Bank');

        final title = isDebtRepayment ? 'Debt Collection ($methodLabel)' : 'Sale Received ($methodLabel)';
        final description = isDebtRepayment
            ? 'Debt payment by ${sale.customerName ?? "Customer"} for #$invoiceShort ($methodLabel)'
            : 'Invoice #$invoiceShort ($methodLabel)';

        movements.add(TillMovement(
          id: '${sale.id}_p$i',
          title: title,
          description: description,
          amount: p.amount,
          timestamp: pDate,
          type: TillMovementType.cashIn,
          userName: sale.cashierName,
        ));
      }
    }

    // 2. Extract Movements from Expense & Closure Records
    for (var expense in expenses) {
      final isOpeningBalance = expense.category == 'Till Opening Balance';
      final isClosure = expense.category == 'Daily Sales Closure' || expense.category == 'CEO Withdrawal';

      // Only include Till Opening Balances, Daily Sales Closures, and CEO Withdrawals in Till Cash Movements
      if (!isOpeningBalance && !isClosure) continue;
      
      movements.add(TillMovement(
        id: expense.id,
        title: expense.category,
        description: expense.title,
        amount: expense.amount,
        timestamp: expense.date.toLocal(),
        type: isOpeningBalance 
            ? TillMovementType.openingBalance 
            : TillMovementType.closure,
        userName: _extractUserName(expense),
      ));
    }

    // 3. Sort chronologically
    movements.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 4. Calculate Pending Cash and Closures by Day
    final Map<DateTime, double> cashInByDay = {};
    final Map<DateTime, double> cashOutByDay = {};
    final Map<DateTime, List<TillMovement>> closuresByDay = {};

    for (var m in movements) {
      final localTs = m.timestamp.toLocal();
      final date = DateTime(localTs.year, localTs.month, localTs.day);

      if (m.type == TillMovementType.cashIn || m.type == TillMovementType.openingBalance) {
        cashInByDay[date] = (cashInByDay[date] ?? 0.0) + m.amount;
      } else if (m.type == TillMovementType.closure || m.type == TillMovementType.cashOut) {
        cashOutByDay[date] = (cashOutByDay[date] ?? 0.0) + m.amount;
        closuresByDay.putIfAbsent(date, () => []).add(m);
      }
    }

    // Calculate pending unclosed cash per day
    final Map<DateTime, double> pendingByDay = {};
    final allDates = {...cashInByDay.keys, ...cashOutByDay.keys};

    for (var date in allDates) {
      final inAmt = cashInByDay[date] ?? 0.0;
      final outAmt = cashOutByDay[date] ?? 0.0;
      final pending = inAmt - outAmt;
      // Pending cash for a day should not drop below zero
      pendingByDay[date] = pending > 0 ? pending : 0.0;
    }

    // Total shop funds = sum of all pending unclosed cash across all days
    final double currentBalance = pendingByDay.values.fold(0.0, (sum, val) => sum + val);

    // 5. Calculate Running Balance for Till Movement History List
    double runningBalance = 0;
    final List<TillMovement> historyWithBalance = [];
    
    for (var m in movements) {
      if (m.type == TillMovementType.cashIn || m.type == TillMovementType.openingBalance) {
        runningBalance += m.amount;
      } else {
        runningBalance -= m.amount;
      }
      
      historyWithBalance.add(TillMovement(
        id: m.id,
        title: m.title,
        description: m.description,
        amount: m.amount,
        timestamp: m.timestamp,
        type: m.type,
        userName: m.userName,
        runningBalance: runningBalance > 0 ? runningBalance : 0.0,
      ));
    }

    // Sort newest first for history display
    final displayHistory = historyWithBalance.reversed.toList();

    // Sort closure lists by time (newest first for card display)
    for (var list in closuresByDay.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    state = TillState(
      history: displayHistory,
      currentBalance: currentBalance,
      pendingByDay: pendingByDay,
      closuresByDay: closuresByDay,
    );
  }

  String _extractUserName(dynamic expense) {
    final notes = expense.notes ?? "";
    if (notes.contains('Recorded by:')) {
      final match = RegExp(r'Recorded by: (.*)\)').firstMatch(notes);
      return match?.group(1) ?? 'Unknown User';
    }
    return 'Unrecorded';
  }

  static List<DebtCollectionInfo> getDebtCollectionsForDate(
    DateTime targetDate, 
    List<SaleRecord> salesHistory, {
    bool cashOnly = false,
  }) {
    final List<DebtCollectionInfo> collections = [];

    for (var sale in salesHistory) {
      if (sale.status == SaleStatus.cancelled || sale.status == SaleStatus.reversed) continue;

      for (int i = 0; i < sale.payments.length; i++) {
        final p = sale.payments[i];
        final pDate = p.date ?? sale.timestamp;
        
        final matchesMethod = !cashOnly || p.method == PaymentMethod.cash;

        if (matchesMethod && 
            pDate.year == targetDate.year && 
            pDate.month == targetDate.month && 
            pDate.day == targetDate.day) {
          
          final isDebtRepayment = i > 0 || 
              (p.date != null && !DateUtils.isSameDay(p.date, sale.timestamp)) ||
              (p.reference?.contains('Collection') ?? false);

          if (isDebtRepayment) {
            double paidUpToP = 0;
            for (int k = 0; k <= i; k++) {
              paidUpToP += sale.payments[k].amount;
            }
            final remBal = sale.totalAmount - paidUpToP;

            collections.add(DebtCollectionInfo(
              customerName: sale.customerName ?? 'Walk-in Customer',
              customerPhone: sale.customerPhone ?? 'N/A',
              invoiceId: sale.id,
              amountPaid: p.amount,
              remainingBalance: remBal < 0.01 ? 0.0 : remBal,
              isFullSettlement: remBal <= 0.01,
              paymentTime: pDate,
              paymentMethod: p.method,
            ));
          }
        }
      }
    }

    collections.sort((a, b) => b.paymentTime.compareTo(a.paymentTime));
    return collections;
  }

  static double getDirectCashSalesForDate(DateTime targetDate, List<SaleRecord> salesHistory) {
    double directCash = 0;
    for (var sale in salesHistory) {
      if (sale.status == SaleStatus.cancelled || sale.status == SaleStatus.reversed) continue;
      
      if (sale.timestamp.year == targetDate.year && 
          sale.timestamp.month == targetDate.month && 
          sale.timestamp.day == targetDate.day) {
        
        if (sale.payments.isNotEmpty) {
          final firstPayment = sale.payments.first;
          if (firstPayment.method == PaymentMethod.cash) {
            final pDate = firstPayment.date ?? sale.timestamp;
            if (DateUtils.isSameDay(pDate, sale.timestamp)) {
              directCash += firstPayment.amount;
            }
          }
        }
      }
    }
    return directCash;
  }

  static PaymentMethodBreakdown getPaymentBreakdownForDate(DateTime targetDate, List<SaleRecord> salesHistory) {
    double physicalCashSales = 0;
    double physicalCashDebt = 0;

    double momoSales = 0;
    double momoDebt = 0;

    double bankSales = 0;
    double bankDebt = 0;

    for (var sale in salesHistory) {
      if (sale.status == SaleStatus.cancelled || sale.status == SaleStatus.reversed) continue;

      for (int i = 0; i < sale.payments.length; i++) {
        final p = sale.payments[i];
        final pDate = p.date ?? sale.timestamp;

        if (pDate.year == targetDate.year && 
            pDate.month == targetDate.month && 
            pDate.day == targetDate.day) {

          final isDebtRepayment = i > 0 || 
              (p.date != null && !DateUtils.isSameDay(p.date, sale.timestamp)) ||
              (p.reference?.contains('Collection') ?? false);

          if (!isDebtRepayment) {
            if (p.method == PaymentMethod.cash) {
              physicalCashSales += p.amount;
            } else if (p.method == PaymentMethod.mobileMoney) {
              momoSales += p.amount;
            } else if (p.method == PaymentMethod.bankDeposit) {
              bankSales += p.amount;
            }
          } else {
            if (p.method == PaymentMethod.cash) {
              physicalCashDebt += p.amount;
            } else if (p.method == PaymentMethod.mobileMoney) {
              momoDebt += p.amount;
            } else if (p.method == PaymentMethod.bankDeposit) {
              bankDebt += p.amount;
            }
          }
        }
      }
    }

    final totalPhysicalCash = physicalCashSales + physicalCashDebt;
    final totalMomo = momoSales + momoDebt;
    final totalBank = bankSales + bankDebt;
    final totalRevenue = totalPhysicalCash + totalMomo + totalBank;

    return PaymentMethodBreakdown(
      physicalCashSales: physicalCashSales,
      physicalCashDebt: physicalCashDebt,
      totalPhysicalCash: totalPhysicalCash,
      momoSales: momoSales,
      momoDebt: momoDebt,
      totalMomo: totalMomo,
      bankSales: bankSales,
      bankDebt: bankDebt,
      totalBank: totalBank,
      totalRevenue: totalRevenue,
    );
  }
}

final tillProvider = StateNotifierProvider<TillNotifier, TillState>((ref) {
  return TillNotifier(ref);
});
