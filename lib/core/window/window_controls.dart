import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// What the app's own title bar can ask of the window. Windows, macOS and Linux only; this is
/// window chrome, so it is allowed to differ by platform (docs: platform code is for hardware
/// and window chrome only).
abstract interface class WindowControls {
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> startDragging();

  /// Whether the window is maximized now, and every change after.
  Future<bool> isMaximized();
  Stream<bool> get maximizedChanges;
}

/// Set in `main()` on desktop; `null` everywhere else (phones, tests), which means no title bar of
/// our own.
final windowControlsProvider = Provider<WindowControls?>((ref) => null);

/// Tests set this to look like another platform; `null` is the running one.
final titleBarPlatformProvider = Provider<TargetPlatform?>((ref) => null);

/// Whether this platform is a desktop one that gets the themed title bar.
bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Hides the system title bar and returns the controls for ours. Call once before `runApp`.
Future<WindowControls> setUpDesktopWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    minimumSize: Size(360, 560),
    title: 'Family Expenses',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  return _ManagerControls();
}

class _ManagerControls with WindowListener implements WindowControls {
  _ManagerControls() {
    windowManager.addListener(this);
  }

  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get maximizedChanges => _changes.stream;

  @override
  void onWindowMaximize() => _changes.add(true);
  @override
  void onWindowUnmaximize() => _changes.add(false);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> startDragging() => windowManager.startDragging();
}
