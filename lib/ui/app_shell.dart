import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme/app_theme.dart';
import 'pages/accounts_page.dart';
import 'pages/budgets_page.dart';
import 'pages/categories_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/jewelry_page.dart';
import 'pages/reports_page.dart';
import 'pages/settings_page.dart';
import 'pages/transactions_page.dart';
import 'widgets/brand_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;
  final mobileScaffoldKey = GlobalKey<ScaffoldState>();
  static const destinations = [
    _Destination('Overview', Icons.space_dashboard_rounded),
    _Destination('Transactions', Icons.swap_vert_circle_rounded),
    _Destination('Cutoffs & budgets', Icons.calendar_view_week_rounded),
    _Destination('Accounts', Icons.account_balance_wallet_rounded),
    _Destination('Gold & jewelry', Icons.diamond_rounded),
    _Destination('Categories', Icons.category_rounded),
    _Destination('Reports', Icons.insights_rounded),
    _Destination('Settings', Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final page = switch (selectedIndex) {
      0 => DashboardPage(
        controller: widget.controller,
        onOpenTransactions: () => setState(() => selectedIndex = 1),
      ),
      1 => TransactionsPage(controller: widget.controller),
      2 => BudgetsPage(controller: widget.controller),
      3 => AccountsPage(controller: widget.controller),
      4 => JewelryPage(controller: widget.controller),
      5 => CategoriesPage(controller: widget.controller),
      6 => ReportsPage(controller: widget.controller),
      _ => SettingsPage(controller: widget.controller),
    };
    return Scaffold(
      key: mobileScaffoldKey,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          destinations[selectedIndex].label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Stored on this phone',
              child: Icon(Icons.phonelink_lock_rounded, size: 21),
            ),
          ),
        ],
      ),
      drawer: NavigationDrawer(
        key: const Key('mobile-navigation-drawer'),
        backgroundColor: context.palette.sidebar,
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          setState(() => selectedIndex = index);
        },
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 18),
              child: Row(
                children: [
                  const BrandLogo(
                    key: Key('mobile-drawer-brand-logo'),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'expenses tracker offline',
                      style: TextStyle(
                        color: context.palette.onSidebar,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            color: context.palette.sidebarBorder,
            indent: 16,
            endIndent: 16,
          ),
          for (final destination in destinations)
            NavigationDrawerDestination(
              icon: Icon(destination.icon),
              label: SizedBox(
                width: 180,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
            child: Text(
              'Everything is saved on this phone. Keep a backup in Settings.',
              style: TextStyle(
                color: context.palette.onSidebarMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(child: page),
            if (widget.controller.isBusy || widget.controller.isRefreshing)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        key: const Key('mobile-navigation-bar'),
        selectedIndex: selectedIndex <= 3 ? selectedIndex : 4,
        onDestinationSelected: (value) {
          if (value == 4) {
            mobileScaffoldKey.currentState?.openDrawer();
          } else {
            setState(() => selectedIndex = value);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_circle_outlined),
            selectedIcon: Icon(Icons.swap_vert_circle_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week_rounded),
            label: 'Budgets',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Accounts',
          ),
          NavigationDestination(icon: Icon(Icons.menu_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}
