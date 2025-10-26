// ground_assets_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_asset_page.dart';

class GroundAssetsPage extends StatefulWidget {
  const GroundAssetsPage({super.key});

  @override
  State<GroundAssetsPage> createState() => _GroundAssetsPageState();
}

class _GroundAssetsPageState extends State<GroundAssetsPage>
    with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getAssetsStream() {
    final uid = _uid;
    if (uid == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('assets')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  Future<void> _navigateToAddAsset() async {
    if (_uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to add assets'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await navigator.push(
      MaterialPageRoute(builder: (_) => const AddAssetPage()),
    );
    if (result != null && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Asset list updated')),
      );
    }
  }

  void _showAssetDialog(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Asset data is null')),
      );
      return;
    }
    final name = data['name'] ?? 'Unnamed';
    final value = (data['value'] ?? 0).toDouble();
    final createdAt = data['created_at'] as Timestamp?;
    final maintenanceEnabled = data['maintenance_enabled'] ?? false;
    final nextMaintenanceDate = data['next_maintenance_date'] as Timestamp?;
    final maintenanceStatus = data['maintenance_status'] ?? 'not_scheduled';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.business, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Value:', '₱${value.toStringAsFixed(2)}'),
              if (createdAt != null) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Created:', _formatDate(createdAt.toDate())),
              ],
              const SizedBox(height: 8),
              _buildDetailRow(
                'Owner:',
                FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
              ),
              if (maintenanceEnabled) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Maintenance Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMaintenanceStatusChip(maintenanceStatus),
                const SizedBox(height: 8),
                if (nextMaintenanceDate != null)
                  _buildDetailRow(
                    'Next Maintenance:',
                    _formatDate(nextMaintenanceDate.toDate()),
                  ),
                _buildDetailRow(
                  'Frequency:',
                  data['maintenance_frequency'] ?? 'Not set',
                ),
                if (data['estimated_maintenance_cost'] != null)
                  _buildDetailRow(
                    'Est. Cost:',
                    '₱${(data['estimated_maintenance_cost']).toStringAsFixed(2)}',
                  ),
                if (data['total_maintenance_cost'] != null &&
                    data['total_maintenance_cost'] > 0)
                  _buildDetailRow(
                    'Total Spent:',
                    '₱${(data['total_maintenance_cost']).toStringAsFixed(2)}',
                  ),
              ] else ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Maintenance tracking not enabled',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'What would you like to do?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        actions: [
          if (maintenanceEnabled)
            TextButton.icon(
              onPressed: () => _showMaintenanceDialog(asset, closeParentDialog: true),
              icon: const Icon(Icons.build, size: 18),
              label: const Text('Maintenance'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
            ),
          TextButton.icon(
            onPressed: () => _editAsset(asset),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Edit'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
          TextButton.icon(
            onPressed: () => _confirmDeleteAsset(asset),
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showMaintenanceDialog(DocumentSnapshot asset, {bool closeParentDialog = false}) {
    if (closeParentDialog) {
      Navigator.pop(context);
    }
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Asset data is null')),
      );
      return;
    }
    final name = data['name'] ?? 'Unnamed';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.build, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Maintenance - $name')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Record Maintenance'),
              subtitle: const Text('Log a maintenance activity'),
              onTap: () {
                Navigator.pop(context);
                _recordMaintenance(asset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('View History'),
              subtitle: const Text('See all maintenance records'),
              onTap: () {
                Navigator.pop(context);
                _viewMaintenanceHistory(asset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Update Schedule'),
              subtitle: const Text('Change maintenance settings'),
              onTap: () {
                Navigator.pop(context);
                _updateMaintenanceSchedule(asset);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _recordMaintenance(DocumentSnapshot asset) {
    final costController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    void showRecordDialog() {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Record Maintenance'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text('Date: ${_formatDate(selectedDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Cost',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    hintText: 'What maintenance was performed?',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => _saveMaintenance(
                  asset.id,
                  selectedDate,
                  costController.text.trim(),
                  descriptionController.text.trim(),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    }

    showRecordDialog();
  }

  Future<void> _saveMaintenance(
      String assetId,
      DateTime date,
      String costText,
      String description,
      ) async {
    final uid = _uid;
    if (uid == null) return;
    if (!mounted) return;
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }
    final cost = double.tryParse(costText);
    if (costText.isNotEmpty && (cost == null || cost < 0)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid cost')),
      );
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc(assetId)
          .collection('maintenance_history')
          .add({
        'date': date,
        'cost': cost ?? 0.0,
        'description': description,
        'performed_by': FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
        'created_at': FieldValue.serverTimestamp(),
      });
      final assetRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc(assetId);
      final assetDoc = await assetRef.get();
      if (assetDoc.exists) {
        final data = assetDoc.data()!;
        final currentTotal = (data['total_maintenance_cost'] ?? 0.0).toDouble();
        final currentCount = (data['maintenance_count'] ?? 0) + 1;
        DateTime? nextDate;
        final frequency = data['maintenance_frequency'];
        if (frequency != null) {
          switch (frequency) {
            case 'monthly':
              nextDate = DateTime(date.year, date.month + 1, date.day);
              break;
            case 'quarterly':
              nextDate = DateTime(date.year, date.month + 3, date.day);
              break;
            case 'yearly':
              nextDate = DateTime(date.year + 1, date.month, date.day);
              break;
            case 'custom':
              final interval = data['maintenance_interval_days'] ?? 30;
              nextDate = date.add(Duration(days: interval));
              break;
          }
        }
        await assetRef.update({
          'last_maintenance_date': date,
          'next_maintenance_date': nextDate,
          'total_maintenance_cost': currentTotal + (cost ?? 0.0),
          'maintenance_count': currentCount,
          'maintenance_status': _getMaintenanceStatus(nextDate),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maintenance recorded successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recording maintenance: $e')),
      );
    }
  }

  void _viewMaintenanceHistory(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return;
    final name = data['name'] ?? 'Unnamed';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Maintenance History - $name',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(_uid)
                      .collection('assets')
                      .doc(asset.id)
                      .collection('maintenance_history')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No maintenance history'));
                    }
                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final record = snapshot.data!.docs[index];
                        final recordData = record.data() as Map<String, dynamic>;
                        final date = (recordData['date'] as Timestamp).toDate();
                        final cost = (recordData['cost'] ?? 0.0).toDouble();
                        final description = recordData['description'] ?? '';
                        final performedBy = recordData['performed_by'] ?? 'Unknown';
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Icon(Icons.build, color: Colors.blue.shade700, size: 20),
                            ),
                            title: Text(description),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Date: ${_formatDate(date)}'),
                                if (cost > 0) Text('Cost: ₱${cost.toStringAsFixed(2)}'),
                                Text('By: $performedBy', style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateMaintenanceSchedule(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return;
    final name = data['name'] ?? 'Unnamed';
    String currentFrequency = data['maintenance_frequency'] ?? 'monthly';
    final intervalController = TextEditingController(
      text: (data['maintenance_interval_days'] ?? '').toString(),
    );
    final costController = TextEditingController(
      text: (data['estimated_maintenance_cost'] ?? '').toString(),
    );
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Update Maintenance Schedule - $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: currentFrequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom')),
                ],
                onChanged: (value) {
                  setState(() => currentFrequency = value!);
                },
              ),
              const SizedBox(height: 16),
              if (currentFrequency == 'custom')
                TextField(
                  controller: intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Interval (Days)',
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Estimated Cost',
                  border: OutlineInputBorder(),
                  prefixText: '₱ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _saveMaintenanceSchedule(
                asset.id,
                currentFrequency,
                intervalController.text.trim(),
                costController.text.trim(),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveMaintenanceSchedule(
      String assetId, String frequency, String intervalText, String costText) async {
    final uid = _uid;
    if (uid == null) return;
    final updateData = <String, dynamic>{
      'maintenance_frequency': frequency,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (frequency == 'custom') {
      final interval = int.tryParse(intervalText);
      if (interval == null || interval <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid interval')),
        );
        return;
      }
      updateData['maintenance_interval_days'] = interval;
    }
    if (costText.isNotEmpty) {
      final cost = double.tryParse(costText);
      if (cost == null || cost < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid cost')),
        );
        return;
      }
      updateData['estimated_maintenance_cost'] = cost;
    }
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc(assetId)
          .update(updateData);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maintenance schedule updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating schedule: $e')),
      );
    }
  }

  String _getMaintenanceStatus(DateTime? nextDate) {
    if (nextDate == null) return 'not_scheduled';
    final days = nextDate.difference(DateTime.now()).inDays;
    if (days < 0) return 'overdue';
    if (days <= 7) return 'due_soon';
    return 'on_schedule';
  }

  Widget _buildDetailRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 70,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
      Expanded(child: Text(value)),
    ],
  );

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

  void _editAsset(DocumentSnapshot asset) {
    Navigator.pop(context);
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return;

    final nameController = TextEditingController(text: data['name'] ?? '');
    final valueController = TextEditingController(text: (data['value'] ?? 0).toString());
    bool maintenanceEnabled = data['maintenance_enabled'] ?? false;
    String maintenanceFrequency = data['maintenance_frequency'] ?? 'monthly';
    final intervalController = TextEditingController(
      text: (data['maintenance_interval_days'] ?? '').toString(),
    );
    final estimatedCostController = TextEditingController(
      text: (data['estimated_maintenance_cost'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Asset'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Asset Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valueController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Asset Value',
                    border: OutlineInputBorder(),
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile.adaptive(
                  title: const Text('Enable Maintenance Tracking'),
                  value: maintenanceEnabled,
                  onChanged: (val) {
                    setState(() {
                      maintenanceEnabled = val;
                    });
                  },
                ),
                if (maintenanceEnabled) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: maintenanceFrequency,
                    items: const [
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                      DropdownMenuItem(value: 'custom', child: Text('Custom')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => maintenanceFrequency = val);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (maintenanceFrequency == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Interval (Days)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: estimatedCostController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Estimated Maintenance Cost',
                      border: OutlineInputBorder(),
                      prefixText: '₱ ',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _updateAssetWithMaintenance(
                asset.id,
                nameController.text.trim(),
                valueController.text.trim(),
                maintenanceEnabled,
                maintenanceFrequency,
                intervalController.text.trim(),
                estimatedCostController.text.trim(),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAssetWithMaintenance(
      String assetId,
      String name,
      String valueText,
      bool maintenanceEnabled,
      String maintenanceFrequency,
      String intervalText,
      String costText,
      ) async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to update assets')),
      );
      return;
    }
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset name cannot be empty')),
      );
      return;
    }
    final newValue = double.tryParse(valueText);
    if (newValue == null || newValue < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive number')),
      );
      return;
    }

    try {
      final assetDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc(assetId)
          .get();
      if (!assetDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Asset not found')),
        );
        return;
      }
      final oldData = assetDoc.data()!;
      final oldValue = (oldData['value'] ?? 0.0).toDouble();

      final updateData = <String, dynamic>{
        'name': name,
        'value': newValue,
        'updated_at': FieldValue.serverTimestamp(),
        'maintenance_enabled': maintenanceEnabled,
      };

      if (maintenanceEnabled) {
        updateData['maintenance_frequency'] = maintenanceFrequency;
        updateData['maintenance_status'] = 'on_schedule';
        updateData['maintenance_count'] = oldData['maintenance_count'] ?? 0;
        updateData['total_maintenance_cost'] = oldData['total_maintenance_cost'] ?? 0.0;

        if (maintenanceFrequency == 'custom') {
          final interval = int.tryParse(intervalText);
          if (interval == null || interval <= 0) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a valid interval')),
            );
            return;
          }
          updateData['maintenance_interval_days'] = interval;
        }

        if (costText.isNotEmpty) {
          final cost = double.tryParse(costText);
          if (cost == null || cost < 0) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter a valid cost')),
            );
            return;
          }
          updateData['estimated_maintenance_cost'] = cost;
        }

        // Set next maintenance date if not exists
        DateTime? nextDate;
        final now = DateTime.now();
        switch (maintenanceFrequency) {
          case 'monthly':
            nextDate = DateTime(now.year, now.month + 1, now.day);
            break;
          case 'quarterly':
            nextDate = DateTime(now.year, now.month + 3, now.day);
            break;
          case 'yearly':
            nextDate = DateTime(now.year + 1, now.month, now.day);
            break;
          case 'custom':
            final interval = updateData['maintenance_interval_days'] as int;
            nextDate = now.add(Duration(days: interval));
            break;
        }
        updateData['next_maintenance_date'] = Timestamp.fromDate(nextDate!);
      }

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('assets')
          .doc(assetId)
          .update(updateData);

      final difference = newValue - oldValue;
      if (difference != 0) {
        final batch = _firestore.batch();
        final description = difference > 0
            ? 'Asset Value Increase - $name'
            : 'Asset Value Decrease - $name';
        final cashFlowData = {
          'description': description,
          'amount': difference.abs(),
          'type': difference > 0 ? 'outflow' : 'inflow',
          'category': 'Asset Adjustment',
          'date': Timestamp.now(),
          'createdAt': FieldValue.serverTimestamp(),
          'isManual': false,
          'isAutogenerated': true,
          'relatedAsset': assetId,
        };
        final cashFlowRef = _firestore
            .collection('users')
            .doc(uid)
            .collection('cashFlowEntries')
            .doc();
        batch.set(cashFlowRef, cashFlowData);
        await batch.commit();
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating asset: $e')),
      );
    }
  }

  void _confirmDeleteAsset(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return;
    final name = data['name'] ?? 'Unnamed';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Delete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to delete this asset?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Value: ₱${(data['value'] ?? 0).toStringAsFixed(2)}'),
                  Text('Owner: ${FirebaseAuth.instance.currentUser?.email ?? 'Unknown'}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone and will also delete all maintenance history.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              await _deleteAsset(asset.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAsset(String assetId) async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to delete assets')),
      );
      return;
    }
    try {
      final cashFlowQuery = await _firestore
          .collection('users')
          .doc(uid)
          .collection('cashFlowEntries')
          .where('relatedAsset', isEqualTo: assetId)
          .where('isAutogenerated', isEqualTo: true)
          .get();
      final batch = _firestore.batch();
      for (final doc in cashFlowQuery.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('users').doc(uid).collection('assets').doc(assetId));
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset and related auto-generated entries deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting asset: $e')),
      );
    }
  }

  Widget _buildAssetCard(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return const SizedBox.shrink();
    final name = data['name'] ?? 'Unnamed';
    final value = (data['value'] ?? 0).toDouble();
    final maintenanceEnabled = data['maintenance_enabled'] ?? false;
    final maintenanceStatus = data['maintenance_status'] ?? 'not_scheduled';
    final nextMaintenanceDate = data['next_maintenance_date'] as Timestamp?;

    return GestureDetector(
      onTap: () => _showAssetDialog(asset),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.business,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  if (maintenanceEnabled)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _getMaintenanceStatusColor(maintenanceStatus),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getMaintenanceStatusIcon(maintenanceStatus),
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '₱${value.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (maintenanceEnabled && nextMaintenanceDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Next: ${_formatDateShort(nextMaintenanceDate.toDate())}',
                  style: TextStyle(
                    fontSize: 10,
                    color: _getMaintenanceStatusColor(maintenanceStatus),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getMaintenanceStatusColor(String status) {
    switch (status) {
      case 'overdue':
        return Colors.red;
      case 'due_soon':
        return Colors.orange;
      case 'on_schedule':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getMaintenanceStatusIcon(String status) {
    switch (status) {
      case 'overdue':
        return Icons.warning;
      case 'due_soon':
        return Icons.schedule;
      case 'on_schedule':
        return Icons.check_circle;
      default:
        return Icons.build;
    }
  }

  Widget _buildMaintenanceStatusChip(String status) {
    Color color;
    String label;
    IconData icon;
    switch (status) {
      case 'overdue':
        color = Colors.red;
        label = 'Overdue';
        icon = Icons.warning;
        break;
      case 'due_soon':
        color = Colors.orange;
        label = 'Due Soon';
        icon = Icons.schedule;
        break;
      case 'on_schedule':
        color = Colors.green;
        label = 'On Schedule';
        icon = Icons.check_circle;
        break;
      default:
        color = Colors.grey;
        label = 'Not Scheduled';
        icon = Icons.info;
    }
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  String _formatDateShort(DateTime date) => '${date.day}/${date.month}/${date.year}';

  Map<String, int> _getMaintenanceSummary(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> assets) {
    int overdue = 0, dueSoon = 0, onSchedule = 0, notScheduled = 0;
    for (final asset in assets) {
      final data = asset.data();
      final enabled = data['maintenance_enabled'] ?? false;
      if (enabled) {
        switch (data['maintenance_status'] ?? 'not_scheduled') {
          case 'overdue':
            overdue++;
            break;
          case 'due_soon':
            dueSoon++;
            break;
          case 'on_schedule':
            onSchedule++;
            break;
          default:
            notScheduled++;
        }
      } else {
        notScheduled++;
      }
    }
    return {
      'overdue': overdue,
      'due_soon': dueSoon,
      'on_schedule': onSchedule,
      'not_scheduled': notScheduled,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Ground Assets',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: const Color(0xFFFAFBFC),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 80,
        bottom: _tabController == null
            ? null
            : PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController!,
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2, size: 20),
                      SizedBox(width: 8),
                      Text('Assets'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.build_circle, size: 20),
                      SizedBox(width: 8),
                      Text('Maintenance'),
                    ],
                  ),
                ),
              ],
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              ),
              labelColor: const Color(0xFFEF4444),
              unselectedLabelColor: Colors.grey.shade600,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              dividerColor: Colors.transparent,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
            ),
          ),
        ),
      ),
      body: _tabController == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController!,
        children: [_buildAssetsTab(), _buildMaintenanceTab()],
      ),
      floatingActionButton: _uid != null
          ? Container(
        margin: const EdgeInsets.only(bottom: 100),
        child: FloatingActionButton(
          onPressed: _navigateToAddAsset,
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add, size: 28),
        ),
      )
          : null,
    );
  }

  Widget _buildAssetsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _getAssetsStream(),
      builder: (context, snapshot) {
        if (_uid == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Login Required',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('Please log in to view and manage your assets',
                    style: TextStyle(color: Colors.grey.shade500)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please implement login functionality'),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading your assets...'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Error loading assets',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text(snapshot.error.toString(),
                    style: TextStyle(color: Colors.grey.shade500)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final assets = snapshot.data?.docs ?? [];
        if (assets.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('No assets yet',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('Tap the + button to add your first asset',
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        return _buildAssetsView(assets);
      },
    );
  }

  Widget _buildMaintenanceTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _getAssetsStream(),
      builder: (context, snapshot) {
        if (_uid == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('Login Required',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Text('Please log in to view maintenance information',
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading data: ${snapshot.error}'));
        }
        final assets = snapshot.data?.docs ?? [];
        return _buildMaintenanceView(assets);
      },
    );
  }

  Widget _buildAssetsView(List<QueryDocumentSnapshot<Map<String, dynamic>>> assets) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Assets',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${assets.length} items',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Value',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${_calculateTotalValue(assets).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: assets.length,
            itemBuilder: (context, index) => _buildAssetCard(assets[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceView(List<QueryDocumentSnapshot<Map<String, dynamic>>> assets) {
    final summary = _getMaintenanceSummary(assets);
    final withMaintenanceTracking = assets
        .where((a) {
      final data = a.data();
      return (data['maintenance_enabled'] ?? false) == true;
    }).toList();
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: _buildMaintenanceCard(
                    'Overdue', summary['overdue']!, Colors.red, Icons.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMaintenanceCard('Due Soon', summary['due_soon']!,
                    Colors.orange, Icons.schedule),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: _buildMaintenanceCard('On Schedule',
                    summary['on_schedule']!, Colors.green, Icons.check_circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMaintenanceCard('Not Scheduled',
                    summary['not_scheduled']!, Colors.grey, Icons.info),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: withMaintenanceTracking.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.build_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('No assets with maintenance tracking',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                Text('Enable maintenance tracking when adding assets',
                    style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
            itemCount: withMaintenanceTracking.length,
            itemBuilder: (context, index) =>
                _buildMaintenanceListItem(withMaintenanceTracking[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceCard(String title, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceListItem(DocumentSnapshot asset) {
    final data = asset.data() as Map<String, dynamic>?;
    if (data == null) return const SizedBox.shrink();
    final maintenanceEnabled = data['maintenance_enabled'];
    if (maintenanceEnabled != true) return const SizedBox.shrink();
    final name = data['name'] ?? 'Unnamed';
    final status = data['maintenance_status'] ?? 'not_scheduled';
    final next = data['next_maintenance_date'] as Timestamp?;
    final last = data['last_maintenance_date'] as Timestamp?;
    final cost = (data['total_maintenance_cost'] ?? 0.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _getMaintenanceStatusColor(status).withValues(alpha: 0.15),
          child: Icon(
            _getMaintenanceStatusIcon(status),
            color: _getMaintenanceStatusColor(status),
            size: 20,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _buildMaintenanceStatusChip(status),
            const SizedBox(height: 8),
            if (next != null)
              Text(
                'Next: ${_formatDateShort(next.toDate())}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            if (last != null)
              Text(
                'Last: ${_formatDateShort(last.toDate())}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            if (cost > 0)
              Text(
                'Total Cost: ₱${cost.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showMaintenanceDialog(asset),
        ),
        onTap: () => _showAssetDialog(asset),
      ),
    );
  }

  double _calculateTotalValue(List<QueryDocumentSnapshot<Map<String, dynamic>>> assets) {
    double total = 0.0;
    for (final asset in assets) {
      final data = asset.data();
      total += (data['value'] ?? 0).toDouble();
    }
    return total;
  }
}