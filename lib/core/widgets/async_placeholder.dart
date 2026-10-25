import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Shown while a screen's data is loading, or when loading failed. One look for every screen:
/// a spinner announced as "Loading", or a plain sentence and a Retry button (never a raw
/// exception).
class AsyncPlaceholder extends StatelessWidget {
  const AsyncPlaceholder({
    super.key,
    required this.what,
    this.error,
    this.onRetry,
  });

  /// What is being loaded, for the sentence: `bills`, `goals`.
  final String what;

  /// Non-null when loading failed.
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (error == null) {
      return Center(
        child: Semantics(
          label: 'Loading $what',
          liveRegion: true,
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: t.rose),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                'Could not load $what. Your data on this device is safe.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: t.text),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Try again',
                excludeSemantics: true,
                child: OutlinedButton(
                  key: const ValueKey('retry'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  ),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
