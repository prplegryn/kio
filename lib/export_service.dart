import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExportService {
  static const _channel = MethodChannel('kio/crash_handler');

  static Future<String> writeZip(String fileName, Uint8List bytes) async {
    try {
      final savedPath = await _channel.invokeMethod<String>(
        'writeExportZip',
        {'fileName': fileName, 'bytes': bytes},
      );
      if (savedPath != null && savedPath.isNotEmpty) return savedPath;
    } catch (_) {
      // Fall through to app-private storage when MediaStore is unavailable.
    }
    return _writeFallback(fileName, bytes);
  }

  static Future<String> _writeFallback(String fileName, Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(directory.path, 'exports'));
    await exports.create(recursive: true);
    final file = File(p.join(exports.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
