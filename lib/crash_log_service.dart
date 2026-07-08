import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CrashLogService {
  static const _channel = MethodChannel('kio/crash_handler');

  static Future<void> install() async {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      unawaited(writeFlutterError(details));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(writeError(error, stack, origin: 'platform_dispatcher'));
      return true;
    };
  }

  static Future<void> writeFlutterError(FlutterErrorDetails details) async {
    await write(
      title: 'Flutter framework error',
      body: details.toString(),
      stack: details.stack,
      origin: 'flutter_error',
    );
  }

  static Future<void> writeError(
    Object error,
    StackTrace stack, {
    required String origin,
  }) async {
    await write(
      title: error.toString(),
      body: error.toString(),
      stack: stack,
      origin: origin,
    );
  }

  static Future<String> write({
    required String title,
    required String body,
    StackTrace? stack,
    required String origin,
  }) async {
    final now = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'kio_crash_$now.txt';
    final content = StringBuffer()
      ..writeln('kio crash report')
      ..writeln('origin: $origin')
      ..writeln('time: ${DateTime.now().toIso8601String()}')
      ..writeln('platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('title: $title')
      ..writeln('')
      ..writeln('message:')
      ..writeln(body)
      ..writeln('')
      ..writeln('stack:')
      ..writeln(stack?.toString() ?? 'No stack trace');

    try {
      final savedPath = await _channel.invokeMethod<String>(
        'writeCrashLog',
        {'fileName': fileName, 'content': content.toString()},
      );
      return savedPath ?? await _writeFallback(fileName, content.toString());
    } catch (_) {
      return _writeFallback(fileName, content.toString());
    }
  }

  static Future<String> _writeFallback(String fileName, String content) async {
    final directory = await getApplicationDocumentsDirectory();
    final logs = Directory(p.join(directory.path, 'crash_logs'));
    await logs.create(recursive: true);
    final file = File(p.join(logs.path, fileName));
    await file.writeAsString(content);
    return file.path;
  }
}
