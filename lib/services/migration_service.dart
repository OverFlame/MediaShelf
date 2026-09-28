import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory;

import '../db/tables.dart';
import 'media_rules.dart';

/// 迁移日志回调。工具与测试各传各的打印；服务本体不依赖 Flutter。
typedef MigrationLogger = void Function(String message);

/// 一次跨库迁移的统计与日志（BUILD_GUIDE 第 8.5 节）。
class MigrationReport {
  MigrationReport({
    required this.srcAudioDb,
    required this.srcImageDb,
    required this.dstDb,
    this.backupDir,
  });

  final String srcAudioDb;
  final String srcImageDb;
  final String dstDb;

  /// 老库备份目录，没备份时为 null。
  final String? backupDir;

  /// 每个目标表的写入行数。
  final Map<String, int> rows = <String, int>{};

  /// 读不了的老表（缺表，或整表读失败）。
  final List<String> skippedTables = <String>[];

  /// 逐条说明：跳过、冲突、类型按扩展名改写。
  final List<String> notes = <String>[];

  /// 两个老库都有的 path（保留先到者）。
  final List<String> duplicatePaths = <String>[];

  /// 摘要用：迁移相关表的固定顺序。
  static const List<String> tableOrder = <String>[
    'tags',
    'works',
    'folders',
    'folder_paths',
    'folder_tags',
    'media',
    'media_tags',
    'play_history',
  ];

  int rowCount(String table) => rows[table] ?? 0;

  void count(String table, [int n = 1]) => rows[table] = rowCount(table) + n;

  void note(String message) {
    notes.add(message);
  }

  String get summary {
    final parts = <String>[
      for (final table in tableOrder) '$table=${rowCount(table)}',
    ];
    return '迁移写入：${parts.join('，')}';
  }
}

/// 把 AudioShelf 与 PictureViewer2 两个老库并进新库（BUILD_GUIDE 第 8.2 节）。
///
/// 只读打开老库，逐表 SELECT，在目标库的单个事务里写入；不用 ATTACH，
/// 这样单元测试能直接造两个老库跑，也不碰 sqflite 的方言差异。
class MigrationService {
  MigrationService({
    this._factory,
    this.backupOldDbs = true,
    this._logger,
    this.overwriteDst = false,
  });

  final DatabaseFactory? _factory;
  final MigrationLogger? _logger;

  /// 迁移前把老库复制到 `<老库目录>/migration-backup-<时间戳>/`。
  final bool backupOldDbs;

  /// 目标库已有数据时是否覆盖。默认 false，遇到已有数据直接报错。
  final bool overwriteDst;

  DatabaseFactory get factory => _factory ?? databaseFactory;

  void _log(String message) => _logger?.call(message);

  Future<MigrationReport> run({
    required String srcAudioDb,
    required String srcImageDb,
    required String dstDb,
  }) async {
    final backups =
        backupOldDbs ? await _backup(<String>[srcAudioDb, srcImageDb]) : const <String>[];
    final report = MigrationReport(
      srcAudioDb: srcAudioDb,
      srcImageDb: srcImageDb,
      dstDb: dstDb,
      backupDir: backups.isEmpty ? null : backups.join('，'),
    );
    for (final dir in backups) {
      report.note('老库已备份到 $dir');
    }

    final audio = await _openReadOnly(srcAudioDb, 'AudioShelf', report);
    final images = await _openReadOnly(srcImageDb, 'PictureViewer2', report);

    if (File(dstDb).existsSync() && overwriteDst) {
      // 目标库是已经在用的库，删掉就没了：先按和老库同样的办法备份一份，
      // 合库中途出错时还能把原库放回去。
      for (final dir in await _backup(<String>[dstDb])) {
        report.note('目标库已备份到 $dir');
      }
      report.note('目标库已存在，按 overwrite 参数先删除：$dstDb');
      await factory.deleteDatabase(dstDb);
    }

    // 目标库可能是应用已经在用的旧版库（BUILD_GUIDE 8.5 的续跑场景），
    // 所以这里必须和应用主库一样接上 onCreate/onUpgrade：只给 version 的话，
    // sqflite 会把 user_version 直接抬成 v8，结构却留在旧版。
    final dst = await factory.openDatabase(
      dstDb,
      options: OpenDatabaseOptions(
        version: Tables.version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, version) => Tables.createAll(db),
        onUpgrade: (db, oldVersion, newVersion) =>
            Tables.applyMigrations(db, oldVersion, newVersion),
      ),
    );

    try {
      final existing = _firstInt(
          await dst.rawQuery('SELECT COUNT(*) FROM media'));
      if (existing > 0 && !overwriteDst) {
        throw StateError(
            '目标库已有 $existing 条 media 记录，迁移中止；确认要覆盖时传 overwrite: true');
      }

      await dst.transaction((txn) async {
        // ── tags：两边按 (namespace, name) 合并 ──
        final tagMapA = await _insertTags(txn, audio, report);
        final tagMapB = await _insertTags(txn, images, report);

        // ── works：只有 AudioShelf 有，一律 library='audio' ──
        final workMap = <int, int>{};
        for (final row in await _rows(audio, 'works', report)) {
          final name = row['name'] as String?;
          if (name == null) continue;
          final id = await txn.insert('works', <String, Object?>{
            'name': name,
            'library': 'audio',
            'cover_path': row['cover_path'],
            'sort_order': row['sort_order'] ?? 0,
            'created_at': row['created_at'] ?? 0,
          });
          workMap[row['id'] as int] = id;
          report.count('works');
        }

        // ── folders：两棵树各一趟，library 标明归属 ──
        final folderMapA = await _insertFolders(
            txn, await _rows(audio, 'folders', report), 'audio', workMap, report);
        final folderMapB = await _insertFolders(
            txn, await _rows(images, 'folders', report), 'image', const <int, int>{}, report);

        // ── folder_paths 与 folder_tags：folder_id 按映射改写 ──
        await _copyFolderPaths(txn, audio, folderMapA, report);
        await _copyFolderPaths(txn, images, folderMapB, report);
        await _copyFolderTags(txn, audio, folderMapA, tagMapA, report);
        await _copyFolderTags(txn, images, folderMapB, tagMapB, report);

        // ── media：tracks 记 audio，images 记 image ──
        final mediaMapA = await _insertTracks(txn, audio, report);
        final mediaMapB = await _insertImages(txn, images, report);

        // ── media_tags 与 play_history ──
        await _copyMediaTags(
            txn, audio, 'track_tags', 'track_id', mediaMapA, tagMapA, report);
        await _copyMediaTags(
            txn, images, 'image_tags', 'image_id', mediaMapB, tagMapB, report);
        await _copyPlayHistory(txn, audio, mediaMapA, report);
      });
    } finally {
      await dst.close();
      await audio?.close();
      await images?.close();
    }

    _log(report.summary);
    for (final note in report.notes) {
      _log(note);
    }
    return report;
  }

  // ═══ 打开与备份 ═══

  Future<Database?> _openReadOnly(
      String path, String label, MigrationReport report) async {
    if (!File(path).existsSync()) {
      report.note('$label 老库不存在，跳过：$path');
      return null;
    }
    report.note('$label 老库只读打开：$path');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
  }

  Future<List<String>> _backup(List<String> sources) async {
    // 同一个目录里的多个老库共用一个备份目录，所以用 Set 去重。
    final dirs = <String>{};
    final stamp = _timestamp();
    for (final src in sources) {
      if (!File(src).existsSync()) continue;
      final dirPath = p.join(p.dirname(src), 'migration-backup-$stamp');
      final dir = Directory(dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // WAL 模式的库还有 -wal 与 -shm 两个伴生文件，一起带上。
      for (final suffix in const <String>['', '-wal', '-shm']) {
        final file = File('$src$suffix');
        if (file.existsSync()) {
          file.copySync(p.join(dir.path, p.basename('$src$suffix')));
        }
      }
      dirs.add(dirPath);
    }
    return dirs.toList();
  }

  // ═══ 各表的写入 ═══

  Future<Map<int, int>> _insertTags(
      DatabaseExecutor txn, Database? src, MigrationReport report) async {
    final map = <int, int>{};
    for (final row in await _rows(src, 'tags', report)) {
      final ns = (row['namespace'] as String?) ?? 'general';
      final name = row['name'] as String?;
      if (name == null) continue;
      final color = (row['color'] as String?) ?? '#cba6f7';
      final n = await txn.insert(
          'tags', <String, Object?>{'namespace': ns, 'name': name, 'color': color},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      final found = await txn.query('tags',
          columns: <String>['id'],
          where: 'namespace = ? AND name = ?',
          whereArgs: <Object?>[ns, name],
          limit: 1);
      if (found.isEmpty) {
        report.note('标签写入失败，跳过：$ns/$name');
        continue;
      }
      map[row['id'] as int] = found.first['id'] as int;
      if (n != 0) {
        report.count('tags');
      } else {
        report.note('标签已存在，合并：$ns/$name');
      }
    }
    return map;
  }

  Future<Map<int, int>> _insertFolders(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String library,
    Map<int, int> workMap,
    MigrationReport report,
  ) async {
    final map = <int, int>{};
    // 第一趟只建节点，parent 留空；老库的父节点不一定先出现。
    for (final row in rows) {
      final name = row['name'] as String?;
      if (name == null) continue;
      final oldWork = row['work_id'] as int?;
      final id = await txn.insert(
        'folders',
        <String, Object?>{
          'name': name,
          'parent': null,
          'library': library,
          'work_id': oldWork == null ? null : workMap[oldWork],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      var newId = id;
      if (newId == 0) {
        final found = await txn.query('folders',
            columns: <String>['id'],
            where: 'name = ? AND parent IS NULL AND library = ?',
            whereArgs: <Object?>[name, library],
            limit: 1);
        if (found.isEmpty) {
          report.note('文件夹插入被忽略又找不到已有节点，跳过：$name（$library）');
          continue;
        }
        newId = found.first['id'] as int;
        report.note('文件夹同名并入已有节点：$name（$library）');
      } else {
        report.count('folders');
      }
      map[row['id'] as int] = newId;
    }
    // 第二趟补 parent。
    for (final row in rows) {
      final parent = row['parent'] as int?;
      if (parent == null) continue;
      final newId = map[row['id'] as int];
      final newParent = map[parent];
      if (newId == null || newParent == null) continue;
      await txn.update('folders', <String, Object?>{'parent': newParent},
          where: 'id = ?', whereArgs: <Object?>[newId]);
    }
    return map;
  }

  Future<void> _copyFolderPaths(DatabaseExecutor txn, Database? src,
      Map<int, int> folderMap, MigrationReport report) async {
    for (final row in await _rows(src, 'folder_paths', report)) {
      final folderId = folderMap[row['folder_id'] as int];
      final path = row['path'] as String?;
      if (folderId == null || path == null) continue;
      final n = await txn.insert(
          'folder_paths',
          <String, Object?>{
            'folder_id': folderId,
            'path': path,
            'recursive': row['recursive'] ?? 1,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (n != 0) report.count('folder_paths');
    }
  }

  Future<void> _copyFolderTags(DatabaseExecutor txn, Database? src,
      Map<int, int> folderMap, Map<int, int> tagMap, MigrationReport report) async {
    for (final row in await _rows(src, 'folder_tags', report)) {
      final folderId = folderMap[row['folder_id'] as int];
      final tagId = tagMap[row['tag_id'] as int];
      if (folderId == null || tagId == null) continue;
      final n = await txn.insert(
          'folder_tags', <String, Object?>{'folder_id': folderId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (n != 0) report.count('folder_tags');
    }
  }

  Future<Map<int, int>> _insertTracks(
      DatabaseExecutor txn, Database? src, MigrationReport report) async {
    final map = <int, int>{};
    for (final row in await _rows(src, 'tracks', report)) {
      final path = row['path'] as String?;
      if (path == null) continue;
      final mediaType = _mediaTypeOf(path, 'audio', report);
      final id = await _insertMedia(txn, report, 'AudioShelf', <String, Object?>{
        'path': path,
        'media_type': mediaType,
        'filename': row['filename'] ?? p.basename(path),
        'format': row['format'],
        'file_size': row['file_size'],
        'file_mtime': row['file_mtime'],
        'added_at': row['added_at'] ?? 0,
        'title': row['title'],
        'artist': row['artist'],
        'album': row['album'],
        'duration_ms': row['duration_ms'],
        'subtitle_path': row['subtitle_path'],
        'cover_path': row['cover_path'],
      });
      if (id != null) map[row['id'] as int] = id;
    }
    return map;
  }

  Future<Map<int, int>> _insertImages(
      DatabaseExecutor txn, Database? src, MigrationReport report) async {
    final map = <int, int>{};
    for (final row in await _rows(src, 'images', report)) {
      final path = row['path'] as String?;
      if (path == null) continue;
      final mediaType = _mediaTypeOf(path, 'image', report);
      final id = await _insertMedia(txn, report, 'PictureViewer2', <String, Object?>{
        'path': path,
        'media_type': mediaType,
        'filename': row['filename'] ?? p.basename(path),
        'format': row['format'],
        'file_size': row['file_size'],
        'file_mtime': row['file_mtime'],
        'added_at': row['added_at'] ?? 0,
        'width': row['width'],
        'height': row['height'],
        'hash': row['hash'],
        'note': row['note'],
        'alias': row['alias'],
      });
      if (id != null) map[row['id'] as int] = id;
    }
    return map;
  }

  /// 按扩展名定类型；认不出时才用源库的类型，两种不一致要写日志。
  String _mediaTypeOf(String path, String sourceType, MigrationReport report) {
    final derived = mediaTypeOfPath(path);
    if (derived == null) {
      report.note('扩展名认不出，沿用源库类型 $sourceType：$path');
      return sourceType;
    }
    if (derived != sourceType) {
      report.note('media_type 按扩展名判成 $derived，源库记为 $sourceType：$path');
    }
    return derived;
  }

  /// 写一行 media；path 撞了返回已有行的 id，并记进 duplicatePaths。
  Future<int?> _insertMedia(DatabaseExecutor txn, MigrationReport report,
      String source, Map<String, Object?> row) async {
    final path = row['path'] as String;
    final full = <String, Object?>{
      ...row,
      'ext': extOfPath(path),
      'name_lower': nameLowerOfPath(path),
    };
    final id = await txn.insert('media', full,
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) {
      report.count('media');
      return id;
    }
    final found = await txn.query('media',
        columns: <String>['id'], where: 'path = ?', whereArgs: <Object?>[path], limit: 1);
    if (found.isEmpty) {
      report.note('media 写入失败，跳过：$path');
      return null;
    }
    report.duplicatePaths.add(path);
    report.note('两个老库都有这个 path，保留先到者（$source 这次没写）：$path');
    return found.first['id'] as int;
  }

  Future<void> _copyMediaTags(
    DatabaseExecutor txn,
    Database? src,
    String table,
    String idColumn,
    Map<int, int> mediaMap,
    Map<int, int> tagMap,
    MigrationReport report,
  ) async {
    for (final row in await _rows(src, table, report)) {
      final mediaId = mediaMap[row[idColumn] as int];
      final tagId = tagMap[row['tag_id'] as int];
      if (mediaId == null || tagId == null) continue;
      final n = await txn.insert(
          'media_tags', <String, Object?>{'media_id': mediaId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (n != 0) report.count('media_tags');
    }
  }

  Future<void> _copyPlayHistory(DatabaseExecutor txn, Database? src,
      Map<int, int> mediaMap, MigrationReport report) async {
    for (final row in await _rows(src, 'play_history', report)) {
      final mediaId = mediaMap[row['track_id'] as int];
      if (mediaId == null) continue;
      final n = await txn.insert(
          'play_history',
          <String, Object?>{
            'media_id': mediaId,
            'played_at': row['played_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (n != 0) report.count('play_history');
    }
  }

  /// 读整张老表。表不存在或读失败就跳过并记日志，不中断整体迁移。
  Future<List<Map<String, Object?>>> _rows(
      Database? src, String table, MigrationReport report) async {
    if (src == null) return const <Map<String, Object?>>[];
    try {
      return await src.query(table);
    } on DatabaseException catch (e) {
      report.skippedTables.add(table);
      report.note('老表 $table 读不了，跳过：${e.toString().split('\n').first}');
      return const <Map<String, Object?>>[];
    }
  }

  int _firstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    final value = rows.first.values.first;
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
