import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final NumberFormat currency = NumberFormat.currency(symbol: '₱');
  late final Stream<QuerySnapshot> Function(int year, [int? quarter]) _profitStreamForPeriod;
  late final Stream<QuerySnapshot> Function(int year, [int? quarter]) _cashFlowStreamForPeriod;
  late final Stream<QuerySnapshot> _assetStream;
  late final Stream<QuerySnapshot> _liabilityStream;
  double totalIncome = 0;
  double totalExpense = 0;
  double totalAssets = 0;
  double totalLiabilities = 0;
  double totalCashInflow = 0;
  double totalCashOutflow = 0;
  double totalEquity = 0;
  double cashPosition = 0;
  List<FlSpot> forecastNet = [];
  int _selectedYear = DateTime.now().year;
  String _selectedPeriod = 'annual'; // 'annual' or 'quarterly'
  int _selectedQuarter = 1;
  final GlobalKey _forecastChartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (_uid != null) {
      _profitStreamForPeriod = (int year, [int? quarter]) {
        final dates = _getPeriodDates(year, quarter);
        return FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('profitRecords')
            .where('date', isGreaterThanOrEqualTo: dates.start)
            .where('date', isLessThan: dates.end)
            .orderBy('date', descending: true)
            .snapshots();
      };
      _cashFlowStreamForPeriod = (int year, [int? quarter]) {
        final dates = _getPeriodDates(year, quarter);
        return FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('cashFlowEntries')
            .where('date', isGreaterThanOrEqualTo: dates.start)
            .where('date', isLessThan: dates.end)
            .orderBy('date', descending: true)
            .snapshots();
      };
      _assetStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('assets')
          .limit(50)
          .snapshots();
      _liabilityStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('liabilities')
          .limit(50)
          .snapshots();
    }
  }

  ({Timestamp start, Timestamp end}) _getPeriodDates(int year, [int? quarter]) {
    if (quarter == null) {
      return (
      start: Timestamp.fromDate(DateTime(year, 1, 1)),
      end: Timestamp.fromDate(DateTime(year + 1, 1, 1))
      );
    } else {
      final startMonth = (quarter - 1) * 3 + 1;
      final startDate = DateTime(year, startMonth, 1);
      final endDate = DateTime(year, startMonth + 3, 1);
      return (
      start: Timestamp.fromDate(startDate),
      end: Timestamp.fromDate(endDate)
      );
    }
  }

  Future<void> _calculateAllTotals(
      List<QueryDocumentSnapshot> profits,
      List<QueryDocumentSnapshot> cashFlows,
      List<QueryDocumentSnapshot> assets,
      List<QueryDocumentSnapshot> liabilities,
      ) async {
    totalIncome = 0.0;
    totalExpense = 0.0;
    totalCashInflow = 0.0;
    totalCashOutflow = 0.0;
    totalAssets = 0.0;
    totalLiabilities = 0.0;
    totalEquity = 0.0;
    cashPosition = 0.0;
    forecastNet = [];

    for (final doc in profits) {
      final d = doc.data() as Map<String, dynamic>?;
      final customParams = d?['customParameters'] as Map<String, dynamic>? ?? {};
      for (final entry in customParams.entries) {
        final paramData = entry.value as Map<String, dynamic>?;
        if (paramData == null) continue;
        final value = _toDouble(paramData['value']);
        final type = paramData['type'] as String?;
        if (type == 'income') {
          totalIncome += value;
        } else if (type == 'expense') {
          totalExpense += value;
        }
      }
    }

    totalCashInflow = cashFlows.fold(0.0, (a, e) {
      final d = e.data() as Map<String, dynamic>?;
      return (d != null &&
          d.containsKey('type') &&
          (d['type'] as String?)?.toLowerCase() == 'inflow')
          ? a + _toDouble(d['amount'])
          : a;
    });
    totalCashOutflow = cashFlows.fold(0.0, (a, e) {
      final d = e.data() as Map<String, dynamic>?;
      return (d != null &&
          d.containsKey('type') &&
          (d['type'] as String?)?.toLowerCase() == 'outflow')
          ? a + _toDouble(d['amount'])
          : a;
    });

    double initialCapital = 0;
    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(_uid!).get();
      initialCapital = (userDoc.data()?['initialCapital'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {}

    cashPosition = initialCapital;
    for (var doc in cashFlows) {
      final data = doc.data() as Map<String, dynamic>;
      final amount = (data['amount'] ?? 0).toDouble();
      final type = (data['type'] as String?)?.toLowerCase() ?? 'inflow';
      cashPosition += (type == 'inflow' ? amount : -amount);
    }

    double physicalAssets = assets.fold(0.0, (a, e) {
      final d = e.data() as Map<String, dynamic>?;
      return a + _toDouble(d?['value']);
    });
    totalAssets = physicalAssets + (cashPosition > 0 ? cashPosition : 0);

    double physicalLiabilities = liabilities.fold(0.0, (a, e) {
      final d = e.data() as Map<String, dynamic>?;
      return a + _toDouble(d?['amount']);
    });
    totalLiabilities = physicalLiabilities + (cashPosition < 0 ? cashPosition.abs() : 0);

    double retainedEarnings = totalIncome - totalExpense;
    totalEquity = initialCapital + retainedEarnings;

    final balanceDifference = totalAssets - (totalLiabilities + totalEquity);
    if (balanceDifference.abs() > 0.01) totalEquity += balanceDifference;

    if (profits.isNotEmpty) {
      _buildForecast(profits);
    } else {
      forecastNet = [];
    }
  }

  void _buildForecast(List<QueryDocumentSnapshot> profits) {
    final monthly = <DateTime, double>{};
    for (final doc in profits) {
      final d = doc.data() as Map<String, dynamic>?;
      final date = (d != null && d.containsKey('date'))
          ? (d['date'] as Timestamp?)?.toDate()
          : DateTime.now();
      final month = DateTime(date!.year, date.month);
      double income = 0, expenses = 0;
      if (d != null) {
        final customParams = d['customParameters'] as Map<String, dynamic>? ?? {};
        for (final entry in customParams.entries) {
          final paramData = entry.value as Map<String, dynamic>?;
          if (paramData == null) continue;
          final value = _toDouble(paramData['value']);
          final type = paramData['type'] as String?;
          if (type == 'income') {
            income += value;
          } else if (type == 'expense') {
            expenses += value;
          }
        }
      }
      final net = income - expenses;
      monthly.update(month, (v) => v + net, ifAbsent: () => net);
    }

    if (monthly.isEmpty) {
      forecastNet = [];
      return;
    }

    final avg = monthly.values.reduce((a, b) => a + b) / monthly.length;
    final lastMonths = monthly.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final forecast = List<double>.generate(6, (i) {
      if (i < lastMonths.length) return lastMonths[i].value;
      return avg;
    });

    forecastNet = forecast
        .asMap()
        .entries
        .map((e) => FlSpot((e.key + 1).toDouble(), e.value))
        .toList();
  }

  double _toDouble(dynamic val) => (val as num?)?.toDouble() ?? 0.0;

  Future<void> _recordBalanceSheet() async {
    if (_uid == null) return;
    final now = DateTime.now();
    final periodLabel = _selectedPeriod == 'annual'
        ? 'Annual'
        : 'Q$_selectedQuarter';
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('balanceSheetRecords')
          .doc('${periodLabel}_$_selectedYear${DateFormat('HHmmss').format(now)}')
          .set({
        'assets': totalAssets,
        'liabilities': totalLiabilities,
        'equity': totalEquity,
        'cashPosition': cashPosition,
        'recordedAt': Timestamp.fromDate(now),
        'year': _selectedYear,
        'period': _selectedPeriod,
        if (_selectedPeriod == 'quarterly') 'quarter': _selectedQuarter,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  String _getPeriodLabelForPdf() {
    if (_selectedPeriod == 'annual') {
      return 'Year Ended December 31, $_selectedYear';
    } else {
      final quarterEnds = [
        DateTime(_selectedYear, 3, 31),
        DateTime(_selectedYear, 6, 30),
        DateTime(_selectedYear, 9, 30),
        DateTime(_selectedYear, 12, 31),
      ];
      final endDate = quarterEnds[_selectedQuarter - 1];
      return 'Quarter Ended ${DateFormat('MMMM dd, yyyy').format(endDate)}';
    }
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document(version: PdfVersion.pdf_1_5, compress: true);
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();

    String formatPdfCurrency(double amount) {
      final formatted = NumberFormat('#,##0.00', 'en_US').format(amount);
      return 'PHP $formatted';
    }

    final now = DateTime.now();
    final reportGeneratedOn = 'Generated on ${DateFormat('MMMM dd, yyyy \'at\' hh:mm a').format(now)}';
    String userName = 'User';
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_uid!).get();
      userName = (userDoc.data()?['displayName'] as String?) ?? 'User';
    } catch (_) {}

    Uint8List? chartBytes;
    try {
      final boundary = _forecastChartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final ui.Image image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        chartBytes = byteData?.buffer.asUint8List();
      }
    } catch (_) {}

    final periodLabel = _getPeriodLabelForPdf();
    final hasData = totalIncome != 0 || totalExpense != 0 || totalCashInflow != 0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        userName,
                        style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.grey900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Financial Report',
                        style: pw.TextStyle(font: bold, fontSize: 20, color: PdfColors.blue900),
                      ),
                      pw.Text(
                        periodLabel,
                        style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                  pw.Container(
                    height: 50,
                    width: 50,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue500,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'F',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 24, font: bold),
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 28),
              if (!hasData)
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'No financial records found for this period.',
                        style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        periodLabel,
                        style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                )
              else ...[
                _buildPdfSection(
                  title: 'Statement of Profit and Loss',
                  children: [
                    _pdfDataRow('Total Revenue', formatPdfCurrency(totalIncome), font, bold, isPositive: true),
                    _pdfDataRow('Total Expenses', formatPdfCurrency(totalExpense), font, bold, isNegative: true),
                    pw.SizedBox(height: 6),
                    _pdfDataRow('Net Profit', formatPdfCurrency(totalIncome - totalExpense), font, bold,
                        isBold: true,
                        isPositive: totalIncome - totalExpense >= 0,
                        isNegative: totalIncome - totalExpense < 0),
                  ],
                  font: font,
                  bold: bold,
                ),
                pw.SizedBox(height: 20),
                _buildPdfSection(
                  title: 'Statement of Financial Position',
                  children: [
                    _pdfDataRow('Total Assets', formatPdfCurrency(totalAssets), font, bold),
                    _pdfDataRow('Total Liabilities', formatPdfCurrency(totalLiabilities), font, bold),
                    pw.SizedBox(height: 6),
                    _pdfDataRow('Total Equity', formatPdfCurrency(totalEquity), font, bold, isBold: true),
                    _pdfDataRow('Cash Position', formatPdfCurrency(cashPosition), font, bold,
                        isBold: true,
                        isPositive: cashPosition >= 0,
                        isNegative: cashPosition < 0),
                  ],
                  font: font,
                  bold: bold,
                ),
                pw.SizedBox(height: 20),
                _buildPdfSection(
                  title: 'Statement of Cash Flows',
                  children: [
                    _pdfDataRow('Cash Inflow', formatPdfCurrency(totalCashInflow), font, bold),
                    _pdfDataRow('Cash Outflow', formatPdfCurrency(totalCashOutflow), font, bold),
                    pw.SizedBox(height: 6),
                    _pdfDataRow('Net Cash Flow', formatPdfCurrency(totalCashInflow - totalCashOutflow), font, bold,
                        isBold: true),
                  ],
                  font: font,
                  bold: bold,
                ),
                pw.SizedBox(height: 20),
                _buildPdfSection(
                  title: 'Key Financial Metrics',
                  children: [
                    _pdfDataRow(
                      'Net Profit Margin',
                      totalIncome > 0
                          ? '${((totalIncome - totalExpense) / totalIncome * 100).toStringAsFixed(1)}%'
                          : '0.0%',
                      font,
                      bold,
                    ),
                    _pdfDataRow(
                      'Debt-to-Asset Ratio',
                      totalAssets > 0 ? '${(totalLiabilities / totalAssets * 100).toStringAsFixed(1)}%' : '0.0%',
                      font,
                      bold,
                    ),
                    _pdfDataRow(
                      'Return on Equity',
                      totalEquity > 0
                          ? '${((totalIncome - totalExpense) / totalEquity * 100).toStringAsFixed(1)}%'
                          : '0.0%',
                      font,
                      bold,
                    ),
                  ],
                  font: font,
                  bold: bold,
                ),
                pw.SizedBox(height: 20),
                if (chartBytes != null || forecastNet.isNotEmpty)
                  _buildPdfSection(
                    title: '6-Month Net Profit Forecast',
                    children: [
                      pw.Container(
                        height: 120,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: chartBytes != null
                            ? pw.Center(child: pw.Image(pw.MemoryImage(chartBytes), fit: pw.BoxFit.contain))
                            : pw.Center(
                          child: pw.Text(
                            'Chart unavailable',
                            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600),
                          ),
                        ),
                      ),
                      if (forecastNet.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 8),
                          child: pw.Text(
                            'Average Forecasted Net Profit: ${formatPdfCurrency(forecastNet.map((e) => e.y).reduce((a, b) => a + b) / forecastNet.length)}',
                            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700),
                          ),
                        ),
                    ],
                    font: font,
                    bold: bold,
                  ),
              ],
              // Footer
              pw.Spacer(),
              pw.Divider(height: 1, color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    reportGeneratedOn,
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey500),
                  ),
                  pw.Text(
                    'Page 1 of 1',
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey500),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfSection({
    required String title,
    required List<pw.Widget> children,
    required pw.Font font,
    required pw.Font bold,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.blue900),
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(6),
                bottomRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfDataRow(
      String label,
      String value,
      pw.Font font,
      pw.Font bold, {
        bool isBold = false,
        bool isPositive = false,
        bool isNegative = false,
      }) {
    PdfColor valueColor = PdfColors.grey900;
    if (isPositive) valueColor = PdfColors.green800;
    if (isNegative) valueColor = PdfColors.red800;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey700),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: isBold ? bold : font,
              fontSize: 11,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPdfPreview() async {
    try {
      final bytes = await _generatePdf();
      if (!mounted) return;
      final periodSuffix = _selectedPeriod == 'annual'
          ? '$_selectedYear'
          : 'Q$_selectedQuarter-$_selectedYear';
      final filename = 'financial_report_$periodSuffix${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text('${_selectedPeriod == "annual" ? "Annual" : "Quarterly"} Report $_selectedYear'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: PdfPreview(
              build: (format) => bytes,
              allowSharing: true,
              allowPrinting: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: filename,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: Text('Login to see reports')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Reports'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generate PDF',
            onPressed: _showPdfPreview,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ FIXED: Period Selector with constrained widths and horizontal scroll
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleButtons(
                    isSelected: [_selectedPeriod == 'annual', _selectedPeriod == 'quarterly'],
                    onPressed: (int index) {
                      setState(() {
                        _selectedPeriod = index == 0 ? 'annual' : 'quarterly';
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('Annual')),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('Quarterly')),
                    ],
                  ),
                  const SizedBox(width: 12),
                  if (_selectedPeriod == 'annual') ...[
                    const Text('Year:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 80,
                      child: DropdownButton<int>(
                        value: _selectedYear,
                        items: List.generate(10, (index) => DateTime.now().year - index)
                            .map((year) => DropdownMenuItem<int>(value: year, child: Text('$year')))
                            .toList(),
                        onChanged: (int? value) {
                          if (value != null) {
                            setState(() {
                              _selectedYear = value;
                            });
                          }
                        },
                        isExpanded: true,
                      ),
                    ),
                  ] else ...[
                    const Text('Quarter:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 60,
                      child: DropdownButton<int>(
                        value: _selectedQuarter,
                        items: [1, 2, 3, 4]
                            .map((q) => DropdownMenuItem<int>(value: q, child: Text('Q$q')))
                            .toList(),
                        onChanged: (int? value) {
                          if (value != null) {
                            setState(() {
                              _selectedQuarter = value;
                            });
                          }
                        },
                        isExpanded: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 70,
                      child: DropdownButton<int>(
                        value: _selectedYear,
                        items: List.generate(5, (index) => DateTime.now().year - index)
                            .map((year) => DropdownMenuItem<int>(value: year, child: Text('$year')))
                            .toList(),
                        onChanged: (int? value) {
                          if (value != null) {
                            setState(() {
                              _selectedYear = value;
                            });
                          }
                        },
                        isExpanded: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _profitStreamForPeriod(_selectedYear, _selectedPeriod == 'quarterly' ? _selectedQuarter : null),
                builder: (context, profitSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _cashFlowStreamForPeriod(_selectedYear, _selectedPeriod == 'quarterly' ? _selectedQuarter : null),
                    builder: (context, cashFlowSnap) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: _assetStream,
                        builder: (context, assetSnap) {
                          return StreamBuilder<QuerySnapshot>(
                            stream: _liabilityStream,
                            builder: (context, liabilitySnap) {
                              if (!profitSnap.hasData ||
                                  !cashFlowSnap.hasData ||
                                  !assetSnap.hasData ||
                                  !liabilitySnap.hasData) {
                                return _loading();
                              }
                              final profits = profitSnap.data!.docs;
                              final cashFlows = cashFlowSnap.data!.docs;
                              final assets = assetSnap.data!.docs;
                              final liabilities = liabilitySnap.data!.docs;
                              final hasProfitData = profits.isNotEmpty;
                              final hasCashFlowData = cashFlows.isNotEmpty;
                              return FutureBuilder<void>(
                                future: _calculateAllTotals(profits, cashFlows, assets, liabilities),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return _loading();
                                  }
                                  _recordBalanceSheet();
                                  return _buildFilledUI(hasProfitData || hasCashFlowData);
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilledUI(bool hasDataForPeriod) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 600;
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                if (!hasDataForPeriod)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _selectedPeriod == 'annual'
                              ? 'No financial records found for $_selectedYear.'
                              : 'No financial records found for Q$_selectedQuarter $_selectedYear.',
                          style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  wide
                      ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildBalanceCard()),
                      const SizedBox(width: 12),
                      Expanded(flex: 5, child: _buildProfitCard()),
                    ],
                  )
                      : Column(
                    children: [
                      _buildBalanceCard(),
                      const SizedBox(height: 12),
                      _buildProfitCard(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCashFlowCard(),
                  const SizedBox(height: 12),
                  _buildForecastCard(),
                  const SizedBox(height: 24),
                ],
                _buildBottomBar(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBalanceCard() {
    final balanced = (totalAssets - (totalLiabilities + totalEquity)).abs() <= 0.01;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text('Balance Sheet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: balanced ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    balanced ? 'Balanced' : 'Auto-balanced',
                    style: TextStyle(
                      color: balanced ? Colors.green.shade800 : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _metricRow('Assets', currency.format(totalAssets), Colors.green),
            _metricRow('Liabilities', currency.format(totalLiabilities), Colors.red),
            _metricRow('Equity', currency.format(totalEquity), Colors.blue),
            const Divider(height: 20),
            _metricRow('Cash Position', currency.format(cashPosition),
                cashPosition >= 0 ? Colors.green : Colors.red,
                bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitCard() {
    final net = totalIncome - totalExpense;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                const Text('Profit & Loss', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: net >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    net >= 0 ? 'Profitable' : 'Loss-making',
                    style: TextStyle(
                      color: net >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _metricRow('Revenue', currency.format(totalIncome), Colors.green),
            _metricRow('Expenses', currency.format(totalExpense), Colors.red),
            const Divider(height: 20),
            _metricRow('Net Profit', currency.format(net), net >= 0 ? Colors.green : Colors.red, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildCashFlowCard() {
    final net = totalCashInflow - totalCashOutflow;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                const Text('Cash Flow', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: net >= 0 ? Colors.blue.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    net >= 0 ? 'Net positive' : 'Net negative',
                    style: TextStyle(
                      color: net >= 0 ? Colors.blue.shade800 : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _metricRow('Inflow', currency.format(totalCashInflow), Colors.green)),
                const SizedBox(width: 16),
                Expanded(child: _metricRow('Outflow', currency.format(totalCashOutflow), Colors.red)),
              ],
            ),
            const Divider(height: 20),
            _metricRow('Net Cash Flow', currency.format(net), net >= 0 ? Colors.blue : Colors.orange, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildForecastCard() {
    final avg = forecastNet.isEmpty
        ? 0.0
        : forecastNet.map((e) => e.y).reduce((a, b) => a + b) / forecastNet.length;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                const Text('6-Month Forecast', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (forecastNet.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Avg / m: ${currency.format(avg)}',
                      style: TextStyle(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: _forecastChartKey,
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: forecastNet.isEmpty
                    ? const Center(child: Text('No forecast data available'))
                    : LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      drawHorizontalLine: true,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 0.5,
                      ),
                      getDrawingVerticalLine: (value) => FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) => val.toInt() >= 1 && val.toInt() <= 6
                              ? Text('${val.toInt()}m', style: const TextStyle(fontSize: 10))
                              : const SizedBox.shrink(),
                          reservedSize: 22,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (val, _) => Text(
                            '₱${val.toInt()}',
                            style: const TextStyle(fontSize: 8),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: forecastNet,
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 3,
                            color: Colors.teal,
                            strokeWidth: 0,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.teal.withValues(alpha: 0.1),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final periodText = _selectedPeriod == 'annual'
        ? 'Annual ($_selectedYear)'
        : 'Quarterly (Q$_selectedQuarter $_selectedYear)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reports reflect $periodText data. Revenue/expenses from profit records; cash flows affect cash position only.',
              style: TextStyle(color: Colors.blue.shade50, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading() => const Center(child: CircularProgressIndicator(strokeWidth: 3));
}