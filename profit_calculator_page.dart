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
  bool isTaxable;
  String taxRateId;

  CustomParameter({
    required this.name,
    required this.type,
    required this.icon,
    this.isTaxable = false,
    this.taxRateId = 'none',
  }) : controller = TextEditingController();

  void dispose() => controller.dispose();
}

class TaxRate {
  final String id;
  final String name;
  final double rate;

  TaxRate({required this.id, required this.name, required this.rate});
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

class BirTaxResult {
  final double vat;
  final double inputVat;
  final double netVat;
  final double percentageTax;
  final double incomeTax;
  final double flatTax;
  final double totalTax;
  final double netProfitAfterTax;

  BirTaxResult({
    required this.vat,
    required this.inputVat,
    required this.netVat,
    required this.percentageTax,
    required this.incomeTax,
    required this.flatTax,
    required this.totalTax,
    required this.netProfitAfterTax,
  });
}

// BIR Individual Income Tax Brackets (2023+)
double calculateIncomeTax(double netTaxableIncome) {
  if (netTaxableIncome <= 250000) return 0.0;
  if (netTaxableIncome <= 400000) return (netTaxableIncome - 250000) * 0.15;
  if (netTaxableIncome <= 800000) return 22500 + (netTaxableIncome - 400000) * 0.20;
  if (netTaxableIncome <= 2000000) return 102500 + (netTaxableIncome - 800000) * 0.25;
  if (netTaxableIncome <= 8000000) return 402500 + (netTaxableIncome - 2000000) * 0.30;
  return 2202500 + (netTaxableIncome - 8000000) * 0.35;
}

BirTaxResult calculateBirTax({
  required double grossIncome,
  required double expenses,
  required double inputVat,
  required bool isVatRegistered,
  required bool use8PercentFlat,
  required bool isTaxExempt,
  required double vatRate,
  required double percentageTaxRate,
  required double flatTaxRate,
}) {
  if (isTaxExempt) {
    final net = grossIncome - expenses;
    return BirTaxResult(
      vat: 0,
      inputVat: 0,
      netVat: 0,
      percentageTax: 0,
      incomeTax: 0,
      flatTax: 0,
      totalTax: 0,
      netProfitAfterTax: net,
    );
  }

  final netIncomeBeforeTax = grossIncome - expenses;
  double outputVat = 0;
  double netVat = 0;
  double percentageTax = 0;
  double incomeTax = 0;
  double flatTax = 0;

  if (isVatRegistered) {
    outputVat = grossIncome * vatRate;
    netVat = (outputVat - inputVat).clamp(0.0, double.infinity);
  } else {
    percentageTax = grossIncome * percentageTaxRate;
  }

  if (use8PercentFlat) {
    flatTax = grossIncome * flatTaxRate;
    percentageTax = 0;
    incomeTax = 0;
  } else {
    if (netIncomeBeforeTax > 0) {
      incomeTax = calculateIncomeTax(netIncomeBeforeTax);
    }
  }

  final totalTax = netVat + percentageTax + incomeTax + flatTax;
  double netProfitAfterTax = netIncomeBeforeTax - incomeTax - flatTax;
  if (!isVatRegistered) {
    netProfitAfterTax -= percentageTax;
  }

  return BirTaxResult(
    vat: outputVat,
    inputVat: inputVat,
    netVat: netVat,
    percentageTax: percentageTax,
    incomeTax: incomeTax,
    flatTax: flatTax,
    totalTax: totalTax,
    netProfitAfterTax: netProfitAfterTax,
  );
}

class _ProfitCalculatorPageState extends State<ProfitCalculatorPage> {
  final _formKey = GlobalKey<FormState>();
  final List<CustomParameter> _customParameters = [];
  final currency = NumberFormat.currency(symbol: '₱');
  DateTime _selectedDate = DateTime.now();
  double _totalIncome = 0;
  double _totalExpenses = 0;
  double _inputVat = 0; // NEW
  double _netProfit = 0;
  bool _isLoading = false;
  bool _showResults = false;
  double _bankMoney = 0.0;
  late final String _uid;

  // BIR Tax Settings (per user)
  bool _isVatRegistered = false;
  bool _use8PercentFlat = false;
  bool _isTaxExempt = false;

  // User-specific tax rates
  double _vatRate = 0.12;
  double _percentageTaxRate = 0.03;
  double _flatTaxRate = 0.08;

  // Global defaults (for fallback)
  double _globalVatRate = 0.12;
  double _globalPercentageTaxRate = 0.03;
  double _globalFlatTaxRate = 0.08;

  final String _adminPassword = 'Admin086511';
  BirTaxResult? _birTaxResult;
  bool _isLoadingChart = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  List<ChartDataPoint> _chartData = [];
  late DocumentReference _globalTaxRatesRef;
  late DocumentReference _userTaxProfileRef;

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
    _globalTaxRatesRef = FirebaseFirestore.instance.collection('appSettings').doc('taxRates');
    _userTaxProfileRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('taxProfile').doc('birSettings');
    _loadSelectedDate();
    _loadChartDateRange();
    _loadBankMoney();
    _loadCustomParameters();
    _loadTaxRatesFromFirebase();
    _loadChartData();
  }

  Future<void> _loadTaxRatesFromFirebase() async {
    try {
      // Load global defaults
      final globalDoc = await _globalTaxRatesRef.get();
      if (globalDoc.exists) {
        final data = globalDoc.data() as Map<String, dynamic>;
        _globalVatRate = (data['vatRate'] as num?)?.toDouble() ?? 0.12;
        _globalPercentageTaxRate = (data['percentageTaxRate'] as num?)?.toDouble() ?? 0.03;
        _globalFlatTaxRate = (data['flatTaxRate'] as num?)?.toDouble() ?? 0.08;
      }

      // Load user-specific overrides
      final userDoc = await _userTaxProfileRef.get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _isVatRegistered = data['isVatRegistered'] as bool? ?? false;
            _use8PercentFlat = data['use8PercentFlat'] as bool? ?? false;
            _isTaxExempt = data['isTaxExempt'] as bool? ?? false;
            _vatRate = (data['vatRate'] as num?)?.toDouble() ?? _globalVatRate;
            _percentageTaxRate = (data['percentageTaxRate'] as num?)?.toDouble() ?? _globalPercentageTaxRate;
            _flatTaxRate = (data['flatTaxRate'] as num?)?.toDouble() ?? _globalFlatTaxRate;
            _inputVat = (data['inputVat'] as num?)?.toDouble() ?? 0.0;
          });
        }
      } else {
        // Initialize with defaults
        if (mounted) {
          setState(() {
            _vatRate = _globalVatRate;
            _percentageTaxRate = _globalPercentageTaxRate;
            _flatTaxRate = _globalFlatTaxRate;
          });
        }
      }
      _cacheTaxRatesLocally();
    } catch (e) {
      debugPrint("Error loading tax rates: $e");
      await _loadTaxRatesFromLocal();
    }
  }

  Future<void> _loadTaxRatesFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isVatRegistered = prefs.getBool('bir_is_vat_registered') ?? false;
        _use8PercentFlat = prefs.getBool('bir_use_8_percent_flat') ?? false;
        _isTaxExempt = prefs.getBool('bir_is_tax_exempt') ?? false;
        _vatRate = prefs.getDouble('vat_rate') ?? 0.12;
        _percentageTaxRate = prefs.getDouble('percentage_tax_rate') ?? 0.03;
        _flatTaxRate = prefs.getDouble('flat_tax_rate') ?? 0.08;
        _inputVat = prefs.getDouble('input_vat') ?? 0.0;
      });
    }
  }

  Future<void> _cacheTaxRatesLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bir_is_vat_registered', _isVatRegistered);
    await prefs.setBool('bir_use_8_percent_flat', _use8PercentFlat);
    await prefs.setBool('bir_is_tax_exempt', _isTaxExempt);
    await prefs.setDouble('vat_rate', _vatRate);
    await prefs.setDouble('percentage_tax_rate', _percentageTaxRate);
    await prefs.setDouble('flat_tax_rate', _flatTaxRate);
    await prefs.setDouble('input_vat', _inputVat);
  }

  Future<void> _saveTaxProfileToFirebase() async {
    try {
      await _userTaxProfileRef.set({
        'isVatRegistered': _isVatRegistered,
        'use8PercentFlat': _use8PercentFlat,
        'isTaxExempt': _isTaxExempt,
        'vatRate': _vatRate,
        'percentageTaxRate': _percentageTaxRate,
        'flatTaxRate': _flatTaxRate,
        'inputVat': _inputVat,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _cacheTaxRatesLocally();
    } catch (e) {
      if (mounted) _showSnackBar('Failed to save tax profile: $e', SnackBarType.error);
    }
  }

  Future<void> _saveGlobalTaxRatesToFirebase() async {
    try {
      await _globalTaxRatesRef.set({
        'vatRate': _vatRate,
        'percentageTaxRate': _percentageTaxRate,
        'flatTaxRate': _flatTaxRate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Global tax rates updated!')),
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar('Failed to save global rates: $e', SnackBarType.error);
    }
  }

  @override
  void dispose() {
    for (final p in _customParameters) {
      p.dispose();
    }
    super.dispose();
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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final customParams = userDoc.data()?['customParameters'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _customParameters.clear();
          for (final param in customParams) {
            final paramMap = param as Map<String, dynamic>;
            _customParameters.add(CustomParameter(
              name: paramMap['name'] as String,
              type: paramMap['type'] as String,
              icon: _getIconFromString(paramMap['icon'] as String? ?? 'attach_money'),
              isTaxable: paramMap['isTaxable'] as bool? ?? false,
              taxRateId: paramMap['taxRateId'] as String? ?? 'none',
            ));
          }
        });
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error loading parameters: $e', SnackBarType.error);
    }
  }

  Future<void> _saveCustomParameters() async {
    try {
      final paramsData = _customParameters.map((p) => {
        'name': p.name,
        'type': p.type,
        'icon': _getStringFromIcon(p.icon),
        'isTaxable': p.isTaxable,
        'taxRateId': p.taxRateId,
      }).toList();
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({'customParameters': paramsData});
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
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      double initialCapital = (userDoc.data()?['initialCapital'] as num?)?.toDouble() ?? 0;
      final cashFlowSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('cashFlowEntries')
          .get();
      double totalInflows = 0, totalOutflows = 0;
      for (final doc in cashFlowSnapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final type = (data['type'] as String?)?.toLowerCase() ?? '';
        if (type == 'inflow' && amount > 0) {
          totalInflows += amount;
        } if (type == 'inflow' && amount > 0) {
          totalInflows += amount;
        } else if (type == 'outflow' && amount > 0) {
          totalOutflows += amount;
        }
}
        if (mounted) setState(() => _bankMoney = initialCapital + totalInflows - totalOutflows);
    } catch (e) {
      if (mounted) _showSnackBar('Error loading bank money: $e', SnackBarType.error);
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
          'afterTaxProfit': (data['netProfitAfterTax'] as num?)?.toDouble() ?? (data['netProfit'] as num?)?.toDouble() ?? 0.0,
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

    final birResult = calculateBirTax(
      grossIncome: income,
      expenses: expenses,
      inputVat: _inputVat,
      isVatRegistered: _isVatRegistered,
      use8PercentFlat: _use8PercentFlat,
      isTaxExempt: _isTaxExempt,
      vatRate: _vatRate,
      percentageTaxRate: _percentageTaxRate,
      flatTaxRate: _flatTaxRate,
    );

    double finalNetProfitAfterTax = birResult.netProfitAfterTax;
    if (_isTaxExempt || birResult.totalTax == 0) {
      finalNetProfitAfterTax = income - expenses;
    }

    setState(() {
      _totalIncome = income;
      _totalExpenses = expenses;
      _netProfit = income - expenses;
      _birTaxResult = BirTaxResult(
        vat: birResult.vat,
        inputVat: birResult.inputVat,
        netVat: birResult.netVat,
        percentageTax: birResult.percentageTax,
        incomeTax: birResult.incomeTax,
        flatTax: birResult.flatTax,
        totalTax: birResult.totalTax,
        netProfitAfterTax: finalNetProfitAfterTax,
      );
      _showResults = income > 0 || expenses > 0;
    });
  }

  Future<void> _saveCalculation() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalIncome <= 0 && _totalExpenses <= 0) {
      _showSnackBar('Enter at least one income or expense value', SnackBarType.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final customData = <String, dynamic>{};
      for (final p in _customParameters) {
        final v = double.tryParse(p.controller.text.replaceAll(',', '')) ?? 0;
        if (v > 0) {
          customData[p.name] = {'value': v, 'type': p.type};
        }
      }

      final recordId = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('profitRecords')
          .doc()
          .id;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('profitRecords')
          .doc(recordId)
          .set({
        'month': DateFormat('yyyy-MM').format(_selectedDate),
        'grossIncome': _totalIncome,
        'expenses': _totalExpenses,
        'inputVat': _inputVat,
        'vatRegistered': _isVatRegistered,
        'use8PercentFlat': _use8PercentFlat,
        'isTaxExempt': _isTaxExempt,
        'taxDue': _birTaxResult!.totalTax,
        'netProfitAfterTax': _birTaxResult!.netProfitAfterTax,
        'netProfitBeforeTax': _netProfit,
        'customParameters': customData,
        'date': Timestamp.fromDate(_selectedDate),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final batch = FirebaseFirestore.instance.batch();
      final dateLabel = DateFormat('MMM d').format(_selectedDate);

      // Save cash flows
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
            'profitRecordId': recordId,
            'isAutogenerated': true,
          });
        }
      }

      // Save tax liabilities
      if (!_isTaxExempt) {
        if (_birTaxResult!.netVat > 0) {
          final vatRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('liabilities').doc();
          batch.set(vatRef, {
            'name': 'VAT Payable ($dateLabel)',
            'amount': _birTaxResult!.netVat,
            'type': 'Tax Payable',
            'date': Timestamp.fromDate(_selectedDate),
            'isTaxLiability': true,
            'profitRecordId': recordId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (_birTaxResult!.percentageTax > 0) {
          final pctRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('liabilities').doc();
          batch.set(pctRef, {
            'name': 'Percentage Tax Payable ($dateLabel)',
            'amount': _birTaxResult!.percentageTax,
            'type': 'Tax Payable',
            'date': Timestamp.fromDate(_selectedDate),
            'isTaxLiability': true,
            'profitRecordId': recordId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (_birTaxResult!.incomeTax > 0) {
          final incRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('liabilities').doc();
          batch.set(incRef, {
            'name': 'Income Tax Payable ($dateLabel)',
            'amount': _birTaxResult!.incomeTax,
            'type': 'Tax Payable',
            'date': Timestamp.fromDate(_selectedDate),
            'isTaxLiability': true,
            'profitRecordId': recordId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (_birTaxResult!.flatTax > 0) {
          final flatRef = FirebaseFirestore.instance.collection('users').doc(_uid).collection('liabilities').doc();
          batch.set(flatRef, {
            'name': '8% Flat Tax Payable ($dateLabel)',
            'amount': _birTaxResult!.flatTax,
            'type': 'Tax Payable',
            'date': Timestamp.fromDate(_selectedDate),
            'isTaxLiability': true,
            'profitRecordId': recordId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      await _loadBankMoney();
      if (mounted) {
        _showSnackBar('Saved successfully – BIR-compliant tax computed!', SnackBarType.success);
        _clearForm();
        _loadChartData();
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error saving: $e', SnackBarType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  Future<void> _deleteRecord(String profitRecordId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('This will remove the profit record, cash flows, and tax liabilities. Continue?'),
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
      final liabilitiesQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('liabilities')
          .where('profitRecordId', isEqualTo: profitRecordId)
          .where('isTaxLiability', isEqualTo: true)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in cashFlowQuery.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in liabilitiesQuery.docs) {
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
      _totalIncome = _totalExpenses = _inputVat = _netProfit = 0;
      _birTaxResult = null;
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
                const SizedBox(height: 20),
                _buildBirTaxSettingsCard(),
                const SizedBox(height: 20),
                _buildCalculatorCard(),
                if (_showResults) ...[
                  const SizedBox(height: 20),
                  _buildResultsCard(),
                ],
                const SizedBox(height: 20),
                _buildProfitChart(),
                const SizedBox(height: 20),
                _buildRecentRecords(),
              ],
            ),
          ),
        ),
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

  Widget _buildBirTaxSettingsCard() {
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
          Row(
            children: [
              const Text('BIR Tax Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                tooltip: 'Edit Tax Rates (Admin)',
                icon: const Icon(Icons.admin_panel_settings, color: Colors.blue),
                onPressed: _showEditTaxRatesDialog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _isTaxExempt,
                onChanged: (val) {
                  setState(() {
                    _isTaxExempt = val ?? false;
                    if (_isTaxExempt) {
                      _isVatRegistered = false;
                      _use8PercentFlat = false;
                    }
                  });
                  _saveTaxProfileToFirebase();
                  _calculate();
                },
              ),
              const Expanded(
                child: Text('I am tax-exempt or do not pay business tax', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isTaxExempt) ...[
            Row(
              children: [
                Checkbox(
                  value: _isVatRegistered,
                  onChanged: (val) {
                    setState(() {
                      _isVatRegistered = val ?? false;
                      if (_isVatRegistered) _use8PercentFlat = false;
                    });
                    _saveTaxProfileToFirebase();
                    _calculate();
                  },
                ),
                Text('VAT-Registered Business (${(_vatRate * 100).toStringAsFixed(1)}% VAT)', style: const TextStyle(fontSize: 14)),
              ],
            ),
            if (_isVatRegistered) ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: _inputVat.toString(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) {
                  setState(() {
                    _inputVat = double.tryParse(v) ?? 0.0;
                  });
                  _calculate();
                },
                decoration: InputDecoration(
                  labelText: 'Input VAT (Creditable)',
                  prefixIcon: const Icon(Icons.receipt_long, color: Colors.blue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: !_isVatRegistered,
                  onChanged: (val) {
                    if (val == true) {
                      setState(() => _isVatRegistered = false);
                      _saveTaxProfileToFirebase();
                      _calculate();
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    'Non-VAT Business (${(_percentageTaxRate * 100).toStringAsFixed(1)}% Percentage Tax)',
                    style: const TextStyle(fontSize: 14),
                    softWrap: true,
                    overflow: TextOverflow.fade, // optional: adds fade effect if still clipped
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _use8PercentFlat,
                  onChanged: (val) {
                    if (val == true && _isVatRegistered) {
                      _showSnackBar('8% flat tax is only for non-VAT taxpayers', SnackBarType.error);
                      return;
                    }
                    setState(() => _use8PercentFlat = val ?? false);
                    _saveTaxProfileToFirebase();
                    _calculate();
                  },
                ),
                Expanded(
                  child: Text(
                    'Use Optional ${(_flatTaxRate * 100).toStringAsFixed(1)}% Flat Rate Tax (in lieu of income tax + percentage tax)',
                    style: const TextStyle(fontSize: 14),
                    softWrap: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                children: [
                  TextSpan(text: '• VAT ${(_vatRate * 100).toStringAsFixed(1)}%: For businesses with >₱3M annual sales\n'),
                  const TextSpan(text: '• Input VAT: Deductible from output VAT\n'),
                  TextSpan(text: '• Percentage Tax ${(_percentageTaxRate * 100).toStringAsFixed(1)}%: For non-VAT taxpayers\n'),
                  const TextSpan(text: '• Progressive Income Tax: Based on BIR brackets\n'),
                  TextSpan(text: '• ${(_flatTaxRate * 100).toStringAsFixed(1)}% Flat Tax: For self-employed (non-VAT only)'),
                ],
              ),
            ),
          ],
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
    if (_birTaxResult == null) return const SizedBox.shrink();
    final isProfitable = _birTaxResult!.netProfitAfterTax >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isProfitable ? [Colors.green[600]!, Colors.green[400]!] : [Colors.red[600]!, Colors.red[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (isProfitable ? Colors.green[200]! : Colors.red[200]!).withValues(alpha: 0.6),
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
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                child: Icon(isProfitable ? Icons.trending_up : Icons.trending_down, color: Colors.white, size: 24),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  isProfitable ? 'Profitable' : 'Loss',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Net Profit After Tax', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            currency.format(_birTaxResult!.netProfitAfterTax),
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _resultRow('Total Income', _totalIncome, null, Colors.black87),
          _resultRow('Total Expenses', _totalExpenses, null, Colors.black87),
          _resultRow('Net Profit (Before Tax)', _netProfit, null, Colors.black87),
          const Divider(color: Colors.black26),
          if (_isVatRegistered) ...[
            _resultRow('Output VAT', _birTaxResult!.vat, null, Colors.orange),
            _resultRow('Input VAT (Credit)', _birTaxResult!.inputVat, null, Colors.green),
            _resultRow('Net VAT Payable', _birTaxResult!.netVat, null, Colors.orange[800]!),
          ] else if (_birTaxResult!.percentageTax > 0) ...[
            _resultRow('Percentage Tax', _birTaxResult!.percentageTax, null, Colors.orange),
          ],
          if (_birTaxResult!.incomeTax > 0) _resultRow('Income Tax (Progressive)', _birTaxResult!.incomeTax, null, Colors.purple),
          if (_birTaxResult!.flatTax > 0) _resultRow('8% Flat Tax', _birTaxResult!.flatTax, null, Colors.orange),
          _resultRow('Total Tax Due', _birTaxResult!.totalTax, null, Colors.orange[800]!),
          const Divider(color: Colors.black26),
          _resultRow('New Cash Balance', _bankMoney + _birTaxResult!.netProfitAfterTax, null, Colors.black87),
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
                    final afterTax = (d['netProfitAfterTax'] ?? d['netProfit'] ?? 0.0).toDouble();
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
                                  color: afterTax >= 0 ? Colors.green[50] : Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  afterTax >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                  color: afterTax >= 0 ? Colors.green[700] : Colors.red[700],
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'After-Tax: ${currency.format(afterTax)}',
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

  Widget _resultRow(String label, double value, double? pct, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white70)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(currency.format(value), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            if (pct != null && !pct.isNaN) Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
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

  void _showEditTaxRatesDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Access Required'),
        content: TextField(
          controller: passwordController,
          decoration: const InputDecoration(labelText: 'Enter admin password'),
          obscureText: true,
          onSubmitted: (_) {
            Navigator.pop(context);
            _verifyPassword(passwordController.text);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _verifyPassword(passwordController.text);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _verifyPassword(String input) {
    if (input == _adminPassword) {
      _showTaxRateEditor();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password'), backgroundColor: Colors.red));
    }
  }

  void _showTaxRateEditor() {
    final vatController = TextEditingController(text: (_vatRate * 100).toStringAsFixed(2));
    final pctController = TextEditingController(text: (_percentageTaxRate * 100).toStringAsFixed(2));
    final flatController = TextEditingController(text: (_flatTaxRate * 100).toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Global Tax Rates (%)'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vatController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'VAT Rate (%)'),
              ),
              TextField(
                controller: pctController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Percentage Tax (%)'),
              ),
              TextField(
                controller: flatController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '8% Flat Tax (%)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final vat = (double.tryParse(vatController.text) ?? 12.0) / 100;
              final pct = (double.tryParse(pctController.text) ?? 3.0) / 100;
              final flat = (double.tryParse(flatController.text) ?? 8.0) / 100;
              setState(() {
                _vatRate = vat;
                _percentageTaxRate = pct;
                _flatTaxRate = flat;
              });
              _saveGlobalTaxRatesToFirebase();
              _calculate();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
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
    final inputVat = (recordData['inputVat'] ?? 0.0).toDouble();
    final netProfitBeforeTax = (recordData['netProfitBeforeTax'] ?? 0.0).toDouble();
    final netProfitAfterTax = (recordData['netProfitAfterTax'] ?? netProfitBeforeTax).toDouble();
    final vatRegistered = recordData['vatRegistered'] as bool? ?? false;
    final use8PercentFlat = recordData['use8PercentFlat'] as bool? ?? false;
    final isTaxExempt = recordData['isTaxExempt'] as bool? ?? false;
    final taxDue = (recordData['taxDue'] ?? 0.0).toDouble();

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
                color: netProfitAfterTax >= 0 ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    netProfitAfterTax >= 0 ? Icons.trending_up : Icons.trending_down,
                    color: netProfitAfterTax >= 0 ? Colors.green.shade800 : Colors.red.shade800,
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
                    _buildDetailRow('Gross Income', grossIncome, Colors.green),
                    _buildDetailRow('Expenses', expenses, Colors.red),
                    if (vatRegistered) _buildDetailRow('Input VAT', inputVat, Colors.blue),
                    _buildDetailRow('Net Profit (Before Tax)', netProfitBeforeTax, Colors.blue),
                    const SizedBox(height: 12),
                    const Divider(thickness: 2, color: Colors.grey),
                    const SizedBox(height: 12),
                    _buildDetailRow('Tax Status', isTaxExempt ? 'Tax-Exempt' : vatRegistered ? 'VAT-Registered' : 'Non-VAT', Colors.grey[800]!),
                    if (!isTaxExempt && !vatRegistered) _buildDetailRow('8% Flat Tax Used', use8PercentFlat ? 'Yes' : 'No', Colors.grey[800]!),
                    _buildDetailRow('Total Tax Due', taxDue, Colors.orange),
                    _buildDetailRow('Net Profit After Tax', netProfitAfterTax, netProfitAfterTax >= 0 ? Colors.green : Colors.red),
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