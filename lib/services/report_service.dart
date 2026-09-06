import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale_model.dart';
import '../models/product.dart';
import '../models/butcher_models.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../models/system_models.dart';

class ReportService {
  static const _primaryMaroon = PdfColor.fromInt(0xFF6B1111);

  static Future<void> generateDailySalesReport(List<SaleRecord> sales, DateTime date) async {
    final doc = pw.Document();
    final todaySales = sales.where((s) => 
      s.timestamp.year == date.year && 
      s.timestamp.month == date.month && 
      s.timestamp.day == date.day
    ).toList();

    final totalRevenue = todaySales.fold(0.0, (sum, s) => sum + s.totalAmount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Daily Sales Report', date),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Total Transactions': todaySales.length.toString(),
            'Gross Revenue': 'GHS ${totalRevenue.toStringAsFixed(2)}',
          }),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Time', 'Invoice ID', 'Customer', 'Items', 'Total (GHS)'],
            data: todaySales.map((s) => [
              DateFormat('HH:mm').format(s.timestamp),
              s.id.substring(s.id.length - 8).toUpperCase(),
              s.customerName ?? 'Walk-in',
              s.items.length.toString(),
              s.totalAmount.toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Daily_Sales_${DateFormat('yyyyMMdd').format(date)}');
  }

  static Future<void> generateMonthlyRevenueSummary(List<SaleRecord> sales, DateTime date) async {
    final doc = pw.Document();
    final monthlySales = sales.where((s) => 
      s.timestamp.year == date.year && 
      s.timestamp.month == date.month
    ).toList();

    final totalRevenue = monthlySales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final totalDiscounts = monthlySales.fold(0.0, (sum, s) => sum + s.totalDiscount);
    
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Monthly Revenue Summary - ${DateFormat('MMMM yyyy').format(date)}', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Total Orders': monthlySales.length.toString(),
            'Gross Revenue': 'GHS ${totalRevenue.toStringAsFixed(2)}',
            'Promo Savings': 'GHS ${totalDiscounts.toStringAsFixed(2)}',
          }),
          pw.SizedBox(height: 20),
          pw.Text('Revenue Breakdown by Day', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Date', 'Transactions', 'Daily Total (GHS)'],
            data: _groupSalesByDay(monthlySales).entries.map((e) => [
              e.key,
              e.value['count'].toString(),
              e.value['total'].toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Monthly_Revenue_${DateFormat('yyyyMM').format(date)}');
  }

  static Future<void> generateInventoryAudit(List<Product> products) async {
    final doc = pw.Document();
    
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Inventory Audit Report', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Total Products': products.length.toString(),
            'Low Stock Items': products.where((p) => p.stockQuantity <= p.lowStockThreshold).length.toString(),
          }),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Category', 'Product Name', 'Current Stock', 'Unit', 'Retail Price'],
            data: products.map((p) => [
              p.category,
              p.name,
              p.stockQuantity.toStringAsFixed(1),
              p.unit,
              p.retailPrice.toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Inventory_Audit_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  static Future<void> generateSlaughterLogReport(List<SlaughterLog> logs) async {
    final doc = pw.Document();
    
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Slaughter & Yield Log', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Date', 'Animal Type', 'Intake (kg)', 'Yield (kg)', 'Waste (kg)', 'Status'],
            data: logs.map((l) => [
              DateFormat('MMM dd').format(l.slaughterTime ?? DateTime.now()),
              l.type.displayName,
              l.liveWeight.toStringAsFixed(1),
              l.meatWeight.toStringAsFixed(1),
              (l.liveWeight - l.meatWeight).toStringAsFixed(1),
              l.status.name.toUpperCase(),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Slaughter_Log_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  static Future<void> generateExpenseLedger(List<ExpenseRecord> expenses) async {
    final doc = pw.Document();
    final total = expenses.fold(0.0, (sum, e) => sum + e.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Business Expense Ledger', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Total Expenses': 'GHS ${total.toStringAsFixed(2)}',
            'Entries': expenses.length.toString(),
          }),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Date', 'Category', 'Description', 'Amount (GHS)'],
            data: expenses.map((e) => [
              DateFormat('yyyy-MM-dd').format(e.date),
              e.category,
              e.title,
              e.amount.toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Expense_Ledger');
  }

  static Future<void> generateCustomerDebtStatement(List<SaleRecord> sales) async {
    final doc = pw.Document();
    final debtSales = sales.where((s) => s.balance > 0).toList();
    final totalDebt = debtSales.fold(0.0, (sum, s) => sum + s.balance);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Customer Debt Statement', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Total Outstanding': 'GHS ${totalDebt.toStringAsFixed(2)}',
            'Pending Invoices': debtSales.length.toString(),
          }),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Customer', 'Phone', 'Invoice Date', 'Total', 'Owed (GHS)'],
            data: debtSales.map((s) => [
              s.customerName ?? 'N/A',
              s.customerPhone ?? 'N/A',
              DateFormat('yyyy-MM-dd').format(s.timestamp),
              s.totalAmount.toStringAsFixed(2),
              s.balance.toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Debt_Statement');
  }

  static Future<void> generateMeatBreakdownAnalysis(List<MeatCut> cuts) async {
    final doc = pw.Document();
    
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Meat Breakdown & Cut Analysis', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.Text('Detailed listing of all meat parts processed by the workstation.', style: pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Processed Date', 'Batch ID', 'Cut/Part Name', 'Weight (kg)'],
            data: cuts.map((c) => [
              DateFormat('MMM dd, HH:mm').format(c.processedAt),
              c.batchId.substring(c.batchId.length - 8).toUpperCase(),
              c.name,
              c.weight.toStringAsFixed(1),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Breakdown_Analysis');
  }

  static Future<void> generateStaffPerformanceReport(List<SaleRecord> sales, List<UserAccount> staff) async {
    final doc = pw.Document();
    
    final Map<String, Map<String, dynamic>> performance = {};
    for (final s in sales) {
      final name = s.cashierName;
      performance.putIfAbsent(name, () => {'total': 0.0, 'count': 0});
      performance[name]!['total'] += s.totalAmount;
      performance[name]!['count'] += 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Staff Performance Metrics', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Staff Member', 'Sales Count', 'Total Generated (GHS)', 'Avg/Sale'],
            data: performance.entries.map((e) => [
              e.key,
              e.value['count'].toString(),
              e.value['total'].toStringAsFixed(2),
              (e.value['total'] / e.value['count']).toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Staff_Performance');
  }

  static Future<void> generateTaxComplianceReport({
    required DateTime date,
    required double totalSales,
    required double totalExpenses,
    required double grossProfit,
    required Map<String, double> taxBreakdown,
    bool isQuarterly = false,
  }) async {
    final doc = pw.Document();
    final periodName = isQuarterly 
        ? 'Q${((date.month - 1) / 3).floor() + 1} ${date.year}' 
        : DateFormat('MMMM yyyy').format(date);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('GRA Tax Compliance Report', date),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Reporting Period': periodName,
            'Type': isQuarterly ? 'QUARTERLY FILING' : 'MONTHLY FILING',
            'Status': 'OFFICIAL RECORD',
          }),
          pw.SizedBox(height: 20),
          
          pw.Text('Profit & Loss Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Description', 'Amount (GHS)'],
            data: [
              ['Total Gross Sales', totalSales.toStringAsFixed(2)],
              ['Total Operational Expenses', totalExpenses.toStringAsFixed(2)],
              ['Gross Profit (Pre-Tax)', grossProfit.toStringAsFixed(2)],
            ],
          ),
          
          pw.SizedBox(height: 30),
          pw.Text('GRA TAX COMPLIANCE SUMMARY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _primaryMaroon)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Tax Component', 'Calculation Base', 'Calculated Amount (GHS)'],
            data: [
              ['VAT (Value Added Tax)', '20% of Sales', taxBreakdown['VAT (20% Sales)']!.toStringAsFixed(2)],
              ['Income Tax', '20% of Profit', taxBreakdown['Income Tax (20% Profit)']!.toStringAsFixed(2)],
              ['TOTAL TAX PAYABLE', '', taxBreakdown['TOTAL']!.toStringAsFixed(2)],
            ],
          ),
          
          pw.SizedBox(height: 40),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('NET PROFIT AFTER TAX', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
              pw.Text('GHS ${(grossProfit - taxBreakdown['TOTAL']!).toStringAsFixed(2)}', 
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: _primaryMaroon)),
            ],
          ),
          
          pw.SizedBox(height: 60),
          pw.Row(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(width: 150, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 5),
                  pw.Text('Manager Signature', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Printed on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Tax_Compliance_${DateFormat('yyyyMM').format(date)}');
  }

  static Future<void> generateHealthCertificate() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(40),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _primaryMaroon, width: 5),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('HEALTH INSPECTION CERTIFICATE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _primaryMaroon)),
                pw.SizedBox(height: 20),
                pw.Text('This is to certify that Mi~Corazon Freshmeat Butchery has passed all health and hygiene standards for the year 2024.', textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 40),
                pw.Text('Status: VERIFIED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                pw.SizedBox(height: 60),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Date: Jan 01, 2024'),
                    pw.Text('Signature: _________________'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Health_Certificate_2024');
  }

  static Future<void> generateSlaughterSOP() async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        header: (context) => _buildHeader('Standard Operating Procedure', DateTime.now()),
        build: (context) => [
          pw.Header(level: 0, text: 'Standard Slaughter SOP v2.1'),
          pw.Paragraph(text: '1. Arrival and Offloading: Ensure animals are rested for at least 12 hours.'),
          pw.Paragraph(text: '2. Pre-Slaughter Inspection: Veterinary officer must verify animal health.'),
          pw.Paragraph(text: '3. Stunning and Bleeding: Performed according to humane standards.'),
          pw.Paragraph(text: '4. Dressing: Immediate removal of hide and viscera.'),
          pw.Paragraph(text: '5. Post-Mortem: Secondary inspection of carcasses.'),
          pw.Paragraph(text: '6. Storage: Cooling at 0-4°C within 1 hour.'),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Slaughter_SOP_v2.1');
  }

  static Future<void> generateTillLedgerReport(List<TillMovement> history) async {
    final doc = pw.Document();
    
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('Till & Cash Movement Ledger', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Final Balance': 'GHS ${history.isEmpty ? "0.00" : history.first.runningBalance.toStringAsFixed(2)}',
            'Total Entries': history.length.toString(),
          }),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            headers: ['Time', 'Action', 'Reference', 'Amount (GHS)', 'Balance (GHS)'],
            data: history.map((m) => [
              DateFormat('MM/dd HH:mm').format(m.timestamp),
              m.title,
              m.description,
              '${m.type == TillMovementType.cashOut ? "-" : "+"} ${m.amount.toStringAsFixed(2)}',
              m.runningBalance.toStringAsFixed(2),
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => doc.save(), name: 'Till_Ledger_${DateFormat('yyyyMMdd').format(DateTime.now())}');
  }

  static Future<void> generateProductActivityReport({
    required List<ProductActivityReportData> reportData,
    required DateTime startDate,
    required DateTime endDate,
    required String branchName,
  }) async {
    final doc = pw.Document();

    double intakesKg = 0.0, intakesUnits = 0.0;
    double soldKg = 0.0, soldUnits = 0.0;
    double stockKg = 0.0, stockUnits = 0.0;
    final totalRevenue = reportData.fold(0.0, (sum, d) => sum + d.totalRevenue);

    for (final d in reportData) {
      final u = d.product.unit.trim().toLowerCase();
      final isKg = u == 'kg' || u == 'kgs' || u == 'kilogram' || u == 'kilograms';
      if (isKg) {
        intakesKg += d.totalIntakeQty;
        soldKg += d.totalQtySold;
        stockKg += d.remainingStock;
      } else {
        intakesUnits += d.totalIntakeQty;
        soldUnits += d.totalQtySold;
        stockUnits += d.remainingStock;
      }
    }

    String formatQtySummary(double kg, double units) {
      if (kg > 0 && units > 0) {
        return '${kg.toStringAsFixed(1)} kg (+ ${units.toStringAsFixed(1)} units)';
      } else if (kg > 0) {
        return '${kg.toStringAsFixed(1)} kg';
      } else if (units > 0) {
        return '${units.toStringAsFixed(1)} units';
      } else {
        return '0.0 kg';
      }
    }

    final dateRangeStr = '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => _buildHeader('CEO Executive Product Activity Report', DateTime.now()),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildSummarySection({
            'Report Period': dateRangeStr,
            'Branch / Entity': branchName,
            'Products Evaluated': reportData.length.toString(),
            'Total Quantity Intaked': formatQtySummary(intakesKg, intakesUnits),
            'Total Quantity Sold': formatQtySummary(soldKg, soldUnits),
            'Gross Revenue Generated': 'GHS ${totalRevenue.toStringAsFixed(2)}',
            'Current Stock Remaining': formatQtySummary(stockKg, stockUnits),
          }),
          pw.SizedBox(height: 15),
          pw.Text('Itemized Product Movement & Financial Analysis',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _primaryMaroon),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Product Name', 'Category', 'Intaked Qty', 'Qty Sold', 'Revenue (GHS)', 'Remaining Stock'],
            data: reportData.map((d) => [
              d.product.name,
              d.product.category,
              d.totalIntakeQty > 0 ? '+${d.totalIntakeQty.toStringAsFixed(1)} ${d.product.unit}' : '0.0 ${d.product.unit}',
              '${d.totalQtySold.toStringAsFixed(1)} ${d.product.unit}',
              d.totalRevenue.toStringAsFixed(2),
              '${d.remainingStock.toStringAsFixed(1)} ${d.product.unit}',
            ]).toList(),
          ),
          pw.SizedBox(height: 30),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Report Generated For: Executive CEO Review', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('System Generated Official Report', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Printed On: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'CEO_Product_Activity_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Map<String, Map<String, dynamic>> _groupSalesByDay(List<SaleRecord> sales) {
    final Map<String, Map<String, dynamic>> groups = {};
    for (final s in sales) {
      final day = DateFormat('yyyy-MM-dd').format(s.timestamp);
      groups[day] = groups[day] ?? {'count': 0, 'total': 0.0};
      groups[day]!['count'] += 1;
      groups[day]!['total'] += s.totalAmount;
    }
    return groups;
  }

  static pw.Widget _buildHeader(String title, DateTime date) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Mi~CORAZON FRESHMEAT BUTCHERY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18, color: _primaryMaroon)),
                pw.Text('Quality Meat Service • Ghana', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text('Report Date: ${DateFormat('yyyy-MM-dd').format(date)}', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 2, color: _primaryMaroon),
        pw.SizedBox(height: 20),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 1, color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by MS Management System', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummarySection(Map<String, String> data) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: data.entries.map((e) => pw.Column(
          children: [
            pw.Text(e.key, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Text(e.value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        )).toList(),
      ),
    );
  }
}

