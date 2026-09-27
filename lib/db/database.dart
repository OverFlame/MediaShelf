import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import '../services/data_dir_service.dart';
import '../utils/log_util.dart';
import 'tables.dart';

/// 数据库管理器 — 初始化、打开、迁移、单例
///
/// Windows / Linux 使用 sqflite_common_ffi；Android / iOS 使用 sqflite 插件。
class DatabaseManager {
  static DatabaseManager? _instance;
  static Database? _db;

  DatabaseManager._();

  static DatabaseManager get instance {
    _instance ??= DatabaseManager._();
    return _instance!;
  }

  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  bool get isOpen => _db != null;

  Future<void> init() async {
    if (_db != null) {
      logWarn('Database', 'Already initialized, skip duplicate init()');
      return;
    }
    logInfo('Database', 'Initializing...');
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await DataDirService.instance.dataDir;
    final dbPath = p.join(dir, 'audioshelf.db');
    logInfo('Database', 'DB path: $dbPath');

    _db = await openDatabase(
      dbPath,
      version: Tables.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        logInfo('Database', 'Creating tables (v$version)');
        for (final sql in Tables.createStatements) {
          await db.execute(sql);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        logInfo('Database', 'Migrating v$oldVersion -> v$newVersion');
        for (int v = oldVersion + 1; v <= newVersion; v++) {
          final migrations = Tables.migrations[v];
          if (migrations == null) continue;
          for (final sql in migrations) {
            await db.execute(sql);
          }
        }
      },
    );

    // journal_mode=WAL 会返回一行结果，Android 端 execSQL 不允许，需用 rawQuery。
    // （Android 8+ 本身默认 WAL，此处桌面端开启；Android 端该语句会被安全执行。）
    await _db!.rawQuery('PRAGMA journal_mode=WAL');
    logInfo('Database', 'Initialized OK (WAL+FK enabled)');
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) {
      logWarn('Database', 'close() called but no open connection');
      return;
    }
    // 先置空再关：并发调用方看到的是「已关闭」，而不是一个正在关闭的句柄。
    _db = null;
    logInfo('Database', 'Closing connection');
    await db.close();
  }
}
