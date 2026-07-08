import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/held_receipt_model.dart';
import '../models/sale_model.dart';

class HeldReceiptNotifier extends StateNotifier<List<HeldReceipt>> {
  HeldReceiptNotifier() : super([]);

  void holdReceipt(List<SaleItem> items, double totalAmount, double totalDiscount, String? appliedPromo, String? customerName, String? customerPhone) {
    final newHeld = HeldReceipt(
      id: 'HELD-${DateTime.now().millisecondsSinceEpoch}',
      items: items,
      totalAmount: totalAmount,
      totalDiscount: totalDiscount,
      appliedPromo: appliedPromo,
      customerName: customerName,
      customerPhone: customerPhone,
      timestamp: DateTime.now(),
    );
    state = [...state, newHeld];
  }

  void resumeReceipt(HeldReceipt receipt) {
    state = state.where((h) => h.id != receipt.id).toList();
  }

  void removeReceipt(String id) {
    state = state.where((h) => h.id != id).toList();
  }
}

final heldReceiptProvider = StateNotifierProvider<HeldReceiptNotifier, List<HeldReceipt>>((ref) {
  return HeldReceiptNotifier();
});
