import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';
import 'placeholder_tab.dart';

/// App root wrapper providing a Material 3 [NavigationBar] across
/// four tabs: Home / Projects / Templates / Profile. Only Home is
/// implemented; the others render a calm [PlaceholderTab] so the
/// shell is real without faking missing features.
///
/// Tab switching uses [IndexedStack] so each tab keeps its scroll
/// position, controllers and any in-flight state when the user
/// hops between them — a small detail that makes the app feel
/// "kept" rather than "rebuilt" on every nav change.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _TabSpec(
      label: 'Projects',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
    _TabSpec(
      label: 'Templates',
      icon: Icons.dashboard_customize_outlined,
      selectedIcon: Icons.dashboard_customize_rounded,
    ),
    _TabSpec(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            PlaceholderTab(
              icon: Icons.folder_open_rounded,
              title: 'Projects',
              body: 'A dedicated home for everything you\u2019ve made.',
            ),
            PlaceholderTab(
              icon: Icons.dashboard_customize_rounded,
              title: 'Templates',
              body: 'Browse the full catalog by category and language.',
            ),
            PlaceholderTab(
              icon: Icons.person_rounded,
              title: 'Profile',
              body: 'Account, sync and personalisation will live here.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
