import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/expense_model.dart';
import 'supabase_expense_service.dart';
import 'user_provider.dart';
import 'offline_sync_service.dart';

class ExpenseState {
  final List<ExpenseRecord> records;
  final List<String> categories;

  ExpenseState({required this.records, required this.categories});

  ExpenseState copyWith({List<ExpenseRecord>? records, List<String>? categories}) {
    return ExpenseState(
      records: records ?? this.records,
      categories: categories ?? this.categories,
    );
  }
}

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final SupabaseExpenseService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  ExpenseNotifier(this._service, this.ref) : super(ExpenseState(
    records: [],
    categories: ['Electricity', 'GRA Tax', 'Water', 'Rent', 'Wages', 'Transport', 'Vet Check', 'Animal Transport', 'Maintenance', 'Bank Deposit'],
  )) {
    _init();
  }

  void _init() {
    _loadFromCache();
    
    // Watch current user and restart subscription if branch changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });

    _startSubscription();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.expensesBoxName);
      if (box.isNotEmpty) {
        final List<ExpenseRecord> cached = box.values
            .map((json) => ExpenseRecord.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = state.copyWith(records: cached);
        debugPrint('Expense Engine: ${cached.length} records loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Expense Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<ExpenseRecord> expenses) {
    try {
      final box = Hive.box(OfflineSyncService.expensesBoxName);
      box.clear();
      for (var e in expenses) {
        box.put(e.id, e.toJson());
      }
    } catch (e) {
      debugPrint('Expense Engine Save Error: $e');
    }
  }

  void _startSubscription() {
    final user = ref.read(currentUserProvider);
    if (user?.branchCode == null) return;

    _subscription?.cancel();
    _subscription = _service.watchExpenses(user!.branchCode!).listen((expenses) {
      state = state.copyWith(records: expenses);
      _saveToCache(expenses);
    }, onError: (e) {
      debugPrint('Expense Stream Error: $e');
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> loadExpenses() async {
    _startSubscription();
  }

  Future<void> addExpense(ExpenseRecord expense) async {
    final user = ref.read(currentUserProvider);
    final expenseWithBranch = expense.copyWith(branchCode: user?.branchCode);
    
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.addExpense(expenseWithBranch);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      // Fallback to Hive Queue
      await OfflineSyncService.addToQueue(
        actionType: 'EXPENSE', 
        data: expenseWithBranch.toJson(),
      );
      // Optimistic local update
      state = state.copyWith(records: [expenseWithBranch, ...state.records]);
    }
  }

  Future<void> updateExpense(ExpenseRecord expense) async {
    final user = ref.read(currentUserProvider);
    final expenseWithBranch = expense.copyWith(branchCode: user?.branchCode);

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateExpense(expenseWithBranch);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      // Fallback to Hive Queue
      await OfflineSyncService.addToQueue(
        actionType: 'EXPENSE',
        data: expenseWithBranch.toJson(),
      );
      // Optimistic local update
      state = state.copyWith(
        records: state.records.map((e) => e.id == expenseWithBranch.id ? expenseWithBranch : e).toList(),
      );
    }
  }

  Future<String?> uploadReceipt(Uint8List bytes, String fileName) async {
    return await _service.uploadReceipt(bytes, fileName);
  }

  Future<void> deleteExpense(String id) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.deleteExpense(id);
      } else {
        await OfflineSyncService.addToQueue(
          actionType: 'DELETE_EXPENSE',
          data: {'id': id},
        );
        state = state.copyWith(records: state.records.where((e) => e.id != id).toList());
      }
    } catch (_) {}
  }

  Future<void> purgeAllRecords() async {
    try {
      for (final exp in state.records) {
        await _service.deleteExpense(exp.id);
      }
      state = state.copyWith(records: []);
    } catch (_) {}
  }

  void addCategory(String category) {
    if (!state.categories.contains(category)) {
      state = state.copyWith(categories: [...state.categories, category]);
    }
  }

  double getTotalExpensesForMonth(int month, int year) {
    return state.records
        .where((e) => e.date.month == month && e.date.year == year)
        .fold(0.0, (sum, e) => sum + e.amount);
  }
}

final expenseServiceProvider = Provider<SupabaseExpenseService>((ref) {
  return SupabaseExpenseService();
});

final expenseProvider = StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier(ref.watch(expenseServiceProvider), ref);
});
