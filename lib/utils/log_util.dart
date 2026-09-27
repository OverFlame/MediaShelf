import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

/// 统一日志工具 — 调用 [dart:developer.log] 输出到控制台 + DevTools
enum Log {
  debug,
  info,
  warn,
  error;

  String get _label {
    switch (this) {
      case Log.debug:
        return 'DBG';
      case Log.info:
        return 'INF';
      case Log.warn:
        return 'WRN';
      case Log.error:
        return 'ERR';
    }
  }
}

// ignore: non_constant_identifier_names
final LogUtil = _LogUtil.instance;

class _LogUtil {
  static final _LogUtil instance = _LogUtil._();
  _LogUtil._();

  bool showDebug = kDebugMode;

  void _emit(Log level, String tag, String msg, [Object? data]) {
    if (level == Log.debug && !showDebug) return;

    final buf = StringBuffer()
      ..write('[${level._label}] ')
      ..write(tag.padRight(18))
      ..write(' | ')
      ..write(msg);

    try {
      dev.log(buf.toString(),
          name: 'MediaShelf',
          level: level == Log.error
              ? 1000
              : level == Log.warn
                  ? 900
                  : level == Log.info
                      ? 800
                      : 500,
          time: DateTime.now());
    } catch (_) {
      debugPrint(buf.toString());
    }
  }

  void d(String tag, String msg, [Object? data]) =>
      _emit(Log.debug, tag, msg, data);
  void i(String tag, String msg, [Object? data]) =>
      _emit(Log.info, tag, msg, data);
  void w(String tag, String msg, [Object? data]) =>
      _emit(Log.warn, tag, msg, data);
  void e(String tag, String msg, [Object? data]) =>
      _emit(Log.error, tag, msg, data);
}

void logDebug(String tag, String msg, [Object? data]) =>
    LogUtil.d(tag, msg, data);
void logInfo(String tag, String msg, [Object? data]) =>
    LogUtil.i(tag, msg, data);
void logWarn(String tag, String msg, [Object? data]) =>
    LogUtil.w(tag, msg, data);
void logError(String tag, String msg, [Object? data]) =>
    LogUtil.e(tag, msg, data);
