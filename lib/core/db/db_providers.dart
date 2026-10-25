import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Overridden in `main()` (and in tests) with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);
