import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'profit_calculator_page.dart';
import 'balance_sheet_page.dart';
import 'cash_flow_page.dart';
import 'reports_page.dart';
import 'ground_assets_page.dart';
import 'profile_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    ProfitCalculatorPage(),
    BalanceSheetPage(),
    CashFlowPage(),
    ReportsPage(),
    GroundAssetsPage(),
    ProfilePage(),
  ];

  // Enhanced navigation items with better organization
  final List<NavigationItem> _navigationItems = const [
    NavigationItem(
      icon: Icons.trending_up_rounded,
      activeIcon: Icons.trending_up_rounded,
      label: 'Profit',
      color: Color(0xFF10B981),
    ),
    NavigationItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Balance',
      color: Color(0xFF8B5CF6),
    ),
    NavigationItem(
      icon: Icons.swap_horizontal_circle_outlined,
      activeIcon: Icons.swap_horizontal_circle,
      label: 'Cash Flow',
      color: Color(0xFF3B82F6),
    ),
    NavigationItem(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      label: 'Reports',
      color: Color(0xFFF59E0B),
    ),
    NavigationItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Assets',
      color: Color(0xFFEF4444),
    ),
    NavigationItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
      color: Color(0xFF6366F1),
    ),
  ];

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;

    // Haptic feedback for better UX
    HapticFeedback.lightImpact();

    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFFAFBFC),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOut,
              )),
              child: child,
            ),
          );
        },
        child: _pages[_selectedIndex],
      ),

      // Enhanced floating navigation bar
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: _buildNavigationBar(),
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Container(
      height: 75,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: List.generate(
            _navigationItems.length,
                (index) => _buildNavigationItem(index),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationItem(int index) {
    final item = _navigationItems[index];
    final isSelected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon container with enhanced styling
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? item.color.withValues(alpha: 0.12)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  size: 24,
                  color: isSelected
                      ? item.color
                      : Colors.grey.shade500,
                ),
              ),

              const SizedBox(height: 4),

              // Label with improved typography
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected
                      ? item.color
                      : Colors.grey.shade500,
                  letterSpacing: 0.2,
                ),
                child: Text(item.label),
              ),

              // Active indicator dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.only(top: 2),
                height: 2,
                width: isSelected ? 16 : 0,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper class for better organization
class NavigationItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color;

  const NavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
  });
}