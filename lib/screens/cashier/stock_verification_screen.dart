import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/transfer_models.dart';
import '../../services/transfer_provider.dart';
import '../../services/feedback_service.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/role_pop_scope.dart';

class StockVerificationScreen extends ConsumerStatefulWidget {
  const StockVerificationScreen({super.key});

  @override
  ConsumerState<StockVerificationScreen> createState() => _StockVerificationScreenState();
}

class _StockVerificationScreenState extends ConsumerState<StockVerificationScreen> {
  final scanController = TextEditingController();
  final scanFocusNode = FocusNode();
  bool _isCameraActive = false;

  @override
  void dispose() {
    scanController.dispose();
    scanFocusNode.dispose();
    super.dispose();
  }

  void _handleScan(String value, List<StockTransfer> transfers) {
    if (value.isEmpty) return;
    
    // Clean the value (sometimes scanners add prefix/suffix)
    final cleanValue = value.trim().toUpperCase();
    
    final match = transfers.where((t) => 
      t.id.toUpperCase() == cleanValue || 
      t.id.toUpperCase().endsWith(cleanValue) ||
      t.batchId.toUpperCase() == cleanValue
    ).firstOrNull;

    if (match != null) {
      FeedbackService.success(ref);
      ref.read(transferProvider.notifier).markAsReceived(match.id).then((_) {
        if (!mounted) return;
        scanController.clear();
        if (_isCameraActive) setState(() => _isCameraActive = false);
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
          SnackBar(
            content: Text('No matching stock found for "$value".'), 
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
      scanController.clear();
    }
    if (!_isCameraActive) scanFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transfers = ref.watch(pendingIncomingTransfersProvider);
    const currentRoute = '/cashier/verify-stock';

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        appBar: MainAppBar(
          title: 'Verify Incoming Stock',
          showBackButton: true,
          showMenuButton: false,
          actions: [
            IconButton(
              icon: Icon(_isCameraActive ? Icons.keyboard_rounded : Icons.camera_alt_rounded),
              onPressed: () => setState(() => _isCameraActive = !_isCameraActive),
              tooltip: _isCameraActive ? 'Switch to Keyboard' : 'Open Camera Scanner',
            ),
          ],
        ),
        body: Column(
          children: [
            if (_isCameraActive)
              Container(
                height: 250,
                margin: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.m),
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.m - 2),
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          _handleScan(barcode.rawValue!, transfers);
                        }
                      }
                    },
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(AppSpacing.l),
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_isCameraActive ? Icons.camera_alt_rounded : Icons.qr_code_scanner, size: 32, color: AppColors.primaryMaroon),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_isCameraActive ? 'Camera Scanner Active' : 'Barcode Scanner Ready', 
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                            Text(_isCameraActive 
                              ? 'Point your camera at the transfer barcode' 
                              : 'Scan items or type ID to receive into inventory', 
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (transfers.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${transfers.length} PENDING', 
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: scanController,
                    focusNode: scanFocusNode,
                    autofocus: !_isCameraActive,
                    decoration: InputDecoration(
                      hintText: _isCameraActive ? 'Scanner is active above...' : 'Click here and scan barcode...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (scanController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.send_rounded, color: Colors.green),
                              onPressed: () => _handleScan(scanController.text, transfers),
                            ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () => ref.read(transferProvider.notifier).loadTransfers(),
                            tooltip: 'Sync with server',
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
                      filled: true,
                      fillColor: theme.cardColor,
                    ),
                    onSubmitted: (v) => _handleScan(v, transfers),
                    onChanged: (v) => setState(() {}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(transferProvider.notifier).loadTransfers(),
                child: transfers.isEmpty
                    ? Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 80, color: Colors.green.withValues(alpha: 0.3)),
                            const SizedBox(height: 16),
                            const Text('All caught up!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const Text('No pending transfers for this branch.', style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushReplacementNamed(context, '/cashier');
                              },
                              child: const Text('Back to POS'),
                            ),
                            const SizedBox(height: 20), // Extra space for keyboard padding
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.l),
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
                                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                  );
                                });
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: (isAwaitingPayment ? Colors.orange : theme.colorScheme.primary).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      isAwaitingPayment ? Icons.payments_outlined : Icons.inventory_2_outlined,
                                      color: isAwaitingPayment ? Colors.orange : theme.colorScheme.primary,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.meatType, 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(WeightConverter.formatShort(t.weight, unit: t.unit), 
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)
                                              ),
                                            ),
                                            Text('Batch: ${t.batchId}', 
                                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                        if (isAwaitingPayment)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text('AWAITING PAYMENT', 
                                              style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w900, letterSpacing: 1.0)
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline, 
                                        color: Colors.green.withValues(alpha: 0.5),
                                        size: 24,
                                      ),
                                      const Text('RECEIVE', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDirectTransferPayment(BuildContext context, WidgetRef ref, StockTransfer transfer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text('Has the customer paid for ${transfer.weight}kg of ${transfer.meatType}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')),
          ElevatedButton(
            onPressed: () {
              ref.read(transferProvider.notifier).markAsReceived(transfer.id).then((_) {
                if (!context.mounted) return;
                Navigator.pop(context);
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Yes, Received'),
          ),
        ],
      ),
    );
  }
}
