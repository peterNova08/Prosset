// add_asset_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddAssetPage extends StatefulWidget {
  const AddAssetPage({super.key});

  @override
  State<AddAssetPage> createState() => _AddAssetPageState();
}

class _AddAssetPageState extends State<AddAssetPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();

  // Replaced text controller with a state variable for asset type
  String _selectedAssetType = 'Fixed Asset';

  final List<String> _assetTypes = [
    'Fixed Asset',
    'Current Asset',
    'Intangible Asset',
    'Financial Asset',
    'Other',
  ];

  bool _maintenanceEnabled = false;
  String _maintenanceFrequency = 'monthly';
  final _maintenanceIntervalController = TextEditingController();
  final _estimatedMaintenanceCostController = TextEditingController();
  DateTime? _nextMaintenanceDate;

  bool _isLoading = false;
  double _currentCashBalance = 0;
  bool _loadingBalance = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentCashBalance();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _maintenanceIntervalController.dispose();
    _estimatedMaintenanceCostController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentCashBalance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final initialCapital = (userDoc.data()?['initialCapital'] ?? 0).toDouble();

      final cashFlowSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('cashFlowEntries')
          .get();

      double inflow = 0, outflow = 0;
      for (final doc in cashFlowSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final type = (data['type'] as String?)?.toLowerCase() ?? '';
        if (type == 'inflow' && amount > 0) inflow += amount;
        if (type == 'outflow' && amount > 0) outflow += amount;
      }

      if (mounted) {
        setState(() {
          _currentCashBalance = initialCapital + inflow - outflow;
          _loadingBalance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingBalance = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading balance: $e')),
        );
      }
    }
  }

  Future<void> _saveAsset() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to add assets'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final assetValue = double.tryParse(_valueController.text.trim()) ?? 0;

    if (assetValue > _currentCashBalance) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Insufficient Funds'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your current cash balance is insufficient for this purchase.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Balance: ₱${_currentCashBalance.toStringAsFixed(2)}'),
                    Text('Asset Value: ₱${assetValue.toStringAsFixed(2)}'),
                    Text(
                      'Shortage: ₱${(assetValue - _currentCashBalance).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Proceeding will result in a negative cash balance (bank overdraft).',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Proceed Anyway'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      // Auto-set next maintenance date if enabled but not selected
      DateTime? effectiveNextMaintenanceDate = _nextMaintenanceDate;
      if (_maintenanceEnabled && effectiveNextMaintenanceDate == null) {
        final now = DateTime.now();
        switch (_maintenanceFrequency) {
          case 'monthly':
            effectiveNextMaintenanceDate = DateTime(now.year, now.month + 1, now.day);
            break;
          case 'quarterly':
            effectiveNextMaintenanceDate = DateTime(now.year, now.month + 3, now.day);
            break;
          case 'yearly':
            effectiveNextMaintenanceDate = DateTime(now.year + 1, now.month, now.day);
            break;
          case 'custom':
            final interval = int.tryParse(_maintenanceIntervalController.text.trim()) ?? 30;
            effectiveNextMaintenanceDate = now.add(Duration(days: interval));
            break;
        }
      }

      final assetData = {
        'name': _nameController.text.trim(),
        'value': assetValue,
        'type': _selectedAssetType, // ✅ Updated to use dropdown value
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'maintenance_enabled': _maintenanceEnabled,
      };

      if (_maintenanceEnabled) {
        assetData['maintenance_frequency'] = _maintenanceFrequency;
        assetData['maintenance_status'] = 'on_schedule';
        assetData['maintenance_count'] = 0;
        assetData['total_maintenance_cost'] = 0.0;

        if (effectiveNextMaintenanceDate != null) {
          assetData['next_maintenance_date'] = Timestamp.fromDate(effectiveNextMaintenanceDate);
        }

        if (_maintenanceFrequency == 'custom' &&
            _maintenanceIntervalController.text.isNotEmpty) {
          assetData['maintenance_interval_days'] =
              int.tryParse(_maintenanceIntervalController.text.trim()) ?? 30;
        }

        if (_estimatedMaintenanceCostController.text.isNotEmpty) {
          assetData['estimated_maintenance_cost'] =
              double.tryParse(_estimatedMaintenanceCostController.text.trim()) ?? 0;
        }
      }

      final assetRef = firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc();
      batch.set(assetRef, assetData);

      // ✅ Create cash flow outflow for asset purchase
      final cashFlowData = {
        'description': 'Asset Purchase - ${_nameController.text.trim()}',
        'amount': assetValue,
        'type': 'outflow',
        'category': 'Asset Purchase',
        'date': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        'isManual': false,
        'isAutogenerated': true,
        'relatedAsset': assetRef.id,
      };

      final cashFlowRef = firestore
          .collection('users')
          .doc(uid)
          .collection('cashFlowEntries')
          .doc();
      batch.set(cashFlowRef, cashFlowData);

      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Asset added successfully! ₱${assetValue.toStringAsFixed(2)} deducted from cash.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding asset: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Asset'),
        elevation: 0,
      ),
      body: _loadingBalance
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentCashBalance >= 0
                      ? Colors.blue.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _currentCashBalance >= 0
                        ? Colors.blue.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: _currentCashBalance >= 0
                          ? Colors.blue.shade700
                          : Colors.red.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available Cash Balance',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₱${_currentCashBalance.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _currentCashBalance >= 0
                                  ? Colors.blue.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Basic Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Asset Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter asset name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Asset Value',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  prefixText: '₱ ',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter asset value';
                  }
                  final amount = double.tryParse(value.trim());
                  if (amount == null || amount <= 0) {
                    return 'Please enter a valid positive number';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {});
                },
              ),
              if (_valueController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildBalanceWarning(),
              ],
              const SizedBox(height: 16),

              // ✅ Replaced with Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedAssetType,
                decoration: const InputDecoration(
                  labelText: 'Asset Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _assetTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedAssetType = value);
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select an asset type';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              const Text(
                'Maintenance Tracking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Enable Maintenance Tracking'),
                subtitle: const Text('Track maintenance schedule and costs'),
                value: _maintenanceEnabled,
                onChanged: (value) {
                  setState(() => _maintenanceEnabled = value);
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              if (_maintenanceEnabled) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _maintenanceFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Maintenance Frequency',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _maintenanceFrequency = value);
                    }
                  },
                ),
                if (_maintenanceFrequency == 'custom') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _maintenanceIntervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Interval (Days)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: (value) {
                      if (_maintenanceFrequency == 'custom') {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter interval days';
                        }
                        final days = int.tryParse(value.trim());
                        if (days == null || days <= 0) {
                          return 'Please enter a valid number of days';
                        }
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Next Maintenance Date'),
                  subtitle: Text(
                    _nextMaintenanceDate == null
                        ? 'Not set (will auto-calculate)'
                        : '${_nextMaintenanceDate!.day}/${_nextMaintenanceDate!.month}/${_nextMaintenanceDate!.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) {
                      setState(() => _nextMaintenanceDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _estimatedMaintenanceCostController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Estimated Maintenance Cost',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    prefixText: '₱ ',
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveAsset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Add Asset',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceWarning() {
    final value = double.tryParse(_valueController.text.trim()) ?? 0;
    if (value <= _currentCashBalance) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This amount exceeds your available balance',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}