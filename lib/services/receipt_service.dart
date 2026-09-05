import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale_model.dart';
import '../models/user_model.dart';
import '../models/salary_model.dart';
import '../core/utils.dart';

class ReceiptService {
  static Future<pw.Document> generateReceiptDocument(SaleRecord sale) async {
    final doc = pw.Document();
    
    pw.Font font;
    pw.Font boldFont;

    try {
      font = await PdfGoogleFonts.notoSansRegular();
      boldFont = await PdfGoogleFonts.notoSansBold();
    } catch (e) {
      debugPrint('Font loading failed, falling back to standard fonts: $e');
      font = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Mi~CORAZON', style: pw.TextStyle(font: boldFont, fontSize: 18)),
                    pw.Text('FRESHMEAT BUTCHERY', style: pw.TextStyle(font: font)),
                    pw.Text('Location: New Town, Road linking From Water works Ltd. to Atronie Road', 
                      style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center),
                    pw.Text('GPS: BS-0006-1566 | Tel: 0209276200', 
                      style: pw.TextStyle(font: font, fontSize: 7)),
                    pw.SizedBox(height: 10),
                  ],
                ),
              ),
              pw.Text('Invoice: ${sale.id}', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.timestamp)}', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('Cashier: ${sale.cashierName}', style: pw.TextStyle(font: font, fontSize: 9)),
              if (sale.customerName != null)
                pw.Text('Customer: ${sale.customerName} ${sale.customerPhone != null ? "(${sale.customerPhone})" : ""}', 
                  style: pw.TextStyle(font: font, fontSize: 9)),

              if (sale.balance > 0.01 && sale.status != SaleStatus.awaitingDeposit)
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.symmetric(vertical: 4),
                  padding: const pw.EdgeInsets.all(4),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.orange50,
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.orange, width: 1),
                      bottom: pw.BorderSide(color: PdfColors.orange, width: 1),
                    ),
                  ),
                  child: pw.Center(
                    child: pw.Text('*** CREDIT / DEBT SALE ***', 
                      style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.orange900)),
                  ),
                ),
              
              if (sale.status == SaleStatus.awaitingDeposit)
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.symmetric(vertical: 8),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.red, width: 2),
                    color: PdfColors.red50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('*** AWAITING BANK DEPOSIT ***', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.red)),
                      pw.Divider(color: PdfColors.red, thickness: 0.5),
                      pw.SizedBox(height: 5),
                      pw.Text('Please pay into the account below:', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.red)),
                      pw.SizedBox(height: 4),
                      pw.Text('Bank: UMB (Universal Merchant Bank)', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                      pw.Text('Branch: Sunyani', style: pw.TextStyle(font: font, fontSize: 8)),
                      pw.Text('Account Name: Mi-Corazon Enterprise', style: pw.TextStyle(font: font, fontSize: 8)),
                      pw.Text('Account Number: 1111069263015', style: pw.TextStyle(font: boldFont, fontSize: 10)),
                      pw.SizedBox(height: 5),
                      pw.Text('VALID ONLY AFTER BANK VERIFICATION', style: pw.TextStyle(font: boldFont, fontSize: 7, color: PdfColors.red)),
                    ],
                  ),
                ),
              
              if (sale.isVerified && sale.bankReceiptUrl != null)
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.symmetric(vertical: 8),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.green, width: 1),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text('PAYMENT VERIFIED', style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.green)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      if (sale.bankReceiptId != null)
                        pw.Text('Bank Ref: ${sale.bankReceiptId}', style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.green)),
                      pw.Text('Receipt Uploaded & Confirmed', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.green700)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
              
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Item', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.Text('Total', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 5),
              ...sale.items.map((item) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text('[${item.product.category.toUpperCase()}] ${item.product.name} (${WeightConverter.formatShort(item.quantity, unit: item.product.unit)})', 
                            style: pw.TextStyle(font: font, fontSize: 8)),
                        ),
                        pw.Text(item.total.toStringAsFixed(2), style: pw.TextStyle(font: font, fontSize: 8)),
                      ],
                    ),
                  ],
                )),
              pw.Divider(thickness: 0.5),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _receiptRow('Sub Total', sale.totalAmount, font),
                      _receiptRow('Net Invoice Value', sale.netInvoiceValue, font, isBold: true),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),

              pw.Text('PAYMENT BREAKDOWN', style: pw.TextStyle(font: boldFont, fontSize: 8)),
              pw.SizedBox(height: 4),

              ...sale.payments.map((p) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('METHOD: ${_formatMethod(p)}', style: pw.TextStyle(font: font, fontSize: 8)),
                      pw.Text('₵ ${p.amount.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    ],
                  )),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Paid Amount', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.Text(sale.amountPaid.toStringAsFixed(2), style: pw.TextStyle(font: boldFont, fontSize: 8)),
                ],
              ),
              
              if (sale.balance > 0.01)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('BALANCE DUE (DEBT)', style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.red)),
                    pw.Text(sale.balance.toStringAsFixed(2), style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.red)),
                  ],
                ),

              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _generateQRData(sale),
                  width: 40,
                  height: 40,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Thank you!', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc;
  }

  static Future<void> printReceipt(SaleRecord sale) async {
    try {
      final doc = await generateReceiptDocument(sale);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Receipt_${sale.id}',
      );
    } catch (e) {
      debugPrint('Printing Error: $e');
    }
  }

  static Future<void> printInvoices(List<SaleRecord> sales) async {
    try {
      for (var sale in sales) {
        await printReceipt(sale);
      }
    } catch (e) {
      debugPrint('Batch Printing Error: $e');
    }
  }

  static Future<void> shareReceipt(SaleRecord sale) async {
    try {
      final doc = await generateReceiptDocument(sale);
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Receipt_${sale.id}.pdf',
      );
    } catch (e) {
      debugPrint('Sharing Error: $e');
    }
  }
static String _generateQRData(SaleRecord sale) {
    final buffer = StringBuffer();
    buffer.writeln('Mi~CORAZON FRESHMEAT');
    buffer.writeln('Invoice: ${sale.id}');
    buffer.writeln('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.timestamp)}');
    buffer.writeln('Cashier: ${sale.cashierName}');
    if (sale.customerName != null) {
      buffer.writeln('Customer: ${sale.customerName}');
    }
    buffer.writeln('Items:');
    for (var item in sale.items) {
      buffer.writeln('- [${item.product.category.toUpperCase()}] ${item.product.name} (${WeightConverter.formatShort(item.quantity, unit: item.product.unit)}): ₵${item.total.toStringAsFixed(2)}');
    }
    buffer.writeln('Total: ₵${sale.totalAmount.toStringAsFixed(2)}');
    buffer.writeln('Paid: ₵${sale.amountPaid.toStringAsFixed(2)}');
    if (sale.balance > 0.01) {
      buffer.writeln('Balance: ₵${sale.balance.toStringAsFixed(2)}');
    }
    return buffer.toString();
  }

  static String _formatMethod(PaymentDetail p) {
    switch (p.method) {
      case PaymentMethod.cash: return 'CASH';
      case PaymentMethod.mobileMoney: return p.isPaystack ? 'MOMO (PAYSTACK)' : 'MOMO';
      case PaymentMethod.bankDeposit: return 'BANK';
    }
  }

  static pw.Widget _receiptRow(String label, double value, pw.Font font, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value.toStringAsFixed(2), style: pw.TextStyle(font: font, fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static Future<void> printSalesReport(List<SaleRecord> sales, {String title = 'Sales Report', double totalExpenses = 0.0}) async {
    try {
      final doc = pw.Document();
      final totalRevenue = sales.where((s) => s.isActive).fold(0.0, (sum, s) => sum + s.totalAmount);
      final netProfit = totalRevenue - totalExpenses;
      
      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text(title, style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Invoice ID', 'Date', 'Cashier', 'Total', 'Paid', 'Status'],
                data: sales.map((s) => [
                  s.id,
                  DateFormat('MMM dd, HH:mm').format(s.timestamp),
                  s.cashierName,
                  s.totalAmount.toStringAsFixed(2),
                  s.amountPaid.toStringAsFixed(2),
                  s.status.name.toUpperCase(),
                ]).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
                cellStyle: pw.TextStyle(font: font, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B1111)),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text('Total Revenue: ', style: pw.TextStyle(font: boldFont)),
                          pw.Text('₵ ${totalRevenue.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont)),
                        ],
                      ),
                      if (totalExpenses > 0)
                        pw.Row(
                          children: [
                            pw.Text('Total Expenses: ', style: pw.TextStyle(font: boldFont, color: PdfColors.red)),
                            pw.Text('₵ ${totalExpenses.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, color: PdfColors.red)),
                          ],
                        ),
                      pw.SizedBox(width: 150, child: pw.Divider()),
                      pw.Row(
                        children: [
                          pw.Text('Estimated Profit: ', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green)),
                          pw.Text('₵ ${netProfit.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Sales_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Sales Report Printing Error: $e');
    }
  }

  static Future<void> printDebtReport(List<SaleRecord> sales) async {
    try {
      final doc = pw.Document();
      final totalDebt = sales.fold(0.0, (sum, s) => sum + s.balance);
      
      // Calculate max debt to determine thresholds
      double maxDebt = 0;
      for (var s in sales) {
        if (s.balance > maxDebt) maxDebt = s.balance;
      }

      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text('OUTSTANDING DEBT REPORT', style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.SizedBox(height: 20),
              
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  // Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B1111)),
                    children: [
                      _tableHeader('Customer', boldFont),
                      _tableHeader('Phone', boldFont),
                      _tableHeader('Invoice ID', boldFont),
                      _tableHeader('Date', boldFont),
                      _tableHeader('Total', boldFont),
                      _tableHeader('Balance', boldFont),
                    ],
                  ),
                  // Data Rows with conditional coloring
                  ...sales.map((s) {
                    PdfColor bgColor = PdfColors.white;
                    PdfColor statusColor = PdfColors.black;

                    if (maxDebt > 0) {
                      if (s.balance >= maxDebt * 0.7 || s.balance >= 500) {
                        bgColor = PdfColors.red50;
                        statusColor = PdfColors.red;
                      } else if (s.balance >= maxDebt * 0.3 || s.balance >= 100) {
                        bgColor = PdfColors.orange50;
                        statusColor = PdfColors.orange;
                      } else {
                        bgColor = PdfColors.green50;
                        statusColor = PdfColors.green;
                      }
                    }

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bgColor),
                      children: [
                        _tableCell(s.customerName ?? 'Walk-in', font),
                        _tableCell(s.customerPhone ?? 'N/A', font),
                        _tableCell(s.id.substring(s.id.length - 8).toUpperCase(), font),
                        _tableCell(DateFormat('MMM dd, yyyy').format(s.timestamp), font),
                        _tableCell('₵${s.totalAmount.toStringAsFixed(2)}', font),
                        _tableCell('₵${s.balance.toStringAsFixed(2)}', boldFont, color: statusColor),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('TOTAL OUTSTANDING DEBT: ', style: pw.TextStyle(font: boldFont)),
                  pw.Text('₵${totalDebt.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(width: 8, height: 8, color: PdfColors.red),
                  pw.SizedBox(width: 4),
                  pw.Text('High (>₵500)', style: pw.TextStyle(fontSize: 7, font: font)),
                  pw.SizedBox(width: 12),
                  pw.Container(width: 8, height: 8, color: PdfColors.orange),
                  pw.SizedBox(width: 4),
                  pw.Text('Medium (₵100-500)', style: pw.TextStyle(fontSize: 7, font: font)),
                  pw.SizedBox(width: 12),
                  pw.Container(width: 8, height: 8, color: PdfColors.green),
                  pw.SizedBox(width: 4),
                  pw.Text('Low (<₵100)', style: pw.TextStyle(fontSize: 7, font: font)),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text('Report Generated by Mi~Corazon Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey)),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Debt_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Debt Report Printing Error: $e');
    }
  }

  static pw.Widget _tableHeader(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, style: pw.TextStyle(font: font, color: PdfColors.white, fontSize: 9)),
    );
  }

  static pw.Widget _tableCell(String text, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8, color: color)),
    );
  }

  static Future<void> printPaidInvoicesReport(List<SaleRecord> sales) async {
    try {
      final doc = pw.Document();
      final totalPaid = sales.fold(0.0, (sum, s) => sum + s.amountPaid);
      
      // Calculate max paid to determine thresholds
      double maxPaid = 0;
      for (var s in sales) {
        if (s.amountPaid > maxPaid) maxPaid = s.amountPaid;
      }

      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text('FULLY PAID INVOICES REPORT', style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.SizedBox(height: 20),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  // Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF28A745)), // Green header
                    children: [
                      _tableHeader('Customer', boldFont),
                      _tableHeader('Invoice ID', boldFont),
                      _tableHeader('Date', boldFont),
                      _tableHeader('Cashier', boldFont),
                      _tableHeader('Total Amount', boldFont),
                    ],
                  ),
                  // Data Rows with conditional coloring
                  ...sales.map((s) {
                    PdfColor bgColor = PdfColors.white;
                    PdfColor textColor = PdfColors.black;

                    if (maxPaid > 0) {
                      if (s.amountPaid >= maxPaid * 0.7) {
                        bgColor = PdfColor.fromInt(0xFFFFEBEE); // Light Red for Highest
                        textColor = PdfColor.fromInt(0xFFB71C1C);
                      } else if (s.amountPaid >= maxPaid * 0.3) {
                        bgColor = PdfColor.fromInt(0xFFFFFDE7); // Light Yellow for Mid
                        textColor = PdfColor.fromInt(0xFFF57F17);
                      } else {
                        bgColor = PdfColor.fromInt(0xFFE8F5E9); // Light Green for Least
                        textColor = PdfColor.fromInt(0xFF1B5E20);
                      }
                    }

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bgColor),
                      children: [
                        _tableCell(s.customerName ?? 'Walk-in', font, color: textColor),
                        _tableCell(s.id, font, color: textColor),
                        _tableCell(DateFormat('MMM dd, yyyy').format(s.timestamp), font, color: textColor),
                        _tableCell(s.cashierName.split(' ')[0], font, color: textColor),
                        _tableCell('₵${s.totalAmount.toStringAsFixed(2)}', boldFont, color: textColor),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('TOTAL PAID REVENUE: ', style: pw.TextStyle(font: boldFont)),
                  pw.Text('₵${totalPaid.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(width: 10, height: 10, color: const PdfColor.fromInt(0xFFFFEBEE)),
                  pw.SizedBox(width: 4),
                  pw.Text('High Value (>70%)', style: pw.TextStyle(fontSize: 8, font: font)),
                  pw.SizedBox(width: 12),
                  pw.Container(width: 10, height: 10, color: const PdfColor.fromInt(0xFFFFFDE7)),
                  pw.SizedBox(width: 4),
                  pw.Text('Mid Value (30-70%)', style: pw.TextStyle(fontSize: 8, font: font)),
                  pw.SizedBox(width: 12),
                  pw.Container(width: 10, height: 10, color: const PdfColor.fromInt(0xFFE8F5E9)),
                  pw.SizedBox(width: 4),
                  pw.Text('Standard (<30%)', style: pw.TextStyle(fontSize: 8, font: font)),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text('Report Generated by Mi~Corazon Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey)),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Paid_Invoices_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Paid Invoices Report Printing Error: $e');
    }
  }

  static Future<void> printSalaryReport(List<UserAccount> users, {Map<String, bool>? advanceStatus}) async {
    try {
      final doc = pw.Document();
      final totalPayroll = users.fold(0.0, (sum, u) => sum + (u.salaryAmount ?? 0.0));
      
      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text('STAFF PAYROLL & SALARY REPORT', style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.SizedBox(height: 20),
              
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B1111)),
                    children: [
                      _tableHeader('Staff Name', boldFont),
                      _tableHeader('Role', boldFont),
                      _tableHeader('Due Day', boldFont),
                      _tableHeader('Type', boldFont),
                      _tableHeader('Amount (GHS)', boldFont),
                    ],
                  ),
                  ...users.where((u) => u.salaryAmount != null).map((u) {
                    final isAdvance = u.lastPaymentWasAdvance;
                    return pw.TableRow(
                      children: [
                        _tableCell(u.name, font),
                        _tableCell(u.role.name.toUpperCase(), font),
                        _tableCell('Day ${u.salaryDay ?? "--"}', font),
                        _tableCell(
                          isAdvance ? 'ADVANCE' : 'FULL', 
                          boldFont, 
                          color: isAdvance ? PdfColors.red : PdfColors.black
                        ),
                        _tableCell(
                          u.salaryAmount?.toStringAsFixed(2) ?? '0.00', 
                          boldFont,
                          color: isAdvance ? PdfColors.red : PdfColors.black
                        ),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text('Total Monthly Payroll: ', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                          pw.Text('₵ ${totalPayroll.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 14, color: PdfColors.green)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text('Authorized by Administrator', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey)),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Salary_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Salary Report Printing Error: $e');
    }
  }

  static Future<void> printDetailedHistoryReport(List<SaleRecord> sales, {required String period}) async {
    try {
      final doc = pw.Document();
      final activeSales = sales.where((s) => s.isActive).toList();
      final totalRevenue = activeSales.fold(0.0, (sum, s) => sum + s.totalAmount);
      final totalCost = activeSales.fold(0.0, (sum, s) => sum + s.totalCost);
      final netProfit = totalRevenue - totalCost;

      // Product breakdown
      final Map<String, double> productQtyMap = {};
      for (var sale in activeSales) {
        for (var item in sale.items) {
          productQtyMap[item.product.name] = (productQtyMap[item.product.name] ?? 0) + item.quantity;
        }
      }
      final sortedProducts = productQtyMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text('DETAILED SALES & PROFIT REPORT', style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.Text('Period: $period', style: pw.TextStyle(fontSize: 12, font: font, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),

              // Financial Summary
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _statBox('TOTAL SALES', '₵${totalRevenue.toStringAsFixed(2)}', PdfColors.blue900, boldFont, font),
                  _statBox('TOTAL COST', '₵${totalCost.toStringAsFixed(2)}', PdfColors.red900, boldFont, font),
                  _statBox('NET PROFIT', '₵${netProfit.toStringAsFixed(2)}', PdfColors.green900, boldFont, font),
                ],
              ),
              pw.SizedBox(height: 30),

              // Product Breakdown
              pw.Text('PRODUCT SALES BREAKDOWN', style: pw.TextStyle(fontSize: 14, font: boldFont)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['Product Name', 'Total Quantity Sold'],
                data: sortedProducts.map((e) => [e.key, WeightConverter.formatShort(e.value, unit: 'kg')]).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                cellStyle: pw.TextStyle(font: font, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B1111)),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 30),

              // Transaction Log
              pw.Text('TRANSACTION LOG', style: pw.TextStyle(fontSize: 14, font: boldFont)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['ID', 'Time', 'Customer', 'Items', 'Total'],
                data: activeSales.map((s) => [
                  s.id.substring(s.id.length - 8).toUpperCase(),
                  DateFormat('MMM dd, HH:mm').format(s.timestamp),
                  s.customerName ?? 'Walk-in',
                  s.items.length.toString(),
                  '₵${s.totalAmount.toStringAsFixed(2)}',
                ]).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                cellStyle: pw.TextStyle(font: font, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Detailed_Sales_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Detailed Report Printing Error: $e');
    }
  }

  static pw.Widget _statBox(String label, String value, PdfColor color, pw.Font boldFont, pw.Font font) {
    return pw.Container(
      width: 170,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 5),
          pw.Text(value, style: pw.TextStyle(font: boldFont, fontSize: 14, color: color)),
        ],
      ),
    );
  }

  static Future<void> printSalaryHistory(UserAccount user, List<SalaryRecord> history, {required String period}) async {
    try {
      final doc = pw.Document();
      final totalPaid = history.fold(0.0, (sum, r) => sum + r.amount);

      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(font: boldFont)),
                    pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), style: pw.TextStyle(font: font)),
                  ],
                ),
              ),
              pw.Text('WORKER PAYMENT STATEMENT', style: pw.TextStyle(fontSize: 18, font: boldFont)),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Employee: ${user.name}', style: pw.TextStyle(font: boldFont)),
                      pw.Text('Role: ${user.role.name.toUpperCase()}', style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Period: $period', style: pw.TextStyle(font: boldFont)),
                      pw.Text('Base Salary: GHS ${user.salaryAmount?.toStringAsFixed(2) ?? "0.00"}', style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.SizedBox(height: 20),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF6B1111)),
                    children: [
                      _tableHeader('Date', boldFont),
                      _tableHeader('For Month', boldFont),
                      _tableHeader('Type', boldFont),
                      _tableHeader('Note', boldFont),
                      _tableHeader('Amount', boldFont),
                    ],
                  ),
                  ...history.map((r) {
                    final color = r.isAdvance ? PdfColors.red : PdfColors.black;
                    return pw.TableRow(
                      children: [
                        _tableCell(DateFormat('yyyy-MM-dd').format(r.date), font, color: color),
                        _tableCell(DateFormat('MMMM yyyy').format(r.targetMonth), font, color: color),
                        _tableCell(r.isAdvance ? 'ADVANCE' : 'FULL', boldFont, color: color),
                        _tableCell(r.displayNote ?? '--', font, color: color),
                        _tableCell(r.amount.toStringAsFixed(2), boldFont, color: color),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Total Paid in Period: ', style: pw.TextStyle(font: boldFont)),
                      pw.Text('GHS ${totalPaid.toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.green)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text('Verified by Mi~Corazon Management System', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey)),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Salary_History_${user.firstName}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('History Report Printing Error: $e');
    }
  }

  static Future<void> printPayslip(UserAccount user, double amount, bool isAdvance, {String? note, DateTime? targetMonth}) async {
    try {
      final isExternal = user.id == 'EXTERNAL';
      final doc = pw.Document();
      
      pw.Font font;
      pw.Font boldFont;

      try {
        font = await PdfGoogleFonts.notoSansRegular();
        boldFont = await PdfGoogleFonts.notoSansBold();
      } catch (e) {
        font = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text('Mi~CORAZON', style: pw.TextStyle(font: boldFont, fontSize: 16)),
                      pw.Text(isExternal ? 'EXTERNAL PAYSLIP' : 'STAFF PAYSLIP', style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.Divider(),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                _payslipRow(isExternal ? 'Worker Name:' : 'Staff Name:', user.name, font, boldFont),
                if (!isExternal)
                  _payslipRow('Staff ID:', user.id.substring(user.id.length - 8).toUpperCase(), font, boldFont),
                if (isExternal && user.phone != null)
                  _payslipRow('Phone:', user.phone!, font, boldFont),
                if (isExternal && user.email.isNotEmpty)
                  _payslipRow('Email:', user.email, font, boldFont),
                _payslipRow('Role:', isExternal ? 'EXTERNAL WORKER' : user.role.name.toUpperCase(), font, boldFont),
                _payslipRow('Date Paid:', DateFormat('yyyy-MM-dd').format(DateTime.now()), font, boldFont),
                if (targetMonth != null)
                  _payslipRow('For Month:', DateFormat('MMMM yyyy').format(targetMonth), font, boldFont),
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('PAYMENT TYPE:', style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text(
                      isAdvance ? 'ADVANCE' : (isExternal ? 'WORK PAYMENT' : 'FULL SALARY'), 
                      style: pw.TextStyle(font: boldFont, fontSize: 9, color: isAdvance ? PdfColors.red : PdfColors.black)
                    ),
                  ],
                ),
                if (note != null && note.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Text('NOTE:', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
                  pw.Text(note, style: pw.TextStyle(font: font, fontSize: 8)),
                ],
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('AMOUNT PAID:', style: pw.TextStyle(font: boldFont, fontSize: 12)),
                    pw.Text(
                      'GHS ${amount.toStringAsFixed(2)}', 
                      style: pw.TextStyle(font: boldFont, fontSize: 12, color: isAdvance ? PdfColors.red : PdfColors.green)
                    ),
                  ],
                ),
                if (!isAdvance && !isExternal && user.salaryAmount != null)
                   _payslipRow('Base Salary:', 'GHS ${user.salaryAmount!.toStringAsFixed(2)}', font, boldFont, fontSize: 8),
                
                pw.SizedBox(height: 20),
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text('Verified by System', style: pw.TextStyle(font: font, fontSize: 7, fontStyle: pw.FontStyle.italic)),
                      pw.SizedBox(height: 5),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: 'PAYSLIP:\nEmployee: ${user.name}\nID: ${user.id}\nAmount: GHS ${amount.toStringAsFixed(2)}\nType: ${isAdvance ? "ADVANCE" : "FULL"}\nDate: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                        width: 40,
                        height: 40,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Payslip_${user.firstName}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      debugPrint('Payslip Printing Error: $e');
    }
  }

  static pw.Widget _payslipRow(String label, String value, pw.Font font, pw.Font boldFont, {double fontSize = 9}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: fontSize)),
          pw.Text(value, style: pw.TextStyle(font: boldFont, fontSize: fontSize)),
        ],
      ),
    );
  }
}
