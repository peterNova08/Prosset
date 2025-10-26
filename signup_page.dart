import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController businessNameController = TextEditingController();
  final TextEditingController capitalController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();

  bool isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    businessNameController.dispose();
    capitalController.dispose();
    super.dispose();
  }

  // Email validation function
  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  // Updated: Include underscore (_) as valid special character
  bool _isStrongPassword(String password) {
    return RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&_])[A-Za-z\d@$!%*?&_]{8,}$',
    ).hasMatch(password);
  }

  // Get password strength message — updated to mention underscore
  String _getPasswordStrengthMessage(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'(?=.*[a-z])').hasMatch(password)) {
      return 'Password must contain lowercase letters';
    }
    if (!RegExp(r'(?=.*[A-Z])').hasMatch(password)) {
      return 'Password must contain uppercase letters';
    }
    if (!RegExp(r'(?=.*\d)').hasMatch(password)) {
      return 'Password must contain numbers';
    }
    if (!RegExp(r'(?=.*[@$!%*?&_])').hasMatch(password)) {
      return 'Password must contain special characters (@\$!%*?&_)';
    }
    return '';
  }

  Future<void> signUp() async {
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final businessName = businessNameController.text.trim();
    final capital = double.tryParse(capitalController.text.trim()) ?? 0.0;

    // Enhanced validation with specific error messages
    if (email.isEmpty) {
      _showSnackBar('Email is required', Colors.red);
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address (e.g., user@example.com)', Colors.red);
      return;
    }

    if (businessName.isEmpty) {
      _showSnackBar('Business name is required', Colors.red);
      return;
    }

    if (businessName.length < 3) {
      _showSnackBar('Business name must be at least 3 characters', Colors.red);
      return;
    }

    if (capital <= 0) {
      _showSnackBar('Initial capital must be greater than ₱0', Colors.red);
      return;
    }

    if (capital < 1000) {
      _showSnackBar('Minimum initial capital is ₱1,000', Colors.red);
      return;
    }

    if (password.isEmpty) {
      _showSnackBar('Password is required', Colors.red);
      return;
    }

    if (password.length < 8) {
      _showSnackBar('Password must be at least 8 characters long', Colors.red);
      return;
    }

    if (!_isStrongPassword(password)) {
      String message = _getPasswordStrengthMessage(password);
      _showSnackBar(message, Colors.orange);
      return;
    }

    if (confirmPassword.isEmpty) {
      _showSnackBar('Please confirm your password', Colors.red);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar('Passwords do not match', Colors.red);
      return;
    }

    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      final userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password)
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Request timed out'),
      );

      if (userCredential.user != null && mounted) {
        await _saveBusinessDetails(
          userCredential.user!.uid,
          email,
          businessName,
          capital,
        );

        // Sign out the user after creating account so they need to login
        await _auth.signOut();

        _showSnackBar('Account created successfully! Please login to continue.', Colors.green);
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showSnackBar(_getFirebaseErrorMessage(e.code), Colors.red);
    } catch (e) {
      if (mounted) _showSnackBar('Sign-up failed. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveBusinessDetails(
      String uid, String email, String businessName, double capital) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'name': '',
      'business': businessName,
      'email': email,
      'phone': '',
      'initialCapital': capital,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please use a different email.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'invalid-email':
        return 'Invalid email format. Please check your email address.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'Account creation is currently disabled. Please try again later.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';
      default:
        return 'Sign-up failed. Please try again.';
    }
  }

  void _showSnackBar(String message, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.blue.shade600],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    elevation: 12,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 40),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 80,
                              width: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.blue.shade50,
                              ),
                              child: Icon(
                                Icons.person_add_alt_1,
                                size: 38,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Set up your business profile',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 32),
                            _field(
                              controller: emailController,
                              label: 'Email Address',
                              icon: Icons.email_outlined,
                              keyboard: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email is required';
                                }
                                if (!_isValidEmail(v.trim())) {
                                  return 'Enter a valid email (e.g., user@example.com)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _field(
                              controller: businessNameController,
                              label: 'Business Name',
                              icon: Icons.business_outlined,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Business name is required';
                                }
                                if (v.trim().length < 3) {
                                  return 'Business name must be at least 3 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _field(
                              controller: capitalController,
                              label: 'Initial Capital (Minimum ₱1,000)',
                              icon: Icons.attach_money,
                              keyboard: const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+\.?\d{0,2}'))
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Initial capital is required';
                                }
                                final amount = double.tryParse(v.trim()) ?? 0;
                                if (amount <= 0) {
                                  return 'Must be greater than ₱0';
                                }
                                if (amount < 1000) {
                                  return 'Minimum capital is ₱1,000';
                                }
                                return null;
                              },
                              prefix: const Text('₱ '),
                            ),
                            const SizedBox(height: 16),
                            _field(
                              controller: passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscure: _obscurePassword,
                              toggleObscure: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Password is required';
                                }
                                if (v.length < 8) {
                                  return 'Password must be at least 8 characters';
                                }
                                if (!_isStrongPassword(v)) {
                                  return 'Use uppercase, lowercase, number, and special char (@\$!%*?&_)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _field(
                              controller: confirmPasswordController,
                              label: 'Confirm Password',
                              icon: Icons.lock_outline,
                              obscure: _obscureConfirm,
                              toggleObscure: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (v != passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Password requirements info — updated to include underscore
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline,
                                          size: 16, color: Colors.blue.shade700),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Password Requirements:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '• At least 8 characters\n'
                                        '• Uppercase & lowercase letters\n'
                                        '• Numbers\n'
                                        '• Special characters (@\$!%*?&_)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade600,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.blue.shade900,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                        color: Colors.blue.shade800,
                                        width: 1.5),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: isLoading ? null : signUp,
                                child: isLoading
                                    ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                        Colors.blue.shade800),
                                  ),
                                )
                                    : const Text(
                                  'Create Business Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text(
                                'Already have an account? Login',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    bool obscure = false,
    Widget? prefix,
    String? Function(String?)? validator,
    VoidCallback? toggleObscure,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: inputFormatters,
      obscureText: obscure,
      enabled: !isLoading,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        prefix: prefix,
        suffixIcon: toggleObscure != null
            ? IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 22,
          ),
          onPressed: toggleObscure,
        )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.all(18),
        errorStyle: const TextStyle(fontSize: 12),
        errorMaxLines: 2,
      ),
    );
  }
}