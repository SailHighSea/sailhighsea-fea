import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/db/db_providers.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/appearance_provider.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/supabase_auth_service.dart';
import 'features/family/data/supabase_household_remote.dart';
import 'features/bills/reminders/reminder_providers.dart';
import 'features/bills/reminders/reminder_scheduler.dart';
import 'features/family/member_providers.dart';
import 'features/integrations/data/supabase_sheets_remote.dart';
import 'features/integrations/sheets_providers.dart';
import 'features/scan/receipt_services.dart';
import 'features/sync/sync_providers.dart';
import 'core/sync/supabase_sync_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US');
  final prefs = await SharedPreferences.getInstance();
  // Local-first: the UI reads and writes this SQLite file.
  final database = AppDatabase(driftDatabase(name: 'family_expenses'));

  // Accounts need a Supabase project (`--dart-define-from-file=.env.json`). Without one the
  // app runs local-only: no sign-in, one person, everything stays on this device.
  const config = SupabaseConfig.fromEnvironment();
  SupabaseClient? client;
  if (config.isConfigured) {
    await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
    client = Supabase.instance.client;
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(database),
        reminderSchedulerProvider.overrideWithValue(
          LocalNotificationsScheduler(),
        ),
        if (client != null) ...[
          authServiceProvider.overrideWithValue(
            SupabaseAuthService(client.auth),
          ),
          householdRemoteProvider.overrideWithValue(
            SupabaseHouseholdRemote(client),
          ),
          syncBackendProvider.overrideWithValue(SupabaseSyncBackend(client)),
          receiptStorageProvider.overrideWithValue(
            SupabaseReceiptStorage(client),
          ),
          sheetsRemoteProvider.overrideWithValue(SupabaseSheetsRemote(client)),
        ],
      ],
      child: const FamilyExpensesApp(),
    ),
  );
}
