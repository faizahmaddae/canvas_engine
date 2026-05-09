import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/project.dart';
import 'widgets/recent_projects_grid.dart';

/// Full list of recent projects, surfaced from the Home "See all"
/// link. Re-uses [RecentProjectsGrid] (no `limit`) so all projects
/// render in the same grid + card design as Home.
///
/// Architecture: pure presentation. Open / create callbacks are
/// delegated up to the caller (Home) so navigation logic stays in
/// one place.
class RecentProjectsScreen extends ConsumerWidget {
  const RecentProjectsScreen({
    super.key,
    required this.onCreate,
    required this.onOpen,
  });

  final VoidCallback onCreate;
  final void Function(Project project) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Recent projects'),
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 24),
          child: RecentProjectsGrid(
            onCreate: onCreate,
            onOpen: onOpen,
          ),
        ),
      ),
    );
  }
}
