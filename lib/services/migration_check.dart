import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory;

import 'media_rules.dart';

/// 一条校验项。
class CheckItem {
  CheckItem(this.name, this.passed, this.detail);

  final String name;
  final bool passed;
  final String detail;

  @override
  String toString() => '${passed ? 'PASS' : 'FAIL'} $name — $detail';
}

/// 校验结果：五项检查加若干说明。
class CheckReport {
  CheckReport();

  final List<CheckItem> items = <CheckItem>[];
  final List<String> notes = <String>[];

  bool get passed => items.every((item) => item.passed);

  int get failedCount => items.where((item) => !item.passed).length;

  String get summary {
    final head = passed
        ? '校验通过：${items.length} 项全过'
        : '校验失败：${items.length} 项里有 $failedCount 项没过';
    final lines = <String>[head, for (final item in items) '  $item'];
    for (final note in notes) {
      lines.add('  说明：$note');
    }
    return lines.join('\n');
  }
}

/// 迁移后的五项校验（BUILD_GUIDE 第 8.5 节）。
///
/// 只读打开三个库，全部判定都在这里；tool/migrate_check.dart 只是打印入口。
class MigrationChecker {
  MigrationChecker({this._factory});

  final DatabaseFactory? _factory;

  DatabaseFactory get factory => _factory ?? databaseFactory;

  Future<CheckReport> run({
    required String srcAudioDb,
    required String srcImageDb,
    required String dstDb,
  }) async {
    final report = CheckReport();
    if (!File(dstDb).existsSync()) {
      report.items.add(CheckItem('目标库存在', false, '找不到 $dstDb'));
      return report;
    }

    final audio = await _openReadOnly(srcAudioDb, 'AudioShelf 老库', report);
    final images = await _openReadOnly(srcImageDb, 'PictureViewer2 老库', report);
    final dst = await factory.openDatabase(dstDb,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));

    try {
      // ① path 集合相等
      final srcPathsA = await _paths(audio, 'tracks', report);
      final srcPathsB = await _paths(images, 'images', report);
      final srcPaths = <String>{...srcPathsA, ...srcPathsB};
      final dstPaths = await _paths(dst, 'media', report);
      final missing = srcPaths.difference(dstPaths);
      final extra = dstPaths.difference(srcPaths);
      final dup = srcPathsA.length + srcPathsB.length - srcPaths.length;
      report.items.add(CheckItem(
        '① path 集合相等',
        missing.isEmpty && extra.isEmpty,
        '源 ${srcPaths.length} 条，目标 ${dstPaths.length} 条'
        '${missing.isEmpty ? '' : '，目标缺 ${missing.length} 条 ${_sample(missing)}'}'
        '${extra.isEmpty ? '' : '，目标多 ${extra.length} 条 ${_sample(extra)}'}',
      ));

      // ② media 行数 == 两库 path 并集条数
      final mediaCount = await _count(dst, 'media', report);
      report.items.add(CheckItem(
        '② media 行数',
        mediaCount == srcPaths.length,
        '目标 $mediaCount 行，源并集 ${srcPaths.length} 条'
        '（AudioShelf ${srcPathsA.length} + PictureViewer2 ${srcPathsB.length}'
        '，两边重复 $dup 条）',
      ));

      // ③ media_tags 覆盖源库的每个 (path, 标签) 对
      final srcTagPairs = <String>{
        ...await _tagPairs(audio, 'tracks', 'track_tags', report),
        ...await _tagPairs(images, 'images', 'image_tags', report),
      };
      final dstTagPairs = await _tagPairs(dst, 'media', 'media_tags', report);
      final missingTags = srcTagPairs.difference(dstTagPairs);
      report.items.add(CheckItem(
        '③ media_tags 覆盖',
        missingTags.isEmpty,
        '源 ${srcTagPairs.length} 对，目标 ${dstTagPairs.length} 对'
        '${missingTags.isEmpty ? '' : '，缺 ${missingTags.length} 对 ${_sample(missingTags)}'}',
      ));

      // ④ 每条 media 的 media_type 与扩展名判定一致
      final mismatches = <String>[];
      for (final row in await _selectAll(dst, 'media',
          columns: <String>['path', 'media_type'], report: report)) {
        final path = '${row['path']}';
        final actual = '${row['media_type']}';
        final expected = mediaTypeOfPath(path);
        final ok = expected != null
            ? actual == expected
            : (actual == 'subtitle' && isSubtitleFile(path));
        if (!ok) mismatches.add('$path（库里 $actual）');
      }
      report.items.add(CheckItem(
        '④ media_type 与扩展名一致',
        mismatches.isEmpty,
        mismatches.isEmpty ? '全部一致' : '${mismatches.length} 条不一致 ${_sample(mismatches)}',
      ));

      // ⑤ integrity_check
      final integrity = await dst.rawQuery('PRAGMA integrity_check');
      final value = integrity.isEmpty ? '(无结果)' : '${integrity.first.values.first}';
      report.items.add(CheckItem('⑤ integrity_check', value == 'ok', value));
    } finally {
      await dst.close();
      await audio?.close();
      await images?.close();
    }
    return report;
  }

  Future<Database?> _openReadOnly(
      String path, String label, CheckReport report) async {
    if (!File(path).existsSync()) {
      report.notes.add('$label 不存在，按空库处理：$path');
      return null;
    }
    return factory.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  }

  Future<Set<String>> _paths(
      Database? db, String table, CheckReport report) async {
    final rows = await _selectAll(db, table, columns: <String>['path'], report: report);
    return <String>{for (final row in rows) '${row['path']}'};
  }

  Future<Set<String>> _tagPairs(Database? db, String mediaTable,
      String linkTable, CheckReport report) async {
    if (db == null) return <String>{};
    // track_tags → track_id，image_tags → image_id，media_tags → media_id
    final idColumn = '${linkTable.substring(0, linkTable.length - 5)}_id';
    try {
      final rows = await db.rawQuery('''
        SELECT m.path AS path, t.namespace AS namespace, t.name AS name
        FROM $linkTable l
        INNER JOIN $mediaTable m ON m.id = l.$idColumn
        INNER JOIN tags t ON t.id = l.tag_id
      ''');
      return <String>{
        for (final row in rows)
          '${row['path']}\u0000${row['namespace']}\u0000${row['name']}',
      };
    } on DatabaseException catch (e) {
      report.notes.add('$linkTable 读不了，按空处理：${e.toString().split('\n').first}');
      return <String>{};
    }
  }

  Future<int> _count(Database db, String table, CheckReport report) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) FROM $table');
      final value = rows.first.values.first;
      return value is int ? value : int.tryParse('$value') ?? 0;
    } on DatabaseException catch (e) {
      report.notes.add('$table 读不了：${e.toString().split('\n').first}');
      return 0;
    }
  }

  Future<List<Map<String, Object?>>> _selectAll(
    Database? db,
    String table, {
    required List<String> columns,
    required CheckReport report,
  }) async {
    if (db == null) return const <Map<String, Object?>>[];
    try {
      return await db.query(table, columns: columns);
    } on DatabaseException catch (e) {
      report.notes.add('$table 读不了，按空处理：${e.toString().split('\n').first}');
      return const <Map<String, Object?>>[];
    }
  }

  String _sample(Iterable<String> values, {int limit = 3}) {
    final list = values.take(limit).toList();
    final suffix = values.length > limit ? ' 等' : '';
    return list.join('、') + suffix;
  }
}
