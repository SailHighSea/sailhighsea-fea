import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/db/db_providers.dart';
import 'core/theme/appearance_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US');
  final prefs = await SharedPreferences.getInstance();
  // Local-first: the UI reads and writes this SQLite file; no account is needed.
  final database = AppDatabase(driftDatabase(name: 'family_expenses'));
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(database),
      ],
      child: const FamilyExpensesApp(),
    ),
  );
}
