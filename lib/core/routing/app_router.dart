import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/appearance/appearance_screen.dart';
import '../../features/expenses/expense_form_screen.dart';
import '../../features/expenses/expense_list_screen.dart';
import '../../features/expenses/widgets/fold_add_panel.dart';
import '../../features/auth/app_access.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/family/domain/permissions.dart';
import '../../features/family/family_screen.dart';
import '../../features/family/join_screen.dart';
import '../../features/family/member_providers.dart';
import '../../features/home/home_screen.dart';
import '../../features/sync/sync_indicator.dart';
import '../layout/adaptive_shell.dart';
import '../layout/destinations.dart';
import '../layout/page_layout.dart';
import '../layout/window_class.dart';
import '../theme/app_tokens.dart';

/// Pages that open full screen on the phone get a back button to Home.
Widget _placeholder(BuildContext context, String title, String phase) {
  return ComingSoonPage(
    title: title,
    phase: phase,
    onBack: context.layout.isCompact ? () => context.go('/home') : null,
  );
}

/// Routes that sit outside the shell (no tabs, rail or sidebar): sign-in and joining.
const _gateRoutes = {'/sign-in', '/welcome', '/starting'};

/// [gate] guards the routes: signed-out people see sign-in, new people the
/// welcome page, and view-only members cannot open the add or edit screens. Without them (the
/// default, used by most tests) nothing is guarded.
/// Tells the router when sign-in, household or role changed so it re-checks its guards.
class RouteGate extends ChangeNotifier {
  RouteGate(this.access, this.permissions);

  AppAccess access;
  final Permissions Function() permissions;

  void update(AppAccess next) {
    access = next;
    notifyListeners();
  }

  void recheck() => notifyListeners();
}

GoRouter buildRouter({String initialLocation = '/home', RouteGate? gate}) {
  String? redirect(BuildContext context, GoRouterState state) {
    final path = state.uri.path;
    // Where the person wanted to go, kept while they pass through starting, sign-in or welcome.
    final from =
        state.uri.queryParameters['from'] ??
        (_gateRoutes.contains(path) || path == '/join'
            ? null
            : state.uri.toString());
    String detour(String page) => from == null || from == '/home'
        ? page
        : '$page?from=${Uri.encodeQueryComponent(from)}';
    switch (gate?.access ?? AppAccess.localOnly) {
      case AppAccess.starting:
        return path == '/starting' ? null : detour('/starting');
      case AppAccess.signedOut:
        return path == '/sign-in' ? null : detour('/sign-in');
      case AppAccess.needsHousehold:
        return (path == '/welcome' || path == '/join')
            ? null
            : detour('/welcome');
      case AppAccess.localOnly:
      case AppAccess.ready:
        if (_gateRoutes.contains(path) ||
            (path == '/join' && gate?.access != AppAccess.ready)) {
          return state.uri.queryParameters['from'] ?? '/home';
        }
        final canWrite = gate?.permissions().canWriteExpenses ?? true;
        if (!canWrite && (path == '/add' || path.endsWith('/edit'))) {
          return '/home';
        }
        return null;
    }
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: gate,
    redirect: redirect,
    routes: [
      GoRoute(
        path: '/sign-in',
        pageBuilder: (c, s) => _page(s, const SignInScreen()),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (c, s) => _page(s, const WelcomeScreen()),
      ),
      GoRoute(
        path: '/join',
        pageBuilder: (c, s) => _page(s, const JoinScreen()),
      ),
      GoRoute(
        path: '/starting',
        pageBuilder: (c, s) => _page(s, const _StartingPage()),
      ),
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
            pageBuilder: (c, s) => _page(s, const FamilyScreen()),
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
    final canAdd = ref.watch(permissionsProvider).canWriteExpenses;
    void openAdd() {
      if (canAdd && location != '/add') context.push('/add');
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
          syncIndicator: (dense) => SyncIndicator(dense: dense),
          foldBottom: location == '/home' && canAdd
              ? const FoldAddPanel()
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// Shown while the saved session and household are checked.
class _StartingPage extends StatelessWidget {
  const _StartingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tokens.background,
      body: Center(
        child: Semantics(
          label: 'Loading',
          child: CircularProgressIndicator(color: context.tokens.primary),
        ),
      ),
    );
  }
}
