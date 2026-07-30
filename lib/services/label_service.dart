import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/transfer_models.dart';
import '../models/butcher_models.dart';
import '../core/utils.dart';
import 'package:intl/intl.dart';

class LabelService {
  static Future<void> printTransferLabel(StockTransfer transfer) async {
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      _addTransferPage(doc, transfer, font, boldFont);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Label_${transfer.id}',
      );
    } catch (e) {
      debugPrint('Label Printing Error: $e');
    }
  }

  static Future<void> printMultipleTransferLabels(List<StockTransfer> transfers) async {
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      for (final t in transfers) {
        _addTransferPage(doc, t, font, boldFont);
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Batch_Labels_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      debugPrint('Multi-Label Printing Error: $e');
    }
  }

  static void _addTransferPage(pw.Document doc, StockTransfer transfer, pw.Font font, pw.Font boldFont) {
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 35 * PdfPageFormat.mm),
        build: (pw.Context context) {
          final dest = transfer.isIndividual 
              ? (transfer.customerName ?? 'Individual') 
              : transfer.destination;
          
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(transfer.meatType.toUpperCase(), 
                  style: pw.TextStyle(font: boldFont, fontSize: 8),
                  textAlign: pw.TextAlign.center),
                pw.Text('Weight: ${WeightConverter.formatShort(transfer.weight, unit: transfer.unit)}', style: pw.TextStyle(font: font, fontSize: 7)),
                pw.SizedBox(height: 1),
                pw.Container(
                  height: 25,
                  width: 25,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: transfer.id,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text('ID: ${transfer.id.length > 8 ? transfer.id.substring(transfer.id.length - 8) : transfer.id}', 
                  style: pw.TextStyle(font: boldFont, fontSize: 5)),
                pw.Text('To: $dest', style: pw.TextStyle(font: font, fontSize: 6), overflow: pw.TextOverflow.clip, maxLines: 1),
                if (transfer.isIndividual && transfer.customerPhone != null)
                   pw.Text('Tel: ${transfer.customerPhone}', style: pw.TextStyle(font: font, fontSize: 5)),
                pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(transfer.transferTime), style: pw.TextStyle(font: font, fontSize: 5)),
              ],
            ),
          );
        },
      ),
    );
  }

  static Future<void> printSlaughterLabel(SlaughterLog log) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (_) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 35 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('SLAUGHTER LOG', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.Text(log.type.displayName.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  pw.Text('Live Wt: ${log.liveWeight.toStringAsFixed(1)}kg', style: pw.TextStyle(font: font, fontSize: 8)),
                  pw.Text('Meat Wt: ${log.meatWeight.toStringAsFixed(1)}kg', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.SizedBox(height: 1),
                  pw.Container(
                    height: 30,
                    width: 30,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: log.id,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text('TAG: ${log.tagNumber ?? log.id.substring(0,8)}', style: pw.TextStyle(font: boldFont, fontSize: 5)),
                  pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(log.slaughterTime ?? DateTime.now()), style: pw.TextStyle(font: font, fontSize: 5)),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Slaughter_${log.id}',
      );
    } catch (e) {
      debugPrint('Slaughter Label Error: $e');
    }
  }

  static Future<void> printCutLabel(MeatCut cut) async {
    try {
      final doc = pw.Document();
      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (_) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 35 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('MEAT CUT', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.Text(cut.name.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  pw.Text('Weight: ${WeightConverter.formatShort(cut.weight, unit: cut.unit)}', style: pw.TextStyle(font: font, fontSize: 8)),
                  pw.SizedBox(height: 2),
                  pw.Container(
                    height: 35,
                    width: 35,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: cut.id,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text('Batch: ${cut.batchId.length > 8 ? cut.batchId.substring(0, 8) : cut.batchId}', style: pw.TextStyle(font: font, fontSize: 5)),
                  pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(cut.processedAt), style: pw.TextStyle(font: font, fontSize: 6)),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Cut_${cut.id}',
      );
    } catch (e) {
      debugPrint('Cut Label Error: $e');
    }
  }

  static Future<void> printBatchLabel(MeatBatch batch) async {
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      _addBatchPage(doc, batch, font, boldFont);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Batch_${batch.id}',
      );
    } catch (e) {
      debugPrint('Batch Label Error: $e');
    }
  }

  static Future<void> printMultipleBatchLabels(List<MeatBatch> batches) async {
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      for (final b in batches) {
        _addBatchPage(doc, b, font, boldFont);
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Bulk_Batch_Labels_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      debugPrint('Bulk Batch Label Error: $e');
    }
  }

  static void _addBatchPage(pw.Document doc, MeatBatch batch, pw.Font font, pw.Font boldFont) {
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 35 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('MEAT BATCH', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                pw.Text(batch.meatType.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 10)),
                pw.Text('Weight: ${WeightConverter.formatShort(batch.weight, unit: 'kg')}', style: pw.TextStyle(font: font, fontSize: 8)),
                pw.SizedBox(height: 2),
                pw.Container(
                  height: 30,
                  width: 30,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: batch.id,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text('ID: ${batch.id.length > 12 ? batch.id.substring(batch.id.length - 12) : batch.id}', style: pw.TextStyle(font: font, fontSize: 5)),
                pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(batch.createdAt), style: pw.TextStyle(font: font, fontSize: 6)),
              ],
            ),
          );
        },
      ),
    );
  }
}
