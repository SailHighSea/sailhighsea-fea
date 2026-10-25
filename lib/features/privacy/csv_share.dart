import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a finished file to the system (share sheet on phones, save dialog elsewhere).
abstract interface class FileSharer {
  Future<void> shareText(String filename, String content, String mimeType);
}

class SystemFileSharer implements FileSharer {
  @override
  Future<void> shareText(
    String filename,
    String content,
    String mimeType,
  ) async {
    final dir = await Directory.systemTemp.createTemp('family_expenses_');
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
  }
}

final fileSharerProvider = Provider<FileSharer>((ref) => SystemFileSharer());
