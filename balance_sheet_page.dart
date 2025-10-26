import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class BalanceSheetPage extends StatefulWidget {
  const BalanceSheetPage({super.key});

  @override
  State<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends State<BalanceSheetPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  double _totalAssets = 0;
  double _totalLiabilities = 0;
  double _totalEquity = 0;
  bool _isLoading = true;

  final List<Map<String, dynamic>> _assets = [];
  final List<Map<String, dynamic>> _liabilities = [];
  final List<Map<String, dynamic>> _equities = [];

  bool _isAssetsExpanded = false;
  bool _isLiabilitiesExpanded = false;
  bool _isEquityExpanded = false;

  String _format(DateTime? d) =>
      d == null ? '' : DateFormat('dd-MMM-yyyy').format(d);

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'N/A';
    return DateFormat('dd-MMM-yyyy • h:mm a').format(ts.toDate());
  }

  // Helper: Compute BIR due date for tax liabilities
  DateTime _computeBirDueDate(DateTime profitDate, String taxType) {
    final nextMonth = DateTime(profitDate.year, profitDate.month + 1, 1);
    if (taxType.toLowerCase().contains('vat')) {
      // VAT due on 25th of next month
      return DateTime(nextMonth.year, nextMonth.month, 25);
    } else {
      // Percentage, Income, Flat tax due on 20th
      return DateTime(nextMonth.year, nextMonth.month, 20);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final uid = _uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final initialCapital = (userDoc.data()?['initialCapital'] ?? 0).toDouble();

      final cashFlowSnap = await _firestore
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
      final realTimeCash = initialCapital + inflow - outflow;

      // === ASSETS ===
      final assetSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .get();

      double manualAssetsValue = 0;
      final assetList = <Map<String, dynamic>>[];

      for (final doc in assetSnap.docs) {
        final data = doc.data();
        final value = (data['value'] ?? 0).toDouble();
        manualAssetsValue += value;
        assetList.add({
          'id': doc.id,
          'name': data['name'] ?? 'Unknown Asset',
          'value': value,
          'type': data['type'] ?? 'Fixed Asset',
          'date': data['created_at'] ?? Timestamp.now(),
          'isCalculated': false,
        });
      }

      final totalAssets = realTimeCash + manualAssetsValue;

      // Add cash (or overdraft) as first asset/liability
      if (realTimeCash >= 0) {
        assetList.insert(0, {
          'id': 'cash_position',
          'name': 'Cash & Bank Balance',
          'value': realTimeCash,
          'type': 'Current Asset',
          'date': Timestamp.now(),
          'isCalculated': true,
        });
      }

      // === LIABILITIES ===
      // Get all existing profit record IDs to validate profitRecordId references
      final profitRecordsSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('profitRecords')
          .get();

      final validProfitRecordIds = profitRecordsSnap.docs.map((doc) => doc.id).toSet();

      final liaSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('liabilities')
          .get();

      double liabilitiesValue = 0;
      final liaList = <Map<String, dynamic>>[];
      final orphanedLiabilities = <String>[];

      for (final doc in liaSnap.docs) {
        final data = doc.data();
        final profitRecordId = data['profitRecordId'] as String?;
        final isTax = data['isTaxLiability'] == true;

        // Check if this liability is orphaned (profit record was deleted)
        if (profitRecordId != null && !validProfitRecordIds.contains(profitRecordId)) {
          orphanedLiabilities.add(doc.id);
          continue; // Skip this liability
        }

        final amount = (data['amount'] ?? 0).toDouble();
        final name = data['name'] ?? 'Unknown Liability';
        final type = data['type'] ?? 'Current Liability';
        final date = data['date'] as Timestamp?;

        Timestamp? dueDate = data['dueDate'] as Timestamp?;

        // If it's a tax liability and dueDate is missing, compute it
        if (isTax && dueDate == null && date != null) {
          final dueDateTime = _computeBirDueDate(date.toDate(), name);
          dueDate = Timestamp.fromDate(dueDateTime);
        }

        liabilitiesValue += amount;
        liaList.add({
          'id': doc.id,
          'name': name,
          'amount': amount,
          'type': type,
          'date': date ?? Timestamp.now(),
          'dueDate': dueDate,
          'isCalculated': false,
          'isTaxLiability': isTax,
          'profitRecordId': profitRecordId,
        });
      }

      // Clean up orphaned liabilities in the background
      if (orphanedLiabilities.isNotEmpty) {
        _cleanupOrphanedLiabilities(uid, orphanedLiabilities);
      }

      // Handle overdraft (negative cash) as liability
      if (realTimeCash < 0) {
        final overdraftAmount = -realTimeCash;
        liabilitiesValue += overdraftAmount;
        liaList.insert(0, {
          'id': 'overdraft',
          'name': 'Negative Cash (Overdraft)',
          'amount': overdraftAmount,
          'type': 'Current Liability (Overdraft)',
          'date': Timestamp.now(),
          'dueDate': null,
          'isCalculated': true,
          'isTaxLiability': false,
        });
      }

      final totalLiabilities = liabilitiesValue;
      final totalEquity = totalAssets - totalLiabilities;

      // === EQUITY ===
      final equityList = <Map<String, dynamic>>[];
      if (initialCapital != 0) {
        equityList.add({
          'id': 'owners_capital',
          'name': "Owner's Capital",
          'amount': initialCapital,
          'type': 'Capital',
          'date': Timestamp.now(),
          'isCalculated': false,
        });
      }

      final retainedEarnings = totalEquity - initialCapital;
      if (retainedEarnings.abs() > 0.01) {
        equityList.add({
          'id': 'retained_earnings',
          'name': retainedEarnings >= 0 ? 'Retained Earnings' : 'Accumulated Losses',
          'amount': retainedEarnings,
          'type': 'Retained Earnings',
          'date': Timestamp.now(),
          'isCalculated': true,
        });
      }

      if (mounted) {
        setState(() {
          _totalAssets = totalAssets;
          _totalLiabilities = totalLiabilities;
          _totalEquity = totalEquity;
          _assets.clear();
          _assets.addAll(assetList);
          _liabilities.clear();
          _liabilities.addAll(liaList);
          _equities.clear();
          _equities.addAll(equityList);
          _isLoading = false;
        });

        // Show cleanup message if any orphaned liabilities were found
        if (orphanedLiabilities.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cleaned up ${orphanedLiabilities.length} orphaned liability record(s)'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading balance sheet: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Clean up orphaned liabilities (liabilities whose profit records were deleted)
  Future<void> _cleanupOrphanedLiabilities(String uid, List<String> orphanedIds) async {
    try {
      final batch = _firestore.batch();
      for (final id in orphanedIds) {
        final docRef = _firestore
            .collection('users')
            .doc(uid)
            .collection('liabilities')
            .doc(id);
        batch.delete(docRef);
      }
      await batch.commit();
      debugPrint('Cleaned up ${orphanedIds.length} orphaned liabilities');
    } catch (e) {
      debugPrint('Error cleaning up orphaned liabilities: $e');
    }
  }

  Future<void> _deleteLiability(String liabilityId) async {
    final uid = _uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Liability'),
        content: const Text('Are you sure you want to delete this liability?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('liabilities')
          .doc(liabilityId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liability deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting liability: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAssetDetails(Map<String, dynamic> item) {
    _showDetailDialog(
      title: item['name'],
      fields: [
        _detailRow('Type', item['type'] ?? 'N/A'),
        _detailRow('Value', '₱${(item['value'] ?? 0).toStringAsFixed(2)}'),
        _detailRow('Date Added', _formatTimestamp(item['date'] as Timestamp?)),
        if (item['isCalculated'] == true)
          _detailRow('Source', 'Auto-calculated (Cash Balance)'),
      ],
    );
  }

  void _showLiabilityDetails(Map<String, dynamic> item) {
    final dueDate = item['dueDate'] as Timestamp?;
    final canDelete = item['isCalculated'] != true;

    _showDetailDialog(
      title: item['name'],
      fields: [
        _detailRow('Type', item['type'] ?? 'N/A'),
        _detailRow('Amount', '₱${(item['amount'] ?? 0).toStringAsFixed(2)}'),
        _detailRow('Created', _formatTimestamp(item['date'] as Timestamp?)),
        if (dueDate != null) _detailRow('Due Date', _format(dueDate.toDate())),
        if (item['isCalculated'] == true)
          _detailRow('Source', 'Auto-calculated (Overdraft)'),
        if (item['isTaxLiability'] == true)
          _detailRow('Category', 'BIR Tax Payable'),
      ],
      showDeleteButton: canDelete,
      onDelete: canDelete ? () {
        Navigator.pop(context);
        _deleteLiability(item['id']);
      } : null,
    );
  }

  void _showEquityDetails(Map<String, dynamic> item) {
    _showDetailDialog(
      title: item['name'],
      fields: [
        _detailRow('Type', item['type'] ?? 'N/A'),
        _detailRow('Amount', '₱${(item['amount'] ?? 0).toStringAsFixed(2)}'),
        _detailRow('Date', _formatTimestamp(item['date'] as Timestamp?)),
        if (item['isCalculated'] == true)
          _detailRow('Source', 'Auto-calculated'),
      ],
    );
  }

  void _showDetailDialog({
    required String title,
    required List<Widget> fields,
    bool showDeleteButton = false,
    VoidCallback? onDelete,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: fields,
          ),
        ),
        actions: [
          if (showDeleteButton && onDelete != null)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String title, double amount, Color color, IconData icon) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: Text(
                '₱${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Map<String, dynamic>> items,
    required Color color,
    required bool isAsset,
    required bool isEquity,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Container(
            color: color.withValues(alpha: 0.04),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isAsset
                      ? Icons.account_balance_wallet_outlined
                      : isEquity
                      ? Icons.account_balance_outlined
                      : Icons.receipt_long_outlined,
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  '$title (${items.length})',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: color,
                    size: 30,
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 60, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'No ${isAsset ? 'assets' : isEquity ? 'equity' : 'liabilities'} yet',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isCalc = item['isCalculated'] == true;
                  final value = item['amount'] ?? item['value'] ?? 0;
                  final dueDate = item['dueDate'] as Timestamp?;

                  return InkWell(
                    onTap: () {
                      if (isAsset) {
                        _showAssetDetails(item);
                      } else if (isEquity) {
                        _showEquityDetails(item);
                      } else {
                        _showLiabilityDetails(item);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isCalc ? Colors.blue.shade50 : color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCalc ? Icons.auto_awesome : Icons.attach_money,
                              color: isCalc ? Colors.blue : color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'],
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item['type']}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                                if (dueDate != null)
                                  Text(
                                    'Due: ${_format(dueDate.toDate())}',
                                    style: const TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                if (isCalc)
                                  Text(
                                    'Auto-calculated',
                                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                                  ),
                                if (item['isTaxLiability'] == true)
                                  Text(
                                    'BIR Tax Payable',
                                    style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${value.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBalanced = (_totalAssets - (_totalLiabilities + _totalEquity)).abs() <= 0.01;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance Sheet', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _uid == null
          ? const Center(
        child: Text('Please log in to view your balance sheet.'),
      )
          : RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _summaryCard('Total Assets', _totalAssets, Colors.green, Icons.trending_up),
                    const SizedBox(width: 16),
                    _summaryCard('Liabilities', _totalLiabilities, Colors.red, Icons.trending_down),
                    const SizedBox(width: 16),
                    _summaryCard('Equity', _totalEquity, Colors.blue, Icons.pie_chart_outline),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Container(
                decoration: BoxDecoration(
                  color: isBalanced ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isBalanced ? Colors.green : Colors.orange,
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBalanced ? Icons.check_circle : Icons.info,
                          color: isBalanced ? Colors.green : Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Balance Sheet Equation',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Assets = Liabilities + Equity',
                      style: TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱${_totalAssets.toStringAsFixed(2)} = ₱${_totalLiabilities.toStringAsFixed(2)} + ₱${_totalEquity.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!isBalanced) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Auto-balanced with adjustment',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'Financial Position',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              _sectionCard(
                title: 'Assets',
                items: _assets,
                color: Colors.green,
                isAsset: true,
                isEquity: false,
                isExpanded: _isAssetsExpanded,
                onToggle: () => setState(() => _isAssetsExpanded = !_isAssetsExpanded),
              ),

              _sectionCard(
                title: 'Liabilities',
                items: _liabilities,
                color: Colors.red,
                isAsset: false,
                isEquity: false,
                isExpanded: _isLiabilitiesExpanded,
                onToggle: () => setState(() => _isLiabilitiesExpanded = !_isLiabilitiesExpanded),
              ),

              _sectionCard(
                title: 'Equity',
                items: _equities,
                color: Colors.blue,
                isAsset: false,
                isEquity: true,
                isExpanded: _isEquityExpanded,
                onToggle: () => setState(() => _isEquityExpanded = !_isEquityExpanded),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}