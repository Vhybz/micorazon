import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sale_model.dart';
import '../models/system_models.dart';
import 'sale_provider.dart';
import 'expense_provider.dart';

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

    // 1. Extract Cash Movements from Sales
    final List<TillMovement> movements = [];
    for (var sale in sales) {
      if (sale.status == SaleStatus.cancelled || sale.status == SaleStatus.reversed) continue;
      
      final cashAmount = sale.payments
          .where((p) => p.method == PaymentMethod.cash)
          .fold(0.0, (sum, p) => sum + p.amount);

      if (cashAmount > 0) {
        movements.add(TillMovement(
          id: sale.id,
          title: 'Cash Sale',
          description: 'Invoice ${sale.id.substring(sale.id.length > 8 ? sale.id.length - 8 : 0).toUpperCase()}',
          amount: cashAmount,
          timestamp: sale.timestamp,
          type: TillMovementType.cashIn,
          userName: sale.cashierName,
        ));
      }
    }

    // 2. Extract Movements from Expenses
    for (var expense in expenses) {
      final isOpeningBalance = expense.category == 'Till Opening Balance';
      final isClosure = expense.category == 'Daily Sales Closure';
      
      movements.add(TillMovement(
        id: expense.id,
        title: expense.category,
        description: expense.title,
        amount: expense.amount,
        timestamp: expense.date,
        type: isOpeningBalance 
            ? TillMovementType.openingBalance 
            : (isClosure ? TillMovementType.closure : TillMovementType.cashOut),
        userName: _extractUserName(expense),
      ));
    }

    // 3. Sort chronologically
    movements.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // 4. Calculate Running Balance
    double balance = 0;
    final List<TillMovement> historyWithBalance = [];
    
    for (var m in movements) {
      if (m.type == TillMovementType.cashIn || m.type == TillMovementType.openingBalance) {
        balance += m.amount;
      } else {
        balance -= m.amount;
      }
      
      historyWithBalance.add(TillMovement(
        id: m.id,
        title: m.title,
        description: m.description,
        amount: m.amount,
        timestamp: m.timestamp,
        type: m.type,
        userName: m.userName,
        runningBalance: balance,
      ));
    }

    // Sort newest first for display
    final displayHistory = historyWithBalance.reversed.toList();

    // 5. Calculate Pending and Closures by Day
    final Map<DateTime, double> pendingByDay = {};
    final Map<DateTime, List<TillMovement>> closuresByDay = {};

    for (var m in movements) {
      final date = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      
      // Calculate Pending (Sales minus any money taken out)
      final currentPending = pendingByDay[date] ?? 0.0;
      if (m.type == TillMovementType.cashIn) {
        pendingByDay[date] = currentPending + m.amount;
      } else if (m.type == TillMovementType.closure || m.type == TillMovementType.cashOut) {
        pendingByDay[date] = currentPending - m.amount;
      }

      // Track Closures and Withdrawals as "Taking Cash"
      if (m.type == TillMovementType.closure || (m.type == TillMovementType.cashOut && m.title == 'CEO Withdrawal')) {
        closuresByDay.putIfAbsent(date, () => []).add(m);
      }
    }

    // Sort closure lists by time (newest first for card display)
    for (var list in closuresByDay.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    state = TillState(
      history: displayHistory,
      currentBalance: balance,
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
}

final tillProvider = StateNotifierProvider<TillNotifier, TillState>((ref) {
  return TillNotifier(ref);
});
