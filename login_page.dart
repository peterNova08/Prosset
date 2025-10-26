import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_page.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = false;
  bool _obscurePassword = true;

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
    super.dispose();
  }

  // Email validation function
  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  Future<void> login() async {
    // Form validation handles all input checks
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (isLoading) return;

    setState(() => isLoading = true);

    try {
      _showSnackBar('Signing you in...', Colors.blue, duration: 2);

      final userCredential = await _auth
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Login timeout. Please check your internet connection and try again.');
        },
      );

      if (userCredential.user != null && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSnackBar('Welcome back! Login successful.', Colors.green, duration: 2);
        await Future.delayed(const Duration(milliseconds: 800));

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DashboardPage()),
                (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = _getFirebaseErrorMessage(e.code);
        _showSnackBar(message, Colors.red);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString().contains('timeout')
            ? 'Login timeout. Please check your internet connection.'
            : 'Login failed. Please check your credentials and try again.';
        _showSnackBar(errorMessage, Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _getFirebaseErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'user-not-found':
        return 'No account found with this email address. Please check your email or sign up.';
      case 'wrong-password':
        return 'Incorrect password. Please try again or reset your password.';
      case 'invalid-email':
        return 'Invalid email address format. Please enter a valid email.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please check your credentials.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Please contact support.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      default:
        return 'Login failed. Please check your credentials and try again.';
    }
  }

  void _showSnackBar(String message, Color backgroundColor, {int duration = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: duration),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade800, Colors.blue.shade600],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Form(
                  key: _formKey,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    elevation: 12,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo
                          Container(
                            height: 80,
                            width: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.shade100,
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 38,
                              color: Colors.blue.shade800,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Title
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to continue to your business dashboard',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Email Field
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enabled: !isLoading,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Email address is required';
                              }
                              if (!_isValidEmail(value.trim())) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'Email Address',
                              hintText: 'Enter your email address',
                              prefixIcon: const Icon(Icons.email_outlined, size: 22),
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
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          TextFormField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enabled: !isLoading,
                            onFieldSubmitted: (_) => !isLoading ? login() : null,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Password is required';
                              }
                              if (value.length < 8) {
                                return 'Password must be at least 8 characters';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline, size: 22),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 22,
                                ),
                                onPressed: isLoading
                                    ? null
                                    : () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding: const EdgeInsets.all(18),
                              errorStyle: const TextStyle(fontSize: 12),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.blue.shade900,
                                disabledBackgroundColor: Colors.grey.shade200,
                                disabledForegroundColor: Colors.grey.shade600,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isLoading ? Colors.grey.shade400 : Colors.blue.shade800,
                                    width: 1.5,
                                  ),
                                ),
                                elevation: 0,
                              ),
                              onPressed: isLoading ? null : login,
                              child: isLoading
                                  ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Signing In...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                                  : const Text(
                                'Sign In to Dashboard',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Login Tips
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    size: 16, color: Colors.blue.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Trouble signing in? Check your email/password.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Sign-up Link
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignupPage(),
                                ),
                              );
                            },
                            child: RichText(
                              text: TextSpan(
                                text: "Don't have an account? ",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isLoading ? Colors.grey : Colors.grey.shade700,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Create One',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: isLoading ? Colors.grey : Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}