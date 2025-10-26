import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Cache user data to avoid repeated Firestore calls
  final Map<String, bool> _userBusinessCache = {};

  // Track if we're currently checking business data
  bool _isCheckingBusiness = false;

  Future<bool> _hasBusiness(User user) async {
    // Return cached result if available
    if (_userBusinessCache.containsKey(user.uid)) {
      return _userBusinessCache[user.uid]!;
    }

    // Prevent multiple simultaneous calls for the same user
    if (_isCheckingBusiness) {
      // Wait a bit and check cache again
      await Future.delayed(const Duration(milliseconds: 100));
      if (_userBusinessCache.containsKey(user.uid)) {
        return _userBusinessCache[user.uid]!;
      }
    }

    _isCheckingBusiness = true;

    try {
      // Add timeout to prevent indefinite waiting
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // Return a default document snapshot if timeout
          throw Exception('Timeout checking user business data');
        },
      );

      final hasBusiness = snap.exists &&
          (snap.data()?['business'] ?? '').toString().isNotEmpty;

      // Cache the result
      _userBusinessCache[user.uid] = hasBusiness;

      return hasBusiness;
    } catch (e) {
      // Default to false if there's an error, but don't cache errors
      return false;
    } finally {
      _isCheckingBusiness = false;
    }
  }

  // Clear cache when user changes (optional cleanup)
  void _clearCache() {
    _userBusinessCache.clear();
    _isCheckingBusiness = false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Handle different connection states
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade600],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Handle connection errors
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Authentication Error'),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _clearCache();
                      // Force rebuild
                      setState(() {});
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        final user = snapshot.data;

        // No user logged in - go to login
        if (user == null) {
          _clearCache(); // Clear cache when user logs out
          return const LoginPage();
        }

        // User is logged in - check business data
        return FutureBuilder<bool>(
          future: _hasBusiness(user),
          builder: (context, bizSnap) {
            // Handle loading state for business check
            if (bizSnap.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade800, Colors.blue.shade600],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Setting up your account...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Handle business check errors
            if (bizSnap.hasError) {
              // On error, default to ProfilePage to let user set up business
              return const ProfilePage();
            }

            // Business check complete - route to appropriate page
            final hasBusiness = bizSnap.data ?? false;
            return hasBusiness ? const DashboardPage() : const ProfilePage();
          },
        );
      },
    );
  }
}

// Alternative: More performant version using a single stream
class AuthGateAlternative extends StatelessWidget {
  const AuthGateAlternative({super.key});

  // This version combines auth and firestore into a single stream
  // More complex but potentially more performant
  Stream<Widget> _getAuthenticatedPage() {
    return FirebaseAuth.instance.authStateChanges().asyncMap<Widget>((user) async {
      if (user == null) {
        return const LoginPage();
      }

      try {
        // Check business data
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 10));

        final hasBusiness = snap.exists &&
            (snap.data()?['business'] ?? '').toString().isNotEmpty;

        return hasBusiness ? const DashboardPage() : const ProfilePage();
      } catch (e) {
        // Log error in debug mode only
        assert(() {
          debugPrint('Error in auth stream: $e');
          return true;
        }());
        // Default to ProfilePage on error
        return const ProfilePage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Widget>(
      stream: _getAuthenticatedPage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade600],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Something went wrong'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Force rebuild
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        return snapshot.data ?? const LoginPage();
      },
    );
  }
}