import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/appearance/appearance_screen.dart';
import '../../features/expenses/expense_form_screen.dart';
import '../../features/expenses/expense_list_screen.dart';
import '../../features/expenses/widgets/fold_add_panel.dart';
import '../../features/family/member_providers.dart';
import '../../features/home/home_screen.dart';
import '../layout/adaptive_shell.dart';
import '../layout/destinations.dart';
import '../layout/page_layout.dart';
import '../layout/window_class.dart';

/// Pages that open full screen on the phone get a back button to Home.
Widget _placeholder(BuildContext context, String title, String phase) {
  return ComingSoonPage(
    title: title,
    phase: phase,
    onBack: context.layout.isCompact ? () => context.go('/home') : null,
  );
}

GoRouter buildRouter({String initialLocation = '/home'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            _Shell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (c, s) => _page(s, const HomeScreen()),
          ),
          GoRoute(
            path: '/budgets',
            pageBuilder: (c, s) =>
                _page(s, _placeholder(c, 'Budgets', 'Phase 5')),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (c, s) =>
                _page(s, _placeholder(c, 'Insights', 'Phase 5')),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (c, s) =>
                _page(s, _placeholder(c, 'Goals', 'Phase 5')),
          ),
          GoRoute(
            path: '/bills',
            pageBuilder: (c, s) =>
                _page(s, _placeholder(c, 'Bills', 'Phase 5')),
          ),
          GoRoute(
            path: '/family',
            pageBuilder: (c, s) =>
                _page(s, _placeholder(c, 'Family', 'Phase 3')),
          ),
          GoRoute(
            path: '/appearance',
            pageBuilder: (c, s) => _page(s, const AppearanceScreen()),
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (c, s) => _page(s, const ExpenseListScreen()),
          ),
          GoRoute(
            path: '/expenses/:id/edit',
            pageBuilder: (c, s) => _page(
              s,
              ExpenseFormScreen(
                key: ValueKey(s.pathParameters['id']),
                editId: s.pathParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: '/add',
            pageBuilder: (c, s) => _page(s, const ExpenseFormScreen()),
          ),
        ],
      ),
    ],
  );
}

Page<void> _page(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

class _Shell extends ConsumerWidget {
  const _Shell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openAdd() {
      if (location != '/add') context.push('/add');
    }

    final onTabRoot = AppDestination.tabs.any((d) => d.path == location);
    // Ctrl or Cmd + N adds an expense from anywhere (desktop, or any keyboard).
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              openAdd,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): openAdd,
        },
        child: AdaptiveShell(
          destination: AppDestination.fromLocation(location),
          onSelect: (d) => context.go(d.path),
          memberInitials: ref.watch(memberInitialsProvider),
          showBottomTabs: onTabRoot,
          foldBottom: location == '/home' ? const FoldAddPanel() : null,
          child: child,
        ),
      ),
    );
  }
}
