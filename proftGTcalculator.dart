import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfitCalculatorPage extends StatefulWidget {
  const ProfitCalculatorPage({super.key});

  @override
  State<ProfitCalculatorPage> createState() => _ProfitCalculatorPageState();
}

class CustomParameter {
  String name;
  TextEditingController controller;
  String type;
  IconData icon;
  CustomParameter({
    required this.name,
    required this.type,
    required this.icon,
  }) : controller = TextEditingController();
  void dispose() => controller.dispose();
}

class ChartDataPoint {
  final DateTime date;
  final double profit;
  final String label;
  ChartDataPoint({
    required this.date,
    required this.profit,
    required this.label,
  });
}

class GraduatedTaxResult {
  final double grossIncome;
  final double totalExpenses;
  final double netTaxableIncome;
  final double incomeTax;
  final double netProfitAfterTax;
  final bool isTaxExempt;
  // Annual fields
  final double annualGrossIncome;
  final double annualExpenses;
  final double annualNetTaxableIncome;
  final double annualIncomeTax;
  final double annualNetProfitAfterTax;
  final bool isAnnualTaxExempt;
  GraduatedTaxResult({
    required this.grossIncome,
    required this.totalExpenses,
    required this.netTaxableIncome,
    required this.incomeTax,
    required this.netProfitAfterTax,
    required this.isTaxExempt,
    required this.annualGrossIncome,
    required this.annualExpenses,
    required this.annualNetTaxableIncome,
    required this.annualIncomeTax,
    required this.annualNetProfitAfterTax,
    required this.isAnnualTaxExempt,
  });
}

// 2025 BIR Graduated Income Tax Brackets (same as 2023–2024 under TRAIN Law)
double calculateGraduatedIncomeTax(double netTaxableIncome) {
  if (netTaxableIncome <= 250000) return 0.0;
  if (netTaxableIncome <= 400000) return (netTaxableIncome - 250000) * 0.15;
  if (netTaxableIncome <= 800000) return 22500 + (netTaxableIncome - 400000) * 0.20;
  if (netTaxableIncome <= 2000000) return 102500 + (netTaxableIncome - 800000) * 0.25;
  if (netTaxableIncome <= 8000000) return 402500 + (netTaxableIncome - 2000000) * 0.30;
  return 2202500 + (netTaxableIncome - 8000000) * 0.35;
}

class _ProfitCalculatorPageState extends State<ProfitCalculatorPage> {
  final _formKey = GlobalKey<FormState>();
  final List<CustomParameter> _customParameters = [];
  final currency = NumberFormat.currency(symbol: '₱');
  DateTime _selectedDate = DateTime.now();
  double _totalIncome = 0;
  double _totalExpenses = 0;
  double _netProfit = 0;
  bool _isLoading = false;
  bool _showResults = false;
  double _bankMoney = 0.0;
  late final String _uid;

  // === NEW: Annual Tax Calculation State ===
  int _selectedTaxYear = DateTime.now().year;
  bool _isCalculatingAnnual = false;
  GraduatedTaxResult? _annualTaxResult;
  bool _showAnnualResults = false;
  bool _isLoadingChart = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  List<ChartDataPoint> _chartData = [];
  late DocumentReference _userDocRef;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _uid = user.uid;
    _userDocRef = FirebaseFirestore.instance.collection('users').doc(_uid);
    _loadSelectedDate();
    _loadChartDateRange();
    _loadBankMoney();
    _loadCustomParameters();
    _loadChartData();
  }

  @override
  void dispose() {
    for (final p in _customParameters) {
      p.dispose();
    }
    super.dispose();
  }

  String _getCategoryFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('rent')) return 'Rent';
    if (lower.contains('utilities') || lower.contains('electric') || lower.contains('water')) return 'Utilities';
    if (lower.contains('salary') || lower.contains('wage')) return 'Salaries';
    if (lower.contains('marketing') || lower.contains('advertising')) return 'Marketing';
    if (lower.contains('operating')) return 'Operating';
    if (lower.contains('tax')) return 'Taxes';
    if (lower.contains('interest')) return 'Interest';
    if (lower.contains('depreciation')) return 'Depreciation';
    return 'Other Expenses';
  }

  Future<void> _loadSelectedDate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_date');
    if (saved != null) {
      final date = DateTime.tryParse(saved);
      if (date != null && mounted) {
        setState(() => _selectedDate = date);
      }
    }
  }

  Future<void> _saveSelectedDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_date', date.toIso8601String());
  }

  Future<void> _loadChartDateRange() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('chart_start_date');
    final endStr = prefs.getString('chart_end_date');
    if (startStr != null) {
      final date = DateTime.tryParse(startStr);
      if (date != null) _startDate = date;
    }
    if (endStr != null) {
      final date = DateTime.tryParse(endStr);
      if (date != null) _endDate = date;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveChartDateRange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chart_start_date', _startDate.toIso8601String());
    await prefs.setString('chart_end_date', _endDate.toIso8601String());
  }

  Future<void> _loadCustomParameters() async {
    try {
      final userDoc = await _userDocRef.get();
      final data = userDoc.data() as Map<String, dynamic>?;
      final customParams = data?['customParameters'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _customParameters.clear();
          for (final param in customParams) {
            if (param is Map<String, dynamic>) {
              _customParameters.add(CustomParameter(
                name: param['name'] as String? ?? '',
                type: param['type'] as String? ?? '',
                icon: _getIconFromString(param['icon'] as String? ?? 'attach_money'),
              ));
            } else {
              debugPrint('⚠️ Skipped invalid parameter: $param');
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error loading parameters: $e', SnackBarType.error);
      }
    }
  }

  Future<void> _saveCustomParameters() async {
    try {
      final paramsData = _customParameters.map((p) => {
        'name': p.name,
        'type': p.type,
        'icon': _getStringFromIcon(p.icon),
      }).toList();
      await _userDocRef.update({'customParameters': paramsData});
    } catch (e) {
      if (mounted) _showSnackBar('Error saving parameters: $e', SnackBarType.error);
    }
  }

  IconData _getIconFromString(String iconName) {
    switch (iconName) {
      case 'attach_money':
        return Icons.attach_money;
      case 'business':
        return Icons.business;
      case 'campaign':
        return Icons.campaign;
      case 'home':
        return Icons.home;
      case 'people':
        return Icons.people;
      case 'savings':
        return Icons.savings;
      case 'receipt':
        return Icons.receipt;
      case 'trending_down':
        return Icons.trending_down;
      case 'inventory':
        return Icons.inventory;
      case 'local_shipping':
        return Icons.local_shipping;
      case 'account_balance':
        return Icons.account_balance;
      case 'credit_card':
        return Icons.credit_card;
      case 'analytics':
        return Icons.analytics;
      case 'shopping_cart':
        return Icons.shopping_cart;
      default:
        return Icons.attach_money;
    }
  }

  String _getStringFromIcon(IconData icon) {
    if (icon == Icons.attach_money) return 'attach_money';
    if (icon == Icons.business) return 'business';
    if (icon == Icons.campaign) return 'campaign';
    if (icon == Icons.home) return 'home';
    if (icon == Icons.people) return 'people';
    if (icon == Icons.savings) return 'savings';
    if (icon == Icons.receipt) return 'receipt';
    if (icon == Icons.trending_down) return 'trending_down';
    if (icon == Icons.inventory) return 'inventory';
    if (icon == Icons.local_shipping) return 'local_shipping';
    if (icon == Icons.account_balance) return 'account_balance';
    if (icon == Icons.credit_card) return 'credit_card';
    if (icon == Icons.analytics) return 'analytics';
    if (icon == Icons.shopping_cart) return 'shopping_cart';
    return 'attach_money';
  }

  Future<void> _loadBankMoney() async {
    try {
      final userDoc = await _userDocRef.get();
      final data = userDoc.data() as Map<String, dynamic>?;
      double initialCapital = (data?['initialCapital'] as num?)?.toDouble() ?? 0;
      final cashFlowSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('cashFlowEntries')
          .get();
      double totalInflows = 0, totalOutflows = 0;
      for (final doc in cashFlowSnapshot.docs) {
        final entryData = doc.data();
        final amount = (entryData['amount'] as num?)?.toDouble() ?? 0;
        final type = (entryData['type'] as String?)?.toLowerCase() ?? '';
        if (type == 'inflow' && amount > 0) {
          totalInflows += amount;
        } else if (type == 'outflow' && amount > 0) {
          totalOutflows += amount;
        }
      }
      if (mounted) {
        setState(() {
          _bankMoney = initialCapital + totalInflows - totalOutflows;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error loading bank money: $e', SnackBarType.error);
      }
    }
  }

  Future<void> _loadChartData() async {
    setState(() => _isLoadingChart = true);
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('profitRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_endDate.add(const Duration(days: 1))))
          .orderBy('date')
          .get();
      final records = query.docs.map((doc) {
        final data = doc.data();
        return {
          'date': (data['date'] as Timestamp).toDate(),
          'afterTaxProfit': (data['netProfit'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
      final chartData = records
          .map((r) => ChartDataPoint(
        date: r['date'] as DateTime,
        profit: r['afterTaxProfit'] as double,
        label: DateFormat('yyyy-MM-dd').format(r['date'] as DateTime),
      ))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (mounted) {
        setState(() {
          _chartData = chartData;
          _isLoadingChart = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error loading chart data: $e', SnackBarType.error);
        setState(() => _isLoadingChart = false);
      }
    }
  }

  void _calculate() {
    double income = 0, expenses = 0;
    for (final p in _customParameters) {
      final rawValue = double.tryParse(p.controller.text.replaceAll(',', '')) ?? 0;
      if (rawValue <= 0) continue;
      if (p.type == 'income') {
        income += rawValue;
      } else {
        expenses += rawValue;
      }
    }
    final currentNet = income - expenses;
    setState(() {
      _totalIncome = income;
      _totalExpenses = expenses;
      _netProfit = currentNet;
      _showResults = income > 0 || expenses > 0;
    });
  }

  // === NEW: Manual Annual Tax Calculation ===
  Future<void> _calculateAnnualTax() async {
    setState(() {
      _isCalculatingAnnual = true;
      _showAnnualResults = false;
      _annualTaxResult = null;
    });
    final startOfYear = DateTime(_selectedTaxYear, 1, 1);
    final endOfYear = DateTime(_selectedTaxYear, 12, 31, 23, 59, 59, 999, 999);
    double annualGrossIncome = 0;
    double annualExpenses = 0;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('profitRecords')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfYear))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfYear))
          .get();
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        annualGrossIncome += (data['grossIncome'] as num?)?.toDouble() ?? 0;
        annualExpenses += (data['expenses'] as num?)?.toDouble() ?? 0;
      }
      final annualNetTaxableIncome = (annualGrossIncome - annualExpenses).clamp(0.0, double.infinity);
      final isAnnualTaxExempt = annualNetTaxableIncome <= 250000;
      final totalAnnualIncomeTax = isAnnualTaxExempt ? 0.0 : calculateGraduatedIncomeTax(annualNetTaxableIncome);
      final annualNetProfitAfterTax = annualNetTaxableIncome - totalAnnualIncomeTax;
      final result = GraduatedTaxResult(
        grossIncome: 0,
        totalExpenses: 0,
        netTaxableIncome: 0,
        incomeTax: 0,
        netProfitAfterTax: 0,
        isTaxExempt: false,
        annualGrossIncome: annualGrossIncome,
        annualExpenses: annualExpenses,
        annualNetTaxableIncome: annualNetTaxableIncome,
        annualIncomeTax: totalAnnualIncomeTax,
        annualNetProfitAfterTax: annualNetProfitAfterTax,
        isAnnualTaxExempt: isAnnualTaxExempt,
      );
      if (mounted) {
        setState(() {
          _annualTaxResult = result;
          _showAnnualResults = true;
          _isCalculatingAnnual = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error calculating annual tax: $e', SnackBarType.error);
        setState(() => _isCalculatingAnnual = false);
      }
    }
  }

  // === NEW: Save Annual Tax Liability ===
  Future<void> _saveAnnualTaxLiability() async {
    if (_annualTaxResult == null || _annualTaxResult!.annualIncomeTax <= 0) return;

    // Check for existing liability for this tax year
    final existingSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('liabilities')
        .where('taxYear', isEqualTo: _selectedTaxYear)
        .where('isTaxLiability', isEqualTo: true)
        .limit(1)
        .get();

    if (existingSnap.docs.isNotEmpty) {
      _showSnackBar('Tax liability for $_selectedTaxYear already exists.', SnackBarType.info);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('liabilities')
          .add({
        'name': 'Income Tax Payable ($_selectedTaxYear)',
        'amount': _annualTaxResult!.annualIncomeTax,
        'type': 'Tax Liability',
        'date': Timestamp.fromDate(DateTime(_selectedTaxYear, 12, 31)),
        'dueDate': Timestamp.fromDate(DateTime(_selectedTaxYear + 1, 4, 15)), // BIR annual deadline
        'isTaxLiability': true,
        'taxYear': _selectedTaxYear,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackBar('Tax liability recorded for $_selectedTaxYear', SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to save tax liability: $e', SnackBarType.error);
      }
    }
  }

  Future<void> _saveCalculation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalIncome <= 0 && _totalExpenses <= 0) {
      _showSnackBar('Enter at least one income or expense value', SnackBarType.error);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final recordRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('profitRecords')
          .doc();
      final customData = <String, dynamic>{};
      for (final p in _customParameters) {
        final v = double.tryParse(p.controller.text.replaceAll(',', '')) ?? 0;
        if (v > 0) customData[p.name] = {'value': v, 'type': p.type};
      }
      await recordRef.set({
        'month': DateFormat('yyyy-MM').format(_selectedDate),
        'grossIncome': _totalIncome,
        'expenses': _totalExpenses,
        'netProfit': _netProfit,
        'customParameters': customData,
        'date': Timestamp.fromDate(_selectedDate),
        'createdAt': FieldValue.serverTimestamp(),
        'taxYear': _selectedDate.year,
      });
      final batch = FirebaseFirestore.instance.batch();
      final dateLabel = DateFormat('MMM d').format(_selectedDate);
      for (final p in _customParameters) {
        final value = double.tryParse(p.controller.text.replaceAll(',', '')) ?? 0;
        if (value > 0) {
          final paramRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('cashFlowEntries').doc();
          batch.set(paramRef, {
            'description': '${p.name} ($dateLabel)',
            'amount': value,
            'type': p.type == 'income' ? 'inflow' : 'outflow',
            'category': p.type == 'income' ? 'Other Income' : _getCategoryFromName(p.name),
            'date': Timestamp.fromDate(_selectedDate),
            'createdAt': FieldValue.serverTimestamp(),
            'profitRecordId': recordRef.id,
            'isAutogenerated': true,
          });
        }
      }
      await batch.commit();
      await _loadBankMoney();
      if (mounted) {
        _showSnackBar('Saved successfully!', SnackBarType.success);
        _clearForm();
        _loadChartData();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error saving: $e', SnackBarType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecord(String profitRecordId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('This will remove the profit record and cash flows. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _isLoading = true);
    try {
      final cashFlowQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('cashFlowEntries')
          .where('profitRecordId', isEqualTo: profitRecordId)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in cashFlowQuery.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(FirebaseFirestore.instance.collection('users').doc(_uid).collection('profitRecords').doc(profitRecordId));
      await batch.commit();
      await _loadBankMoney();
      if (mounted) {
        _showSnackBar('Record deleted successfully', SnackBarType.success);
        _loadChartData();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error deleting: $e', SnackBarType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRecordDetails(Map<String, dynamic> recordData, String recordId, DateTime date) {
    showDialog(
      context: context,
      builder: (context) => _RecordDetailsDialog(
        recordData: recordData,
        recordId: recordId,
        date: date,
        currency: currency,
        onDelete: () {
          Navigator.pop(context);
          _deleteRecord(recordId);
        },
      ),
    );
  }

  void _clearForm() {
    for (final p in _customParameters) {
      p.controller.clear();
    }
    setState(() {
      _totalIncome = _totalExpenses = _netProfit = 0;
      _showResults = false;
      _selectedDate = DateTime.now();
      _saveSelectedDate(_selectedDate);
    });
    FocusScope.of(context).unfocus();
  }

  void _addCustomParameter() {
    showDialog(
      context: context,
      builder: (context) => _AddParameterDialog(
        onAdd: (name, type, icon) async {
          setState(() {
            _customParameters.add(CustomParameter(name: name, type: type, icon: icon));
          });
          await _saveCustomParameters();
        },
      ),
    );
  }

  Future<void> _removeCustomParameter(CustomParameter param) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text('Are you sure you want to remove "${param.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[600]),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        param.dispose();
        _customParameters.remove(param);
        _calculate();
      });
      await _saveCustomParameters();
    }
  }

  void _showSnackBar(String message, SnackBarType type) {
    if (!mounted) return;
    final config = _getSnackBarConfig(type);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (config.icon != null) ...[
              config.isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(config.icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: config.color,
        behavior: config.isLoading ? SnackBarBehavior.fixed : SnackBarBehavior.floating,
        shape: config.isLoading
            ? null
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: config.isLoading ? null : const EdgeInsets.all(16),
        duration: config.isLoading ? const Duration(minutes: 1) : const Duration(seconds: 3),
      ),
    );
  }

  _SnackBarConfig _getSnackBarConfig(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return _SnackBarConfig(icon: Icons.check_circle, color: Colors.green[600]!);
      case SnackBarType.error:
        return _SnackBarConfig(icon: Icons.error_outline, color: Colors.red[600]!);
      case SnackBarType.info:
        return _SnackBarConfig(icon: Icons.info_outline, color: Colors.blue[600]!);
      case SnackBarType.loading:
        return _SnackBarConfig(icon: Icons.hourglass_empty, color: Colors.blue[600]!, isLoading: true);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _saveSelectedDate(picked);
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: _endDate,
    );
    if (picked != null && mounted) {
      setState(() => _startDate = picked);
      _saveChartDateRange();
      _loadChartData();
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
      _saveChartDateRange();
      _loadChartData();
    }
  }

  // === NEW: Select Tax Year (Year-only picker) ===
  Future<void> _selectTaxYear() async {
    final currentYear = DateTime.now().year;
    const minYear = 2020;
    final maxYear = currentYear + 1;
    final selectedYear = await showDialog<int>(
      context: context,
      builder: (context) {
        int selected = _selectedTaxYear;
        return AlertDialog(
          title: const Text('Select Tax Year'),
          content: SizedBox(
            width: 250,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Pick a year between $minYear and $maxYear'),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selected,
                  items: List.generate(maxYear - minYear + 1, (i) {
                    final year = minYear + i;
                    return DropdownMenuItem<int>(value: year, child: Text('$year'));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      selected = value;
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Year',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (selectedYear != null && mounted) {
      setState(() => _selectedTaxYear = selectedYear);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Profit Calculator', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey[200]),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Parameter',
            icon: Icon(Icons.add, color: Colors.blue[600]),
            onPressed: _addCustomParameter,
          ),
          IconButton(
            tooltip: 'Clear Form',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _clearForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadBankMoney();
            await _loadChartData();
          },
          color: Colors.blue[600],
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBankMoneyCard(),
                const SizedBox(height: 24),
                _buildTaxInfoCard(),
                const SizedBox(height: 24),
                _buildAnnualTaxCard(), // <<< NEW SECTION
                const SizedBox(height: 24),
                _buildCalculatorCard(),
                if (_showResults) ...[
                  const SizedBox(height: 24),
                  _buildResultsCard(),
                ],
                const SizedBox(height: 24),
                _buildProfitChart(),
                const SizedBox(height: 24),
                _buildRecentRecords(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // === NEW: Annual Tax Card ===
  Widget _buildAnnualTaxCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Annual Tax Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Select a tax year and click "Calculate Annual Tax" to check your tax exemption status and liabilities.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.date_range, color: Colors.purple),
            title: const Text('Tax Year', style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('$_selectedTaxYear'),
            onTap: _selectTaxYear,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isCalculatingAnnual ? null : _calculateAnnualTax,
            icon: _isCalculatingAnnual
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                : const Icon(Icons.calculate),
            label: Text(_isCalculatingAnnual ? 'Calculating...' : 'Calculate Annual Tax'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_showAnnualResults && _annualTaxResult != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _annualTaxResult!.isAnnualTaxExempt ? Colors.green[50] : Colors.orange[50],
                border: Border.all(color: _annualTaxResult!.isAnnualTaxExempt ? Colors.green : Colors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _annualTaxResult!.isAnnualTaxExempt ? Icons.check_circle : Icons.warning,
                        color: _annualTaxResult!.isAnnualTaxExempt ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _annualTaxResult!.isAnnualTaxExempt ? '✅ TAX EXEMPT' : '⚠️ TAX APPLIES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _annualTaxResult!.isAnnualTaxExempt ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _resultRow('Annual Gross Income', _annualTaxResult!.annualGrossIncome, Colors.black87),
                  _resultRow('Annual Expenses', _annualTaxResult!.annualExpenses, Colors.black87),
                  _resultRow('Annual Net Taxable Income', _annualTaxResult!.annualNetTaxableIncome, Colors.blue),
                  const Divider(color: Colors.grey),
                  _resultRow('Annual Income Tax Due', _annualTaxResult!.annualIncomeTax, Colors.red),
                  _resultRow('Annual Net Profit After Tax', _annualTaxResult!.annualNetProfitAfterTax, Colors.green),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // === NEW: Record Liability Button ===
            if (!_annualTaxResult!.isAnnualTaxExempt && _annualTaxResult!.annualIncomeTax > 0)
              ElevatedButton.icon(
                onPressed: _saveAnnualTaxLiability,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Record Tax Liability'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBankMoneyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.account_balance_wallet, color: Colors.blue[700], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Current Cash Balance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
              Text(currency.format(_bankMoney), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
          ),
          IconButton(
            icon: _isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue[600]))
                : const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadBankMoney,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildTaxInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tax Rules (2025 Graduated Income Tax)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              children: const [
                TextSpan(text: '• All income is aggregated annually as Gross Income\n'),
                TextSpan(text: '• Expenses are deducted annually to get Net Taxable Income\n'),
                TextSpan(text: '• If Annual Net Taxable Income ≤ ₱250,000 → Tax Exempt (0% tax)\n'),
                TextSpan(text: '• Otherwise, graduated rates apply: 15%–35%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Business Calculation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Add income and expense parameters below. Enter values and tap "Calculate" to preview your profit.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          if (_customParameters.isNotEmpty) ...[
            for (final p in _customParameters) _customParam(p),
          ],
          if (_customParameters.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap the + button above to add custom income or expense parameters',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          _datePicker(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _calculate,
                  icon: const Icon(Icons.calculate, color: Colors.blue),
                  label: const Text('Calculate'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveCalculation,
                  icon: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Icon(Icons.save),
                  label: Text(_isLoading ? 'Saving...' : 'Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                child: Icon(_netProfit >= 0 ? Icons.trending_up : Icons.trending_down, color: _netProfit >= 0 ? Colors.green : Colors.red, size: 24),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _netProfit >= 0 ? 'Profit' : 'Loss',
                  style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Net Profit (Before Tax)', style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            currency.format(_netProfit),
            style: const TextStyle(color: Colors.black87, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _resultRow('Your Entry Income', _totalIncome, Colors.black87),
          _resultRow('Your Entry Expenses', _totalExpenses, Colors.black87),
          const Divider(color: Colors.black26),
          _resultRow('New Cash Balance', _bankMoney + _netProfit, Colors.black87),
        ],
      ),
    );
  }

  Widget _buildProfitChart() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Profit Trends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
                onPressed: _loadChartData,
                tooltip: 'Refresh chart',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Adjust the date range to view historical profit records.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                  title: const Text('From', style: TextStyle(fontSize: 13)),
                  subtitle: Text(DateFormat('MMM d, y').format(_startDate)),
                  onTap: _selectStartDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today, size: 18, color: Colors.green),
                  title: const Text('To', style: TextStyle(fontSize: 13)),
                  subtitle: Text(DateFormat('MMM d, y').format(_endDate)),
                  onTap: _selectEndDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_chartData.isNotEmpty) ...[
            _buildProfitSummaryCards(),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 260,
            child: _isLoadingChart
                ? const Center(child: CircularProgressIndicator())
                : _chartData.isEmpty
                ? _buildEmptyState(
              icon: Icons.show_chart,
              title: 'No Profit Data',
              subtitle: 'Select a date range with saved profit records',
            )
                : LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                  getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: _getBottomTitleWidget,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 80,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(_formatChartValue(value), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                minX: 0,
                maxX: (_chartData.length - 1).toDouble(),
                minY: _getMinY(),
                maxY: _getMaxY(),
                lineBarsData: [
                  LineChartBarData(
                    spots: _chartData.asMap().entries.map((entry) => FlSpot(entry.key.toDouble(), entry.value.profit)).toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 5,
                        color: spot.y >= 0 ? Colors.green : Colors.red,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(show: true, color: Colors.blue.withValues(alpha: 0.1)),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.blue.shade900,
                    tooltipRoundedRadius: 10,
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        final dataPoint = _chartData[barSpot.x.toInt()];
                        return LineTooltipItem(
                          '${DateFormat('MMM d, yyyy').format(dataPoint.date)}\n${currency.format(barSpot.y)}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitSummaryCards() {
    if (_chartData.isEmpty) return const SizedBox.shrink();
    Map<String, double> daily = {}, weekly = {}, monthly = {}, yearly = {};
    for (var p in _chartData) {
      String dailyKey = DateFormat('yyyy-MM-dd').format(p.date);
      String weekKey = '${p.date.year}-W${((p.date.difference(DateTime(p.date.year, 1, 1)).inDays) / 7).floor() + 1}';
      String monthKey = DateFormat('yyyy-MM').format(p.date);
      String yearKey = p.date.year.toString();
      daily[dailyKey] = (daily[dailyKey] ?? 0) + p.profit;
      weekly[weekKey] = (weekly[weekKey] ?? 0) + p.profit;
      monthly[monthKey] = (monthly[monthKey] ?? 0) + p.profit;
      yearly[yearKey] = (yearly[yearKey] ?? 0) + p.profit;
    }
    double avgDaily = daily.isEmpty ? 0 : daily.values.fold(0.0, (a, b) => a + b) / daily.length;
    double avgWeekly = weekly.isEmpty ? 0 : weekly.values.fold(0.0, (a, b) => a + b) / weekly.length;
    double avgMonthly = monthly.isEmpty ? 0 : monthly.values.fold(0.0, (a, b) => a + b) / monthly.length;
    double avgYearly = yearly.isEmpty ? 0 : yearly.values.fold(0.0, (a, b) => a + b) / yearly.length;
    return SizedBox(
      height: 75,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildSummaryCard('Avg Daily', avgDaily, Icons.calendar_today),
          const SizedBox(width: 10),
          _buildSummaryCard('Avg Weekly', avgWeekly, Icons.calendar_view_week),
          const SizedBox(width: 10),
          _buildSummaryCard('Avg Monthly', avgMonthly, Icons.calendar_month),
          const SizedBox(width: 10),
          _buildSummaryCard('Avg Yearly', avgYearly, Icons.date_range),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, double value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(currency.format(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentRecords() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'Tap any record to view details or delete it.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_uid)
                  .collection('profitRecords')
                  .orderBy('createdAt', descending: true)
                  .limit(500)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return _buildErrorState(message: 'Error: ${snap.error}', onRetry: () => _loadChartData());
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No Records Yet',
                    subtitle: 'Your profit records will appear here after saving',
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final netProfit = (d['netProfit'] ?? 0.0).toDouble();
                    final date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      elevation: 1,
                      shadowColor: Colors.black.withValues(alpha: 0.05),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showRecordDetails(d, docs[i].id, date),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: netProfit >= 0 ? Colors.green[50] : Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  netProfit >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                  color: netProfit >= 0 ? Colors.green[700] : Colors.red[700],
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Net Profit: ${currency.format(netProfit)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                    Text(
                                      DateFormat('MMM d').format(date),
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                onPressed: _isLoading ? null : () => _deleteRecord(docs[i].id),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _customParam(CustomParameter p) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: p.controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _calculate(),
                decoration: InputDecoration(
                  labelText: p.name,
                  prefixIcon: Icon(p.icon, color: p.type == 'income' ? Colors.green[600] : Colors.red[600]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.grey)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.type == 'income' ? Colors.green : Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: _isLoading ? null : () => _removeCustomParameter(p),
              tooltip: 'Remove ${p.name}',
            ),
          ],
        ),
      ],
    ),
  );

  Widget _datePicker() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      color: Colors.grey[50],
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: const Icon(Icons.calendar_today, color: Colors.blue),
      title: const Text('Date', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(DateFormat('MMM d, y').format(_selectedDate)),
      trailing: const Icon(Icons.arrow_drop_down, color: Colors.grey),
      onTap: _selectDate,
    ),
  );

  Widget _resultRow(String label, double value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87)),
        Text(currency.format(value), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    ),
  );

  double _getMinY() {
    if (_chartData.isEmpty) return -1000;
    final minProfit = _chartData.map((e) => e.profit).reduce((a, b) => a < b ? a : b);
    return minProfit < 0 ? minProfit * 1.2 : minProfit * 0.8;
  }

  double _getMaxY() {
    if (_chartData.isEmpty) return 1000;
    final maxProfit = _chartData.map((e) => e.profit).reduce((a, b) => a > b ? a : b);
    return maxProfit > 0 ? maxProfit * 1.2 : maxProfit * 0.8;
  }

  String _formatChartValue(double value) {
    if (value.abs() >= 1000000) return '₱${(value / 1000000).toStringAsFixed(1)}M';
    if (value.abs() >= 1000) return '₱${(value / 1000).toStringAsFixed(1)}K';
    return '₱${value.toStringAsFixed(0)}';
  }

  Widget _getBottomTitleWidget(double value, TitleMeta meta) {
    if (value.toInt() >= _chartData.length || value.toInt() < 0) return const SizedBox();
    final dataPoint = _chartData[value.toInt()];
    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Transform.rotate(
        angle: -0.6,
        child: Text(
          DateFormat('MMM d').format(dataPoint.date),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildErrorState({required String message, required VoidCallback onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red[400], size: 48),
            const SizedBox(height: 12),
            const Text('Something went wrong', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey[400], size: 48),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _RecordDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> recordData;
  final String recordId;
  final DateTime date;
  final NumberFormat currency;
  final VoidCallback onDelete;
  const _RecordDetailsDialog({
    required this.recordData,
    required this.recordId,
    required this.date,
    required this.currency,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final grossIncome = (recordData['grossIncome'] ?? 0.0).toDouble();
    final expenses = (recordData['expenses'] ?? 0.0).toDouble();
    final netProfit = (recordData['netProfit'] ?? 0.0).toDouble();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: netProfit >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                    color: netProfit >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                    size: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Profit Record Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(DateFormat('MMMM d, yyyy').format(date), style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.grey), tooltip: 'Close'),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('Entry Gross Income', grossIncome, Colors.green),
                    _buildDetailRow('Entry Expenses', expenses, Colors.red),
                    _buildDetailRow('Net Profit', netProfit, netProfit >= 0 ? Colors.green : Colors.red),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Delete Record', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Close'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          Text(
            value is double ? currency.format(value) : value.toString(),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _AddParameterDialog extends StatefulWidget {
  final Function(String name, String type, IconData icon) onAdd;
  const _AddParameterDialog({required this.onAdd});

  @override
  State<_AddParameterDialog> createState() => _AddParameterDialogState();
}

class _AddParameterDialogState extends State<_AddParameterDialog> {
  final _nameController = TextEditingController();
  String _selectedType = 'expense';
  IconData _selectedIcon = Icons.attach_money;
  final List<IconData> _availableIcons = [
    Icons.attach_money,
    Icons.business,
    Icons.campaign,
    Icons.home,
    Icons.people,
    Icons.savings,
    Icons.receipt,
    Icons.trending_down,
    Icons.inventory,
    Icons.local_shipping,
    Icons.account_balance,
    Icons.credit_card,
    Icons.analytics,
    Icons.shopping_cart,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Custom Parameter', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Parameter Name',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: InputDecoration(
                labelText: 'Type',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'income', child: Text('Income')),
                DropdownMenuItem(value: 'expense', child: Text('Expense')),
              ],
              onChanged: (value) => setState(() => _selectedType = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<IconData>(
              initialValue: _selectedIcon,
              decoration: InputDecoration(
                labelText: 'Icon',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _availableIcons
                  .map((icon) => DropdownMenuItem(
                value: icon,
                child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 10), Text(icon.toString().split('.').last)]),
              ))
                  .toList(),
              onChanged: (value) => setState(() => _selectedIcon = value!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.trim().isNotEmpty) {
              widget.onAdd(_nameController.text.trim(), _selectedType, _selectedIcon);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white),
          child: const Text('Add'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}

enum SnackBarType { success, error, info, loading }

class _SnackBarConfig {
  final IconData? icon;
  final Color color;
  final bool isLoading;
  _SnackBarConfig({required this.icon, required this.color, this.isLoading = false});
}
