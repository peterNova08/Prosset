import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isEditing = false;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _businessController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _capitalController = TextEditingController();
  final TextEditingController _profilePictureUrlController = TextEditingController();

  User? get user => FirebaseAuth.instance.currentUser;

  String? _businessLock;
  double? _capitalLock;
  String? _profileImageUrl; // URL of profile image

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _capitalController.dispose();
    _profilePictureUrlController.dispose();
    super.dispose();
  }

  void _loadProfile() {
    final u = user;
    if (u == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(u.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _businessController.text = data['business'] ?? '';
          _emailController.text = data['email'] ?? u.email!;
          _phoneController.text = data['phone'] ?? '';
          _profileImageUrl = data['profilePicture'];
          _profilePictureUrlController.text = _profileImageUrl ?? '';

          final capitalValue = data['initialCapital'];
          if (capitalValue != null) {
            _capitalController.text = capitalValue.toString();
            _capitalLock = (capitalValue as num).toDouble();
          } else {
            _capitalController.text = '0';
            _capitalLock = null;
          }

          _businessLock = data['business'];
        });
      }
    }, onError: (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_pictures')
          .child('${user!.uid}.jpg');

      final uploadTask = storageRef.putFile(File(pickedFile.path));
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _profilePictureUrlController.text = downloadUrl;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    final u = user;
    if (u == null) return;

    final trimmedBusiness = _businessController.text.trim();
    final capital = double.tryParse(_capitalController.text.trim()) ?? 0.0;

    if (trimmedBusiness.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business name is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (capital < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Initial capital cannot be negative'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'name': _nameController.text.trim(),
        'business': trimmedBusiness,
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'initialCapital': capital,
        'profilePicture': _profileImageUrl,
      }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _isEditing = false;
        _isLoading = false;
        _businessLock = trimmedBusiness;
        _capitalLock = capital;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text(_businessLock == trimmedBusiness
                  ? 'Business & capital set successfully'
                  : 'Profile updated'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showLogoutDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.red.shade50, Colors.orange.shade50],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout_rounded,
                    color: Colors.red.shade700, size: 32),
              ),
              const SizedBox(height: 20),
              const Text('Sign Out',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 12),
              Text('Are you sure you want to sign out?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Sign Out',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();

    try {
      setState(() => _isLoading = true);
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign-out failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    bool enabled = false,
    String? helper,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? prefix,
  }) {
    final isLocked = label.contains('Business') && _businessLock != null;
    final isCapitalLocked = label.contains('Capital') && _capitalLock != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled && !isLocked && !isCapitalLocked,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: enabled && !isLocked && !isCapitalLocked
                      ? null
                      : Colors.grey.shade600,
                ),
                decoration: InputDecoration(
                  labelText: label,
                  helperText: helper,
                  helperStyle: helper != null
                      ? TextStyle(
                    color: Colors.red.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  )
                      : null,
                  border: InputBorder.none,
                  prefix: prefix,
                  labelStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  disabledBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
              ),
            ),
            if (isLocked || isCapitalLocked)
              Tooltip(
                message: 'This field is locked after initial setup.',
                child: Icon(
                  Icons.lock,
                  color: Colors.grey.shade500,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = user;
    final userName = _nameController.text.isNotEmpty
        ? _nameController.text
        : (u?.displayName ?? "");
    final userEmail = u?.email ?? "";

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text(
            "My Profile",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          elevation: 0,
          actions: [
            if (_isEditing)
              IconButton(
                icon: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
                    : const Icon(Icons.save_rounded, color: Colors.white),
                onPressed: _isLoading ? null : _saveProfile,
              )
            else
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
                onPressed: _isLoading ? null : () => setState(() => _isEditing = true),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),

              // Profile Header Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Picture Display
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        ClipOval(
                          child: _profileImageUrl != null
                              ? Image.network(
                            _profileImageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.account_circle_rounded, size: 80, color: Colors.white),
                          )
                              : const Icon(Icons.account_circle_rounded, size: 80, color: Colors.white),
                        ),
                        if (_isEditing)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade300, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (userName.isNotEmpty)
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    if (userEmail.isNotEmpty)
                      Text(
                        userEmail,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 12),
                    if (_isEditing)
                      TextButton.icon(
                        onPressed: _isLoading ? null : _pickImage,
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text("Change Picture", style: TextStyle(color: Colors.white70)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Editable Fields
              _buildInfoCard(
                icon: Icons.person,
                label: "Full Name",
                controller: _nameController,
                enabled: _isEditing,
              ),
              _buildInfoCard(
                icon: Icons.storefront,
                label: "Business Name",
                controller: _businessController,
                enabled: _isEditing,
                helper: (_businessController.text.trim().isEmpty && _isEditing)
                    ? 'Required – cannot be changed later'
                    : null,
              ),
              _buildInfoCard(
                icon: Icons.monetization_on,
                label: "Initial Capital (₱)",
                controller: _capitalController,
                enabled: _isEditing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                helper: ((_capitalController.text.trim().isEmpty ||
                    (double.tryParse(_capitalController.text.trim()) ?? 0) == 0) &&
                    _isEditing)
                    ? 'Required – cannot be changed later'
                    : null,
              ),
              _buildInfoCard(
                icon: Icons.phone,
                label: "Phone Number",
                controller: _phoneController,
                enabled: _isEditing,
              ),
              _buildInfoCard(
                icon: Icons.email,
                label: "Email",
                controller: _emailController,
                enabled: false,
              ),

              const SizedBox(height: 24),

              // Save Button (only in edit mode)
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isLoading ||
                          _businessController.text.trim().isEmpty ||
                          (double.tryParse(_capitalController.text.trim()) ?? 0) == 0)
                          ? null
                          : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : const Text(
                        "Save Changes",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

              // Logout Button (only in view mode)
              if (!_isEditing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _showLogoutDialog,
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      label: const Text(
                        "Sign Out",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}