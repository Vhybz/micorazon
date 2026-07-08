import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transfer_models.dart';
import '../services/transfer_provider.dart';
import '../services/feedback_service.dart';
import '../core/utils.dart';
import '../core/constants.dart';

class IncomingStockDialog extends ConsumerStatefulWidget {
  final List<StockTransfer> initialTransfers;
  const IncomingStockDialog({super.key, required this.initialTransfers});

  @override
  ConsumerState<IncomingStockDialog> createState() => _IncomingStockDialogState();

  static void show(BuildContext context, List<StockTransfer> transfers) {
    showDialog(
      context: context,
      builder: (context) => IncomingStockDialog(initialTransfers: transfers),
    );
  }
}

class _IncomingStockDialogState extends ConsumerState<IncomingStockDialog> {
  final scanController = TextEditingController();
  final scanFocusNode = FocusNode();

  @override
  void dispose() {
    scanController.dispose();
    scanFocusNode.dispose();
    super.dispose();
  }

  void _handleScan(String value, List<StockTransfer> transfers) {
    if (value.isEmpty) return;
    // Try to find a matching transfer by ID (handling short IDs on labels)
    final match = transfers.where((t) => 
      t.id.toLowerCase() == value.toLowerCase() || 
      t.id.endsWith(value.toUpperCase())
    ).firstOrNull;

    if (match != null) {
      FeedbackService.success(ref);
      ref.read(transferProvider.notifier).markAsReceived(match.id).then((_) {
        if (!mounted) return;
        scanController.clear();
      }).catchError((e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception:', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      });
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching stock found for this barcode.'), duration: Duration(seconds: 1)),
        );
      }
      scanController.clear();
    }
    scanFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Watch the filtered provider to get live updates if items are received
    final transfers = ref.watch(pendingIncomingTransfersProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.s, AppSpacing.m),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.03),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Incoming Stock', 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), 
                    overflow: TextOverflow.ellipsis
                  ),
                  const Text('Inventory Verification', 
                    style: TextStyle(fontSize: 9, color: Colors.grey), 
                    overflow: TextOverflow.ellipsis
                  ),
                ],
              ),
            ),
            if (transfers.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2), 
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${transfers.length}', 
                  style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w900)
                ),
              ),
            IconButton(
              onPressed: () => ref.read(transferProvider.notifier).loadTransfers(),
              icon: const Icon(Icons.refresh, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (transfers.isNotEmpty) ...[
              TextField(
                controller: scanController,
                focusNode: scanFocusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Scan QR or type ID...',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Use barcode scanner to verify instantly',
                  helperStyle: TextStyle(fontSize: 9),
                ),
                onSubmitted: (v) => _handleScan(v, transfers),
              ),
              const SizedBox(height: 16),
            ],
            Flexible(
              child: transfers.isEmpty
                  ? const Padding(padding: EdgeInsets.all(30), child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 12),
                        Text('All stock verified and received.', textAlign: TextAlign.center),
                      ],
                    ))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: transfers.length,
                      itemBuilder: (context, index) {
                        final t = transfers[index];
                        final isAwaitingPayment = t.status == TransferStatus.awaitingPayment;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isAwaitingPayment 
                                ? Colors.orange.withValues(alpha: 0.05)
                                : theme.cardColor,
                            borderRadius: BorderRadius.circular(AppRadius.m),
                            border: Border.all(
                              color: isAwaitingPayment 
                                  ? Colors.orange.withValues(alpha: 0.3) 
                                  : theme.dividerColor.withValues(alpha: 0.5)
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.m),
                            onTap: () {
                              if (isAwaitingPayment) {
                                _confirmDirectTransferPayment(context, ref, t);
                              } else {
                                ref.read(transferProvider.notifier).markAsReceived(t.id).catchError((e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: ${e.toString().replaceAll('Exception:', '')}'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                });
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: (isAwaitingPayment ? Colors.orange : theme.colorScheme.primary).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isAwaitingPayment ? Icons.payments_outlined : Icons.inventory_2_outlined,
                                      color: isAwaitingPayment ? Colors.orange : theme.colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.meatType, 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(WeightConverter.formatShort(t.weight), 
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)
                                              ),
                                            ),
                                            Text('Batch: ${t.batchId.length > 8 ? t.batchId.substring(0, 8) : t.batchId}', 
                                              style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                        if (isAwaitingPayment)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text('AWAITING PAYMENT', 
                                              style: TextStyle(fontSize: 9, color: Colors.orange.shade800, fontWeight: FontWeight.w900, letterSpacing: 0.5)
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded, 
                                    size: 14, 
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  void _confirmDirectTransferPayment(BuildContext context, WidgetRef ref, StockTransfer transfer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Third-Party Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Has the customer paid for this direct transfer?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _detailRow(context, 'Item', transfer.meatType),
                  _detailRow(context, 'Weight', '${transfer.weight}kg'),
                  _detailRow(context, 'Source', 'Butcher House'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not Yet')),
          ElevatedButton(
            onPressed: () {
              ref.read(transferProvider.notifier).markAsReceived(transfer.id).then((_) {
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment Confirmed & Stock Updated'), backgroundColor: Colors.green),
                );
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Yes, Paid & Received'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value, 
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)
            ),
          ),
        ],
      ),
    );
  }
}
